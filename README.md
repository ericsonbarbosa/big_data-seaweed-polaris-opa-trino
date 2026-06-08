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
│   │   ├── postgres/              # Banco de metadados do Hive
│   │   ├── polaris/               # Polaris
│   │   ├── trino/                 # Engine SQL distribuída
│   │   └── k3s/                   # Kubernetes leve + CSI Driver (opcional)
│   │
│   ├── ansible.cfg                # Ajustes do Ansible
│   └── playbook.yml               # Orquestração principal
│
├── tests/                         # Scripts de validação do laboratório
│   ├── trino-test.md
│   ├── kubernetes-test.md
│   ├── postgres-test.md
│   ├── seaweed-test.md
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
└── README.md                      # Guia técnico do projeto
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

## Renovação de TOKEN:
```bash
# 1. Execute o request para renovar e salvar na variável TOKEN (Python)
# 1.1 Substitua <CLIENT_ID> = root, <CLIENT_SECRET> = root_secret_changeme
export TOKEN=$(curl -s -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=<CLIENT_ID>&client_secret=<CLIENT_SECRET>&scope=PRINCIPAL_ROLE:ALL" \
  http://127.0.0.1:8182/api/catalog/v1/oauth/tokens | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Confirme se funcionou
echo $TOKEN
```

## Diagramas

### Caso de Uso
```mermaid
flowchart TB

    %% =========================
    %% ATORES
    %% =========================
    USER["Usuário / Aplicações SQL"]
    K8S["Kubernetes (K3s)"]

    %% =========================
    %% CAMADA COMPUTE
    %% =========================
    subgraph COMPUTE["Camada de Processamento"]
        TRINO["Trino Coordinator + Workers"]

        UC1["Executar consultas SQL"]
        UC2["Planejar execução distribuída"]
        UC3["Ler e escrever dados analíticos"]

        TRINO --> UC1
        TRINO --> UC2
        TRINO --> UC3
    end

    %% =========================
    %% CAMADA METADATA
    %% =========================
    subgraph METADATA["Camada de Metadados"]
        HIVE["Hive Metastore"]
        PG["PostgreSQL"]

        UC4["Consultar metadados"]
        UC5["Registrar tabelas e schemas"]

        HIVE --> UC4
        HIVE --> UC5
        PG --> UC5
    end

    %% =========================
    %% CAMADA STORAGE
    %% =========================
    subgraph STORAGE["Camada de Persistência"]
        S3["SeaweedFS S3 Gateway"]
        FILER["SeaweedFS Filer"]
        MASTER["SeaweedFS Master"]
        VOLUME["SeaweedFS Volume"]

        UC6["Acessar objetos via S3"]
        UC7["Provisionar volumes persistentes"]
        UC8["Gerenciar namespace filesystem"]
        UC9["Persistir blocos físicos"]
        UC10["Gerenciar localização dos volumes"]

        S3 --> UC6
        FILER --> UC7
        FILER --> UC8
        VOLUME --> UC9
        MASTER --> UC10
    end

    %% =========================
    %% RELAÇÕES DE USO
    %% =========================
    USER --> UC1

    UC1 -. include .-> UC2
    UC2 -. include .-> UC4
    UC2 -. include .-> UC3

    UC3 -. include .-> UC6

    UC4 -. include .-> UC5

    K8S --> UC7
    UC7 -. include .-> UC8
    UC8 -. include .-> UC9

    UC6 -. include .-> UC9
    UC9 -. include .-> UC10
```
### Diagrama de Sequência — Trino + Polaris + SeaweedFS
```mermaid
sequenceDiagram
    autonumber

    actor User as Usuário SQL
    participant Trino as Trino Coordinator
    participant Hive as Hive Metastore
    participant PG as PostgreSQL
    participant S3 as SeaweedFS S3 Gateway
    participant Master as SeaweedFS Master
    participant Volume as SeaweedFS Volume

    User->>Trino: Envia consulta SQL

    Trino->>Hive: Solicita metadados (Thrift :9083)
    Hive->>PG: Consulta schemas/tabelas
    PG-->>Hive: Retorna metadados
    Hive-->>Trino: Metadados da tabela

    Trino->>S3: Solicita leitura dos objetos (S3 API :8333)

    S3->>Master: Consulta localização dos volumes
    Master-->>S3: Retorna localização física

    S3->>Volume: Lê blocos de dados
    Volume-->>S3: Dados retornados

    S3-->>Trino: Arquivos/objetos do Data Lake

    Trino->>Trino: Planeja execução distribuída
    Trino->>Trino: Executa tarefas nos Workers

    Trino-->>User: Retorna resultado SQL
```

### Diagrama de Sequência — Kubernetes + SeaweedFS (CSI Driver)
```mermaid
sequenceDiagram
    autonumber

    actor Dev as Desenvolvedor
    participant K8s as Kubernetes API
    participant CSI as SeaweedFS CSI Driver
    participant Filer as SeaweedFS Filer
    participant Master as SeaweedFS Master
    participant Volume as SeaweedFS Volume
    participant Pod as Pod Aplicação

    Dev->>K8s: Cria PersistentVolumeClaim (PVC)

    K8s->>CSI: Solicita provisionamento do volume

    CSI->>Filer: Cria namespace/diretório persistente

    Filer->>Master: Solicita localização dos volumes
    Master-->>Filer: Retorna volumes disponíveis

    Filer->>Volume: Cria estrutura física
    Volume-->>Filer: Volume persistente criado

    Filer-->>CSI: Volume provisionado
    CSI-->>K8s: PersistentVolume disponível

    K8s->>Pod: Monta volume persistente

    Pod->>Filer: Leitura/escrita filesystem
    Filer->>Volume: Persistência física dos dados
    Volume-->>Filer: Dados gravados

    Filer-->>Pod: Operação concluída
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

### Utilizando TAGs Ansible
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