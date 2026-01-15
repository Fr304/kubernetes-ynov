# Base - Namespace

## Fichiers

| Fichier | Description |
|---------|-------------|
| `namespace.yaml` | Crée le namespace `algohive` |

## Qu'est-ce qu'un Namespace ?

Un namespace est un **espace isolé** dans Kubernetes. C'est comme un dossier qui regroupe toutes les ressources d'une application.

**Avantages :**
- Isolation des ressources
- Gestion des droits par namespace
- Facilite la suppression (supprimer le namespace = tout supprimer)

## Appliquer

```bash
kubectl apply -f namespace.yaml
```

## Debug

```bash
# Lister les namespaces
kubectl get namespaces

# Voir les ressources dans le namespace
kubectl get all -n algohive

# Supprimer le namespace (ATTENTION: supprime tout !)
kubectl delete namespace algohive
```
