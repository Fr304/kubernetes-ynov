# Kube-Flannel CNI

Flannel est le CNI (Container Network Interface) utilisé pour le réseau overlay du cluster.

## Version déployée

| Composant       | Version              |
|----------------|----------------------|
| flannel        | v0.28.0              |
| flannel-cni-plugin | v1.8.0-flannel1  |

## Configuration réseau

- **Pod CIDR** : `10.244.0.0/16`
- **Backend** : VXLAN
- **Namespace** : `kube-flannel`

## Fichiers

| Fichier                    | Contenu                        |
|---------------------------|--------------------------------|
| `00-namespace.yaml`       | Namespace `kube-flannel`       |
| `01-serviceaccount.yaml`  | ServiceAccount `flannel`       |
| `02-clusterroles.yaml`    | ClusterRole RBAC               |
| `03-clusterrolebindings.yaml` | ClusterRoleBinding RBAC    |
| `04-configmap.yaml`       | Config réseau CNI              |
| `05-daemonset.yaml`       | DaemonSet sur tous les noeuds  |

## Installation

```bash
kubectl apply -f kube-flannel/
```

## Notes

- Flannel doit être installé **avant** de joindre les noeuds workers
- Le DaemonSet tourne sur tous les noeuds (master + workers)
- `system-node-critical` priorityClass pour éviter l'éviction
