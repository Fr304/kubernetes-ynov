# OpenEBS - Local Persistent Volumes

OpenEBS fournit le stockage persistant local pour les pods du cluster via le provisioner `openebs.io/local`.

## Version déployée

| Composant                  | Version |
|---------------------------|---------|
| provisioner-localpv       | 3.4.0   |
| node-disk-manager (ndm)   | 2.1.0   |
| node-disk-operator        | 2.1.0   |
| node-disk-exporter        | 2.1.0   |
| linux-utils               | 3.5.0   |

## StorageClasses disponibles

| StorageClass        | Type     | ReclaimPolicy | VolumeBindingMode    |
|--------------------|----------|---------------|----------------------|
| `openebs-hostpath` | hostpath | Delete        | WaitForFirstConsumer |
| `openebs-device`   | device   | Delete        | WaitForFirstConsumer |

**Base path hostpath** : `/var/openebs/local/`

## Fichiers

| Fichier                    | Contenu                                        |
|---------------------------|------------------------------------------------|
| `00-namespace.yaml`       | Namespace `openebs`                            |
| `01-serviceaccount.yaml`  | ServiceAccount `openebs-maya-operator`         |
| `02-clusterroles.yaml`    | ClusterRole RBAC                               |
| `03-clusterrolebindings.yaml` | ClusterRoleBinding RBAC                    |
| `04-configmap.yaml`       | Config NDM (filtres, probes)                   |
| `05-storageclasses.yaml`  | StorageClasses hostpath + device               |
| `06-deployments.yaml`     | localpv-provisioner, ndm-operator, ndm-cluster-exporter |
| `07-daemonsets.yaml`      | openebs-ndm, openebs-ndm-node-exporter         |
| `08-services.yaml`        | Services Prometheus (headless)                 |

## Installation

```bash
kubectl apply -f openebs/
```

## Notes

- OpenEBS doit être installé **avant** de créer les PVC
- Le NDM tourne en `privileged: true` pour accéder aux devices
- Les données sont stockées sur le noeud qui schedule le pod (WaitForFirstConsumer)
- Les métriques sont exposées sur `:9100` (cluster) et `:9101` (node)
