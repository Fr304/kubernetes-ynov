# Deployments - Applications

## Fichiers

| Fichier | Description | Dépendances |
|---------|-------------|-------------|
| `01-postgres.yaml` | Base de données PostgreSQL | PVC, Secret |
| `02-redis.yaml` | Cache Redis | Secret |
| `03-beeapi.yaml` | API Bee | PostgreSQL, Redis |
| `04-beehub.yaml` | Hub Bee | BeeAPI |
| `05-algohive-server.yaml` | Backend AlgoHive | PostgreSQL, Redis |
| `06-algohive-client.yaml` | Frontend AlgoHive | Server |
| `07-monitoring.yaml` | Prometheus/exporters | - |

## Ordre de déploiement

L'ordre est important car il y a des dépendances :

```
1. PostgreSQL  ─┐
2. Redis       ─┼──→ 3. BeeAPI ──→ 4. BeeHub
                │
                └──→ 5. Server ──→ 6. Client
```

## Appliquer

```bash
# Tout d'un coup
kubectl apply -f .

# Un par un (respecter l'ordre)
kubectl apply -f 01-postgres.yaml
kubectl apply -f 02-redis.yaml
# Attendre que postgres/redis soient prêts...
kubectl apply -f 03-beeapi.yaml
kubectl apply -f 04-beehub.yaml
kubectl apply -f 05-algohive-server.yaml
kubectl apply -f 06-algohive-client.yaml
kubectl apply -f 07-monitoring.yaml
```

## Debug

```bash
# Voir tous les pods
kubectl get pods -n algohive

# Voir les deployments
kubectl get deployments -n algohive

# Logs d'un pod
kubectl logs -n algohive <pod-name>

# Logs en temps réel
kubectl logs -n algohive <pod-name> -f

# Logs du conteneur précédent (après crash)
kubectl logs -n algohive <pod-name> --previous

# Shell dans un pod
kubectl exec -it -n algohive <pod-name> -- /bin/sh

# Décrire un pod (événements, erreurs)
kubectl describe pod -n algohive <pod-name>

# Redémarrer un deployment
kubectl rollout restart deployment/<name> -n algohive

# Voir l'historique des déploiements
kubectl rollout history deployment/<name> -n algohive

# Revenir à la version précédente
kubectl rollout undo deployment/<name> -n algohive
```

## États des pods

| État | Signification | Action |
|------|---------------|--------|
| `Running` | Fonctionne | OK |
| `Pending` | En attente | Vérifier les ressources, PVC |
| `CrashLoopBackOff` | Crash répétés | Voir les logs |
| `ImagePullBackOff` | Image introuvable | Vérifier le nom de l'image |
| `ContainerCreating` | Démarrage | Attendre |

## Qu'est-ce qu'un Deployment ?

Un Deployment gère un ensemble de pods identiques (replicas).

**Fonctionnalités :**
- Rolling updates (mise à jour sans downtime)
- Rollback (retour arrière)
- Scaling (augmenter/diminuer les replicas)
- Self-healing (recréation automatique des pods crashés)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mon-app
spec:
  replicas: 2              # Nombre de pods
  selector:
    matchLabels:
      app: mon-app
  template:
    spec:
      containers:
        - name: mon-app
          image: mon-image:v1
          ports:
            - containerPort: 8080
```
