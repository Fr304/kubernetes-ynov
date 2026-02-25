#!/bin/bash
# ============================================================
# setup-master.sh — Initialisation du nœud master kubeadm
# Usage  : sudo bash kubeadm/setup-master.sh
# Prérequis : Ubuntu 22.04, exécuté en root
# ============================================================
set -euo pipefail

# --- Couleurs -----------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
die()  { echo -e "${RED}  ✗ ERREUR :${NC} $*" >&2; exit 1; }

# --- Paramètres ---------------------------------------------
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Charger les variables du cluster (cluster.env)
CLUSTER_ENV="${REPO_DIR}/cluster.env"
if [[ -f "$CLUSTER_ENV" ]]; then
  set -a; source "$CLUSTER_ENV"; set +a
else
  warn "cluster.env introuvable, utilisation des valeurs par défaut"
fi

K8S_VERSION="${K8S_VERSION:-1.30.14-1.1}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-2.2.0-2~ubuntu.22.04~jammy}"
MASTER_IP="${MASTER_IP:-192.168.1.142}"
MASTER_HOSTNAME="${MASTER_HOSTNAME:-ubuntu-kubernetes-master}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.96.0.0/12}"
CLUSTER_DNS="${CLUSTER_DNS:-10.96.0.10}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"

# ============================================================
echo -e "\n${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     SETUP MASTER — AlgoHive K8s Cluster      ║${NC}"
echo -e "${BOLD}║     Kubernetes v1.30.14 — containerd 2.2.0   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}\n"

# --- Vérifications préalables -------------------------------
[[ $EUID -eq 0 ]] || die "Ce script doit être exécuté en root (sudo)"
[[ "$(lsb_release -rs 2>/dev/null)" == "22.04" ]] || \
  warn "OS non testé (attendu: Ubuntu 22.04)"

# --- Étape 1 : Désactiver le swap ---------------------------
log "Étape 1/8 — Désactivation du swap"
swapoff -a
sed -i '/\sswap\s/d' /etc/fstab
ok "Swap désactivé"

# --- Étape 2 : Modules noyau --------------------------------
log "Étape 2/8 — Chargement des modules noyau"
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
ok "Modules overlay et br_netfilter chargés"

# --- Étape 3 : Paramètres sysctl ----------------------------
log "Étape 3/8 — Configuration des paramètres sysctl"
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null
ok "Paramètres réseau noyau appliqués"

# --- Étape 4 : Containerd -----------------------------------
log "Étape 4/8 — Installation de containerd ${CONTAINERD_VERSION}"
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq containerd.io="${CONTAINERD_VERSION}"
ok "containerd ${CONTAINERD_VERSION} installé"

# Configurer SystemdCgroup
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd --quiet
ok "containerd configuré (SystemdCgroup=true)"

# --- Étape 5 : kubeadm / kubelet / kubectl ------------------
log "Étape 5/8 — Installation de kubeadm/kubelet/kubectl v${K8S_VERSION}"
apt-get install -y -qq apt-transport-https ca-certificates curl gpg

if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y -qq \
  kubelet="${K8S_VERSION}" \
  kubeadm="${K8S_VERSION}" \
  kubectl="${K8S_VERSION}"
apt-mark hold kubelet kubeadm kubectl > /dev/null
ok "kubeadm, kubelet, kubectl ${K8S_VERSION} installés et figés"

# --- Étape 6 : kubeadm init ---------------------------------
log "Étape 6/8 — Initialisation du cluster (kubeadm init)"
KUBEADM_TPL="${REPO_DIR}/kubeadm/kubeadm-config.yaml"
[[ -f "$KUBEADM_TPL" ]] || die "Fichier introuvable : $KUBEADM_TPL"

# Rendre le template kubeadm-config avec les variables de cluster.env
KUBEADM_CONFIG=$(mktemp /tmp/kubeadm-config-XXXXXX.yaml)
envsubst < "$KUBEADM_TPL" > "$KUBEADM_CONFIG"
log "Config rendue : ${KUBEADM_CONFIG} (MASTER_IP=${MASTER_IP}, MASTER_HOSTNAME=${MASTER_HOSTNAME})"

kubeadm init --config "$KUBEADM_CONFIG" --upload-certs
rm -f "$KUBEADM_CONFIG"
ok "Cluster initialisé"

# --- Étape 7 : Configurer kubectl ---------------------------
log "Étape 7/8 — Configuration de kubectl"

# Pour root (nécessaire pour les étapes suivantes du script)
KUBE_DIR="/root/.kube"
mkdir -p "$KUBE_DIR"
cp /etc/kubernetes/admin.conf "$KUBE_DIR/config"
chown 0:0 "$KUBE_DIR/config"
ok "kubectl configuré pour root → ${KUBE_DIR}/config"

# Pour l'utilisateur non-root qui a lancé sudo (ex: ubuntu)
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  USER_KUBE_DIR="${USER_HOME}/.kube"
  mkdir -p "$USER_KUBE_DIR"
  cp /etc/kubernetes/admin.conf "$USER_KUBE_DIR/config"
  chown "$(id -u "$SUDO_USER"):$(id -g "$SUDO_USER")" "$USER_KUBE_DIR/config"
  ok "kubectl configuré pour ${SUDO_USER} → ${USER_KUBE_DIR}/config"
  warn "Utilisez 'kubectl' sans sudo depuis le compte ${SUDO_USER}"
fi

# Activer l'autocomplétion
if [[ -f /etc/bash_completion ]]; then
  kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true
fi

# --- Étape 8 : Flannel CNI ----------------------------------
log "Étape 8/8 — Déploiement de Flannel (CNI)"
FLANNEL_DIR="${REPO_DIR}/kube-flannel"
[[ -d "$FLANNEL_DIR" ]] || die "Dossier introuvable : $FLANNEL_DIR"

kubectl apply -f "$FLANNEL_DIR/"
log "Attente de Flannel (timeout 120s)..."
kubectl wait --namespace kube-flannel \
  --for=condition=ready pod \
  --selector=app=flannel \
  --timeout=120s
ok "Flannel prêt"

# --- Résumé -------------------------------------------------
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                 MASTER INITIALISÉ !                      ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC} IP master  : ${MASTER_IP}"
echo -e "${BOLD}║${NC} Pod CIDR   : ${POD_CIDR}"
echo -e "${BOLD}║${NC}"
echo -e "${BOLD}║${NC} Commande pour joindre les workers :"
echo -e "${BOLD}║${NC}   ${YELLOW}${JOIN_CMD}${NC}"
echo -e "${BOLD}║${NC}"
echo -e "${BOLD}║${NC} Vérification :"
echo -e "${BOLD}║${NC}   kubectl get nodes"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Prochaine étape :${NC} exécuter ${BOLD}setup-worker.sh${NC} sur chaque worker,"
echo -e "puis continuer avec ${BOLD}../install-all.sh${NC}"
