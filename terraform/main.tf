# =============================================================================
# main.tf — AWS Provider + Remote State (S3 + DynamoDB Locking)
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state: keeps tfstate out of Git (SOC2 best practice)
  # Uncomment and configure after creating the S3 bucket manually
  # backend "s3" {
  #   bucket         = "dckap-tfstate-432004895733"
  #   key            = "devops-platform/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "dckap-tf-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "dckap-devops-platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "krishnaprasad"
    }
  }
}

# ---------------------------------------------------------------------------
# Input Variables
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1" # Mumbai
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Your Route 53 hosted zone domain"
  type        = string
  default     = "devops.example.com"
}

variable "docker_image" {
  description = "Docker image for the application"
  type        = string
  default     = "krishnajune2000/hospital-app:latest"
}

variable "db_password" {
  description = "RDS master password — store in AWS Secrets Manager or GitHub Secrets"
  type        = string
  sensitive   = true
  default     = "ChangeMeStr0ng!"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "alb_dns_name" {
  description = "Application Load Balancer DNS"
  value       = aws_lb.app_alb.dns_name
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint (private)"
  value       = aws_db_instance.mysql_rds.endpoint
  sensitive   = true
}
