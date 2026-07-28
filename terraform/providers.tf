terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }

  # Recommended: store state remotely instead of locally once you have
  # an S3 bucket + DynamoDB table for locking. Example:
  #
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "hello-world-eks/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

# These providers let Terraform talk to the cluster it just created
# (used for the ALB controller Helm release).
data "aws_eks_cluster" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  config_path = "C:\\Users\\natty\\.kube\\config"
}

provider "helm" {
  kubernetes {
    config_path = "C:\\Users\\natty\\.kube\\config"
  }
}