#!/bin/bash
# =============================================================================
# Script de déploiement complet pour cluster Kubeadm
# =============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       DÉPLOIEMENT ALGOHIVE SUR KUBERNETES                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Vérification du cluster
echo -e "${YELLOW}Vérification du cluster...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}✗ Impossible de se connecter au cluster Kubernetes${NC}"
    echo "Vérifiez que kubectl est configuré correctement."
    exit 1
fi
echo -e "${GREEN}✓ Cluster accessible${NC}"
echo ""

# =============================================================================
# 1. MetalLB
# =============================================================================
echo -e "${BLUE}=== 1/5 Déploiement MetalLB ===${NC}"

if kubectl get ns metallb-system &>/dev/null; then
    echo -e "${YELLOW}MetalLB déjà installé, skip...${NC}"
else
    echo "Installation de MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml

    echo "Attente des pods MetalLB..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=120s
fi

# Appliquer la configuration IP
echo "Configuration du pool d'IPs..."
kubectl apply -f metallb/10-ipaddresspool.yaml
kubectl apply -f metallb/11-l2advertisement.yaml

echo -e "${GREEN}✓ MetalLB OK${NC}"
echo ""

# =============================================================================
# 2. Ingress NGINX
# =============================================================================
echo -e "${BLUE}=== 2/5 Déploiement Ingress NGINX ===${NC}"

if kubectl get ns ingress-nginx &>/dev/null; then
    echo -e "${YELLOW}Ingress NGINX déjà installé, skip...${NC}"
else
    echo "Installation d'Ingress NGINX..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

    echo "Attente du controller..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s
fi

echo -e "${GREEN}✓ Ingress NGINX OK${NC}"
echo ""

# =============================================================================
# 3. Application Algohive
# =============================================================================
echo -e "${BLUE}=== 3/5 Déploiement Application Algohive ===${NC}"

echo "Déploiement avec Kustomize..."
kubectl apply -k .

echo -e "${GREEN}✓ Application déployée${NC}"
echo ""

# =============================================================================
# 4. Attente des pods
# =============================================================================
echo -e "${BLUE}=== 4/5 Attente des pods ===${NC}"

echo "Attente du démarrage des pods (peut prendre quelques minutes)..."
sleep 10

# Attendre que les pods algohive soient prêts
if kubectl get ns algohive &>/dev/null; then
    kubectl wait --namespace algohive \
        --for=condition=ready pod \
        --all \
        --timeout=300s 2>/dev/null || echo -e "${YELLOW}Certains pods ne sont pas encore prêts${NC}"
fi

echo -e "${GREEN}✓ Pods démarrés${NC}"
echo ""

# =============================================================================
# 5. Résumé
# =============================================================================
echo -e "${BLUE}=== 5/5 Résumé ===${NC}"
echo ""

# Récupérer l'IP de l'Ingress
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "En attente...")

echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              DÉPLOIEMENT TERMINÉ !                       ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} IP Ingress: ${YELLOW}$INGRESS_IP${NC}"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC} ${BLUE}Ajoutez dans /etc/hosts :${NC}                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}   $INGRESS_IP  algohive.local"
echo -e "${GREEN}║${NC}   $INGRESS_IP  api.algohive.local"
echo -e "${GREEN}║${NC}   $INGRESS_IP  beehub.algohive.local"
echo -e "${GREEN}║${NC}   $INGRESS_IP  grafana.algohive.local"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC} ${BLUE}URLs :${NC}                                                   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}   http://algohive.local"
echo -e "${GREEN}║${NC}   http://api.algohive.local"
echo -e "${GREEN}║${NC}   http://grafana.algohive.local"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Afficher l'état des pods
echo -e "${BLUE}État des pods :${NC}"
kubectl get pods -A | grep -E "metallb-system|ingress-nginx|algohive|monitoring" || true
