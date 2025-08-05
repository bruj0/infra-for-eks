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

## Adding HTTPS (Optional)

To enable HTTPS, you need an SSL certificate. Here are your options:

### Option 1: AWS Certificate Manager (ACM) - Recommended
1. **Request a certificate in ACM:**
   ```bash
   aws acm request-certificate --domain-name yourdomain.com --validation-method DNS
   ```

2. **Add certificate ARN to ingress:**
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
     alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
     alb.ingress.kubernetes.io/ssl-redirect: "443"
   ```

### Option 2: Self-Signed Certificate (Development Only)
```bash
# Create a self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt

# Create Kubernetes secret
kubectl create secret tls my-tls-secret --key tls.key --cert tls.crt

# Add to ingress:
spec:
  tls:
  - hosts:
    - yourdomain.com
    secretName: my-tls-secret
```

## Cost Monitoring

Expected monthly costs:
- **EKS Control Plane**: ~$73/month
- **1x t3.small Spot Instance**: ~$5-7/month (up to 90% off on-demand)
- **NAT Gateway**: ~$32/month
- **Application Load Balancer**: ~$16/month
- **EBS Storage (20GB)**: ~$2/month

**Total estimated cost**: ~$128-130/month

## Cleanup

To avoid ongoing charges, destroy the infrastructure when not needed:

```bash
tofu destroy
```

## Security Considerations

This is a minimal setup for development/testing. For production:

1. Enable private endpoint access only
2. Implement proper RBAC
3. Use encrypted storage
4. Configure network policies
5. Enable logging and monitoring
6. Use dedicated subnets per AZ
7. Implement proper backup strategies

## Troubleshooting

### Common Issues

1. **ALB Controller not working:**
   ```bash
   kubectl logs -n aws-load-balancer-controller deployment/aws-load-balancer-controller
   ```

2. **Nodes not joining cluster:**
   ```bash
   kubectl describe nodes
   ```

3. **Spot instance interruptions:**
   - Check AWS Spot pricing history
   - Consider mixed instance types

### Useful Commands

```bash
# Check cluster status
kubectl cluster-info

# View all resources
kubectl get all -A

# Check ALB controller logs
kubectl logs -n aws-load-balancer-controller -l app.kubernetes.io/name=aws-load-balancer-controller

# View node details
kubectl describe nodes

# Check ingress details
kubectl describe ingress sample-app-ingress
```

## Next Steps

1. Deploy your actual application
2. Configure monitoring (Prometheus/Grafana)
3. Set up CI/CD pipelines
4. Implement cluster autoscaling
5. Add additional security measures
