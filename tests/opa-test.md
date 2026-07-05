# Role: Open Policy Agent (OPA)

## Estrutura

```text
roles/  
└── opa/  
    ├── defaults/  
    │   └── main.yml          # Variáveis de configuração   
    ├── handlers/  
    │   └── main.yml          # Handlers para restart/reload  
    ├── tasks/  
    │   └── main.yml          # Tasks de instalação e configuração  
    ├── templates/  
    │   ├── opa.service.j2    # Unit do systemd  
    │   └── config.yaml.j2    # Configuração do OPA (opcional para server mode)  
    └── README.md             # Documentação do role
```

## Visão Geral
Este role instala e configura o OPA em modo servidor para centralizar governança e autorização no projeto Big Data.

## Endpoints Principais

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/health` | GET | Health check do servidor |
| `/v1/data/{path}` | GET/POST | Avaliar políticas de dados |
| `/v1/policies` | GET/PUT/DELETE | Gerenciar políticas Rego |
| `/v1/query` | POST | Executar consultas Rego ad-hoc |

## Testes Rápidos (após instalação)

```bash
# Health check
curl http://127.0.0.1:8181/health

# Listar políticas carregadas
curl http://127.0.0.1:8181/v1/policies

# Avaliar política de exemplo
curl -X POST http://127.0.0.1:8181/v1/data/http.authz \
  -H "Content-Type: application/json" \
  -d '{"input": {"method": "GET", "path": ["v1", "data", "example"]}}'

# Query Rego ad-hoc
curl -X POST http://127.0.0.1:8181/v1/query \
  -H "Content-Type: application/json" \
  -d '{"query": "data.example.greeting = message"}'