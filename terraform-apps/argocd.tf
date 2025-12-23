# ArgoCD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  create_namespace = false

  values = [
    yamlencode({
      server = {
        ingress = { enabled = false }
        extraArgs = ["--insecure"]
        service = { type = "ClusterIP" }

        resources = {
          limits = { memory = "512Mi", cpu = "500m" }
          requests = { memory = "256Mi", cpu = "100m" }
        }
      }

      controller = {
        resources = {
          limits = { memory = "2Gi", cpu = "1000m" }
          requests = { memory = "1Gi", cpu = "500m" }
        }
      }

      repoServer = {
        resources = {
          limits = { memory = "1Gi", cpu = "1000m" }
          requests = { memory = "512Mi", cpu = "250m" }
        }
      }

      configs = {
        params = {
          "server.insecure" = true
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
        }
        cm = {
          "application.resourceTrackingMethod" = "annotation"
          "timeout.reconciliation" = "180s"
        }
      }
    })
  ]

  depends_on = [
    kubectl_manifest.karpenter_nodepool_default,
    helm_release.aws_load_balancer_controller
  ]
}

# ArgoCD Image Updater
resource "helm_release" "argocd_image_updater" {
  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = "0.11.0"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      config = {
        argocd = {
          serverAddress = "http://argocd-server.argocd.svc.cluster.local"
          insecure      = true
          plaintext     = true
        }
      }
    })
  ]

  depends_on = [helm_release.argocd]
}

# Root Application (App of Apps)
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = templatefile("${path.module}/../argocd/bootstrap/root-app.yaml", {
    repo_url = var.git_repo_url
    revision = var.git_revision
  })

  depends_on = [
    helm_release.argocd
  ]
}
