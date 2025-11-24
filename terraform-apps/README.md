# Terraform Applications Workspace

This workspace deploys platform services and operators on top of the infrastructure:

## Components

- **Karpenter NodePools**: Defines node provisioning policies for workloads
- **Strimzi Kafka Operator**: Manages Kafka clusters
- **ArgoCD**: GitOps continuous delivery
- **ArgoCD Image Updater**: Automated image updates
- **AWS Load Balancer Controller**: Manages ALB for ingress
- **Route53 DNS**: Automated DNS record management
- **Namespaces**: kafka, argocd, flink, consumers

## Prerequisites

1. Infrastructure workspace must be deployed first (`terraform-infra/`)
2. ACM certificate created for `*.democloud.click`
3. Route53 hosted zone for `democloud.click`
4. Update `terraform.tfvars` with:
   - `git_repo_url` (your repository)
   - `certificate_arn` (from ACM)

## Usage

### Initialize

```bash
terraform init
```

### Plan

```bash
terraform plan -out=tfplan
```

### Apply

```bash
terraform apply tfplan
```

This takes approximately 5-10 minutes to complete.

### Verify

```bash
# Check worker nodes (Karpenter creates them)
kubectl get nodes

# Check NodePools
kubectl get nodepools

# Check operators
kubectl get pods -n kafka
kubectl get pods -n argocd

# Check ALB Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check ArgoCD applications
kubectl get applications -n argocd
```

## What Gets Deployed

1. **Karpenter NodePools**: Worker nodes will appear after this completes
2. **Strimzi Operator**: Ready to deploy Kafka clusters
3. **ArgoCD**: GitOps engine with initial root application
4. **AWS Load Balancer Controller**: Creates ALB from Ingress resources
5. **DNS Records**: argocd.democloud.click and flink.democloud.click

## Accessing ArgoCD

```bash
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access via domain (after DNS propagates)
open https://argocd.democloud.click

# Or port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
open https://localhost:8080
```

## State Management

Reads infrastructure state from `../terraform-infra/terraform.tfstate`.

For production with S3 backend, update `data.tf`:

```hcl
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state"
    key    = "cdc-platform/infra/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## GitOps Workflow

After this workspace is applied, all application changes (Kafka, Flink, consumers) are managed through Git:

```bash
# Edit application manifests
vim argocd/app-manifests/flink/flink-jobmanager.yaml

# Commit and push
git commit -am "Scale Flink JobManager"
git push

# ArgoCD auto-syncs within 3 minutes
```

## Notes

- Worker nodes appear after Karpenter NodePools are created
- ALB creation takes 2-3 minutes after Ingress resources are applied
- DNS propagation can take 5-10 minutes
- ArgoCD root application bootstraps all other applications from Git
