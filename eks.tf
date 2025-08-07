# Dynamic AMI fetching using Terraform data sources
# data "aws_ssm_parameter" "eks_ami_release_version" {
#   name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2/recommended/release_version"
# }
# data "aws_ssm_parameter" "eks_ami_image_id" {
#   name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2/recommended/image_id"
# }
# ami_id = data.aws_ssm_parameter.eks_ami_image_id.value
# aws ssm get-parameters-by-path \
#   --path /aws/service/eks/optimized-ami \
#   --query 'Parameters[?contains(Name, `amazon-linux-2/recommended/image_id`)].Name' \
#   --region eu-north-1

# EKS Cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Cluster endpoint configuration
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    main = {
      name           = var.node_group_name
      use_name_prefix = false

      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size



      # Use the latest EKS optimized AMI
      ami_type = "AL2_x86_64"  # Previous generic AMI type
      #ami_id = "ami-06396cf1b09f14a4e"  # Latest EKS-optimized AMI for K8s 1.30 in eu-north-1
      
      # Disk configuration
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20  # Minimal disk size
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Node group scaling configuration
      update_config = {
        max_unavailable_percentage = 25
      }

      labels = {
        Environment = "dev"
        NodeGroup   = var.node_group_name
      }

      tags = var.tags
    }
  }

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}

# EKS Container Insights addon for enhanced monitoring
resource "aws_eks_addon" "container_insights" {
  count = var.enable_container_insights ? 1 : 0
  
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = null  # Use latest version
  service_account_role_arn    = aws_iam_role.container_insights[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  configuration_values = jsonencode({
    agent = {
      config = {
        logs = {
          metrics_collected = {
            application_signals = {}
            kubernetes = {
              enhanced_container_insights = true
            }
          }
        }
      }
    }
  })

  depends_on = [
    module.eks.eks_managed_node_groups,
    aws_iam_role_policy_attachment.container_insights
  ]

  tags = var.tags
}

# IAM role for Container Insights
resource "aws_iam_role" "container_insights" {
  count = var.enable_container_insights ? 1 : 0
  name  = "${var.cluster_name}-container-insights-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Attach AWS managed policy for CloudWatch Agent
resource "aws_iam_role_policy_attachment" "container_insights" {
  count      = var.enable_container_insights ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.container_insights[0].name
}

# Security group rule to allow ALB to reach worker nodes
resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = module.eks.node_security_group_id
  description              = "Allow ALB to reach worker nodes"
}
