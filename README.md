# Minimal EKS Cluster with ALB Ingress

This project creates a cost-optimized EKS cluster using OpenTofu with the AWS Load Balancer Controller for ingress.

To be used with CI/CD on this repo: https://github.com/bruj0/cicd-for-eks
## Cost Optimization Features

- **Dual Availability Zone**: Minimum required for EKS (2 AZs)
- **Spot Instances**: Up to 90% cost savings on EC2 instances
- **Minimal Node Group**: 1-2 t3.small instances
- **Single NAT Gateway**: Shared across all private subnets
- **Minimal Storage**: 20GB GP3 volumes
- **Resource Limits**: Conservative CPU/memory allocation

## Monitoring Features

- **CloudWatch Container Insights**: Enhanced monitoring for EKS clusters
  - Pod, node, and cluster-level metrics
  - Application logs and performance insights
  - Enhanced container insights with detailed resource utilization
  - Integration with CloudWatch dashboards
  - Can be disabled by setting `enable_container_insights = false`

## Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **OpenTofu** installed (or Terraform)
3. **kubectl** installed
4. **Helm** installed (optional, for manual chart management)

### Required AWS Permissions

Your AWS user/role needs the following permissions:
- EKS cluster management
- EC2 instance and VPC management
- IAM role and policy management
- Application Load Balancer management


### Backend Configuration

#### Option 1: Automated Setup (Recommended)

Use the provided script to automatically create and configure the remote backend:

```bash
# Create S3 bucket and DynamoDB table with default settings
./setup-backend.sh

# Or customize the configuration
./setup-backend.sh --bucket-prefix my-tf-state --region us-east-1 --profile my-aws-profile
```

The script will:
- Create a uniquely named S3 bucket with versioning and encryption
- Create a DynamoDB table for state locking
- Update `backend.tf` with the correct configuration
- Block public access on the S3 bucket


#### Backend Cleanup

To remove the backend resources and return to local state:

```bash
./cleanup-backend.sh
```


## Quick Start

1. **Set up remote state backend (recommended):**
   ```bash
   ./setup-backend.sh
   tofu init
   tofu plan
   tofu apply
   ```

1. **Configure kubectl:**
   ```bash
   aws eks --region us-west-2 update-kubeconfig --name minimal-eks-cluster
   ```

1. **Verify the cluster:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

1. **Verify Container Insights (if enabled):**
   ```bash
   # Check if the CloudWatch addon is installed
   aws eks describe-addon --cluster-name minimal-eks-cluster --addon-name amazon-cloudwatch-observability
   
   # Check CloudWatch agent pods
   kubectl get pods -n amazon-cloudwatch
   
   # View Container Insights in AWS Console
   # Navigate to CloudWatch → Container Insights → Performance monitoring
   ```

## Application Deployment

The configuration includes a sample application that demonstrates ALB ingress functionality. After deployment:

1. **Get the ALB DNS name:**
   ```bash
   kubectl get ingress sample-app-ingress
   ```

2. **Access the application:**
   Open the ALB DNS name in your browser

## Cost Monitoring

Expected monthly costs:
- **EKS Control Plane**: ~$73/month
- **1x t3.small Spot Instance**: ~$5-7/month (up to 90% off on-demand)
- **NAT Gateway**: ~$32/month
- **Application Load Balancer**: ~$16/month
- **EBS Storage (20GB)**: ~$2/month
- **CloudWatch Container Insights**: ~$2-5/month (depends on log volume and metrics)

**Total estimated cost**: ~$130-135/month

> **Note**: Container Insights adds minimal cost but provides significant value for monitoring and troubleshooting. You can disable it by setting `enable_container_insights = false` in your terraform.tfvars.

