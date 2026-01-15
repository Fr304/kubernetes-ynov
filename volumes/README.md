# Volumes - Stockage Persistant

## Fichiers

| Fichier | Description |
|---------|-------------|
| `pvcs.yaml` | PersistentVolumeClaims pour le stockage |

## Qu'est-ce qu'un PVC ?

Un **PersistentVolumeClaim (PVC)** est une demande de stockage persistant.

**Problème sans PVC :** Quand un pod redémarre, toutes les données sont perdues.

**Solution :** Le PVC conserve les données même si le pod est supprimé.

**Utilisations typiques :**
- Base de données PostgreSQL
- Cache Redis
- Fichiers uploadés

## Appliquer

```bash
kubectl apply -f pvcs.yaml
```

## Debug

```bash
# Lister les PVC
kubectl get pvc -n algohive

# Voir les PV (volumes physiques)
kubectl get pv

# Statut d'un PVC
kubectl describe pvc <nom> -n algohive

# Vérifier l'espace utilisé (depuis un pod)
kubectl exec -it <pod> -n algohive -- df -h
```

## États d'un PVC

| État | Signification |
|------|---------------|
| `Pending` | En attente d'un volume |
| `Bound` | Lié à un volume, prêt |
| `Lost` | Volume perdu |

## Exemple de PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes:
    - ReadWriteOnce      # Un seul pod peut écrire
  resources:
    requests:
      storage: 5Gi       # Taille demandée
```
