locals {
  name     = "blogapp-dev"
  vpc_cidr = "10.10.0.0/16"
  cluster_tags = {
    "kubernetes.io/cluster/blogapp-dev" = "owned"
  }
}
