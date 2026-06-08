# 🚀 Guia de Testes de Integração e Sistema: Ecossistema Big Data
## SeaweedFS | Hive | Trino

Este documento fornece as instruções passo a passo para acessar as plataformas e executar os testes de integração que validam a fluidez dos dados entre o armazenamento (S3), o catálogo de metadados (Hive) e o motor de consulta distribuída (Trino).

---
## Teste 1 - Acesse a interface UI do Trino:

Login: admin
http://192.168.56.102:8080

## Teste 2 - SeaweedFS-Node (Armazenamento e Metadados)
Este nó contém o **S3** e o **Hive Server/Metastore**.

* **Acesso à VM:** 
    ```bash
    vagrant ssh seaweedfs-node
    ```
* **Validar se o Metastore está rodando na 9083 e pronto para receber o Trino:**
    ```bash
    sudo netstat -nlpt | grep 9083
    ```
    *Nota: O comando deve retornar que está ecutando: tcp 0.0.0.0:9083*

## Teste 3 - Trino-Node (Motor de Consulta)
Este nó é responsável pela execução de queries de alta performance sobre os dados do Hadoop.

* **Acesso à VM:**
    ```bash
    vagrant ssh trino-node
    ```
* **Inserir o TOKEN novo no catalog iceberg.properties do Trino:**
    ```bash
    # Captura do TOKEN para a variável TOKEN_TRINO:
    TOKEN_TRINO=$(curl -s -X POST http://192.168.56.101:8182/api/catalog/v1/oauth/tokens \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=root&client_secret=root_secret_changeme&scope=PRINCIPAL_ROLE:ALL" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

    # Aplicação do TOKEN_TRINO no iceberg.properties da VM:
    sudo sed -i "s|^iceberg.rest-catalog.oauth2.token=.*|iceberg.rest-catalog.oauth2.token=$TOKEN_TRINO|" \
    /opt/trino/etc/catalog/iceberg.properties

    # Restart do serviço com pausa de 15 segundos:
    sudo systemctl restart trino && sleep 15
    ```

* **Acesso ao Trino CLI:**
    ```bash
    trino --catalog iceberg --schema default
    ```
    *Nota: O Trino utiliza conectores para "enxergar" o catálogo do Hive e os arquivos físicos no HDFS.*

---

### ✅ Passo A: Escrita e Consulta via Trino CLI
Objetivo: Validar se o Trino consegue ler do Hive e criar novos arquivos no S3. No `Trino CLI`, execute:

```sql
-- Deve listar o catalog iceberg
SHOW CATALOGS;

-- Mostrar os SCHEMS dentro do iceberg
SHOW SCHEMAS IN iceberg;

-- Cria um schema de teste
    CREATE SCHEMA IF NOT EXISTS iceberg.sandbox
    WITH (location = 's3://warehouse/sandbox/');

-- Cria uma tabela Iceberg real gravando no SeaweedFS
CREATE TABLE iceberg.sandbox.teste (
    id    BIGINT,
    nome  VARCHAR
) WITH (format = 'PARQUET');

INSERT INTO iceberg.sandbox.teste VALUES (1, 'Polaris OK');

SELECT * FROM iceberg.sandbox.teste;
```

### ✅ Passo B: – Verificar a gravação dos dados no SeaweedFS S3
Liste o conteúdo do bucket diretamente no S3:
```bash
# Usando AWS CLI recursivo
AWS_ACCESS_KEY_ID=admin AWS_SECRET_ACCESS_KEY=admin_secret aws --endpoint-url http://192.168.56.101:8333 s3 ls s3://warehouse/ --recursive

# Ou via curl no endpoint REST (listagem simples)
http://192.168.56.101:8888/buckets/warehouse/
```

### ✅ Passo C: – Validar as tabelas do Metastore no PostgreSQL
Conecte‑se ao PostgreSQL e verifique se as informações da tabela criada foram registradas:

```bash
sudo -u postgres psql -d metastore -c "SELECT t.\"TBL_NAME\", d.\"NAME\" FROM \"TBLS\" t JOIN \"DBS\" d ON t.\"DB_ID\" = d.\"DB_ID\";"
```
Saída esperada:

```text
  tabela  | banco
----------+---------
 usuarios | lab_ed
```

## 🧹 Limpeza do labratório

```sql
-- 1. Exclusão do schema
DROP SCHEMA IF EXISTS hive.lab_ed CASCADE;

-- 2. Conferir exclusão do schema, deve retornar (0 rows)
SHOW TABLES;
```