# Testes de Sistema Postgres
## Teste 1 - Listar todas as tabelas do Metastore (incluindo as de sistema)

```bash
sudo -u postgres psql -d metastore -c "\dt"
```

Você verá algo como:

```text
            List of relations
 Schema |       Name        | Type  | Owner 
--------+-------------------+-------+-------
 public | AUX_TABLE         | table | hive
 public | BUCKETING_COLS    | table | hive
 public | CDS               | table | hive
 public | COLUMNS_V2        | table | hive
 public | COMPACTION_QUEUE  | table | hive
 public | COMPLETED_TXN_COMPONENTS | table | hive
 public | DATABASE_PARAMS   | table | hive
 public | DBS               | table | hive
 public | DB_PRIVS          | table | hive
 public | DELEGATION_TOKENS | table | hive
```

## Teste 2 - Consultar a versão do Metastore

```bash
sudo -u postgres psql -d metastore -c "SELECT * FROM \"VERSION\";"
```

Saída típica:

```text
 VER_ID | SCHEMA_VERSION | VERSION_COMMENT 
--------+----------------+-----------------
      1 | 3.1.0          | Hive release version 3.1.0
```