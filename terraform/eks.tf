# EKS cluster + managed node group with autoscaling (1 -> 4 nodes),
# using the official community EKS module.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      capacity_type = "ON_DEMAND"
    }
  }

  # Lets the Cluster Autoscaler and ALB Controller manage AWS resources on our behalf
  enable_irsa = true

  tags = {
    Project = var.cluster_name
  }
}

# ECR repository the Jenkins pipeline / GitHub Actions push images to
resource "aws_ecr_repository" "app" {
  name                 = "${var.cluster_name}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
