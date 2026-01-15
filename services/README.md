# Services - Réseau

## Fichiers

| Fichier | Description |
|---------|-------------|
| `ingress.yaml` | Expose les applications via des noms de domaine |
| `network-policies.yaml` | Règles de firewall entre pods |

## Ingress

L'Ingress route le trafic externe vers les services internes.

```
Internet
    │
    ▼
┌─────────────────────────────────────────┐
│  Ingress Controller (nginx)             │
│  192.168.1.100                          │
└─────────────────────────────────────────┘
    │
    ├── algohive.local      → frontend (port 80)
    ├── api.algohive.local  → backend (port 3000)
    └── kubeview.algohive.local → kubeview (port 8000)
```

## Network Policies

Les Network Policies contrôlent quel pod peut communiquer avec quel autre pod.

**Par défaut :** Tous les pods peuvent communiquer entre eux.

**Avec Network Policy :** On peut restreindre (ex: seul le backend peut accéder à PostgreSQL).

## Appliquer

```bash
kubectl apply -f ingress.yaml
kubectl apply -f network-policies.yaml
```

## Debug

```bash
# Lister les ingress
kubectl get ingress -n algohive

# Détails d'un ingress
kubectl describe ingress <nom> -n algohive

# Lister les services
kubectl get svc -n algohive

# Tester la connectivité depuis un pod
kubectl exec -it <pod> -n algohive -- curl http://service-name:port

# Voir les network policies
kubectl get networkpolicies -n algohive

# Vérifier l'IP de l'ingress controller
kubectl get svc -n ingress-nginx
```

## Configuration /etc/hosts

Pour accéder via les noms de domaine, ajouter dans `/etc/hosts` :

```
192.168.1.100   algohive.local
192.168.1.100   api.algohive.local
192.168.1.100   kubeview.algohive.local
192.168.1.100   grafana.algohive.local
```

## Types de Services

| Type | Description |
|------|-------------|
| `ClusterIP` | Accessible uniquement dans le cluster (défaut) |
| `NodePort` | Accessible via IP-node:port |
| `LoadBalancer` | Accessible via IP externe (cloud) |
