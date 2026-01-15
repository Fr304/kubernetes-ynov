# MetalLB - Load Balancer pour Kubernetes Bare Metal

MetalLB est un load balancer pour les clusters Kubernetes bare metal (sans cloud provider).

## Installation

### 1. Installer MetalLB via manifests officiels

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
```

### 2. Attendre que les pods MetalLB soient prêts

```bash
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

### 3. Appliquer la configuration (IPAddressPool + L2Advertisement)

```bash
kubectl apply -f metallb.yaml
```

## Configuration

Le fichier `metallb.yaml` contient :

- **IPAddressPool** : Plage d'adresses IP disponibles pour les services LoadBalancer
  - Plage actuelle : `192.168.1.100 - 192.168.1.120`

- **L2Advertisement** : Mode Layer 2 pour annoncer les IPs sur le réseau local

## Commandes de Debug

### Vérifier l'état des pods MetalLB

```bash
kubectl get pods -n metallb-system
```

### Voir les logs du controller

```bash
kubectl logs -n metallb-system -l component=controller -f
```

### Voir les logs des speakers (un par node)

```bash
kubectl logs -n metallb-system -l component=speaker -f
```

### Vérifier la configuration IPAddressPool

```bash
kubectl get ipaddresspool -n metallb-system
kubectl describe ipaddresspool default-pool -n metallb-system
```

### Vérifier L2Advertisement

```bash
kubectl get l2advertisement -n metallb-system
kubectl describe l2advertisement default -n metallb-system
```

### Lister les services avec IP externe assignée

```bash
kubectl get svc -A | grep LoadBalancer
```

### Vérifier les événements MetalLB

```bash
kubectl get events -n metallb-system --sort-by='.lastTimestamp'
```

### Diagnostiquer un service qui n'obtient pas d'IP

```bash
# Vérifier le status du service
kubectl describe svc <nom-du-service> -n <namespace>

# Vérifier si la plage IP est épuisée
kubectl get ipaddresspool -n metallb-system -o yaml
```

### Tester la connectivité vers un service LoadBalancer

```bash
# Ping l'IP externe
ping <EXTERNAL-IP>

# Curl sur le service
curl http://<EXTERNAL-IP>:<PORT>
```

### Redémarrer MetalLB (en cas de problème)

```bash
kubectl rollout restart deployment controller -n metallb-system
kubectl rollout restart daemonset speaker -n metallb-system
```

## Problèmes courants

| Problème | Cause possible | Solution |
|----------|----------------|----------|
| Service reste en `<pending>` | Plage IP épuisée | Étendre la plage dans IPAddressPool |
| IP non accessible | Speaker pas sur le bon node | Vérifier les logs speaker |
| Conflit ARP | Autre équipement utilise l'IP | Changer la plage d'adresses |

## Modifier la plage d'adresses IP

Éditez `metallb.yaml` et changez la plage dans `spec.addresses`, puis :

```bash
kubectl apply -f metallb.yaml
```
