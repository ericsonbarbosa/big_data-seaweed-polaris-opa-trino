# Testes de sitema as portas SeaweedFS

## Teste 1 - Verificação dos serviços SeaweedFS

| Serviço               | URL                               | Descrição                                                                 |
|-----------------------|-----------------------------------|---------------------------------------------------------------------------|
| SeaweedFS Master      | http://192.168.56.101:9333        | Painel de status do cluster (volumes ativos, health checks)               |
| SeaweedFS Filer       | http://192.168.56.101:8888        | Interface web tipo "Google Drive" para navegar pelos arquivos do data lake |
| SeaweedFS S3 Gateway  | http://192.168.56.101:8333        | Endpoint compatível com S3 (retorna XML com informações do bucket) 

## Extra: Validação no seaweedfs-node o volume shell:
```bash
# Na VM1 (SeaweedFS)
echo "ls /" | weed shell -master=localhost:9333
```
Retorno esperado:  
***buckets***  
***topics***