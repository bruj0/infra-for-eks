# Terraform Backend Configuration
# This file configures remote state storage in S3 with DynamoDB locking

terraform {
  backend "s3" {
    bucket         = "terraform-state-285552317064-eu-north-1"
    key            = "eks-cluster/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

# Local values for reference
locals {
  backend_bucket_name = "terraform-state-285552317064-eu-north-1"
  backend_key         = "eks-cluster/terraform.tfstate"
  backend_region      = "eu-north-1"
  backend_table       = "terraform-state-lock"
}
