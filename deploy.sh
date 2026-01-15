#!/bin/bash

# Script de gestion AlgoHive
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="algohive"

case "$1" in
  install|deploy)
    echo -e "${BLUE}Déploiement d'AlgoHive...${NC}"
    kubectl apply -k .
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
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           URLS D'ACCÈS                   ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} Frontend:   http://$NODE_IP:30000       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} API:        http://$NODE_IP:30080       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} BeeHub:     http://$NODE_IP:30082       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} Prometheus: http://$NODE_IP:30090       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} Grafana:    http://$NODE_IP:30030       ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    ;;
    
  *)
    echo "Usage: $0 {install|status|logs|restart|delete|urls}"
    echo ""
    echo "  install   - Déployer AlgoHive"
    echo "  status    - Voir l'état des pods/services"
    echo "  logs      - Voir les logs (ex: $0 logs algohive-server)"
    echo "  restart   - Redémarrer un service"
    echo "  delete    - Supprimer AlgoHive"
    echo "  urls      - Afficher les URLs d'accès"
    ;;
esac
