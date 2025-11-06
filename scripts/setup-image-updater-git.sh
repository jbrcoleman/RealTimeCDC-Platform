#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ArgoCD Image Updater Git Credentials${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "ArgoCD Image Updater needs write access to your Git repository"
echo "to automatically update image tags in kustomization.yaml"
echo ""
echo "Choose authentication method:"
echo "  1) GitHub Personal Access Token (recommended)"
echo "  2) SSH Key"
echo ""
read -p "Enter choice [1-2]: " choice

case $choice in
  1)
    echo ""
    echo -e "${YELLOW}GitHub Personal Access Token Setup${NC}"
    echo ""
    echo "Create a GitHub Personal Access Token (classic) with 'repo' scope:"
    echo "  1. Go to: https://github.com/settings/tokens/new"
    echo "  2. Note: ArgoCD Image Updater"
    echo "  3. Expiration: Set as needed"
    echo "  4. Select scopes: [x] repo (Full control of private repositories)"
    echo "  5. Click 'Generate token'"
    echo "  6. Copy the token (you won't see it again!)"
    echo ""
    read -p "Enter your GitHub username: " GH_USERNAME
    read -sp "Enter your GitHub token: " GH_TOKEN
    echo ""

    # Create secret for ArgoCD
    kubectl create secret generic git-creds \
      --from-literal=username="$GH_USERNAME" \
      --from-literal=password="$GH_TOKEN" \
      --namespace=argocd \
      --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}✓ Git credentials secret created${NC}"
    echo ""

    # Configure Image Updater
    kubectl patch configmap argocd-image-updater-config -n argocd --type merge -p '{"data":{"git.user":"'$GH_USERNAME'","git.email":"'$GH_USERNAME'@users.noreply.github.com"}}'

    # Restart Image Updater to pick up changes
    kubectl rollout restart deployment argocd-image-updater -n argocd
    kubectl rollout status deployment argocd-image-updater -n argocd

    echo -e "${GREEN}✓ Image Updater configured${NC}"
    ;;

  2)
    echo ""
    echo -e "${YELLOW}SSH Key Setup${NC}"
    echo ""
    echo "Ensure you have an SSH key with write access to your repository"
    echo ""
    read -p "Enter path to your SSH private key [~/.ssh/id_rsa]: " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}

    if [ ! -f "$SSH_KEY_PATH" ]; then
      echo -e "${RED}Error: SSH key not found at $SSH_KEY_PATH${NC}"
      exit 1
    fi

    # Create secret for ArgoCD
    kubectl create secret generic git-creds \
      --from-file=sshPrivateKey="$SSH_KEY_PATH" \
      --namespace=argocd \
      --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}✓ Git credentials secret created${NC}"
    echo ""

    # Add GitHub to known hosts
    kubectl patch configmap argocd-image-updater-ssh-config -n argocd --type merge -p '{"data":{"config":"Host github.com\n  HostName github.com\n  User git\n  IdentityFile ~/.ssh/id_rsa\n  StrictHostKeyChecking no\n"}}'

    # Configure Image Updater
    kubectl patch configmap argocd-image-updater-config -n argocd --type merge -p '{"data":{"git.user":"argocd-image-updater","git.email":"argocd-image-updater@noreply.local"}}'

    # Restart Image Updater to pick up changes
    kubectl rollout restart deployment argocd-image-updater -n argocd
    kubectl rollout status deployment argocd-image-updater -n argocd

    echo -e "${GREEN}✓ Image Updater configured${NC}"
    ;;

  *)
    echo -e "${RED}Invalid choice${NC}"
    exit 1
    ;;
esac

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Ensure git credentials are stored in ArgoCD:"
echo "     kubectl get secret git-creds -n argocd"
echo ""
echo "  2. Push new Docker images to ECR"
echo ""
echo "  3. Image Updater will automatically:"
echo "     - Detect new images in ECR (checks every 2 minutes)"
echo "     - Update kustomization.yaml in your Git repo"
echo "     - Commit changes with message: 'build: automatic image update'"
echo "     - ArgoCD will auto-sync the changes to cluster"
echo ""
echo -e "${YELLOW}Monitor Image Updater:${NC}"
echo "  kubectl logs -l app.kubernetes.io/name=argocd-image-updater -n argocd --follow"
echo ""
