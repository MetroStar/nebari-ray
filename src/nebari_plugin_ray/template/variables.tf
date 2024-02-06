variable "name" {
  description = "Chart name"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  type = string
}

variable "domain" {
  description = "Domain"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider"
  type        = string
}

variable "realm_id" {
  description = "Keycloak realm_id"
  type        = string
}

variable "client_id" {
  description = "OpenID Client ID"
  type        = string
}

variable "base_url" {
  description = "Default URL to use when the auth server needs to redirect or link back to the client"
  type        = string
}

variable "external_url" {
  description = "External url for keycloak auth endpoint"
  type        = string
}

variable "valid_redirect_uris" {
  description = "A list of valid URIs a browser is permitted to redirect to after a successful login or logout"
  type        = list(string)
}

variable "create_namespace" {
  type = bool
}

variable "namespace" {
  type = string
}

variable "nebari_namespace" {
  type = string
}

variable "ingress" {
  type = object({
    enabled = optional(bool, true)
    path    = string
  })
  default = {
    enabled = false
    path    = "/airflow"
  }
}

variable "overrides" {
  type    = map(any)
  default = {}
}

variable "auth_enabled" {
  type = bool
}

variable "extraEnv" {
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "ray_version" {
  type = string
}

variable "python_version" {
  type = string
}

variable "head" {
  type = object({
    replicas     = optional(number, 1)
    minReplicas  = optional(number, 1)
    maxReplicas  = optional(number, 1)
    nodeSelector = optional(map(string), {})
    resources = optional(object({
      limits = optional(map(string), {
        cpu    = "1"
        memory = "2G"
      })
      requests = optional(map(string), {
        cpu    = "1"
        memory = "2G"
      })
    }), {})
  })
  default = {
    replicas     = 1
    minReplicas  = 1
    maxReplicas  = 2
    nodeSelector = {}
    resources = {
      limits = {
        cpu    = "1"
        memory = "2G"
      }
      requests = {
        cpu    = "1"
        memory = "2G"
      }
    }
  }
}

variable "workers" {
  type = map(object({
    disabled     = optional(bool, false)
    gpu          = optional(bool, false)
    replicas     = optional(number, 1)
    minReplicas  = optional(number, 1)
    maxReplicas  = optional(number, 10)
    nodeSelector = optional(map(string), {})
    resources = optional(object({
      limits   = optional(map(string), {})
      requests = optional(map(string), {})
    }), {})
  }))
  default = {}
}

variable "log_level" {
  type    = string
  default = "INFO"
}

variable "insecure" {
  type    = bool
  default = false
}

variable "operator" {
  type = object({
    enabled    = optional(bool, true)
    namespaced = optional(bool, true)
  })
  default = {
    enabled    = true
    namespaced = true
  }
}
