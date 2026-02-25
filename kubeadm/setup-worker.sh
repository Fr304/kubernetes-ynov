#!/bin/bash
# ============================================================
# setup-worker.sh — Préparation et jonction d'un nœud worker
# Usage  : sudo bash kubeadm/setup-worker.sh
# Prérequis : Ubuntu 22.04, exécuté en root
#
# Le script prépare le nœud (swap, modules, sysctl, containerd,
# packages) puis demande la commande "kubeadm join" à coller
# (récupérée sur le master avec : kubeadm token create --print-join-command)
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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Charger les variables du cluster (cluster.env)
CLUSTER_ENV="${REPO_DIR}/cluster.env"
[[ -f "$CLUSTER_ENV" ]] && source "$CLUSTER_ENV" || warn "cluster.env introuvable, utilisation des valeurs par défaut"

K8S_VERSION="${K8S_VERSION:-1.30.14-1.1}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-2.2.0-2~ubuntu.22.04~jammy}"
MASTER_IP="${MASTER_IP:-192.168.1.142}"

# ============================================================
echo -e "\n${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     SETUP WORKER — AlgoHive K8s Cluster      ║${NC}"
echo -e "${BOLD}║     Kubernetes v1.30.14 — containerd 2.2.0   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}\n"

# --- Vérifications préalables -------------------------------
[[ $EUID -eq 0 ]] || die "Ce script doit être exécuté en root (sudo)"
[[ "$(lsb_release -rs 2>/dev/null)" == "22.04" ]] || \
  warn "OS non testé (attendu: Ubuntu 22.04)"

HOSTNAME=$(hostname)
log "Préparation du nœud worker : ${BOLD}${HOSTNAME}${NC}"

# --- Étape 1 : Désactiver le swap ---------------------------
log "Étape 1/6 — Désactivation du swap"
swapoff -a
sed -i '/\sswap\s/d' /etc/fstab
ok "Swap désactivé"

# --- Étape 2 : Modules noyau --------------------------------
log "Étape 2/6 — Chargement des modules noyau"
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
ok "Modules overlay et br_netfilter chargés"

# --- Étape 3 : Paramètres sysctl ----------------------------
log "Étape 3/6 — Configuration des paramètres sysctl"
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null
ok "Paramètres réseau noyau appliqués"

# --- Étape 4 : Containerd -----------------------------------
log "Étape 4/6 — Installation de containerd ${CONTAINERD_VERSION}"
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

# --- Étape 5 : kubeadm / kubelet ----------------------------
log "Étape 5/6 — Installation de kubeadm/kubelet v${K8S_VERSION}"
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
  kubeadm="${K8S_VERSION}"
apt-mark hold kubelet kubeadm > /dev/null
ok "kubeadm et kubelet ${K8S_VERSION} installés et figés"

# --- Étape 6 : Rejoindre le cluster -------------------------
log "Étape 6/6 — Jonction au cluster"
echo ""
echo -e "${YELLOW}Sur le master, récupérez la commande join :${NC}"
echo -e "  ${BOLD}kubeadm token create --print-join-command${NC}"
echo ""
echo -e "Collez la commande ${BOLD}kubeadm join ...${NC} ci-dessous"
echo -e "(ou appuyez sur ${YELLOW}Entrée${NC} pour ignorer et joindre manuellement)\n"

read -r -p "  > " JOIN_CMD

if [[ -z "$JOIN_CMD" ]]; then
  warn "Jonction ignorée. Exécutez manuellement la commande kubeadm join."
  warn "Exemple :"
  warn "  kubeadm join 192.168.1.142:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
else
  # Vérification basique du format
  if [[ "$JOIN_CMD" != kubeadm\ join\ * ]]; then
    die "La commande ne commence pas par 'kubeadm join'. Vérifiez et réessayez."
  fi

  log "Exécution de la commande join..."
  eval "$JOIN_CMD"
  ok "Nœud ${HOSTNAME} joint au cluster"

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║               WORKER REJOINT LE CLUSTER !                ║${NC}"
  echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOLD}║${NC} Nœud    : ${HOSTNAME}"
  echo -e "${BOLD}║${NC}"
  echo -e "${BOLD}║${NC} Vérification depuis le master :"
  echo -e "${BOLD}║${NC}   ${YELLOW}kubectl get nodes${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
fi
