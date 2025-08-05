#!/bin/bash

# Terraform/OpenTofu State Backend Cleanup Script
# This script removes the S3 bucket and DynamoDB table used for Terraform state

set -e

# Configuration variables
AWS_REGION="us-west-2"
PROFILE=""

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --region REGION          AWS region (default: us-west-2)"
    echo "  -p, --profile PROFILE        AWS profile to use"
    echo "  -f, --force                  Skip confirmation prompts"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --region us-east-1 --profile my-aws-profile"
}

# Parse command line arguments
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
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

# Get current backend configuration from backend.tf
if [ -f "backend.tf" ]; then
    BUCKET_NAME=$(grep 'backend_bucket_name' backend.tf | sed 's/.*= "//' | sed 's/".*//' || echo "")
    DYNAMODB_TABLE=$(grep 'backend_table' backend.tf | sed 's/.*= "//' | sed 's/".*//' || echo "")
else
    echo "ERROR: backend.tf file not found. Cannot determine backend resources."
    echo "Please run this script from the directory containing backend.tf"
    exit 1
fi

if [ -z "$BUCKET_NAME" ] || [ -z "$DYNAMODB_TABLE" ]; then
    echo "ERROR: Could not parse backend configuration from backend.tf"
    exit 1
fi

echo "WARNING: DANGER: This will permanently delete your Terraform state backend!"
echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo "Region: $AWS_REGION"
echo ""

if [ "$FORCE" = false ]; then
    echo "Make sure you have:"
    echo "  1. Backed up any important state files"
    echo "  2. Destroyed all infrastructure managed by this state"
    echo "  3. Migrated to local state if needed"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# Function to empty and delete S3 bucket
cleanup_s3_bucket() {
    echo "Checking if S3 bucket exists: $BUCKET_NAME"
    
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" $AWS_CLI_PROFILE --region "$AWS_REGION" 2>/dev/null; then
        echo "WARNING: S3 bucket $BUCKET_NAME does not exist or is not accessible"
        return 0
    fi
    
    echo "Emptying S3 bucket: $BUCKET_NAME"
    aws s3 rm "s3://$BUCKET_NAME" --recursive $AWS_CLI_PROFILE --region "$AWS_REGION"
    
    echo "Deleting S3 bucket: $BUCKET_NAME"
    aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" $AWS_CLI_PROFILE
    
    echo "S3 bucket deleted: $BUCKET_NAME"
}

# Function to delete DynamoDB table
cleanup_dynamodb_table() {
    echo "Checking if DynamoDB table exists: $DYNAMODB_TABLE"
    
    if ! aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" $AWS_CLI_PROFILE &> /dev/null; then
        echo "WARNING: DynamoDB table $DYNAMODB_TABLE does not exist or is not accessible"
        return 0
    fi
    
    echo "Deleting DynamoDB table: $DYNAMODB_TABLE"
    aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" $AWS_CLI_PROFILE
    
    echo "Waiting for DynamoDB table to be deleted..."
    aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" $AWS_CLI_PROFILE
    
    echo "DynamoDB table deleted: $DYNAMODB_TABLE"
}

# Function to update backend configuration to local
update_backend_to_local() {
    echo "Updating backend configuration to local state..."
    
    cat > backend.tf << 'EOF'
# Local backend configuration
# Remote state backend has been removed

# Uncomment the block below to re-enable remote state:
# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "eks-cluster/terraform.tfstate"
#     region         = "us-west-2"
#     dynamodb_table = "terraform-state-lock"
#     encrypt        = true
#   }
# }

# To set up a new backend, run: ./setup-backend.sh
EOF
    
    echo "Backend configuration updated to use local state"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "Backend cleanup completed!"
    echo ""
    echo "Resources Removed:"
    echo "  - S3 Bucket:      $BUCKET_NAME"
    echo "  - DynamoDB Table: $DYNAMODB_TABLE"
    echo ""
    echo "Important Notes:"
    echo "  • Terraform state is now local (terraform.tfstate)"
    echo "  • Remote state history has been permanently deleted"
    echo "  • You can set up a new backend with: ./setup-backend.sh"
    echo ""
    echo "Next Steps:"
    echo "  1. Run 'tofu init' to reinitialize with local backend"
    echo "  2. Verify your infrastructure state with 'tofu plan'"
    echo "  3. Set up a new remote backend if needed"
}

# Main execution
main() {
    echo "Cleaning up Terraform state backend..."
    echo ""
    
    # Check AWS credentials
    if ! aws sts get-caller-identity $AWS_CLI_PROFILE &> /dev/null; then
        echo "ERROR: AWS credentials are not configured or invalid."
        exit 1
    fi
    
    cleanup_s3_bucket
    cleanup_dynamodb_table
    update_backend_to_local
    display_cleanup_summary
}

# Run the script
main "$@"
