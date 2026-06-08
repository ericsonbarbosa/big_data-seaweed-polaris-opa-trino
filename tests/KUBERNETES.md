## Teste de integração SeaweedFS + Kubernetes
## Entre na VM3 k8s-node
```bash
vagrant ssh k8s-node
```

## Teste 1 - Verificar a Saúde dos PODs e o apontamento seaweedfs-storage:
```bash
sudo k3s kubectl get sc,pods -n kube-system
```

Retorno esperado:  
***storageclass.storage.k8s.io/seaweedfs-storage (default)***

Pods do seaweed-csi-driver (geralmente um controller e um node) com o status Running:  
***pod/seaweedfs-csi-controller-66fd64d57b-tn88k   5/5     Running     5 (21h ago)   22h***   
***pod/seaweedfs-csi-node-ktvdr                    3/3     Running     4 (38m ago)   22h***   

## Teste 2 - Realizaremos os testes de Escrita e Lakehouse

### 2.1. Vamos criar e aplicar automaticamente um manifesto YAML com as seguintes características:

1. Um PVC chamado pvc-teste-lakehouse solicitando 1 GiB de armazenamento da classe seaweedfs-storage.

2. Um Pod chamado pod-teste-escrita que monta esse PVC em /mnt/lakehouse e escreve um arquivo status.txt dentro do volume.
```bash
sudo k3s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-teste-lakehouse
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: seaweedfs-storage
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-teste-escrita
spec:
  containers:
  - name: worker
    image: alpine
    command: ["/bin/sh", "-c"]
    args: ["echo 'Integracao K3s SeaweedFS' > /mnt/lakehouse/status.txt && sync; sleep 3600"]
    volumeMounts:
    - name: storage-seaweed
      mountPath: /mnt/lakehouse
  volumes:
  - name: storage-seaweed
    persistentVolumeClaim:
      claimName: pvc-teste-lakehouse
EOF
```
## Teste 3 - Verificação do POD, aguarde o POD subir e verifique:
```bash
sudo k3s kubectl get pvc pvc-teste-lakehouse
```

```bash
sudo k3s kubectl get pod pod-teste-escrita
```
Retorno esperado:  
***PVC Bound e Pod Running***

## Teste 4 - Verificação de leitura do arquvo recem criado:
```bash
sudo k3s kubectl exec pod-teste-escrita -- cat /mnt/lakehouse/status.txt
```
Retorno esperado:  
***Integracao K3s SeaweedFS***  

## 🧹 Limpeza dos recursos criados nos testes (K3s + SeaweedFS)
### 1. Deletar o Pod de teste

```bash
sudo k3s kubectl delete pod pod-teste-escrita --ignore-not-found=true
```

### 2. Deletar o PVC (e o volume persistente associado)

```bash
sudo k3s kubectl delete pvc pvc-teste-lakehouse --ignore-not-found=true
```

### 3. Remover o arquivo diretamente do SeaweedFS S3
Se quiser apagar o dado escrito dentro do bucket warehouse (caso o volume tenha sido provisionado como um subdiretório do bucket), você pode usar o AWS CLI:

```bash
# Na VM seaweedfs-node
AWS_ACCESS_KEY_ID=admin AWS_SECRET_ACCESS_KEY=admin_secret aws --endpoint-url http://192.168.56.101:8333 s3 rm s3://warehouse/pvc-teste-lakehouse/status.txt
```