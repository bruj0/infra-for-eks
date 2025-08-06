# AWS Load Balancer Controller Namespace
resource "kubernetes_namespace" "aws_load_balancer_controller" {
  metadata {
    name = "aws-load-balancer-controller"
    labels = {
      "app.kubernetes.io/name" = "aws-load-balancer-controller"
    }
  }
  
  depends_on = [module.eks]
}

# Additional IAM policy for AWS Load Balancer Controller
data "aws_iam_policy_document" "load_balancer_controller_additional" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:ModifySecurityGroupRules"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "load_balancer_controller_additional" {
  name_prefix = "${var.cluster_name}-alb-controller-additional"
  description = "Additional permissions for AWS Load Balancer Controller"
  policy      = data.aws_iam_policy_document.load_balancer_controller_additional.json

  tags = var.tags
}

# IAM role for AWS Load Balancer Controller
module "load_balancer_controller_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-aws-load-balancer-controller"

  attach_load_balancer_controller_policy = true
  role_policy_arns = {
    additional = aws_iam_policy.load_balancer_controller_additional.arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["aws-load-balancer-controller:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# Service Account for AWS Load Balancer Controller
resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = kubernetes_namespace.aws_load_balancer_controller.metadata[0].name
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = module.load_balancer_controller_irsa_role.iam_role_arn
    }
  }

  depends_on = [
    module.eks,
    module.load_balancer_controller_irsa_role
  ]
}

# AWS Load Balancer Controller Helm Chart
# https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = kubernetes_namespace.aws_load_balancer_controller.metadata[0].name
  version    = "1.7.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  # Resource limits for cost optimization
  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "500Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "200Mi"
  }

  depends_on = [
    module.eks,
    kubernetes_service_account.aws_load_balancer_controller
  ]
}

# Security Group for ALB to allow public internet access
resource "aws_security_group" "alb" {
  name_prefix = "${var.cluster_name}-alb"
  description = "Security group for ALB to allow public internet access"
  vpc_id      = module.vpc.vpc_id

  # Allow HTTP traffic from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS traffic from anywhere
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-alb-sg"
    Type = "ALB Security Group"
  })
}
