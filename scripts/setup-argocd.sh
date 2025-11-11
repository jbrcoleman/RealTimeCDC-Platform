#!/bin/bash
set -e

echo "=== Setting up ArgoCD for CDC Platform ==="
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    exit 1
fi

# Install ArgoCD
echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "✓ ArgoCD installed"
echo ""

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd

echo "✓ ArgoCD is ready"
echo ""

# Install ArgoCD Image Updater
echo "Installing ArgoCD Image Updater..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/v0.12.2/manifests/install.yaml

echo "Waiting for Image Updater to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-image-updater -n argocd --timeout=120s

echo "✓ ArgoCD Image Updater installed"
echo ""

# Configure ArgoCD for insecure mode (required for GitHub Codespaces and similar environments)
echo "Configuring ArgoCD for insecure mode..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl wait --for=condition=available --timeout=120s deployment/argocd-server -n argocd

echo "✓ ArgoCD configured for insecure mode"
echo ""

# Get initial admin password
echo "Retrieving ArgoCD initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "==================================================================="
echo "ArgoCD Installation Complete!"
echo "==================================================================="
echo ""
echo "Access ArgoCD UI:"
echo "  1. Port forward: kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "  2. GitHub Codespaces: Go to PORTS tab and open port 8080 in browser"
echo "     Local: Open browser to http://localhost:8080"
echo "  3. Login with:"
echo "     Username: admin"
echo "     Password: $ARGOCD_PASSWORD"
echo ""
echo "Install ArgoCD CLI (optional):"
echo "  macOS:   brew install argocd"
echo "  Linux:   curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
echo ""
echo "Login via CLI:"
echo "  argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure"
echo ""
echo "==================================================================="
echo ""

# Ask if user wants to create the root application
read -p "Do you want to create the root ArgoCD application now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Creating ArgoCD root application..."
    
    # Check if argocd directory exists
    if [ ! -d "argocd/bootstrap" ]; then
        echo "Error: argocd/bootstrap directory not found"
        echo "Please create the ArgoCD application manifests first"
        exit 1
    fi
    
    kubectl apply -f argocd/bootstrap/root-app.yaml
    echo "✓ Root application created"
    echo ""
    echo "View applications:"
    echo "  kubectl get applications -n argocd"
    echo "  Or visit the ArgoCD UI"
fi

echo ""
echo "Next steps:"
echo "1. Configure Image Updater Git credentials:"
echo "   ./scripts/setup-image-updater-git.sh"
echo "2. Create your ArgoCD application definitions in argocd/apps/"
echo "3. Configure your Git repository in ArgoCD"
echo "4. Set up sync policies (auto-sync, self-heal, etc.)"
echo "5. Deploy your CDC platform components!"