locals {
  name                    = var.name
  cluster_name            = var.cluster_name
  domain                  = var.domain
  provider                = var.cloud_provider
  realm_id                = var.realm_id
  client_id               = var.client_id
  base_url                = var.base_url
  valid_redirect_uris     = var.valid_redirect_uris
  external_url            = var.external_url
  cluster_oidc_issuer_url = var.cluster_oidc_issuer_url

  log_level = var.log_level
  insecure  = var.insecure

  create_namespace = var.create_namespace
  namespace        = var.namespace
  nebari_namespace = var.nebari_namespace
  overrides        = var.overrides
  ingress          = var.ingress
  auth_enabled     = var.auth_enabled
  extraEnv         = var.extraEnv
  ray_version      = var.ray_version
  python_version   = var.python_version
  head             = var.head
  workers          = var.workers

  chart_namespace = local.create_namespace ? kubernetes_namespace.this[0].metadata[0].name : local.namespace

  signing_key = local.auth_enabled ? random_password.signing_key[0].result : ""

  # not sure what these would need to be for other clouds
  default_nodeselector = {
    aws = {
      default = {
        "eks.amazonaws.com/nodegroup" : "general"
      }
      worker = {
        "eks.amazonaws.com/nodegroup" : "worker"
      }
    }
  }

  operator = var.operator
}

resource "kubernetes_namespace" "this" {
  count = local.create_namespace ? 1 : 0

  metadata {
    name = local.namespace
  }
}

resource "helm_release" "ray_operator" {
  count = local.operator.enabled ? 1 : 0

  name      = "${local.name}-operator"
  namespace = local.chart_namespace

  repository = "https://ray-project.github.io/kuberay-helm/"
  chart      = "kuberay-operator"
  version    = "1.0.0"

  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = "${local.name}-operator"
      }
      singleNamespaceInstall = local.operator.namespaced
      nodeSelector = (length(local.head.nodeSelector) > 0 ?
        local.head.nodeSelector :
        try(local.default_nodeselector[local.provider].default, {})
      )
    }),
    yamlencode(lookup(local.overrides, "kuberay-operator", {})),
  ]
}

resource "helm_release" "ray_cluster" {
  name      = "${local.name}-cluster"
  chart     = "./chart/ray-cluster"
  namespace = local.chart_namespace

  values = [
    yamlencode({
      image = {
        repository = "rayproject/ray"
        tag        = "${local.ray_version}-py${replace(local.python_version, ".", "")}"
      }
      head = {
        rayVersion = local.ray_version
        autoscalerOptions = {
          idleTimeoutSeconds = 300
        }
        serviceAccountName = kubernetes_service_account.head.metadata[0].name
        containerEnv = concat([
          {
            name  = "RAY_GRAFANA_HOST"
            value = "http://nebari-grafana.${local.nebari_namespace}"
          },
          {
            name  = "RAY_PROMETHEUS_HOST"
            value = "http://nebari-kube-prometheus-sta-prometheus.${local.nebari_namespace}:9090"
          },
          {
            name  = "RAY_PROMETHEUS_NAME"
            value = "Prometheus"
          },
          {
            name  = "RAY_GRAFANA_IFRAME_HOST"
            value = "https://${local.domain}/monitoring"
          }
        ], local.extraEnv)
        resources = (length(local.head.resources) > 0 ? local.head.resources : {
          limits = {
            cpu    = "1"
            memory = "2G"
          }
          requests = {
            cpu    = "1"
            memory = "2G"
          }
        })
        nodeSelector = (length(local.head.nodeSelector) > 0 ?
          local.head.nodeSelector :
          try(local.default_nodeselector[local.provider].default, {})
        )
      }

      worker = {
        disabled = length(local.workers) > 0
      }

      additionalWorkerGroups = { for k, v in local.workers : k => {
        disabled = v.disabled
        image = {
          repository = "rayproject/ray"
          tag = (v.gpu ?
            "${local.ray_version}-py${replace(local.python_version, ".", "")}-gpu" :
            "${local.ray_version}-py${replace(local.python_version, ".", "")}"
          )
        }
        replicas           = v.replicas
        minReplicas        = v.minReplicas
        maxReplicas        = v.maxReplicas
        serviceAccountName = kubernetes_service_account.worker.metadata[0].name
        containerEnv       = local.extraEnv
        resources          = v.resources
        nodeSelector = (length(v.nodeSelector) > 0 ?
          v.nodeSelector :
          try(local.default_nodeselector[local.provider].worker, {})
        )
        volumes = [
          {
            name     = "log-volume"
            emptyDir = {}
          }
        ]
        volumeMounts = [
          {
            name      = "log-volume"
            mountPath = "/tmp/ray"
          }
        ]
      } }
    }),
    yamlencode(lookup(local.overrides, "ray-cluster", {})),
  ]

  depends_on = [
    helm_release.ray_operator
  ]
}

resource "keycloak_openid_client" "this" {
  count = local.auth_enabled ? 1 : 0

  realm_id                     = local.realm_id
  name                         = local.client_id
  client_id                    = local.client_id
  access_type                  = "CONFIDENTIAL"
  base_url                     = local.base_url
  valid_redirect_uris          = local.valid_redirect_uris
  enabled                      = true
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  web_origins                  = ["+"]
}

resource "keycloak_openid_audience_protocol_mapper" "this" {
  count = local.auth_enabled ? 1 : 0

  realm_id  = local.realm_id
  client_id = keycloak_openid_client.this[0].id
  name      = "audience"

  included_client_audience = keycloak_openid_client.this[0].name
}

resource "keycloak_openid_group_membership_protocol_mapper" "this" {
  count = local.auth_enabled ? 1 : 0

  realm_id  = local.realm_id
  client_id = keycloak_openid_client.this[0].id
  name      = "groups"

  claim_name = "groups"
}

resource "random_password" "signing_key" {
  count = local.auth_enabled ? 1 : 0

  length  = 32
  special = false
}

resource "kubernetes_service_account" "head" {
  metadata {
    name      = "${local.name}-head"
    namespace = local.chart_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = module.s3_role.iam_role_arn
    }
  }
}

resource "kubernetes_service_account" "worker" {
  metadata {
    name      = "${local.name}-worker"
    namespace = local.chart_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = module.s3_role.iam_role_arn
    }
  }
}
