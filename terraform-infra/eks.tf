module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = "1.33"

  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_kms_key = var.create_eks_kms_key
  encryption_config = {
    provider_key_arn = var.create_eks_kms_key ? null : (var.eks_kms_key_arn != null ? var.eks_kms_key_arn : data.aws_kms_key.eks[0].arn)
    resources        = ["secrets"]
  }
  kms_key_deletion_window_in_days = var.kms_key_deletion_window_in_days

  addons = {
    vpc-cni = {
      most_recent = true
      before_compute = true  # Install VPC CNI before node groups
      resolve_conflicts_on_create = "OVERWRITE"
    }
    kube-proxy = {
      most_recent = true
      before_compute = true
    }
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = [
          # Allow CoreDNS to run on the same nodes as the Karpenter controller
          # for use during cluster creation when Karpenter nodes do not yet exist
          {
            key    = "karpenter.sh/controller"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
      # Pod Identity association handles IAM role binding
      configuration_values = jsonencode({
        controller = {
          tolerations = [
            {
              key      = "karpenter.sh/controller"
              operator = "Exists"
              effect   = "NoSchedule"
            }
          ]
        }
      })
    }
  }

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"] 

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
      }

      taints = {
        # The pods that do not tolerate this taint should run on nodes
        # created by Karpenter
        karpenter = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  node_security_group_tags = {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  }



  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}