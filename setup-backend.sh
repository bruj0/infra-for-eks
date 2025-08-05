#!/bin/bash

# OpenTofu State Backend Setup Script
# This script creates an S3 bucket and DynamoDB table for storing OpenTofu state

set -e

# Configuration variables
BUCKET_PREFIX="terraform-state"
DYNAMODB_TABLE="terraform-state-lock"
AWS_REGION="eu-north-1"
PROFILE=""

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -b, --bucket-prefix PREFIX   S3 bucket prefix (default: terraform-state)"
    echo "  -r, --region REGION          AWS region (default: us-west-2)"
    echo "  -t, --table TABLE            DynamoDB table name (default: terraform-state-lock)"
    echo "  -p, --profile PROFILE        AWS profile to use"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --bucket-prefix my-tf-state --region us-east-1 --profile my-aws-profile"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bucket-prefix)
            BUCKET_PREFIX="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -t|--table)
            DYNAMODB_TABLE="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Set AWS CLI profile option
AWS_CLI_PROFILE=""
if [ -n "$PROFILE" ]; then
    AWS_CLI_PROFILE="--profile $PROFILE"
    echo "Using AWS profile: $PROFILE"
fi

# Generate unique bucket name
ACCOUNT_ID=$(aws sts get-caller-identity $AWS_CLI_PROFILE --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: Failed to get AWS account ID. Please check your AWS credentials."
    exit 1
fi

BUCKET_NAME="${BUCKET_PREFIX}-${ACCOUNT_ID}-${AWS_REGION}"

echo "Starting Terraform state backend setup..."
echo "AWS Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity $AWS_CLI_PROFILE &> /dev/null; then
    echo "ERROR: AWS credentials are not configured or invalid."
    echo "Please run 'aws configure' or set up your credentials."
    exit 1
fi

echo "AWS credentials validated"

# Function to check if S3 bucket exists
bucket_exists() {
    aws s3api head-bucket --bucket "$BUCKET_NAME" $AWS_CLI_PROFILE --region "$AWS_REGION" 2>/dev/null
}

# Function to create S3 bucket
create_s3_bucket() {
    echo "Creating S3 bucket: $BUCKET_NAME"
    
    if bucket_exists; then
        echo "WARNING: S3 bucket $BUCKET_NAME already exists"
        return 0
    fi
    
    # Create bucket with appropriate location constraint
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            $AWS_CLI_PROFILE
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION" \
            $AWS_CLI_PROFILE
    fi
    
    echo "S3 bucket created: $BUCKET_NAME"
}

# Function to configure S3 bucket
configure_s3_bucket() {
    echo "Configuring S3 bucket security settings..."
    
    # Enable versioning
    echo "Enabling S3 bucket versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION" \
        $AWS_CLI_PROFILE
    
    # Enable server-side encryption
    echo "Enabling S3 bucket encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }' \
        --region "$AWS_REGION" \
        $AWS_CLI_PROFILE
    
    # Block public access
    echo "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region "$AWS_REGION" \
        $AWS_CLI_PROFILE
    
    echo "S3 bucket security configured"
}

# Function to check if DynamoDB table exists
table_exists() {
    aws dynamodb describe-table \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION" \
        $AWS_CLI_PROFILE &> /dev/null
}

# Function to create DynamoDB table
create_dynamodb_table() {
    echo "Creating DynamoDB table: $DYNAMODB_TABLE"
    
    if table_exists; then
        echo "WARNING: DynamoDB table $DYNAMODB_TABLE already exists"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions \
            AttributeName=LockID,AttributeType=S \
        --key-schema \
            AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" \
        $AWS_CLI_PROFILE
    
    echo "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION" \
        $AWS_CLI_PROFILE
    
    echo "DynamoDB table created: $DYNAMODB_TABLE"
}

# Function to update backend configuration
update_backend_config() {
    echo "Updating backend configuration..."
    
    # Update backend.tf file
    cat > backend.tf << EOF
# Terraform Backend Configuration
# This file configures remote state storage in S3 with DynamoDB locking

terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "eks-cluster/terraform.tfstate"
    region         = "$AWS_REGION"
    dynamodb_table = "$DYNAMODB_TABLE"
    encrypt        = true
  }
}

# Local values for reference
locals {
  backend_bucket_name = "$BUCKET_NAME"
  backend_key         = "eks-cluster/terraform.tfstate"
  backend_region      = "$AWS_REGION"
  backend_table       = "$DYNAMODB_TABLE"
}
EOF
    
    echo "Backend configuration updated in backend.tf"
}

# Function to display summary
display_summary() {
    echo ""
    echo "Terraform state backend setup completed!"
    echo ""
    echo "Backend Configuration:"
    echo "  S3 Bucket:      $BUCKET_NAME"
    echo "  DynamoDB Table: $DYNAMODB_TABLE"
    echo "  Region:         $AWS_REGION"
    echo "  State Key:      eks-cluster/terraform.tfstate"
    echo ""
    echo "Security Features:"
    echo "  - S3 Bucket Versioning Enabled"
    echo "  - S3 Server-Side Encryption (AES256)"
    echo "  - S3 Public Access Blocked"
    echo "  - DynamoDB State Locking"
    echo ""
    echo "Next Steps:"
    echo "  1. Run 'tofu init' to initialize the backend"
    echo "  2. When prompted, type 'yes' to migrate existing state"
    echo "  3. Deploy your infrastructure with 'tofu apply'"
    echo ""
    echo "To clean up backend resources:"
    echo "  aws s3 rm s3://$BUCKET_NAME --recursive"
    echo "  aws s3api delete-bucket --bucket $BUCKET_NAME --region $AWS_REGION"
    echo "  aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION"
}

# Main execution
main() {
    echo "Setting up Terraform state backend..."
    echo ""
    
    create_s3_bucket
    configure_s3_bucket
    create_dynamodb_table
    update_backend_config
    display_summary
}

# Run the script
main "$@"

# To clean up backend resources:
#   aws s3 rm s3://terraform-state-285552317064-eu-north-1 --recursive
#   aws s3api delete-bucket --bucket terraform-state-285552317064-eu-north-1 --region eu-north-1
#   aws dynamodb delete-table --table-name terraform-state-lock --region eu-north-1