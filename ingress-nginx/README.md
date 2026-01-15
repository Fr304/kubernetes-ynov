# Ingress NGINX Controller

L'Ingress NGINX Controller est un contrôleur Ingress qui utilise NGINX comme reverse proxy et load balancer. Il permet d'exposer les services HTTP/HTTPS du cluster vers l'extérieur.

## État actuel du cluster

| Composant | Status | Version |
|-----------|--------|---------|
| Controller | ✅ Running | v1.11.1 |
| Service | ✅ LoadBalancer | 192.168.1.100 |
| IngressClass | ✅ nginx | Actif |
| Webhook | ✅ Configuré | Validating |

**Points d'accès:**
- HTTP: `http://192.168.1.100`
- HTTPS: `https://192.168.1.100`

---

## Architecture

```
                         Internet / Réseau Local
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │      MetalLB (Layer 2)       │
                    │      192.168.1.100           │
                    └──────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                    ingress-nginx-controller                       │
│                         (LoadBalancer)                            │
│                    Port 80 (HTTP) / 443 (HTTPS)                  │
└──────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                   NGINX Ingress Controller                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    nginx.conf (dynamique)                   │  │
│  │                                                             │  │
│  │  server {                                                   │  │
│  │    listen 80;                                               │  │
│  │    server_name app.example.com;                             │  │
│  │    location / {                                             │  │
│  │      proxy_pass http://service-backend;                     │  │
│  │    }                                                        │  │
│  │  }                                                          │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
              ┌──────────┐  ┌──────────┐  ┌──────────┐
              │ Service  │  │ Service  │  │ Service  │
              │    A     │  │    B     │  │    C     │
              └──────────┘  └──────────┘  └──────────┘
```

---

## Installation

### Option 1: Via manifests officiels

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
```

### Option 2: Via Helm

```bash
# Ajouter le repo Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installer
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --version 4.11.1
```

### Option 3: Via manifests séparés (ce dossier)

```bash
# Appliquer tous les manifests dans l'ordre
kubectl apply -f .

# Attendre que le controller soit prêt
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

---

## Structure des Manifests

| Fichier | Description |
|---------|-------------|
| `00-namespace.yaml` | Namespace `ingress-nginx` |
| `01-serviceaccounts.yaml` | ServiceAccounts (controller + admission) |
| `02-clusterroles.yaml` | Permissions cluster-wide |
| `03-roles.yaml` | Permissions namespace-scoped |
| `04-rolebindings.yaml` | Bindings SA → Roles |
| `05-configmap.yaml` | Configuration NGINX |
| `06-ingressclass.yaml` | IngressClass "nginx" |
| `07-deployment.yaml` | Deployment du controller |
| `08-services.yaml` | Services LoadBalancer + Webhook |
| `09-validatingwebhook.yaml` | Webhook de validation |
| `10-admission-jobs.yaml` | Jobs de configuration certificats |

---

## Description des Composants

### Controller (`07-deployment.yaml`)

Le **Controller** est le composant principal:
- Surveille les ressources Ingress du cluster
- Génère dynamiquement la configuration NGINX
- Recharge NGINX automatiquement lors des changements
- Expose un endpoint de health check sur le port 10254

```yaml
image: registry.k8s.io/ingress-nginx/controller:v1.11.1
args:
  - /nginx-ingress-controller
  - --controller-class=k8s.io/ingress-nginx
  - --ingress-class=nginx
  - --configmap=$(POD_NAMESPACE)/ingress-nginx-controller
```

### Services (`08-services.yaml`)

Deux services sont déployés:

1. **ingress-nginx-controller** (LoadBalancer)
   - Point d'entrée pour le trafic HTTP/HTTPS
   - Reçoit une IP externe via MetalLB
   - Ports: 80 (HTTP), 443 (HTTPS)

2. **ingress-nginx-controller-admission** (ClusterIP)
   - Service interne pour le webhook
   - Utilisé par l'API Server Kubernetes

### ConfigMap (`05-configmap.yaml`)

Permet de personnaliser NGINX sans modifier le deployment:

```yaml
data:
  proxy-body-size: "50m"           # Taille max requêtes
  proxy-read-timeout: "120"        # Timeout lecture
  use-forwarded-headers: "true"    # Headers X-Forwarded-*
  ssl-protocols: "TLSv1.2 TLSv1.3" # Protocoles TLS
```

---

## Utilisation

### Créer un Ingress basique

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mon-app
  namespace: default
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mon-service
                port:
                  number: 80
```

### Ingress avec TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mon-app-tls
  namespace: default
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.example.com
      secretName: mon-certificat-tls
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mon-service
                port:
                  number: 80
```

### Annotations utiles

```yaml
metadata:
  annotations:
    # Redirection HTTP → HTTPS
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

    # Taille max upload
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"

    # Timeout
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"

    # Rewrite path
    nginx.ingress.kubernetes.io/rewrite-target: /

    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"

    # CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"

    # Auth basique
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
```

---

## Commandes de Debug

### Vérifier l'état des pods

```bash
kubectl get pods -n ingress-nginx
```

### Voir les logs du controller

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f
```

### Vérifier la configuration NGINX générée

```bash
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- cat /etc/nginx/nginx.conf
```

### Lister les Ingress

```bash
kubectl get ingress -A
```

### Vérifier le service LoadBalancer

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### Tester la connectivité

```bash
# Test HTTP
curl -v http://192.168.1.100

# Test avec Host header
curl -H "Host: app.example.com" http://192.168.1.100

# Test HTTPS (ignorer certificat auto-signé)
curl -k https://192.168.1.100
```

### Voir les événements

```bash
kubectl get events -n ingress-nginx --sort-by='.lastTimestamp'
```

### Redémarrer le controller

```bash
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```

---

## Problèmes Courants

| Problème | Cause possible | Solution |
|----------|----------------|----------|
| 502 Bad Gateway | Backend non disponible | Vérifier le service backend |
| 503 Service Unavailable | Pas de pods backend | Vérifier le deployment backend |
| 404 Not Found | Path ou host incorrect | Vérifier la config Ingress |
| Certificat invalide | Secret TLS manquant | Créer le secret TLS |
| Service en Pending | MetalLB non configuré | Vérifier MetalLB |

### Débugger un 502/503

```bash
# Vérifier que le backend existe
kubectl get svc <nom-service> -n <namespace>

# Vérifier que les pods backend tournent
kubectl get pods -n <namespace> -l <selector>

# Vérifier les endpoints
kubectl get endpoints <nom-service> -n <namespace>
```

---

## Configuration Avancée

### Activer les métriques Prometheus

Modifier le deployment pour ajouter `--enable-metrics=true`:

```yaml
args:
  - /nginx-ingress-controller
  - --enable-metrics=true
  - --metrics-per-host=false
```

### Définir nginx comme IngressClass par défaut

```bash
kubectl annotate ingressclass nginx \
  ingressclass.kubernetes.io/is-default-class=true
```

### Configurer le proxy protocol (si load balancer externe)

```yaml
# Dans la ConfigMap
data:
  use-proxy-protocol: "true"
```

---

## Références

- [Documentation officielle](https://kubernetes.github.io/ingress-nginx/)
- [GitHub](https://github.com/kubernetes/ingress-nginx)
- [Annotations disponibles](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [ConfigMap options](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/)
