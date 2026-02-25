#!/bin/bash
# =============================================================================
# install-all.sh — Déploiement complet AlgoHive sur cluster Kubeadm
# Usage : bash install-all.sh
# Prérequis : cluster.env à la racine du repo, kubectl configuré
# =============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Charger cluster.env --------------------------------------------------
CLUSTER_ENV="${SCRIPT_DIR}/cluster.env"
if [[ ! -f "$CLUSTER_ENV" ]]; then
  echo -e "${RED}✗ cluster.env introuvable : $CLUSTER_ENV${NC}"
  exit 1
fi
set -a; source "$CLUSTER_ENV"; set +a

# Vérifier les variables critiques
: "${MASTER_IP:?Variable MASTER_IP manquante dans cluster.env}"
: "${LB_POOL_START:?Variable LB_POOL_START manquante dans cluster.env}"
: "${LB_POOL_END:?Variable LB_POOL_END manquante dans cluster.env}"
: "${DOMAIN_FRONTEND:?Variable DOMAIN_FRONTEND manquante dans cluster.env}"
: "${DOMAIN_API:?Variable DOMAIN_API manquante dans cluster.env}"
: "${DOMAIN_BEEHUB:?Variable DOMAIN_BEEHUB manquante dans cluster.env}"
: "${DOMAIN_GRAFANA:?Variable DOMAIN_GRAFANA manquante dans cluster.env}"
: "${DOMAIN_KUBEVIEW:?Variable DOMAIN_KUBEVIEW manquante dans cluster.env}"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       DÉPLOIEMENT ALGOHIVE SUR KUBERNETES                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Helper : applique un template YAML après substitution des variables
apply_tpl() { envsubst < "$1" | kubectl apply -f -; }

# =============================================================================
# Vérification du cluster
# =============================================================================
echo -e "${BLUE}=== Vérification des prérequis ===${NC}"

if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}✗ Impossible de se connecter au cluster Kubernetes${NC}"
  echo "  → mkdir -p ~/.kube && cp /etc/kubernetes/admin.conf ~/.kube/config"
  exit 1
fi
echo -e "${GREEN}  ✓ Cluster accessible${NC}"

NOT_READY=$(kubectl get nodes --no-headers | grep -v " Ready" | wc -l)
if [ "$NOT_READY" -gt 0 ]; then
  echo -e "${RED}✗ Certains nodes ne sont pas Ready${NC}"
  kubectl get nodes
  exit 1
fi
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo -e "${GREEN}  ✓ $NODE_COUNT node(s) Ready${NC}"

COREDNS_STATUS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$COREDNS_STATUS" == "Pending" ]; then
  echo -e "${RED}✗ CNI non installé (CoreDNS Pending) — installez Flannel d'abord${NC}"
  echo "  → kubectl apply -f kube-flannel/"
  exit 1
fi
echo -e "${GREEN}  ✓ CNI fonctionnel${NC}"
echo ""

# =============================================================================
# 1. MetalLB
# =============================================================================
echo -e "${BLUE}=== 1/5 MetalLB (pool: ${LB_POOL_START}-${LB_POOL_END}) ===${NC}"

if kubectl get ns metallb-system &>/dev/null; then
  echo -e "${YELLOW}  MetalLB déjà installé, skip installation...${NC}"
else
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
  kubectl wait --namespace metallb-system \
    --for=condition=ready pod --selector=app=metallb --timeout=120s
fi

apply_tpl metallb/10-ipaddresspool.yaml
kubectl apply -f metallb/11-l2advertisement.yaml
echo -e "${GREEN}  ✓ MetalLB OK${NC}"
echo ""

# =============================================================================
# 2. Ingress NGINX
# =============================================================================
echo -e "${BLUE}=== 2/5 Ingress NGINX ===${NC}"

if kubectl get ns ingress-nginx &>/dev/null; then
  echo -e "${YELLOW}  Ingress NGINX déjà installé, skip...${NC}"
else
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller --timeout=120s
fi
echo -e "${GREEN}  ✓ Ingress NGINX OK${NC}"
echo ""

# =============================================================================
# 3. Application AlgoHive (Kustomize — sans les ingress)
# =============================================================================
echo -e "${BLUE}=== 3/5 Application AlgoHive ===${NC}"
kubectl apply -k .
echo -e "${GREEN}  ✓ Application déployée${NC}"
echo ""

# =============================================================================
# 4. Ingress (via envsubst — contiennent des variables)
# =============================================================================
echo -e "${BLUE}=== 4/5 Ingress rules (${DOMAIN_FRONTEND}, ${DOMAIN_GRAFANA}, ...) ===${NC}"
apply_tpl services/ingress.yaml
apply_tpl monitoring/grafana-ingress.yaml
apply_tpl kubeview/ingress.yaml
echo -e "${GREEN}  ✓ Ingress rules appliquées${NC}"
echo ""

# =============================================================================
# 5. Attente des pods + Résumé
# =============================================================================
echo -e "${BLUE}=== 5/5 Attente des pods ===${NC}"
sleep 10
kubectl wait --namespace algohive \
  --for=condition=ready pod --all --timeout=300s 2>/dev/null \
  || echo -e "${YELLOW}  Certains pods ne sont pas encore prêts${NC}"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "En attente...")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              DÉPLOIEMENT TERMINÉ !                       ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} IP Ingress : ${YELLOW}${INGRESS_IP}${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC} ${BLUE}Ajoutez dans /etc/hosts :${NC}"
echo -e "${GREEN}║${NC}   ${INGRESS_IP}  ${DOMAIN_FRONTEND}"
echo -e "${GREEN}║${NC}   ${INGRESS_IP}  ${DOMAIN_API}"
echo -e "${GREEN}║${NC}   ${INGRESS_IP}  ${DOMAIN_BEEHUB}"
echo -e "${GREEN}║${NC}   ${INGRESS_IP}  ${DOMAIN_GRAFANA}"
echo -e "${GREEN}║${NC}   ${INGRESS_IP}  ${DOMAIN_KUBEVIEW}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC} ${BLUE}URLs :${NC}"
echo -e "${GREEN}║${NC}   http://${DOMAIN_FRONTEND}"
echo -e "${GREEN}║${NC}   http://${DOMAIN_API}"
echo -e "${GREEN}║${NC}   http://${DOMAIN_GRAFANA}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

kubectl get pods -A | grep -E "metallb-system|ingress-nginx|algohive|monitoring|kubeview" || true
