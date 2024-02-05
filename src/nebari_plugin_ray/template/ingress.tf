resource "kubernetes_manifest" "ingressroute" {
  count = local.ingress.enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = local.name
      namespace = local.namespace
    }
    spec = {
      entryPoints = [
        "websecure",
      ]
      routes = concat(local.auth_enabled ? [
        {
          kind  = "Rule"
          match = "Host(`${local.domain}`) && PathPrefix(`${local.ingress.path}/oauth2/`)"
          middlewares = [
            {
              name      = "${local.name}-oauth-errors"
              namespace = local.chart_namespace
            }
          ]
          services = [
            {
              name           = "${local.name}-oauth2-proxy"
              passHostHeader = true
              port           = 4180
            }
          ]
        }] : [],
        [
          {
            kind  = "Rule"
            match = "Host(`${local.domain}`) && PathPrefix(`${local.ingress.path}`)"
            middlewares = concat(local.auth_enabled ? [
              {
                name      = "${local.name}-oauth-errors"
                namespace = local.chart_namespace
              },
              {
                name      = "${local.name}-oauth2-proxy"
                namespace = local.chart_namespace
              },
              ] : [], [
              {
                name      = "${local.name}-stripprefix"
                namespace = local.chart_namespace
              }
            ])
            services = [
              {
                name           = "${local.name}-cluster-kuberay-head-svc"
                passHostHeader = true
                port           = 8265
              }
            ]
          }
        ]
      )
    }
  }

  field_manager {
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "stripprefix_middleware" {
  count = local.ingress.enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "${local.name}-stripprefix"
      namespace = local.namespace
    }
    spec = {
      stripPrefix = {
        forceSlash = true
        prefixes = [
          local.ingress.path,
        ]
      }
    }
  }
}

resource "kubernetes_deployment" "auth" {
  count = local.ingress.enabled && local.auth_enabled ? 1 : 0

  metadata {
    name      = "${local.name}-oauth2-proxy"
    namespace = local.namespace
    labels = {
      app = "${local.name}-oauth2-proxy"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "${local.name}-oauth2-proxy"
      }
    }

    template {
      metadata {
        labels = {
          app = "${local.name}-oauth2-proxy"
        }
        annotations = {
          "checksum/plugin-secrets-sha256" = base64sha256(
            jsonencode(kubernetes_secret.auth[0].data)
          )
        }
      }

      spec {
        node_selector = (length(local.head.nodeSelector) > 0 ?
          local.head.nodeSelector :
          try(local.default_nodeselector[local.provider].default, {})
        )

        container {
          name  = "main"
          image = "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"

          args = [
            "--provider=keycloak-oidc",
            "--proxy-prefix=${local.ingress.path}/oauth2",
            "--redirect-url=https://${local.domain}${local.ingress.path}/oauth2/callback",
            "--email-domain=*",
            "--upstream=http://${local.name}-cluster-kuberay-head-svc.ray:8265",
            "--http-address=0.0.0.0:4180",
            "--pass-user-headers=true",
            "--pass-access-token=true",
            "--set-authorization-header=true",
            "--set-xauthrequest=true",
            "--reverse-proxy=true",
            "--code-challenge-method=S256",
            # "--skip-provider-button",
            "--silence-ping-logging",
            "--insecure-oidc-allow-unverified-email",
            local.insecure ? "--ssl-insecure-skip-verify" : "",
          ]

          port {
            container_port = 4180
            protocol       = "TCP"
            name           = "http"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.auth[0].metadata[0].name
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_secret" "auth" {
  count = local.ingress.enabled && local.auth_enabled ? 1 : 0

  metadata {
    name      = "${local.name}-auth"
    namespace = local.chart_namespace
  }

  data = {
    OAUTH2_PROXY_CLIENT_ID       = keycloak_openid_client.this[0].client_id
    OAUTH2_PROXY_CLIENT_SECRET   = keycloak_openid_client.this[0].client_secret
    OAUTH2_PROXY_OIDC_ISSUER_URL = "${local.external_url}realms/${local.realm_id}"

    OAUTH2_PROXY_COOKIE_SECRET     = local.signing_key

    # https://github.com/oauth2-proxy/oauth2-proxy/issues/1297
    # OAUTH2_PROXY_FOOTER = "<script>(function(){var rd=document.getElementsByName('rd');for(var i=0;i<rd.length;i++)rd[i].value=window.location.toString().split('${local.ingress.path}/oauth2')[0]})()</script>"

    discovery_url = "${local.external_url}realms/${local.realm_id}/.well-known/openid-configuration"
    auth_url      = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/auth"
    token_url     = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/token"
    jwks_url      = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/certs"
    logout_url    = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/logout"
    userinfo_url  = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/userinfo"
  }
}


resource "kubernetes_service" "auth" {
  count = local.ingress.enabled && local.auth_enabled ? 1 : 0

  metadata {
    name      = "${local.name}-oauth2-proxy"
    namespace = local.namespace
  }
  spec {
    selector = {
      app = kubernetes_deployment.auth[0].spec[0].template[0].metadata[0].labels.app
    }

    port {
      port        = 4180
      target_port = "http"
      protocol    = "TCP"
      name        = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "oauth2_errors" {
  count = local.ingress.enabled && local.auth_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "${local.name}-oauth-errors"
      namespace = local.namespace
    }
    spec = {
      errors = {
        status = [
          "401-403"
        ]
        service = {
          name = "${local.name}-oauth2-proxy"
          port = 4180
        }
        query = "${local.ingress.path}/oauth2/sign_in?rd={url}"
        # query = "${local.ingress.path}/oauth2/start?rd={url}"
      }
    }
  }

  field_manager {
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "oauth2_proxy" {
  count = local.ingress.enabled && local.auth_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "${local.name}-oauth2-proxy"
      namespace = local.namespace
    }
    spec = {
      forwardAuth = {
        # address            = "http://${local.name}-oauth2-proxy.${local.chart_namespace}:4180${local.ingress.path}/oauth2/start?rd={url}"
        address            = "http://${local.name}-oauth2-proxy.${local.chart_namespace}:4180${local.ingress.path}/oauth2/auth"
        trustForwardHeader = true
        authResponseHeaders = [
          "X-Auth-Request-User",
          "X-Auth-Request-Access-Token",
          "Set-Cookie",
          "Authorization",
        ]
      }
    }
  }

  field_manager {
    force_conflicts = true
  }
}
