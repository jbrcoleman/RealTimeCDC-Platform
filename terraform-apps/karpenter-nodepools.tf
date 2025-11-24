# Wait for Karpenter CRDs to be available
resource "time_sleep" "wait_for_karpenter_crds" {
  create_duration = "60s"

  triggers = {
    cluster_name = local.cluster_name
  }
}

# EC2NodeClass
resource "kubectl_manifest" "karpenter_ec2_node_class" {
  yaml_body = templatefile("${path.module}/../k8s/karpenter/ec2nodeclass.yaml", {
    cluster_name = local.cluster_name
  })

  depends_on = [time_sleep.wait_for_karpenter_crds]
}

# Default NodePool
resource "kubectl_manifest" "karpenter_nodepool_default" {
  yaml_body = file("${path.module}/../k8s/karpenter/nodepool-default.yaml")

  depends_on = [kubectl_manifest.karpenter_ec2_node_class]
}

# Spot-Optimized NodePool
resource "kubectl_manifest" "karpenter_nodepool_spot" {
  yaml_body = file("${path.module}/../k8s/karpenter/nodepool-spot.yaml")

  depends_on = [kubectl_manifest.karpenter_ec2_node_class]
}
