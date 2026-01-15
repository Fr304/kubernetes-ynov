# KubeView - Visualisation du Cluster

Interface web pour visualiser les ressources Kubernetes.

## Fichiers

| Fichier | Description |
|---------|-------------|
| `serviceaccount.yaml` | Identité du pod KubeView |
| `clusterrole.yaml` | Permissions (lecture seule) |
| `clusterrolebinding.yaml` | Lie l'identité aux permissions |
| `deployment.yaml` | Déploie l'application KubeView |
| `service.yaml` | Expose en interne (ClusterIP) |
| `ingress.yaml` | Expose via kubeview.algohive.local |
| `kustomization.yaml` | Fichier Kustomize |

## Architecture RBAC

```
┌─────────────────────┐
│   ServiceAccount    │  ← "Je suis kubeview"
│   (Identité)        │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ ClusterRoleBinding  │  ← "kubeview a le rôle X"
│   (Contrat)         │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│    ClusterRole      │  ← "Rôle X peut: get, list, watch"
│   (Permissions)     │
└─────────────────────┘
```

**Sans ces 3 éléments** → Le pod ne peut pas lire les ressources Kubernetes.

## Flux réseau

```
Navigateur
    │
    ▼ http://kubeview.algohive.local
┌─────────────────┐
│     Ingress     │
└────────┬────────┘
         │
         ▼ port 8000
┌─────────────────┐
│     Service     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Pod KubeView  │ ──→ API Kubernetes
└─────────────────┘
```

## Appliquer

```bash
# Avec Kustomize (recommandé)
kubectl apply -k .

# Manifest par manifest
kubectl apply -f serviceaccount.yaml
kubectl apply -f clusterrole.yaml
kubectl apply -f clusterrolebinding.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

## Debug

```bash
# Vérifier les pods
kubectl get pods -n kubeview

# Voir les logs
kubectl logs -n kubeview -l app.kubernetes.io/name=kubeview

# Logs en temps réel
kubectl logs -n kubeview -l app.kubernetes.io/name=kubeview -f

# Vérifier le service
kubectl get svc -n kubeview

# Vérifier l'ingress
kubectl get ingress -n kubeview

# Tester l'accès à l'API (depuis le pod)
kubectl exec -it -n kubeview <pod> -- wget -qO- http://localhost:8000/health

# Vérifier les permissions RBAC
kubectl auth can-i list pods --as=system:serviceaccount:kubeview:kubeview

# Voir le ClusterRole
kubectl describe clusterrole kubeview
```

## Accès

- **URL :** http://kubeview.algohive.local
- **Port :** 8000

Ajouter dans `/etc/hosts` :
```
192.168.1.100   kubeview.algohive.local
```

## Erreurs courantes

| Erreur | Cause | Solution |
|--------|-------|----------|
| 403 Forbidden | Pas de permissions | Vérifier ClusterRole et ClusterRoleBinding |
| 404 Not Found | Ingress mal configuré | Vérifier ingressClassName |
| Pod CrashLoop | Erreur de config | Voir les logs |
