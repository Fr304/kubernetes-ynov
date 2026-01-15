# Monitoring - Grafana

Dashboards de monitoring pour visualiser les métriques.

## Fichiers

| Fichier | Description |
|---------|-------------|
| `grafana-serviceaccount.yaml` | Identité du pod Grafana |
| `grafana-secrets.yaml` | Identifiants admin |
| `grafana-configmaps.yaml` | Configuration Grafana |
| `grafana-deployment.yaml` | Déploie Grafana + sidecars |
| `grafana-service.yaml` | Expose en interne (ClusterIP) |
| `kustomization.yaml` | Fichier Kustomize |

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Pod Grafana                                    │
│                                                 │
│  ┌─────────────────┐  ┌─────────────────────┐   │
│  │ grafana-sc-     │  │ grafana-sc-         │   │
│  │ dashboard       │  │ datasources         │   │
│  │ (sidecar)       │  │ (sidecar)           │   │
│  └────────┬────────┘  └──────────┬──────────┘   │
│           │                      │              │
│           ▼                      ▼              │
│  ┌──────────────────────────────────────────┐   │
│  │           Grafana (port 3000)            │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

**Sidecars :** Conteneurs auxiliaires qui surveillent les ConfigMaps pour charger automatiquement les dashboards et datasources.

## Appliquer

```bash
# Avec Kustomize (recommandé)
kubectl apply -k .

# Manifest par manifest
kubectl apply -f grafana-serviceaccount.yaml
kubectl apply -f grafana-secrets.yaml
kubectl apply -f grafana-configmaps.yaml
kubectl apply -f grafana-deployment.yaml
kubectl apply -f grafana-service.yaml
```

## Debug

```bash
# Vérifier les pods
kubectl get pods -n monitoring

# Voir les logs de Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana

# Voir les logs des sidecars
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-datasources

# Vérifier le service
kubectl get svc -n monitoring

# Tester l'accès (depuis le pod)
kubectl exec -it -n monitoring <pod> -c grafana -- wget -qO- http://localhost:3000/api/health

# Voir les secrets (identifiants)
kubectl get secret monitoring-grafana -n monitoring -o jsonpath='{.data.admin-user}' | base64 -d
kubectl get secret monitoring-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

## Accès

- **URL :** http://grafana.algohive.local (si ingress configuré)
- **NodePort :** http://<node-ip>:30030
- **User :** admin
- **Password :** (voir dans le secret)

## Identifiants par défaut

```bash
# Récupérer le mot de passe admin
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

## Ajouter un dashboard

Créer un ConfigMap avec le label `grafana_dashboard: "1"` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mon-dashboard
  labels:
    grafana_dashboard: "1"
data:
  mon-dashboard.json: |
    { ... contenu JSON du dashboard ... }
```

Le sidecar le détectera automatiquement et l'ajoutera à Grafana.

## Erreurs courantes

| Erreur | Cause | Solution |
|--------|-------|----------|
| 502 Bad Gateway | Pod pas prêt | Attendre ou voir les logs |
| Login failed | Mauvais password | Vérifier le secret |
| No data | Datasource manquant | Configurer Prometheus |
