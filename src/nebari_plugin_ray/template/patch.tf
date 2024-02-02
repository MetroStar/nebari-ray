resource "kubernetes_role" "patch" {
  metadata {
    name      = "${local.name}-operator-patch"
    namespace = local.chart_namespace
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs = [
      "create",
      "delete",
      "get",
      "list",
      "patch",
      "update",
      "watch",
    ]
  }
}

resource "kubernetes_role_binding" "patch" {
  metadata {
    name      = "${local.name}-operator-patch"
    namespace = local.chart_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "${local.name}-operator-patch"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "${local.name}-operator"
    namespace = local.chart_namespace
  }
}
