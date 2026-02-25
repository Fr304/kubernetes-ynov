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

# =============================================================================
# Prérequis : Vérification du cluster
# =============================================================================
echo -e "${BLUE}=== Vérification des prérequis ===${NC}"
echo ""

# 1. Vérifier kubectl et connexion au cluster
echo -e "${YELLOW}1. Connexion au cluster...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}✗ Impossible de se connecter au cluster Kubernetes${NC}"
    echo "  Vérifiez que kubectl est configuré correctement."
    echo "  → mkdir -p ~/.kube && cp /etc/kubernetes/admin.conf ~/.kube/config"
    exit 1
fi
echo -e "${GREEN}   ✓ Cluster accessible${NC}"

# 2. Vérifier que les nodes sont Ready
echo -e "${YELLOW}2. État des nodes...${NC}"
NOT_READY=$(kubectl get nodes --no-headers | grep -v " Ready" | wc -l)
if [ "$NOT_READY" -gt 0 ]; then
    echo -e "${RED}✗ Certains nodes ne sont pas Ready :${NC}"
    kubectl get nodes
    exit 1
fi
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo -e "${GREEN}   ✓ $NODE_COUNT node(s) Ready${NC}"

# 3. Vérifier le CNI (CoreDNS doit être Running)
echo -e "${YELLOW}3. CNI (Container Network Interface)...${NC}"
COREDNS_STATUS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

if [ "$COREDNS_STATUS" == "Running" ]; then
    echo -e "${GREEN}   ✓ CNI fonctionnel (CoreDNS Running)${NC}"
elif [ "$COREDNS_STATUS" == "Pending" ]; then
    echo -e "${RED}✗ CNI non installé (CoreDNS en Pending)${NC}"
    echo ""
    echo "  Le CNI est requis pour que les pods communiquent."
    echo "  Installez Flannel ou Calico :"
    echo ""
    echo "  # Flannel (simple)"
    echo "  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
    echo ""
    echo "  # Calico (avec Network Policies)"
    echo "  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml"
    echo ""
    echo "  Voir cni/README.md pour plus de détails."
    exit 1
else
    echo -e "${YELLOW}   ⚠ Impossible de vérifier CoreDNS (status: $COREDNS_STATUS)${NC}"
fi

# 4. Vérifier le Pod CIDR
echo -e "${YELLOW}4. Configuration réseau...${NC}"
POD_CIDR=$(kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || echo "Non défini")
echo -e "${GREEN}   ✓ Pod CIDR: $POD_CIDR${NC}"

echo ""
echo -e "${GREEN}✓ Tous les prérequis sont satisfaits${NC}"
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
