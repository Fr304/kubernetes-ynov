# Secrets

## Fichiers

| Fichier | Description |
|---------|-------------|
| `secrets.yaml` | Mots de passe et données sensibles |

## Qu'est-ce qu'un Secret ?

Un Secret stocke des données sensibles (mots de passe, tokens, clés API) de manière encodée en base64.

**Contenu typique :**
- Mot de passe PostgreSQL
- Mot de passe Redis
- Clés API
- Tokens JWT

## Appliquer

```bash
kubectl apply -f secrets.yaml
```

## Debug

```bash
# Lister les secrets
kubectl get secrets -n algohive

# Voir le contenu d'un secret (encodé base64)
kubectl get secret <nom> -n algohive -o yaml

# Décoder une valeur
kubectl get secret <nom> -n algohive -o jsonpath='{.data.password}' | base64 -d

# Décrire un secret
kubectl describe secret <nom> -n algohive
```

## Sécurité

- Ne jamais commiter les secrets en clair dans Git
- Utiliser des outils comme `sealed-secrets` ou `vault` en production
- Les secrets sont encodés en base64, pas chiffrés !
