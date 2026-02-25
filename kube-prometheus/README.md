# kube-prometheus-stack

Stack de monitoring Kubernetes complète basée sur Prometheus Operator.

## Version déployée

| Composant                  | Version  |
|---------------------------|----------|
| kube-prometheus-stack     | 80.14.3  |
| Prometheus                | v3.9.1   |
| Alertmanager              | v0.30.1  |
| kube-state-metrics        | 2.17.0   |
| prometheus-node-exporter  | 1.10.2   |

## Prérequis

- Helm 3 installé
- Namespace `monitoring` créé (ou `--create-namespace`)
- Ingress NGINX déployé (pour l'accès Grafana)

## Installation

```bash
# 1. Ajouter le repo Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Installer la stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version 80.14.3 \
  -f kube-prometheus/values.yaml

# 3. Vérifier le déploiement
kubectl get pods -n monitoring
```

## Composants déployés

| Composant | Type | Description |
|-----------|------|-------------|
| `monitoring-kube-prometheus-operator` | Deployment | Gère les CRDs Prometheus |
| `prometheus-monitoring-kube-prometheus-prometheus-0` | StatefulSet | Instance Prometheus |
| `alertmanager-monitoring-kube-prometheus-alertmanager-0` | StatefulSet | Gestion des alertes |
| `monitoring-kube-state-metrics` | Deployment | Métriques des objets K8s |
| `monitoring-prometheus-node-exporter` | DaemonSet | Métriques système par noeud |
| `monitoring-grafana` | Deployment | Dashboards de visualisation |

## Services exposés

| Service | Port | Type |
|---------|------|------|
| `monitoring-kube-prometheus-prometheus` | 9090 | ClusterIP |
| `monitoring-kube-prometheus-alertmanager` | 9093 | ClusterIP |
| `monitoring-grafana` | 80 | ClusterIP |
| `monitoring-kube-state-metrics` | 8080 | ClusterIP |
| `monitoring-prometheus-node-exporter` | 9100 | ClusterIP |

## Accès Grafana

L'ingress Grafana est géré dans [`services/ingress.yaml`](../services/ingress.yaml) :

```
http://grafana.frd75.local  →  monitoring-grafana:80
```

Ajouter dans `/etc/hosts` :
```
192.168.1.100  grafana.frd75.local
```

Identifiants par défaut :
```bash
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

## Mise à jour

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 80.14.3 \
  -f kube-prometheus/values.yaml
```

## Désinstallation

```bash
helm uninstall monitoring -n monitoring

# Nettoyer les CRDs (optionnel — supprime toutes les configs)
kubectl delete crd \
  alertmanagers.monitoring.coreos.com \
  podmonitors.monitoring.coreos.com \
  probes.monitoring.coreos.com \
  prometheuses.monitoring.coreos.com \
  prometheusrules.monitoring.coreos.com \
  servicemonitors.monitoring.coreos.com \
  thanosrulers.monitoring.coreos.com
```

## Vérification

```bash
# Pods de la stack
kubectl get pods -n monitoring

# Ressources CRD actives
kubectl get prometheus,alertmanager,servicemonitor -n monitoring

# Logs de l'opérateur
kubectl logs -n monitoring -l app=kube-prometheus-stack-operator

# Tester Prometheus
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090
```
