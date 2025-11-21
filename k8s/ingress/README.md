# Ingress Configuration - Single ALB

This directory contains Ingress resources that share a **single Application Load Balancer (ALB)** for multiple services.

## How It Works

### Single ALB via Group Annotation

Both Ingresses use the **same group name** to share one ALB:

```yaml
# ArgoCD Ingress (argocd namespace)
annotations:
  alb.ingress.kubernetes.io/group.name: cdc-platform  # ← Same group
  alb.ingress.kubernetes.io/group.order: '1'           # ← Lower order = evaluated first

# Flink Ingress (flink namespace)
annotations:
  alb.ingress.kubernetes.io/group.name: cdc-platform  # ← Same group
  alb.ingress.kubernetes.io/group.order: '2'           # ← Higher order
```

**Result:** AWS Load Balancer Controller creates **1 ALB** with multiple listener rules:
```
Single ALB
├─ argocd.democloud.click → ArgoCD Service (argocd namespace)
└─ flink.democloud.click → Flink Service (flink namespace)
```

### Host-based Routing

Each Ingress uses a different hostname:
- `argocd.democloud.click` → Routes to ArgoCD
- `flink.democloud.click` → Routes to Flink

ALB uses SNI (Server Name Indication) to route traffic based on hostname.

---

## Declarative Deployment

### Option 1: Direct kubectl Apply

```bash
# Apply Ingresses
kubectl apply -f k8s/ingress/ingress-argocd-flink.yaml

# Or use Kustomize
kubectl apply -k k8s/ingress/
```

### Option 2: ArgoCD GitOps (Recommended)

Deploy via ArgoCD for continuous sync:

```bash
# Apply ArgoCD application
kubectl apply -f k8s/argocd/apps/ingress.yaml
```

This creates an ArgoCD app that:
- Watches `k8s/ingress/` directory
- Auto-syncs on Git changes
- Self-heals if manually modified

---

## Verification

### Check Ingresses

```bash
# List all Ingresses
kubectl get ingress -A

# Expected output:
# NAMESPACE   NAME              CLASS   HOSTS                      ADDRESS                                 PORTS
# argocd      argocd-ingress    <none>  argocd.democloud.click     k8s-cdcplatf-abc123.elb.amazonaws.com  80, 443
# flink       flink-ingress     <none>  flink.democloud.click      k8s-cdcplatf-abc123.elb.amazonaws.com  80, 443
#                                                                   ↑ Same ALB address!
```

### Check ALB

```bash
# List ALBs (should see only 1)
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-cdcplatf`)].LoadBalancerName'

# Check listener rules
kubectl describe ingress argocd-ingress -n argocd
kubectl describe ingress flink-ingress -n flink
```

### Test Access

```bash
# Test ArgoCD
curl -I https://argocd.democloud.click

# Test Flink
curl -I https://flink.democloud.click

# Both should return 200 OK (or 301 redirect to HTTPS)
```

---

## Customization

### Add IP Whitelisting

Restrict access to your IP only:

```yaml
annotations:
  alb.ingress.kubernetes.io/inbound-cidrs: "1.2.3.4/32"  # Your public IP
```

Get your IP:
```bash
curl https://ifconfig.me
```

### Add More Services

To add a new service (e.g., Grafana):

1. Create new Ingress file: `k8s/ingress/ingress-grafana.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/group.name: cdc-platform       # ← Same group!
    alb.ingress.kubernetes.io/group.order: '3'               # ← Next order
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:... # Same cert
spec:
  rules:
    - host: grafana.democloud.click
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: prometheus-operator-grafana
                port:
                  number: 80
```

2. Apply:
```bash
kubectl apply -f k8s/ingress/ingress-grafana.yaml
```

3. Update DNS:
```bash
# Add ALIAS record: grafana.democloud.click → Same ALB
```

**No additional LoadBalancer cost!** Same ALB handles all services.

---

## Troubleshooting

### Two ALBs Created

**Problem:** You see 2 ALBs instead of 1.

**Cause:** Missing or mismatched `group.name` annotation.

**Fix:**
```bash
# Delete both Ingresses
kubectl delete ingress argocd-ingress -n argocd
kubectl delete ingress flink-ingress -n flink

# Wait for ALBs to be deleted (~2 min)
sleep 120

# Verify both Ingresses have matching group.name
grep "group.name" k8s/ingress/ingress-argocd-flink.yaml

# Should show:
#   alb.ingress.kubernetes.io/group.name: cdc-platform
#   alb.ingress.kubernetes.io/group.name: cdc-platform

# Reapply
kubectl apply -f k8s/ingress/ingress-argocd-flink.yaml
```

### ALB Not Provisioning

```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Common issues:
# - ALB controller not installed
# - IAM permissions missing
# - Invalid certificate ARN
```

### 502 Bad Gateway

**Cause:** Services are ClusterIP but pods aren't ready.

```bash
# Check pods
kubectl get pods -n argocd
kubectl get pods -n flink

# Check services
kubectl get svc argocd-server -n argocd
kubectl get svc flink-jobmanager -n flink

# Ensure services are ClusterIP and pods are Running
```

### SSL Certificate Issues

```bash
# Verify certificate ARN is correct
aws acm list-certificates --region us-east-1

# Verify certificate is ISSUED (not PENDING_VALIDATION)
aws acm describe-certificate --certificate-arn <YOUR_ARN>
```

---

## Cost Comparison

| Setup | LoadBalancers | Cost/Month | Annual |
|-------|---------------|------------|--------|
| **Before** (2 LBs) | ArgoCD LB + Flink LB | $32 | $384 |
| **After** (1 ALB) | Single shared ALB | $16 | $192 |
| **Savings** | - | **$16/month** | **$192/year** |

Plus free SSL certificate from ACM!

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│          Application Load Balancer (ALB)           │
│                                                     │
│  *.democloud.click (ACM Certificate)               │
│                                                     │
│  Listener Rules (Host-based routing):              │
│    - argocd.democloud.click → Target Group 1       │
│    - flink.democloud.click → Target Group 2        │
│                                                     │
└──────────────┬──────────────┬───────────────────────┘
               │              │
               │              │
    ┌──────────▼─────┐   ┌───▼──────────┐
    │  ArgoCD        │   │  Flink       │
    │  Namespace     │   │  Namespace   │
    │                │   │              │
    │  Service:      │   │  Service:    │
    │  ClusterIP     │   │  ClusterIP   │
    │  Port: 80      │   │  Port: 8081  │
    └────────────────┘   └──────────────┘
```

---

## Files in This Directory

- **`ingress-argocd-flink.yaml`** - Main Ingress configuration (both ArgoCD and Flink)
- **`kustomization.yaml`** - Kustomize configuration for easy apply
- **`README.md`** - This file

---

## References

- [AWS Load Balancer Controller - Ingress Groups](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/guide/ingress/annotations/#group.name)
- [AWS Load Balancer Controller - Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/guide/ingress/annotations/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
