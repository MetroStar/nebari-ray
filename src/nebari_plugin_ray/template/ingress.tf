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
      routes = [
        {
          kind  = "Rule"
          match = "Host(`${local.domain}`) && PathPrefix(`${local.ingress.path}`)"
          middlewares = concat(local.auth_enabled ? [
            {
              name      = "${local.name}-traefik-forward-auth"
              namespace = local.chart_namespace
            }
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
    }
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
    name      = "${local.name}-traefik-forward-auth"
    namespace = local.namespace
    labels = {
      app = "${local.name}-traefik-forward-auth"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "${local.name}-traefik-forward-auth"
      }
    }

    template {
      metadata {
        labels = {
          app = "${local.name}-traefik-forward-auth"
        }
      }

      spec {
        node_selector = (length(local.head.nodeSelector) > 0 ?
          local.head.nodeSelector :
          try(local.default_nodeselector[local.provider].default, {})
        )

        container {
          name  = "main"
          image = "thomseddon/traefik-forward-auth:2"

          port {
            container_port = 4181
            protocol       = "TCP"
            name           = "http"
          }

          env {
            name  = "LOG_LEVEL"
            value = local.log_level
          }

          env {
            name  = "INSECURE_COOKIE"
            value = local.insecure ? "true" : "false"
          }

          env {
            name  = "URL_PATH"
            value = "${local.ingress.path}/_oauth"
          }

          env {
            name  = "DEFAULT_PROVIDER"
            value = "oidc"
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
    PROVIDERS_OIDC_CLIENT_ID     = keycloak_openid_client.this[0].client_id
    PROVIDERS_OIDC_CLIENT_SECRET = keycloak_openid_client.this[0].client_secret
    SECRET                       = local.signing_key

    PROVIDERS_OIDC_ISSUER_URL = "${local.external_url}realms/${local.realm_id}"
    discovery_url             = "${local.external_url}realms/${local.realm_id}/.well-known/openid-configuration"
    auth_url                  = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/auth"
    token_url                 = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/token"
    jwks_url                  = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/certs"
    logout_url                = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/logout"
    userinfo_url              = "${local.external_url}realms/${local.realm_id}/protocol/openid-connect/userinfo"
  }
}


resource "kubernetes_service" "auth" {
  count = local.ingress.enabled && local.auth_enabled ? 1 : 0

  metadata {
    name      = "${local.name}-traefik-forward-auth"
    namespace = local.namespace
  }
  spec {
    selector = {
      app = kubernetes_deployment.auth[0].spec[0].template[0].metadata[0].labels.app
    }

    port {
      port        = 4181
      target_port = "http"
      protocol    = "TCP"
      name        = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "auth" {
  count = local.ingress.enabled && local.auth_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "${local.name}-traefik-forward-auth"
      namespace = local.namespace
    }
    spec = {
      forwardAuth = {
        address = "http://${local.name}-traefik-forward-auth.${local.chart_namespace}:4181/"
        authResponseHeaders = [
          "X-Forwarded-User",
        ]
      }
    }
  }
}
