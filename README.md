# Minimal EKS Cluster with ALB Ingress

This project creates a cost-optimized EKS cluster using OpenTofu with the AWS Load Balancer Controller for ingress.

## Cost Optimization Features

- **Dual Availability Zone**: Minimum required for EKS (2 AZs)
- **Spot Instances**: Up to 90% cost savings on EC2 instances
- **Minimal Node Group**: 1-2 t3.small instances
- **Single NAT Gateway**: Shared across all private subnets
- **Minimal Storage**: 20GB GP3 volumes
- **Resource Limits**: Conservative CPU/memory allocation

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

**Total estimated cost**: ~$128-130/month

