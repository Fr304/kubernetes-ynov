# MetalLB - Load Balancer pour Kubernetes Bare Metal

MetalLB est un load balancer pour les clusters Kubernetes bare metal (sans cloud provider). Il permet d'utiliser des services de type `LoadBalancer` sans dépendre d'un fournisseur cloud.

## État actuel du cluster

| Composant | Status | Version |
|-----------|--------|---------|
| Controller | ✅ Running | v0.15.3 |
| Speaker | ✅ Running (4 pods) | v0.15.3 |
| IPAddressPool | ✅ Configuré | 192.168.1.100-105 |
| L2Advertisement | ✅ Actif | Mode Layer 2 |

**Service utilisant MetalLB:**
- `ingress-nginx-controller` → `192.168.1.100`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────┐         ┌──────────────────────────────────┐ │
│   │  Controller  │         │         Speaker (DaemonSet)      │ │
│   │  (Deployment)│         │  ┌────────┐ ┌────────┐ ┌────────┐│ │
│   │              │         │  │Node 1  │ │Node 2  │ │Node 3  ││ │
│   │ - Assigne IP │         │  │Speaker │ │Speaker │ │Speaker ││ │
│   │ - Webhooks   │         │  └────────┘ └────────┘ └────────┘│ │
│   └──────────────┘         └──────────────────────────────────┘ │
│          │                              │                        │
│          ▼                              ▼                        │
│   ┌──────────────┐         ┌──────────────────────────────────┐ │
│   │IPAddressPool │         │      L2Advertisement             │ │
│   │192.168.1.100 │◄────────│      (Annonce ARP)               │ │
│   │     -105     │         └──────────────────────────────────┘ │
│   └──────────────┘                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ ARP
                    ┌──────────────────┐
                    │   Réseau Local   │
                    │   192.168.1.x    │
                    └──────────────────┘
```

---

## Installation

### Option 1: Via manifests officiels (méthode actuelle)

```bash
# Installer MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml

# Attendre que les pods soient prêts
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Appliquer la configuration IP
kubectl apply -f 10-ipaddresspool.yaml
kubectl apply -f 11-l2advertisement.yaml
```

### Option 2: Via Helm

```bash
# Ajouter le repo Helm
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Installer MetalLB
helm install metallb metallb/metallb \
  -n metallb-system \
  --create-namespace \
  --version 0.15.3

# Attendre que les pods soient prêts
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=metallb \
  --timeout=120s

# Appliquer la configuration IP
kubectl apply -f 10-ipaddresspool.yaml
kubectl apply -f 11-l2advertisement.yaml
```

### Option 3: Via manifests séparés (ce dossier)

```bash
# Appliquer tous les manifests dans l'ordre
kubectl apply -f .
```

---

## Structure des Manifests

Les manifests sont organisés avec un préfixe numérique pour l'ordre d'application:

| Fichier | Description |
|---------|-------------|
| `00-namespace.yaml` | Crée le namespace `metallb-system` |
| `01-serviceaccounts.yaml` | ServiceAccounts pour controller et speaker |
| `02-clusterroles.yaml` | Permissions au niveau cluster |
| `03-roles.yaml` | Permissions au niveau namespace |
| `04-rolebindings.yaml` | Lie les SA aux roles |
| `05-configmap.yaml` | Configuration d'exclusion d'interfaces L2 |
| `06-deployment-controller.yaml` | Deployment du controller |
| `07-daemonset-speaker.yaml` | DaemonSet des speakers |
| `08-webhook-service.yaml` | Service pour les webhooks |
| `09-validatingwebhook.yaml` | Configuration des webhooks de validation |
| `10-ipaddresspool.yaml` | Pool d'adresses IP |
| `11-l2advertisement.yaml` | Configuration L2 Advertisement |

---

## Description des Composants

### Controller (`06-deployment-controller.yaml`)

Le **Controller** est le cerveau de MetalLB:
- Surveille les services de type `LoadBalancer`
- Assigne les adresses IP depuis l'IPAddressPool
- Met à jour le champ `status.loadBalancer.ingress` des services
- Gère les webhooks de validation des CRDs

```yaml
# Extrait clé
image: quay.io/metallb/controller:v0.15.3
args:
  - --port=7472          # Port pour les métriques Prometheus
  - --log-level=info     # Niveau de log
  - --tls-min-version=VersionTLS12
```

### Speaker (`07-daemonset-speaker.yaml`)

Le **Speaker** est déployé sur chaque node (DaemonSet):
- Annonce les IPs LoadBalancer sur le réseau via ARP (mode L2)
- Répond aux requêtes ARP pour les IPs virtuelles
- Utilise `hostNetwork: true` pour accéder au réseau physique
- Nécessite la capability `NET_RAW` pour manipuler les paquets

```yaml
# Points importants
hostNetwork: true              # Accès réseau direct
capabilities:
  add: ["NET_RAW"]            # Manipulation paquets ARP
tolerations:                   # Tourne aussi sur les masters
  - key: node-role.kubernetes.io/control-plane
```

### IPAddressPool (`10-ipaddresspool.yaml`)

Définit la plage d'IPs disponibles:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.100-192.168.1.105   # 6 IPs disponibles
  autoAssign: true                   # Assignation automatique
```

**Status actuel:**
- IPs assignées: 1 (192.168.1.100 → ingress-nginx)
- IPs disponibles: 5

### L2Advertisement (`11-l2advertisement.yaml`)

Configure l'annonce en mode Layer 2:

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - first-pool    # Référence au pool d'IPs
```

**Mode L2 - Comment ça marche:**
1. Un service demande une IP externe
2. Le controller assigne une IP du pool
3. Les speakers élisent un leader pour cette IP
4. Le speaker leader répond aux requêtes ARP
5. Tout le trafic passe par ce node
6. Si le node tombe, un autre speaker prend le relais

---

## Configuration

### Modifier la plage d'adresses IP

Éditez `10-ipaddresspool.yaml`:

```yaml
spec:
  addresses:
    - 192.168.1.100-192.168.1.120   # Nouvelle plage (21 IPs)
    # Ou plusieurs plages:
    # - 192.168.1.100-192.168.1.110
    # - 192.168.1.200-192.168.1.210
```

Puis appliquez:

```bash
kubectl apply -f 10-ipaddresspool.yaml
```

### Demander une IP spécifique

Ajoutez l'annotation `metallb.universe.tf/loadBalancerIPs` à votre service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mon-service
  annotations:
    metallb.universe.tf/loadBalancerIPs: 192.168.1.102
spec:
  type: LoadBalancer
  # ...
```

### Créer plusieurs pools

Vous pouvez créer plusieurs pools pour différents usages:

```yaml
# Pool pour la production
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.100-192.168.1.110
---
# Pool pour le développement
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: dev-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.210
```

---

## Commandes de Debug

### Vérifier l'état des pods

```bash
kubectl get pods -n metallb-system
```

### Voir les logs du controller

```bash
kubectl logs -n metallb-system -l component=controller -f
```

### Voir les logs des speakers

```bash
kubectl logs -n metallb-system -l component=speaker -f
```

### Vérifier l'IPAddressPool

```bash
# Lister les pools
kubectl get ipaddresspool -n metallb-system

# Détails avec status
kubectl get ipaddresspool -n metallb-system -o yaml
```

### Vérifier L2Advertisement

```bash
kubectl get l2advertisement -n metallb-system
kubectl describe l2advertisement l2-advert -n metallb-system
```

### Lister les services LoadBalancer

```bash
kubectl get svc -A | grep LoadBalancer
```

### Vérifier les événements

```bash
kubectl get events -n metallb-system --sort-by='.lastTimestamp'
```

### Diagnostiquer un service sans IP

```bash
# Vérifier le status du service
kubectl describe svc <nom-service> -n <namespace>

# Vérifier si la plage est épuisée
kubectl get ipaddresspool -n metallb-system -o yaml | grep -A5 status
```

### Tester la connectivité

```bash
# Ping l'IP externe
ping 192.168.1.100

# Curl sur le service
curl http://192.168.1.100
```

### Redémarrer MetalLB

```bash
kubectl rollout restart deployment controller -n metallb-system
kubectl rollout restart daemonset speaker -n metallb-system
```

---

## Problèmes Courants

| Problème | Cause possible | Solution |
|----------|----------------|----------|
| Service reste en `<pending>` | Plage IP épuisée | Étendre la plage dans IPAddressPool |
| IP non accessible | Speaker pas sur le bon node | Vérifier les logs speaker |
| Conflit ARP | Autre équipement utilise l'IP | Changer la plage d'adresses |
| Webhook timeout | Controller pas prêt | Attendre ou redémarrer le controller |
| Pods speaker CrashLoop | Problème memberlist secret | Vérifier le secret memberlist existe |

---

## Métriques Prometheus

MetalLB expose des métriques sur le port 7472:

```bash
# Métriques du controller
kubectl port-forward -n metallb-system deploy/controller 7472:7472
curl http://localhost:7472/metrics

# Métriques d'un speaker
kubectl port-forward -n metallb-system ds/speaker 7472:7472
curl http://localhost:7472/metrics
```

### Métriques utiles

| Métrique | Description |
|----------|-------------|
| `metallb_allocator_addresses_in_use_total` | Nombre d'IPs utilisées |
| `metallb_allocator_addresses_total` | Nombre total d'IPs disponibles |
| `metallb_bgp_session_up` | État des sessions BGP (mode BGP) |
| `metallb_speaker_announced` | Services annoncés par le speaker |

---

## Références

- [Documentation officielle MetalLB](https://metallb.io/)
- [GitHub MetalLB](https://github.com/metallb/metallb)
- [Configuration L2](https://metallb.io/configuration/#layer-2-configuration)
- [Configuration BGP](https://metallb.io/configuration/#bgp-configuration)
