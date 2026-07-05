## Requitements do projeto

Instalação das dependências do projeto:
```bash
ansible-galaxy install -r requirements.yml
```
---

## Arquitetura IaC

```text
seaweed-trino-lab-data-lakehouse/
├── ansible/
│   ├── inventory/
│   │   └── hosts.ini              # IPs das VMs e grupos Ansible
│   │
│   ├── roles/
│   │   ├── common/                # Configurações básicas (rede, pacotes, utilitários)
│   │   ├── seaweed/               # SeaweedFS (Master, Volume, Filer e S3)
│   │   ├── opa/                   # Open Policy Agent (Autenticação e Autorização)
│   │   ├── postgres/              # Banco de metadados do Hive
│   │   ├── polaris/               # Polaris
│   │   ├── trino/                 # Engine SQL distribuída
│   │   └── k3s-seaweed-csi/       # Kubernetes leve + CSI Driver (opcional)
│   │
│   ├── ansible.cfg                # Ajustes do Ansible
│   └── playbook.yml               # Orquestração principal
│
├── tests/                         # Scripts de validação do laboratório
│   ├── trino-test.md
│   ├── kubernetes-test.md
│   ├── postgres-test.md
│   ├── seaweed-test.md
│   ├── opa-test.md
│   └── polaris-test.md
│
├── docs/                          # Diagramas e documentação técnica
│   ├── arquitetura/
│   ├── fluxogramas/
│   └── kubernetes/
│
├── Vagrantfile                    # Provisionamento das VMs locais
├── setup.sh                       # Execução automatizada do laboratório
├── destroy.sh                     # Destruição do ambiente
├── .gitignore                     # Exclusão de arquivos temporários
├── update-opa-bundle.sh           # Script de Atualização de Bundle OPA via GitHub
└── README.md                      # Guia técnico do projeto
```

---

## Panorama Comportamental

```text
┌─────────────────────────────────────────────────────────────┐
│                    CONSULTA OPA (Obrigatória)                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Trino   │    │  Polaris │    │   K8s    │    │   S3     │
│  (SQL)   │    │ (Catalog)│    │ (Volume) │    │ (Auth)   │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     ↓               ↓               ↓               ↓
  Query SQL    Create Table    Mount Volume    Read/Write
     ↓               ↓               ↓               ↓
  ✅/❌ OPA      ✅/❌ OPA      ✅/❌ OPA      ✅/❌ Auth
     ↓               ↓
     ↓         ┌──────────┐
     └────────>│PostgreSQL│ (Catálogo Iceberg)
               └──────────┘
```
---

## Verificação dos serviços SeaweedFS

| Serviço               | URL                                       | Descrição                                               |
|-----------------------|-------------------------------------------|---------------------------------------------------------------------------|
| SeaweedFS Master      | http://192.168.56.101:9333                | Painel de status do cluster (volumes ativos, health checks)               |
| SeaweedFS Filer       | http://192.168.56.101:8888                | Interface web tipo "Google Drive" para navegar pelo arquivos do data lake |
| SeaweedFS S3 Gateway  | http://192.168.56.101:8333                | Endpoint compatível com S3 (retorna XML com informações do bucket)        |
| Apache Polaris        | http://192.168.56.101:8182/q/health/ready | Health Check saudável e perfeitamente conectado ao PostgreSQL |
| Trino                 | http://192.168.56.102:8080        | Interface web do Trino (login: `admin`, sem senha)                        | 

## Diagramas

### Diagrama de Sequência - Fluxo GitOps do Bundle OPA

```mermaid
sequenceDiagram
    participant Dev as Desenvolvedor
    participant GH as GitHub
    participant Script as Script
    participant S3 as SeaweedFS
    participant OPA as OPA

    Dev->>GH: Commit + Push
    Dev->>Script: Executa update-opa-bundle.sh
    
    loop 5 Passos do Script
        Script->>GH: 1. Clona repositório
        Script->>Script: 2. Valida estrutura
        Script->>Script: 3. Gera manifest.json
        Script->>Script: 4. Compacta bundle.tar.gz
        Script->>S3: 5. Upload via Filer
    end
    
    loop Polling (10-30s)
        OPA->>S3: Verifica novo bundle
    end
    
    S3-->>OPA: Novo bundle detectado
    OPA->>OPA: Hot-reload (sem reinício)
    
    Note over OPA: ✅ Políticas aplicadas<br/>em até 30 segundos
```

### Diagrama de Sequência - Fluxograma da Pipiline
```mermaid
sequenceDiagram
    autonumber
    
    actor User as Usuário Final
    participant Trino as Trino
    participant OPA as OPA (SSOT)
    participant Polaris as Polaris
    participant S3 as SeaweedFS

    Note over User,S3: Fluxo com Single Source of Truth
    
    User->>Trino: SELECT * FROM producao.vendas<br/>user: rodrigo (analista)
    
    Trino->>OPA: POST /v1/data/trino/allow<br/>user: rodrigo, action: SELECT,<br/>namespace: producao
    OPA-->>Trino: {"result": true}
    
    Note over Trino,Polaris: Trino usa SERVICE ACCOUNT<br/>(não o usuário final)
    
    Trino->>Polaris: GET /namespaces/producao<br/>Authorization: Bearer <service_token>
    Polaris->>Polaris: Valida JWT do service account<br/>(tem permissão total)
    Polaris-->>Trino: Metadados Iceberg
    
    Trino->>S3: Ler Parquet<br/>(admin:admin_secret)
    S3-->>Trino: Dados
    Trino-->>User: Resultado da query
```

### Diagrama de Sequência — Governança OPA entre Frameworks
```mermaid
sequenceDiagram
    autonumber

    actor User as Usuário SQL
    participant Trino as Trino Coordinator
    participant Polaris as Polaris Catalog
    participant PG as PostgreSQL
    participant OPA as OPA Server
    participant S3 as SeaweedFS S3 Gateway
    participant Filer as SeaweedFS Filer
    participant Master as SeaweedFS Master
    participant Volume as SeaweedFS Volume
    participant K8s as Kubernetes API
    participant CSI as SeaweedFS CSI Driver
    participant Pod as Pod Aplicação

    Note over User,Pod: CENÁRIO 1 — Polaris criando namespace "financeiro" (via OPA)

    User->>Polaris: POST /v1/namespaces {name: "financeiro"}
    Polaris->>OPA: POST /v1/data/polaris/allow<br/>input: {user: "admin",<br/>action: "CreateNamespace",<br/>namespace: "financeiro"}
    OPA-->>Polaris: {"result": true}
    Polaris->>PG: INSERT INTO namespaces<br/>(name='financeiro')
    PG-->>Polaris: Namespace persistido
    Polaris->>S3: PUT /buckets/financeiro/
    S3->>Master: Alocar volume
    Master-->>S3: Volume ID: 1
    S3->>Volume: Criar bucket físico
    Volume-->>S3: Bucket criado
    S3-->>Polaris: Namespace criado
    Polaris-->>User: Namespace "financeiro" criado

    Note over User,Pod: CENÁRIO 2 — Trino query NEGADA (analista em financeiro)

    User->>Trino: SELECT * FROM financeiro.vendas
    Trino->>OPA: POST /v1/data/trino/allow<br/>input: {user: "rodrigo",<br/>role: "analista",<br/>action: "Select",<br/>namespace: "financeiro"}
    OPA-->>Trino: {"result": false}<br/>deny: ["Acesso negado..."]
    Trino-->>User: Access Denied:<br/>User 'rodrigo' cannot<br/>read namespace 'financeiro'

    Note over User,Pod: CENÁRIO 3 — Trino query PERMITIDA (analista em producao)

    User->>Trino: SELECT * FROM producao.clientes
    Trino->>OPA: POST /v1/data/trino/allow<br/>input: {user: "rodrigo",<br/>role: "analista",<br/>action: "Select",<br/>namespace: "producao"}
    OPA-->>Trino: {"result": true}
    Trino->>Polaris: GET /v1/namespaces/<br/>producao/tables/clientes<br/>(REST Catalog API)
    Polaris->>PG: SELECT * FROM tables<br/>WHERE namespace='producao'
    PG-->>Polaris: Metadados Iceberg
    Polaris-->>Trino: Schema + localização S3
    Trino->>S3: GET /producao/clientes/<br/>data/*.parquet (S3 API :8333)
    S3->>Master: Onde estão os blocos?
    Master-->>S3: Volume 1, offsets [0-1024]
    S3->>Volume: READ blocks [0-1024]
    Volume-->>S3: Dados Parquet (378 bytes)
    S3-->>Trino: Arquivos Parquet retornados
    Trino->>Trino: Planejar execução distribuída
    Trino->>Trino: Executar nos Workers
    Trino-->>User: 1.234 rows returned

    Note over User,Pod: CENÁRIO 4 — Kubernetes montando volume SeaweedFS (via OPA)

    User->>K8s: kubectl apply -f<br/>pod-with-seaweedfs.yaml
    K8s->>OPA: POST /v1/data/k8s/allow<br/>input: {serviceAccount: "app-trino",<br/>action: "MountVolume",<br/>bucket: "warehouse"}
    OPA-->>K8s: {"result": true}
    K8s->>CSI: Provisionar volume<br/>(SeaweedFS CSI Driver)
    CSI->>Filer: Criar diretório<br/>/persistent/warehouse
    Filer->>Master: Alocar volumes
    Master-->>Filer: Volumes [1,2,3]
    Filer->>Volume: Criar estrutura física
    Volume-->>Filer: Volume provisionado
    Filer-->>CSI: Volume pronto
    CSI-->>K8s: PersistentVolume disponível
    K8s->>Pod: Montar volume em /data
    Pod->>Filer: READ/WRITE /data/
    Filer->>Volume: Persistência física
    Volume-->>Filer: Dados gravados
    Filer-->>Pod: Operação concluída
    K8s-->>User: Pod running with /data mounted
```

### Diagrama de Sequência — Governança OPA entre Frameworks (Simplificada)
```mermaid
sequenceDiagram
    autonumber

    actor User as Usuário SQL
    participant Trino as Trino
    participant Polaris as Polaris
    participant PG as PostgreSQL
    participant OPA as OPA
    participant S3 as SeaweedFS S3
    participant K8s as Kubernetes
    participant CSI as CSI Driver
    participant Pod as Pod Aplicação

    Note over User,Pod: CENÁRIO 1 — Polaris criando namespace

    User->>Polaris: Criar namespace "financeiro"
    Polaris->>OPA: Pode criar?
    OPA-->>Polaris: Allow (admin)
    Polaris->>PG: Persistir metadados
    PG-->>Polaris: OK
    Polaris->>S3: Criar bucket
    S3-->>Polaris: OK
    Polaris-->>User: Namespace criado

    Note over User,Pod: CENÁRIO 2 — Trino query negada

    User->>Trino: SELECT * FROM financeiro.vendas
    Trino->>OPA: Pode ler?
    OPA-->>Trino: Deny (analista)
    Trino-->>User: Access Denied

    Note over User,Pod: CENÁRIO 3 — Trino query permitida

    User->>Trino: SELECT * FROM producao.clientes
    Trino->>OPA: Pode ler?
    OPA-->>Trino: Allow (analista + Select)
    Trino->>Polaris: Buscar metadados (REST)
    Polaris->>PG: Consultar catálogo
    PG-->>Polaris: Metadados Iceberg
    Polaris-->>Trino: Schema + localização S3
    Trino->>S3: Ler arquivos Parquet
    S3-->>Trino: Dados retornados
    Trino->>Trino: Executar query distribuída
    Trino-->>User: 1.234 rows returned

    Note over User,Pod: CENÁRIO 4 — K8s montando volume

    User->>K8s: kubectl apply (PVC)
    K8s->>OPA: Pode montar volume?
    OPA-->>K8s: Allow (service account)
    K8s->>CSI: Provisionar volume
    CSI->>S3: Criar estrutura física
    S3-->>CSI: Volume pronto
    CSI-->>K8s: PersistentVolume disponível
    K8s->>Pod: Montar volume em /data
    Pod->>S3: READ/WRITE
    S3-->>Pod: Operação concluída
    K8s-->>User: Pod running
```

## Caso não faça sentido o K8 ao seu projeto:

### 1. Remover do ansible/enventory/hosts.ini  
```bash
[k8s]
k8s-node ansible_host=192.168.56.103 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/k8s-node/virtualbox/private_key
```

### 2. Remover do ansible/playbook.yml
```bash
- name: "Configuração do Nó Kubernetes (VM 3)"
  hosts: k8s
  become: yes
  roles:
    - role: k8s-seaweed-csi
      tags: k8s-seaweed-csi
```

### 3. Remover do `Vagrantefile`
```bash
# VM 3: Kubernetes Node (K3s)
  config.vm.define "k8s-node" do |node|
    node.vm.box = "ubuntu/focal64"
    node.vm.hostname = "k8s-node"
    node.vm.network "private_network", ip: "192.168.56.103"
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
      vb.cpus = 1
      vb.name = "k8s-node"
    end
  end
```

### 4. Remover do `setup.sh` apenas o ***"k8s-node:key_k8s"*** do `for` de dentro do loop.
```bash
# Adicionei a VM3 (k8s-node) que planejamos anteriormente na lista
for VM in "seaweedfs-node:key_seaweed" "trino-sea-node:key_trino" "k8s-node:key_k8s"; do
  VM_NAME="${VM%%:*}"
  KEY_NAME="${VM##*:}"
  DEST="$SSH_DIR/$KEY_NAME"
  ```

## Outros comandos

### Utilizando TAGs Ansible-Playbook
```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbook.yml --tags "seaweed"

# ou

./setup.sh --tags seaweed
```

### Utilizando SSH e Vagarent para acessar as VMs

```bash
# Acesso via SSH com o Vagrant
vagrant ssh 192.169.56.101
# ou (nome da VM no virtual box)
vagrant ssh seaweedfs-node

# Acesso via SSH com iteração da com a chave SSH privada.
ssh -i .\.vagrant\machines\seaweedfs-node\virtualbox\private_key vagrant@192.168.56.101

# Vagrant destroy - Limpar IP antigo da tabela SSH Windows
ssh-keygen -R 192.168.56.101

```

### Como executar o script update-opa-bundle.sh

```bash
# Necessário instalar o AWS CLI na máquina que está rodando o script
sudo apt-get install -y awscli

# Configurar AWS CLI com as credenciais do SeaweedFS (ficam armazendas em ~/.aws/credentials)
aws configure set aws_access_key_id "admin"
aws configure set aws_secret_access_key "admin_secret"
aws configure set default.region "us-east-1"

# script + repositório git
./update-opa-bundle.sh https://github.com/ericsonbarbosa/opa-policies.git

# caso haja uma brach específica basta acrecentar ao final da uri
./update-opa-bundle.sh https://github.com/ericsonbarbosa/opa-policies.git main

```