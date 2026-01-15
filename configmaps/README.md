# ConfigMaps

## Fichiers

| Fichier | Description |
|---------|-------------|
| `configmaps.yaml` | Configurations des applications |

## Qu'est-ce qu'un ConfigMap ?

Un ConfigMap stocke des configurations non-sensibles sous forme de clés/valeurs.

**Différence avec Secret :**
- ConfigMap = données non-sensibles (URLs, ports, options)
- Secret = données sensibles (mots de passe, tokens)

**Contenu typique :**
- URLs des services
- Variables d'environnement
- Fichiers de configuration

## Appliquer

```bash
kubectl apply -f configmaps.yaml
```

## Debug

```bash
# Lister les configmaps
kubectl get configmaps -n algohive

# Voir le contenu
kubectl get configmap <nom> -n algohive -o yaml

# Décrire un configmap
kubectl describe configmap <nom> -n algohive
```

## Utilisation dans un pod

```yaml
# En variable d'environnement
env:
  - name: DATABASE_URL
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: database-url

# En fichier monté
volumes:
  - name: config
    configMap:
      name: app-config
```
