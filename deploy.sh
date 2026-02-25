#!/bin/bash
# Script de gestion AlgoHive
# Usage : ./deploy.sh {install|status|logs|restart|delete|urls}
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="algohive"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Charger cluster.env
CLUSTER_ENV="${SCRIPT_DIR}/cluster.env"
if [[ -f "$CLUSTER_ENV" ]]; then
  set -a; source "$CLUSTER_ENV"; set +a
fi

# Helper : applique un template YAML après substitution des variables
apply_tpl() { envsubst < "$1" | kubectl apply -f -; }

case "$1" in
  install|deploy)
    echo -e "${BLUE}Déploiement d'AlgoHive...${NC}"
    kubectl apply -k .
    apply_tpl services/ingress.yaml
    apply_tpl monitoring/grafana-ingress.yaml
    apply_tpl kubeview/ingress.yaml
    echo -e "${GREEN}✓ Déploiement lancé !${NC}"
    echo ""
    echo "Attente des pods..."
    sleep 5
    kubectl get pods -n $NAMESPACE
    ;;

  status)
    echo -e "${BLUE}=== PODS ===${NC}"
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
    echo -e "${BLUE}=== SERVICES ===${NC}"
    kubectl get svc -n $NAMESPACE
    echo ""
    echo -e "${BLUE}=== PVC ===${NC}"
    kubectl get pvc -n $NAMESPACE
    ;;

  logs)
    SERVICE=${2:-algohive-server}
    kubectl logs -f deployment/$SERVICE -n $NAMESPACE
    ;;

  restart)
    SERVICE=${2:-algohive-server}
    echo -e "${YELLOW}Redémarrage de $SERVICE...${NC}"
    kubectl rollout restart deployment/$SERVICE -n $NAMESPACE
    ;;

  delete|uninstall)
    echo -e "${RED}Suppression d'AlgoHive...${NC}"
    read -p "Confirmer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      kubectl delete namespace $NAMESPACE
      echo -e "${GREEN}✓ Supprimé${NC}"
    fi
    ;;

  urls)
    INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "En attente...")
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           URLS D'ACCÈS                            ║${NC}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} IP Ingress : ${YELLOW}${INGRESS_IP}${NC}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} Frontend  : http://${DOMAIN_FRONTEND:-algohive.local}"
    echo -e "${BLUE}║${NC} API       : http://${DOMAIN_API:-api.algohive.local}"
    echo -e "${BLUE}║${NC} BeeHub    : http://${DOMAIN_BEEHUB:-beehub.algohive.local}"
    echo -e "${BLUE}║${NC} Grafana   : http://${DOMAIN_GRAFANA:-grafana.frd75.local}"
    echo -e "${BLUE}║${NC} KubeView  : http://${DOMAIN_KUBEVIEW:-kubeview.algohive.local}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} Ajoutez dans /etc/hosts :"
    echo -e "${BLUE}║${NC}   ${INGRESS_IP}  ${DOMAIN_FRONTEND:-algohive.local}"
    echo -e "${BLUE}║${NC}   ${INGRESS_IP}  ${DOMAIN_API:-api.algohive.local}"
    echo -e "${BLUE}║${NC}   ${INGRESS_IP}  ${DOMAIN_BEEHUB:-beehub.algohive.local}"
    echo -e "${BLUE}║${NC}   ${INGRESS_IP}  ${DOMAIN_GRAFANA:-grafana.frd75.local}"
    echo -e "${BLUE}║${NC}   ${INGRESS_IP}  ${DOMAIN_KUBEVIEW:-kubeview.algohive.local}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
    ;;

  *)
    echo "Usage: $0 {install|status|logs|restart|delete|urls}"
    echo ""
    echo "  install   - Déployer AlgoHive (kustomize + ingress envsubst)"
    echo "  status    - Voir l'état des pods/services/PVC"
    echo "  logs      - Voir les logs (ex: $0 logs algohive-server)"
    echo "  restart   - Redémarrer un service"
    echo "  delete    - Supprimer AlgoHive"
    echo "  urls      - Afficher les URLs d'accès"
    ;;
esac
