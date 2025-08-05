#!/bin/bash

# EKS Cluster Deployment Script
# This script automates the deployment of the minimal EKS cluster

set -e

echo "Starting EKS cluster deployment..."

# Check prerequisites
echo "Checking prerequisites..."

commands=("tofu" "aws" "kubectl")
for cmd in "${commands[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: $cmd is not installed. Please install it first."
        exit 1
    fi
done

echo "All prerequisites are installed"

# Initialize OpenTofu
echo "Initializing OpenTofu..."
tofu init
echo "OpenTofu initialized"

# Plan deployment
echo "Planning deployment..."
tofu plan -out=tfplan
echo "Plan created"

echo "Review the plan above. Continue? (y/N)"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 1
fi

# Apply configuration
echo "Applying configuration..."
tofu apply tfplan
echo "Infrastructure deployed"

# Configure kubectl
echo "Configuring kubectl..."

# Get cluster name and region from outputs
CLUSTER_NAME=$(tofu output -raw cluster_name)
AWS_REGION=$(tofu output -raw vpc_id | cut -d: -f4)

aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
echo "kubectl configured"

# Verify deployment
echo "Verifying deployment..."

echo "Checking cluster status..."
kubectl cluster-info

echo "Checking nodes..."
kubectl get nodes

echo "Checking AWS Load Balancer Controller..."
kubectl get pods -n aws-load-balancer-controller

echo "Checking sample application..."
kubectl get deployment sample-app
kubectl get service sample-app-service
kubectl get ingress sample-app-ingress

echo "Verification complete"

# Get ALB URL
echo "Getting Application Load Balancer URL..."

# Wait for ALB to be provisioned
echo "Waiting for ALB to be ready (this may take a few minutes)..."
kubectl wait --for=condition=Ready ingress/sample-app-ingress --timeout=300s

ALB_URL=$(kubectl get ingress sample-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -n "$ALB_URL" ]; then
    echo "Sample application is available at: http://$ALB_URL"
else
    echo "ALB is still being provisioned. Check later with:"
    echo "kubectl get ingress sample-app-ingress"
fi

# Display summary
echo ""
echo "EKS cluster deployment completed!"
echo ""
echo "Cluster Information:"
echo "Cluster Name: $(tofu output -raw cluster_name)"
echo "Cluster Endpoint: $(tofu output -raw cluster_endpoint)"
echo "Region: $(tofu output -raw vpc_id | cut -d: -f4)"
echo ""
echo "Useful Commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl get ingress"
echo ""
echo "To destroy the cluster:"
echo "  tofu destroy"
echo ""
