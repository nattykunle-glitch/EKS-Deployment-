## Cluster Autoscaler: watches for unschedulable pods and adds nodes
# (up to node_max_size), and removes nodes when they're underutilized
# (down to node_min_size = 1). This is what makes "1 node always on,
# scalable to 4" actually happen.

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  # NEW: annotate the pod's service account with the IRSA role ARN
  # so it authenticates as that role instead of falling back to the
  # node's instance profile (which doesn't have autoscaling perms).
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_autoscaler_irsa_role.iam_role_arn
  }

  depends_on = [
    module.eks,
    module.cluster_autoscaler_irsa_role  # NEW
  ]
}

# AWS Load Balancer Controller: watches Kubernetes Ingress resources
# and provisions a real Application Load Balancer (ALB) in AWS for them.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  depends_on = [
    module.eks,
    kubernetes_service_account.alb_controller
  ]
}