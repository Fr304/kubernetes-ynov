# Guide de Déploiement sur Cluster Kubeadm

Ce guide explique comment déployer l'ensemble de l'infrastructure sur un cluster Kubernetes créé avec kubeadm.

## Prérequis

### Cluster Kubernetes
- Cluster kubeadm fonctionnel (1 master + N workers)
- kubectl configuré sur votre machine
- CNI installé — **Flannel v0.28.0** (voir [Étape 0a](#étape-0a--déployer-flannel-cni))
- Stockage persistant — **OpenEBS v3.5.0** (voir [Étape 0b](#étape-0b--déployer-openebs))

### Vérification du cluster

```bash
# Vérifier que le cluster est accessible
kubectl cluster-info

# Vérifier les nodes
kubectl get nodes

# Tous les nodes doivent être "Ready"
NAME      STATUS   ROLES           AGE   VERSION
master    Ready    control-plane   10d   v1.29.0
worker1   Ready    <none>          10d   v1.29.0
worker2   Ready    <none>          10d   v1.29.0
```

---

## Ordre de Déploiement

L'ordre est **important** car certains composants dépendent d'autres :

```
0a. Flannel (CNI)   → Réseau inter-pods (avant de joindre les workers)
0b. OpenEBS         → Stockage local persistant (avant les PVC)
1.  MetalLB         → Fournit les IPs externes (LoadBalancer)
2.  Ingress NGINX   → Routage HTTP/HTTPS (utilise MetalLB)
3.  Application     → Algohive + bases de données
4.  Monitoring      → Grafana (optionnel)
5.  KubeView        → Visualisation (optionnel)
```

---

## Étape 0a : Déployer Flannel (CNI)

Flannel est le CNI (Container Network Interface) qui gère le réseau overlay entre les pods. Il doit être installé **sur le master avant de joindre les workers**.

```bash
# Depuis le dossier algohive-k8s/
kubectl apply -f kube-flannel/
```

Cela applique dans l'ordre : namespace, serviceaccount, RBAC, configmap, daemonset.

### Vérification

```bash
# Attendre que le DaemonSet soit prêt sur tous les noeuds
kubectl wait --namespace kube-flannel \
  --for=condition=ready pod \
  --selector=app=flannel \
  --timeout=120s

kubectl get pods -n kube-flannel
```

Résultat attendu (un pod par noeud) :

```
NAMESPACE      NAME                  READY   STATUS    NODE
kube-flannel   kube-flannel-ds-xxx   1/1     Running   master
kube-flannel   kube-flannel-ds-yyy   1/1     Running   worker1
kube-flannel   kube-flannel-ds-zzz   1/1     Running   worker2
```

> Voir [`kube-flannel/README.md`](kube-flannel/README.md) pour les détails de configuration (CIDR, backend VXLAN).

---

## Étape 0b : Déployer OpenEBS

OpenEBS fournit le stockage local persistant (`openebs-hostpath`) utilisé par tous les PVC de l'application. Il doit être installé **avant** `kubectl apply -k .`.

```bash
# Depuis le dossier algohive-k8s/
kubectl apply -f openebs/
```

Cela applique dans l'ordre : namespace, serviceaccount, RBAC, configmap, storageclasses, deployments, daemonsets, services.

### Vérification

```bash
# Attendre que le provisioner soit prêt
kubectl wait --namespace openebs \
  --for=condition=ready pod \
  --selector=name=openebs-localpv-provisioner \
  --timeout=120s

kubectl get pods -n openebs
kubectl get storageclass
```

Résultat attendu :

```
NAME               PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE
openebs-device     openebs.io/local   Delete          WaitForFirstConsumer
openebs-hostpath   openebs.io/local   Delete          WaitForFirstConsumer
```

> **Note :** Les données sont stockées dans `/var/openebs/local/` sur le noeud qui schedule le pod.
> Voir [`openebs/README.md`](openebs/README.md) pour les détails.

---

## Étape 1 : Déployer MetalLB

MetalLB permet d'avoir des IPs externes pour les services LoadBalancer (indispensable en bare-metal).

```bash
# 1. Installer MetalLB via manifests officiels
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml

# 2. Attendre que les pods soient prêts
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

# 3. Configurer le pool d'IPs (ADAPTER À VOTRE RÉSEAU)
kubectl apply -f metallb/10-ipaddresspool.yaml
kubectl apply -f metallb/11-l2advertisement.yaml
```

### ⚠️ Configuration réseau

Éditez `metallb/10-ipaddresspool.yaml` pour adapter la plage d'IPs à votre réseau :

```yaml
spec:
  addresses:
    - 192.168.1.100-192.168.1.120   # Adaptez à votre réseau !
```

Ces IPs doivent :
- Être sur le même sous-réseau que vos nodes
- Ne pas être utilisées par d'autres machines (hors plage DHCP)

### Vérification

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

---

## Étape 2 : Déployer Ingress NGINX

L'Ingress Controller permet de router le trafic HTTP/HTTPS vers vos applications.

```bash
# 1. Installer Ingress NGINX via manifests officiels
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

# 2. Attendre que le controller soit prêt
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 3. Vérifier que l'IP externe est attribuée par MetalLB
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Vous devriez voir une EXTERNAL-IP (ex: 192.168.1.100) :

```
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
ingress-nginx-controller   LoadBalancer   10.104.163.197  192.168.1.100   80:31867/TCP,443:30308/TCP
```

---

## Étape 3 : Déployer l'Application Algohive

### Option A : Tout d'un coup avec Kustomize (recommandé)

```bash
# Depuis le dossier algohive-k8s/
kubectl apply -k .
```

### Option B : Dossier par dossier

```bash
# 1. Namespace
kubectl apply -f base/

# 2. Secrets (mots de passe)
kubectl apply -f secrets/

# 3. ConfigMaps (configuration)
kubectl apply -f configmaps/

# 4. Volumes persistants
kubectl apply -f volumes/

# 5. Deployments (applications)
kubectl apply -f deployments/

# 6. Services et Ingress
kubectl apply -f services/
```

### Vérification

```bash
# Voir tous les pods
kubectl get pods -n algohive

# Attendre que tous les pods soient Running
kubectl wait --namespace algohive \
  --for=condition=ready pod \
  --all \
  --timeout=300s
```

---

## Étape 4 : Déployer le Monitoring (optionnel)

```bash
kubectl apply -k monitoring/
```

---

## Étape 5 : Déployer KubeView (optionnel)

```bash
kubectl apply -k kubeview/
```

---

## Configuration DNS / Hosts

Pour accéder aux applications via les noms de domaine, ajoutez ces entrées dans `/etc/hosts` (ou votre DNS) :

```bash
# Remplacez 192.168.1.100 par l'IP de votre Ingress
192.168.1.100  algohive.local
192.168.1.100  api.algohive.local
192.168.1.100  beehub.algohive.local
192.168.1.100  grafana.algohive.local
192.168.1.100  kubeview.algohive.local
```

Sous Windows : `C:\Windows\System32\drivers\etc\hosts`

---

## Script de Déploiement Complet

Créez un script `install-all.sh` :

```bash
#!/bin/bash
set -e

echo "=== 1/5 Déploiement MetalLB ==="
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s
kubectl apply -f metallb/10-ipaddresspool.yaml
kubectl apply -f metallb/11-l2advertisement.yaml
echo "✓ MetalLB OK"

echo ""
echo "=== 2/5 Déploiement Ingress NGINX ==="
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
echo "✓ Ingress NGINX OK"

echo ""
echo "=== 3/5 Déploiement Application ==="
kubectl apply -k .
echo "✓ Application déployée"

echo ""
echo "=== 4/5 Attente des pods ==="
sleep 10
kubectl wait --namespace algohive --for=condition=ready pod --all --timeout=300s
echo "✓ Tous les pods sont prêts"

echo ""
echo "=== 5/5 Résumé ==="
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              DÉPLOIEMENT TERMINÉ !                       ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║ IP Ingress: $INGRESS_IP"
echo "║                                                          ║"
echo "║ Ajoutez dans /etc/hosts :                                ║"
echo "║   $INGRESS_IP  algohive.local                      ║"
echo "║   $INGRESS_IP  api.algohive.local                  ║"
echo "║   $INGRESS_IP  grafana.algohive.local              ║"
echo "║                                                          ║"
echo "║ URLs :                                                   ║"
echo "║   http://algohive.local                                  ║"
echo "║   http://api.algohive.local                              ║"
echo "║   http://grafana.algohive.local                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
```

---

## Vérification Globale

```bash
# Voir tous les namespaces
kubectl get ns

# Voir tous les pods de tous les namespaces
kubectl get pods -A

# Voir tous les services LoadBalancer
kubectl get svc -A | grep LoadBalancer

# Voir tous les Ingress
kubectl get ingress -A
```

### État attendu

```
NAMESPACE        NAME                              READY   STATUS
kube-flannel     kube-flannel-ds-xxx               1/1     Running
openebs          openebs-localpv-provisioner-xxx   1/1     Running
openebs          openebs-ndm-xxx                   1/1     Running
openebs          openebs-ndm-operator-xxx          1/1     Running
metallb-system   controller-xxx                    1/1     Running
metallb-system   speaker-xxx                       1/1     Running
ingress-nginx    ingress-nginx-controller-xxx      1/1     Running
algohive         algohive-client-xxx               1/1     Running
algohive         algohive-server-xxx               1/1     Running
algohive         algohive-db-xxx                   1/1     Running
algohive         algohive-cache-xxx                1/1     Running
monitoring       grafana-xxx                       1/1     Running
```

---

## Dépannage

### MetalLB ne donne pas d'IP

```bash
# Vérifier les logs du controller
kubectl logs -n metallb-system -l component=controller

# Vérifier que l'IPAddressPool existe
kubectl get ipaddresspool -n metallb-system
```

### Ingress ne route pas

```bash
# Vérifier les logs du controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Vérifier la config NGINX générée
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | grep server_name
```

### Pods en CrashLoopBackOff

```bash
# Voir les logs du pod
kubectl logs -n algohive <nom-pod>

# Voir les événements
kubectl describe pod -n algohive <nom-pod>
```

### Connexion refusée aux services

```bash
# Vérifier que les endpoints existent
kubectl get endpoints -n algohive

# Tester depuis un pod
kubectl run test --rm -it --image=busybox -- wget -qO- http://algohive-server:8080/health
```

---

## Désinstallation

```bash
# Supprimer l'application
kubectl delete -k .

# Supprimer Ingress NGINX
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

# Supprimer MetalLB
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml

# Supprimer OpenEBS
kubectl delete -f openebs/

# Supprimer Flannel
kubectl delete -f kube-flannel/

# Ou supprimer les namespaces directement
kubectl delete ns algohive metallb-system ingress-nginx monitoring openebs kube-flannel
```

---

## Résumé des Commandes

| Action | Commande |
|--------|----------|
| Déployer tout | `kubectl apply -k .` |
| Voir les pods | `kubectl get pods -A` |
| Logs d'un pod | `kubectl logs -n <ns> <pod>` |
| État du cluster | `./deploy.sh status` |
| URLs d'accès | `./deploy.sh urls` |
| Redémarrer un service | `kubectl rollout restart deploy/<name> -n <ns>` |
| Supprimer tout | `kubectl delete -k .` |
