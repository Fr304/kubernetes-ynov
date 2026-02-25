# Kubeadm — Initialisation du Cluster

Guide complet pour reproduire le cluster Kubernetes bare-metal du projet AlgoHive.

## Scripts d'installation

| Script | Usage | Cible |
|--------|-------|-------|
| `setup-master.sh` | Prépare le nœud + `kubeadm init` + Flannel | Master uniquement |
| `setup-worker.sh` | Prépare le nœud + `kubeadm join` | Chaque worker |

```bash
# Sur le master
sudo bash kubeadm/setup-master.sh

# Sur chaque worker (copier-coller la commande join affichée par le master)
sudo bash kubeadm/setup-worker.sh
```

> Les scripts automatisent toutes les étapes manuelles décrites ci-dessous.

---

## Topologie du Cluster

| Nœud | Rôle | IP | OS |
|------|------|----|----|
| `ubuntu-kubernetes-master` | control-plane | 192.168.1.142 | Ubuntu 22.04.5 LTS |
| `ubuntu-kubernetes-slave-1` | worker | 192.168.1.143 | Ubuntu 22.04.5 LTS |
| `ubuntu-kubernetes-slave-2` | worker | 192.168.1.26 | Ubuntu 22.04.5 LTS |
| `ubuntu-kubernetes-slave-3` | worker | 192.168.1.51 | Ubuntu 22.04.5 LTS |

## Versions déployées

| Composant | Version |
|-----------|---------|
| Kubernetes (kubeadm/kubelet/kubectl) | v1.30.14 |
| containerd | 2.2.0 |
| kubernetes-cni | 1.4.0-1.1 |
| OS | Ubuntu 22.04.5 LTS |
| Kernel | 5.15.0-164-generic |

## Configuration réseau

| Paramètre | Valeur |
|-----------|--------|
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.96.0.0/12` |
| DNS ClusterIP | `10.96.0.10` |
| DNS domain | `cluster.local` |
| CNI | Flannel v0.28.0 (VXLAN) |
| kube-proxy | iptables |
| cgroup driver | systemd |

---

## Étape 1 — Préparation (tous les nœuds)

> Répéter sur **master + tous les workers**.

### 1.1 Désactiver le swap

```bash
swapoff -a
sed -i '/swap/d' /etc/fstab
```

### 1.2 Charger les modules noyau

```bash
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
```

### 1.3 Configurer les paramètres sysctl

```bash
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

### 1.4 Installer containerd

```bash
# Ajouter le repo Docker (fournit containerd.io)
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y containerd.io=2.2.0-2~ubuntu.22.04~jammy
```

### 1.5 Configurer containerd (SystemdCgroup)

```bash
# Générer la config par défaut
containerd config default > /etc/containerd/config.toml

# Activer SystemdCgroup (obligatoire avec kubeadm + systemd)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
```

### 1.6 Installer kubeadm, kubelet, kubectl

```bash
# Ajouter le repo Kubernetes v1.30
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet=1.30.14-1.1 kubeadm=1.30.14-1.1 kubectl=1.30.14-1.1
apt-mark hold kubelet kubeadm kubectl
```

---

## Étape 2 — Initialiser le master

> Sur le **nœud master uniquement**.

```bash
# Depuis le dossier algohive-k8s/
kubeadm init --config kubeadm/kubeadm-config.yaml
```

### Configurer kubectl

```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

### Vérification

```bash
kubectl get nodes
# NAME                       STATUS     ROLES           AGE   VERSION
# ubuntu-kubernetes-master   NotReady   control-plane   1m    v1.30.14
# (NotReady normal — CNI pas encore installé)
```

---

## Étape 3 — Déployer Flannel (CNI)

> Sur le **master**, avant de joindre les workers.

```bash
kubectl apply -f kube-flannel/
```

Attendre que le DaemonSet soit prêt :

```bash
kubectl wait --namespace kube-flannel \
  --for=condition=ready pod \
  --selector=app=flannel \
  --timeout=120s

kubectl get nodes
# NAME                       STATUS   ROLES           AGE   VERSION
# ubuntu-kubernetes-master   Ready    control-plane   2m    v1.30.14
```

---

## Étape 4 — Rejoindre les workers

> Sur **chaque nœud worker**.

### Récupérer la commande de join

```bash
# Sur le master — afficher la commande de join
kubeadm token create --print-join-command
```

La commande ressemble à :

```bash
kubeadm join 192.168.1.142:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### Exécuter sur chaque worker

```bash
# Sur ubuntu-kubernetes-slave-1 (192.168.1.143)
kubeadm join 192.168.1.142:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Répéter sur slave-2 (192.168.1.26) et slave-3 (192.168.1.51)
```

### Vérification depuis le master

```bash
kubectl get nodes
# NAME                        STATUS   ROLES           AGE   VERSION
# ubuntu-kubernetes-master    Ready    control-plane   5m    v1.30.14
# ubuntu-kubernetes-slave-1   Ready    <none>          2m    v1.30.14
# ubuntu-kubernetes-slave-2   Ready    <none>          2m    v1.30.14
# ubuntu-kubernetes-slave-3   Ready    <none>          2m    v1.30.14
```

---

## Étape 5 — Exposer les métriques du control-plane (Prometheus)

Par défaut, kubeadm configure etcd, kube-scheduler et kube-controller-manager pour n'écouter que sur `127.0.0.1`. Il faut exposer leurs métriques sur `0.0.0.0` pour que Prometheus puisse les scraper.

```bash
# Modifier les static pod manifests sur le master
sed -i 's|--listen-metrics-urls=http://127.0.0.1:2381|--listen-metrics-urls=http://0.0.0.0:2381|' \
  /etc/kubernetes/manifests/etcd.yaml

sed -i 's|--bind-address=127.0.0.1|--bind-address=0.0.0.0|' \
  /etc/kubernetes/manifests/kube-scheduler.yaml

sed -i 's|--bind-address=127.0.0.1|--bind-address=0.0.0.0|' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml
```

> Le kubelet détecte automatiquement les changements et redémarre les pods (environ 20s).

Vérifier que les pods ont redémarré :

```bash
kubectl get pods -n kube-system | grep -E "etcd|scheduler|controller"
# etcd-ubuntu-kubernetes-master                      1/1     Running
# kube-controller-manager-ubuntu-kubernetes-master   1/1     Running
# kube-scheduler-ubuntu-kubernetes-master            1/1     Running
```

Vérifier que Prometheus scrape correctement :

```bash
# Les 3 targets doivent être "up"
kubectl exec -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    job = t['labels'].get('job','')
    if any(x in job for x in ['etcd','scheduler','controller']):
        print(job, t['health'])
"
# kube-controller-manager up
# kube-etcd              up
# kube-scheduler         up
```

---

## Étape 6 — Déployer le reste de l'infrastructure

Continuer avec les étapes de [INSTALL.md](../INSTALL.md) :

```
1. MetalLB     → IPs externes (LoadBalancer)
2. Ingress NGINX → Routage HTTP/HTTPS
3. Application   → AlgoHive
4. kube-prometheus-stack → Monitoring
```

---

## Dépannage

### Token expiré (après 24h)

```bash
# Recréer un token sur le master
kubeadm token create --print-join-command
```

### Nœud NotReady

```bash
# Vérifier les logs kubelet sur le nœud en question
journalctl -u kubelet -n 50

# Vérifier les pods système
kubectl get pods -n kube-system
```

### Réinitialiser un nœud

```bash
# Sur le nœud à réinitialiser (master ou worker)
kubeadm reset
rm -rf /etc/kubernetes/ /var/lib/etcd/ $HOME/.kube/

# Sur le master — retirer le nœud du cluster
kubectl delete node <node-name>
```

### Vérifier la config containerd

```bash
# SystemdCgroup doit être true
grep SystemdCgroup /etc/containerd/config.toml
# SystemdCgroup = true
```

---

## Résumé des commandes

| Action | Commande |
|--------|----------|
| Setup master (automatique) | `sudo bash kubeadm/setup-master.sh` |
| Setup worker (automatique) | `sudo bash kubeadm/setup-worker.sh` |
| Init master (manuel) | `kubeadm init --config kubeadm/kubeadm-config.yaml` |
| Créer token join | `kubeadm token create --print-join-command` |
| Joindre un worker | `kubeadm join 192.168.1.142:6443 --token … --discovery-token-ca-cert-hash …` |
| Voir les nœuds | `kubectl get nodes -o wide` |
| Réinitialiser un nœud | `kubeadm reset` |
| Vérifier kubelet | `systemctl status kubelet` |
