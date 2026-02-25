# AlgoHive - Kubernetes

Manifests Kubernetes pour déployer l'application AlgoHive sur un cluster bare-metal (kubeadm).

## Prérequis

- Cluster Kubernetes (kubeadm) fonctionnel
- kubectl configuré
- CNI — **Flannel v0.28.0** installé avant les noeuds workers (voir [`kube-flannel/`](kube-flannel/README.md))
- Stockage — **OpenEBS v3.5.0** installé avant l'application (voir [`openebs/`](openebs/README.md))

## Structure

```
algohive-k8s/
├── kube-flannel/      # CNI réseau — Flannel v0.28.0 (avant les workers)
├── openebs/           # Stockage local persistant — OpenEBS v3.5.0 (avant les PVC)
├── metallb/           # Load Balancer bare-metal (IPs externes)
├── ingress-nginx/     # Ingress Controller (routage HTTP/HTTPS)
├── base/              # Namespace algohive
├── secrets/           # Données sensibles (mots de passe)
├── configmaps/        # Configurations applicatives
├── volumes/           # Stockage persistant (PVC — openebs-hostpath)
├── deployments/       # Applications (pods)
├── services/          # Ingress rules et Network Policies
├── monitoring/        # Grafana (dashboards)
├── kubeview/          # Visualisation du cluster
├── install-all.sh     # Script de déploiement complet
├── deploy.sh          # Script de gestion
└── INSTALL.md         # Guide détaillé d'installation
```

---

## Déploiement Rapide

### Installation complète (recommandé)

```bash
# Exécuter le script d'installation
./install-all.sh
```

Ce script installe dans l'ordre :
1. MetalLB (Load Balancer)
2. Ingress NGINX (routage HTTP)
3. Application Algohive

> **Note :** Flannel (CNI) et OpenEBS (stockage) sont des prérequis cluster à installer **avant** ce script. Voir [INSTALL.md](INSTALL.md).

### Installation manuelle

Voir [INSTALL.md](INSTALL.md) pour le guide détaillé.

---

## Gestion de l'Application

```bash
./deploy.sh install   # Déployer l'application
./deploy.sh status    # Voir l'état des pods/services
./deploy.sh logs      # Voir les logs
./deploy.sh urls      # Afficher les URLs d'accès
./deploy.sh restart   # Redémarrer un service
./deploy.sh delete    # Supprimer l'application
```

---

## Architecture

```
                    Internet / Réseau Local
                              │
                              ▼
                    ┌──────────────────┐
                    │     MetalLB      │
                    │  192.168.1.100   │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Ingress NGINX   │
                    │   (HTTP/HTTPS)   │
                    └──────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│algohive.local │   │api.algohive   │   │grafana.local  │
│   (Frontend)  │   │   (Backend)   │   │  (Monitoring) │
└───────────────┘   └───────────────┘   └───────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
              ┌──────────┐        ┌──────────┐
              │PostgreSQL│        │  Redis   │
              └──────────┘        └──────────┘
```

---

## URLs d'accès

Après déploiement, ajoutez dans `/etc/hosts` :

```
192.168.1.100  algohive.local
192.168.1.100  api.algohive.local
192.168.1.100  beehub.algohive.local
192.168.1.100  grafana.algohive.local
192.168.1.100  kubeview.algohive.local
```

| Service | URL |
|---------|-----|
| Frontend | http://algohive.local |
| API | http://api.algohive.local |
| BeeHub | http://beehub.algohive.local |
| Grafana | http://grafana.algohive.local |
| KubeView | http://kubeview.algohive.local |

### Ports NodePort (fallback sans Ingress)

| Service | Port |
|---------|------|
| Frontend | 30000 |
| API | 30080 |
| BeeHub | 30082 |
| Prometheus | 30090 |
| Grafana | 30030 |

---

## Commandes Utiles

```bash
# Voir tous les pods
kubectl get pods -A

# Pods de l'application
kubectl get pods -n algohive

# Logs d'un pod
kubectl logs -n algohive <nom-du-pod> -f

# Shell dans un pod
kubectl exec -it -n algohive <nom-du-pod> -- /bin/sh

# Voir les services LoadBalancer
kubectl get svc -A | grep LoadBalancer

# Voir les Ingress
kubectl get ingress -A

# Événements récents
kubectl get events -n algohive --sort-by='.lastTimestamp'
```

---

## Composants

| Dossier | Description | Documentation |
|---------|-------------|---------------|
| `kube-flannel/` | CNI réseau Flannel v0.28.0 — à installer avant les workers | [README](kube-flannel/README.md) |
| `openebs/` | Stockage local persistant OpenEBS v3.5.0 — à installer avant les PVC | [README](openebs/README.md) |
| `metallb/` | Load Balancer Layer 2 pour IPs externes | [README](metallb/README.md) |
| `ingress-nginx/` | Controller Ingress NGINX | [README](ingress-nginx/README.md) |
| `base/` | Namespace algohive | [README](base/README.md) |
| `secrets/` | Mots de passe base de données | [README](secrets/README.md) |
| `configmaps/` | Configuration applicative | [README](configmaps/README.md) |
| `volumes/` | PersistentVolumeClaims (StorageClass : openebs-hostpath) | [README](volumes/README.md) |
| `deployments/` | Pods applicatifs | [README](deployments/README.md) |
| `services/` | Ingress rules + NetworkPolicies | [README](services/README.md) |
| `monitoring/` | Stack Grafana | [README](monitoring/README.md) |
| `kubeview/` | Visualisation cluster | [README](kubeview/README.md) |

---

## Dépannage

### Service en Pending (pas d'IP externe)

```bash
# Vérifier MetalLB
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l component=controller
```

### 502 Bad Gateway

```bash
# Vérifier que le backend tourne
kubectl get pods -n algohive
kubectl get endpoints -n algohive
```

### Pods en CrashLoopBackOff

```bash
kubectl logs -n algohive <pod-name>
kubectl describe pod -n algohive <pod-name>
```

Voir [INSTALL.md](INSTALL.md) pour plus de détails sur le dépannage.
