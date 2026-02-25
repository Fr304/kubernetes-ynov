# Déploiement sur un nouveau cluster

Guide complet pour reproduire le cluster AlgoHive sur une nouvelle infrastructure.
**Prérequis** : 4 machines Ubuntu 22.04 LTS, accès root, connectivité réseau entre elles.

---

## Étape 0 — Cloner le repo et adapter cluster.env

Sur le **master** (et idéalement chaque worker) :

```bash
git clone https://github.com/Fr304/kubernetes-ynov.git algohive-k8s
cd algohive-k8s
```

Ouvrir `cluster.env` et adapter **uniquement** ce fichier à votre réseau :

```bash
nano cluster.env
```

```bash
# IPs des nœuds
MASTER_IP=192.168.X.X          # IP de votre master
MASTER_HOSTNAME=mon-master     # hostname du master (hostname -s)
WORKER_1_IP=192.168.X.X
WORKER_1_HOSTNAME=mon-worker-1
WORKER_2_IP=192.168.X.X
WORKER_2_HOSTNAME=mon-worker-2
WORKER_3_IP=192.168.X.X
WORKER_3_HOSTNAME=mon-worker-3

# Pool MetalLB — plage d'IPs libres sur votre réseau (hors DHCP)
LB_POOL_START=192.168.X.100
LB_POOL_END=192.168.X.105
LB_INGRESS_IP=192.168.X.100   # première IP du pool → ingress-nginx

# Domaines (adaptez à votre DNS ou /etc/hosts)
DOMAIN_FRONTEND=algohive.local
DOMAIN_API=api.algohive.local
DOMAIN_BEEHUB=beehub.algohive.local
DOMAIN_GRAFANA=grafana.mondomaine.local
DOMAIN_KUBEVIEW=kubeview.algohive.local
```

> Les versions (K8S_VERSION, CONTAINERD_VERSION) et les CIDRs réseau peuvent rester inchangés sauf besoin spécifique.

---

## Étape 1 — Initialiser le master

Sur le **nœud master**, depuis le dossier `algohive-k8s/` :

```bash
sudo bash kubeadm/setup-master.sh
```

Ce script effectue automatiquement :
- Désactivation du swap
- Chargement des modules noyau (overlay, br_netfilter)
- Installation de containerd et kubeadm/kubelet/kubectl
- `kubeadm init` avec les variables de `cluster.env`
- Configuration de kubectl
- Déploiement de Flannel (CNI)

À la fin, le script affiche la **commande `kubeadm join`** — copiez-la, vous en aurez besoin à l'étape suivante.

**Vérification :**
```bash
kubectl get nodes
# ubuntu-kubernetes-master   Ready   control-plane   2m   v1.30.14
```

---

## Étape 2 — Joindre les workers

Sur **chaque nœud worker**, copier le repo puis exécuter :

```bash
sudo bash kubeadm/setup-worker.sh
```

Le script prépare le nœud (swap, modules, containerd, kubeadm/kubelet) puis demande la commande `kubeadm join` affichée à l'étape 1.

Si le token a expiré (> 24h), régénérez-en un sur le master :
```bash
kubeadm token create --print-join-command
```

**Vérification depuis le master :**
```bash
kubectl get nodes
# NAME                        STATUS   ROLES           AGE
# ubuntu-kubernetes-master    Ready    control-plane   5m
# ubuntu-kubernetes-slave-1   Ready    <none>          2m
# ubuntu-kubernetes-slave-2   Ready    <none>          1m
# ubuntu-kubernetes-slave-3   Ready    <none>          1m
```

---

## Étape 3 — Déployer OpenEBS (stockage persistant)

Sur le **master**, depuis `algohive-k8s/` :

```bash
kubectl apply -f openebs/
kubectl wait --namespace openebs \
  --for=condition=ready pod \
  --selector=name=openebs-localpv-provisioner \
  --timeout=120s
```

**Vérification :**
```bash
kubectl get storageclass
# openebs-hostpath   openebs.io/local   WaitForFirstConsumer
```

---

## Étape 4 — Déployer l'application complète

Depuis `algohive-k8s/` sur le master :

```bash
bash install-all.sh
```

Ce script installe dans l'ordre :
1. **MetalLB** — pool d'IPs `${LB_POOL_START}-${LB_POOL_END}`
2. **Ingress NGINX** — controller HTTP/HTTPS
3. **Application AlgoHive** — via Kustomize (`kubectl apply -k .`)
4. **Ingress rules** — via `envsubst` (domaines depuis `cluster.env`)

À la fin, le script affiche les entrées `/etc/hosts` à ajouter.

---

## Étape 5 — Monitoring (optionnel)

### kube-prometheus-stack (Prometheus + Grafana)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Rendre le template values.yaml avec cluster.env
source cluster.env && export MASTER_IP
envsubst < kube-prometheus/values.yaml > /tmp/prom-values.yaml

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version 80.14.3 \
  -f /tmp/prom-values.yaml
```

### Grafana custom avec sidecars et dashboards

```bash
kubectl apply -k monitoring/
source cluster.env && export DOMAIN_GRAFANA
envsubst < monitoring/grafana-ingress.yaml | kubectl apply -f -
```

> **Prérequis Grafana** : exposer les métriques etcd/scheduler/controller-manager sur 0.0.0.0 (voir [kubeadm/README.md](kubeadm/README.md#étape-5--exposer-les-métriques-du-control-plane-prometheus))

---

## Étape 6 — Configurer /etc/hosts

Sur **chaque machine cliente** (poste de travail, etc.) :

```bash
# Remplacez LB_INGRESS_IP par l'IP assignée à ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Ajoutez dans `/etc/hosts` (Linux/Mac) ou `C:\Windows\System32\drivers\etc\hosts` (Windows) :

```
192.168.X.100  algohive.local
192.168.X.100  api.algohive.local
192.168.X.100  beehub.algohive.local
192.168.X.100  grafana.mondomaine.local
192.168.X.100  kubeview.algohive.local
```

---

## Vérification finale

```bash
# Tous les pods doivent être Running
kubectl get pods -A

# État de l'application
./deploy.sh status

# URLs d'accès (lit cluster.env automatiquement)
./deploy.sh urls
```

---

## Résumé des commandes

| Étape | Machine | Commande |
|-------|---------|----------|
| 0. Cloner + adapter | master | `git clone ... && nano cluster.env` |
| 1. Init master | master | `sudo bash kubeadm/setup-master.sh` |
| 2. Joindre workers | chaque worker | `sudo bash kubeadm/setup-worker.sh` |
| 3. OpenEBS | master | `kubectl apply -f openebs/` |
| 4. Application | master | `bash install-all.sh` |
| 5. Monitoring | master | `helm install ... -f /tmp/prom-values.yaml` |
| 6. /etc/hosts | clients | Ajouter les entrées DNS |

---

## Réinitialiser un nœud

```bash
# Sur le nœud à réinitialiser
kubeadm reset
rm -rf /etc/kubernetes/ /var/lib/etcd/ $HOME/.kube/

# Sur le master — supprimer le nœud du cluster
kubectl delete node <nom-du-nœud>
```
