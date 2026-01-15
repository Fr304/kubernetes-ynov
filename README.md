# AlgoHive - Kubernetes

Manifests Kubernetes pour déployer l'application AlgoHive.

## Structure

```
algohive-k8s/
├── base/           # Namespace (espace isolé)
├── secrets/        # Données sensibles (mots de passe)
├── configmaps/     # Configurations applicatives
├── volumes/        # Stockage persistant (PVC)
├── deployments/    # Applications (pods)
├── services/       # Ingress et Network Policies
├── kubeview/       # Visualisation du cluster
├── monitoring/     # Grafana (dashboards)
└── kustomization.yaml
```

## Déploiement

### Option 1 : Script automatique

```bash
./deploy.sh install   # Déployer
./deploy.sh status    # Voir l'état
./deploy.sh logs      # Voir les logs
./deploy.sh urls      # Afficher les URLs
./deploy.sh delete    # Supprimer
```

### Option 2 : Kustomize (tout d'un coup)

```bash
kubectl apply -k .
```

### Option 3 : Dossier par dossier

```bash
kubectl apply -f base/
kubectl apply -f secrets/
kubectl apply -f configmaps/
kubectl apply -f volumes/
kubectl apply -f deployments/
kubectl apply -f services/
kubectl apply -k kubeview/
kubectl apply -k monitoring/
```

## URLs d'accès

| Service | URL |
|---------|-----|
| Frontend | http://algohive.local |
| API | http://api.algohive.local |
| KubeView | http://kubeview.algohive.local |
| Grafana | http://grafana.algohive.local |

## Ports NodePort (fallback)

| Service | Port |
|---------|------|
| Frontend | 30000 |
| API | 30080 |
| BeeHub | 30082 |
| Prometheus | 30090 |
| Grafana | 30030 |

## Commandes de debug

```bash
# Voir tous les pods
kubectl get pods -n algohive

# Logs d'un pod
kubectl logs -n algohive <nom-du-pod>

# Logs en temps réel
kubectl logs -n algohive <nom-du-pod> -f

# Shell dans un pod
kubectl exec -it -n algohive <nom-du-pod> -- /bin/sh

# Événements et erreurs
kubectl describe pod -n algohive <nom-du-pod>

# Voir les ressources d'un namespace
kubectl get all -n algohive
```

## Dossiers

Voir le `README.md` dans chaque dossier pour les détails.
