#!/bin/bash

set -e

CURRENT_USER=$USER
MY_HOME=$HOME

VAGRANT="/mnt/c/Program Files (x86)/Vagrant/bin/vagrant.exe"

echo "🔍 Olá $CURRENT_USER, verificando o status das máquinas virtuais..."

VM_STATUS=$(eval "\"$VAGRANT\" status --machine-readable" | tr -d "\r" | grep ",state," | cut -d',' -f4)

if echo "$VM_STATUS" | grep -qv "running"; then
    echo "pit stop 🛑 Algumas VMs estão desligadas ou não criadas. Iniciando..."
    eval "\"$VAGRANT\" up --no-provision"
else
    echo "✅ VMs já estão em execução. Pulando o boot."
fi

# ==============================================================================
# 1. CÓPIA DAS CHAVES SSH
# ==============================================================================
echo "🔑 Verificando chaves SSH das VMs..."
SSH_DIR="$MY_HOME/.ssh/seaweed_lab"
mkdir -p "$SSH_DIR"

windows_to_wsl() {
  echo "$1" | sed 's|\\|/|g' | sed 's|^\([A-Za-z]\):|/mnt/\L\1|'
}

for VM in "seaweedfs-node:key_seaweed" "trino-sea-node:key_trino" "k8s-node:key_k8s"; do
  VM_NAME="${VM%%:*}"
  KEY_NAME="${VM##*:}"
  DEST="$SSH_DIR/$KEY_NAME"

  VAGRANT_KEY_RAW=$(eval "\"$VAGRANT\" ssh-config $VM_NAME" 2>/dev/null | tr -d "\r" | grep IdentityFile | awk '{print $2}')

  if [ -z "$VAGRANT_KEY_RAW" ]; then
    echo "⚠️  Não foi possível obter a chave da VM $VM_NAME, pulando..."
    continue
  fi

  VAGRANT_KEY=$(windows_to_wsl "$VAGRANT_KEY_RAW")

  EXPECTED=$(md5sum "$VAGRANT_KEY" 2>/dev/null | awk '{print $1}')
  CURRENT=$(md5sum "$DEST" 2>/dev/null | awk '{print $1}')

  if [ "$CURRENT" = "$EXPECTED" ]; then
    echo "✅ Chave de $VM_NAME já está atualizada."
  else
    echo "🔄 Atualizando chave de $VM_NAME..."
    cp "$VAGRANT_KEY" "$DEST"
    chmod 600 "$DEST"
  fi
done

# ==============================================================================
# 2. AGUARDAR SSH DE TODAS AS VMs
# ==============================================================================
echo "⏳ Aguardando SSH das VMs ficar disponível..."

declare -A VM_KEYS
VM_KEYS["192.168.56.101"]="$SSH_DIR/key_seaweed"
VM_KEYS["192.168.56.102"]="$SSH_DIR/key_trino"
VM_KEYS["192.168.56.103"]="$SSH_DIR/key_k8s"

declare -A VM_NAMES
VM_NAMES["192.168.56.101"]="seaweedfs-node"
VM_NAMES["192.168.56.102"]="trino-sea-node"
VM_NAMES["192.168.56.103"]="k8s-node"

for HOST in "192.168.56.101" "192.168.56.102" "192.168.56.103"; do
  NAME="${VM_NAMES[$HOST]}"
  KEY="${VM_KEYS[$HOST]}"
  echo "   Aguardando $NAME ($HOST)..."
  RETRIES=30
  until ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            -i "$KEY" \
            vagrant@$HOST "exit" 2>/dev/null; do
    RETRIES=$((RETRIES - 1))
    if [ $RETRIES -eq 0 ]; then
      echo "❌ Timeout aguardando $NAME"
      exit 1
    fi
    sleep 3
  done
  echo "   ✅ $NAME pronto"
done

# ==============================================================================
# 3. EXECUÇÃO DO ANSIBLE
# ==============================================================================
echo "⚙️  Executando a orquestração com Ansible..."
export ANSIBLE_HOST_KEY_CHECKING=False

if command -v ansible-playbook >/dev/null 2>&1; then
    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbook.yml "$@"
else
    echo "❌ Erro: ansible-playbook não encontrado no WSL."
    exit 1
fi

echo "🏁 Processo concluído!"
read -p "Pressione [Enter] para fechar..."