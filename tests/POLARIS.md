

---

## Laboratório via API REST

```bash
# 1. No seaweedfs-node, gerar token válido
export TOKEN=$(curl -s -X POST http://127.0.0.1:8182/api/catalog/v1/oauth/tokens \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=root&client_secret=root_secret_changeme&scope=PRINCIPAL_ROLE:ALL" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# 2. Variáveis de conveniência
export POLARIS="http://127.0.0.1:8182"
export WAREHOUSE="iceberg"
export REALM="POLARIS"
export AUTH="-H \"Authorization: Bearer $TOKEN\" -H \"Polaris-Realm: $REALM\""

# 3. Criar a tabela via API REST
curl -s -X POST "$POLARIS/api/catalog/v1/$WAREHOUSE/namespaces/api_lab/tables" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: $REALM" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "produtos",
    "location": "s3://warehouse/api_lab/produtos",
    "schema": {
      "type": "struct",
      "fields": [
        {"id": 1, "name": "id", "type": "long", "required": false},
        {"id": 2, "name": "nome", "type": "string", "required": false}
      ]
    },
    "partitionSpec": [],
    "writeOrder": [],
    "properties": {
      "format-version": "2",
      "format": "parquet"
    }
  }' | python3 -m json.tool

# 4. Listar tabelas para confirmar
curl -s "$POLARIS/api/catalog/v1/$WAREHOUSE/namespaces/api_lab/tables" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: $REALM" \
  | python3 -m json.tool

# 5. Garantir que o bucket físico existe no SeaweedFS
http://192.168.56.101:8888/buckets/warehouse/
```

## Consulta Trino e inclusão de dados na nova tabela 

```sql
-- Listar schemas para confirmar que api_lab aparece
SHOW SCHEMAS IN iceberg;

-- Listar tabelas no schema api_lab
SHOW TABLES IN iceberg.api_lab;

-- Inserir dados na tabela criada via API
INSERT INTO iceberg.api_lab.produtos VALUES 
    (1, 'Criado via API REST!'),
    (2, 'Polaris + Trino + SeaweedFS');

-- Consultar os dados
SELECT * FROM iceberg.api_lab.produtos;
```

## Listar endpoints da API REST Polaris

```bash
# Endpoints do REST Catalog (retorna os endpoints iceberg)
curl -s "http://127.0.0.1:8182/api/catalog/v1/config?warehouse=iceberg" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: POLARIS" | python3 -m json.tool

# Referência definitiva para interagir com o Polaris via curl:
# http://192.168.56.101:8182/api/catalog/v1/iceberg/{recurso}
```