module "s3" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket        = "${local.cluster_name}-${local.name}-${local.namespace}-storage"
  force_destroy = true

  versioning = {
    enabled = true
  }
}

module "s3_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.34.0"

  create_role      = true
  role_name        = "${local.cluster_name}-${local.name}-${local.namespace}-storage"
  role_description = "${local.cluster_name}-${local.name}-${local.namespace}-storage"
  provider_url     = replace(var.cluster_oidc_issuer_url, "https://", "")
  role_policy_arns = [aws_iam_policy.s3.arn]
  oidc_fully_qualified_subjects = [
    "system:serviceaccount:${local.chart_namespace}:${local.name}-head",
    "system:serviceaccount:${local.chart_namespace}:${local.name}-worker",
  ]
}

resource "aws_iam_policy" "s3" {
  name = "${local.cluster_name}-${local.name}-${local.namespace}-storage"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*Object",
        ]
        Resource = ["${module.s3.s3_bucket_arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = [module.s3.s3_bucket_arn]
      }
    ]
  })
}
