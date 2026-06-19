#!/bin/bash

# ==============================================================================
# Script de Atualização de Bundle OPA via GitHub
# Uso: ./update-opa-bundle.sh <github-repo-url> [branch]
# Exemplo: ./update-opa-bundle.sh https://github.com/usuario/opa-policies.git main
# ==============================================================================

set -e  # Sair em caso de erro

# ==============================================================================
# CONFIGURAÇÕES (ajuste conforme seu ambiente)
# ==============================================================================
FILER_URL="http://192.168.56.101:8888"
FILER_BUCKET="opa-policies"

# Diretório temporário para trabalho
WORK_DIR="/tmp/opa-bundle-update"
BUNDLE_NAME="bundle.tar.gz"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# FUNÇÕES AUXILIARES
# ==============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

cleanup() {
    log_info "Limpando diretório temporário..."
    rm -rf "$WORK_DIR"
}

# Capturar Ctrl+C e limpar
trap cleanup EXIT

# ==============================================================================
# VALIDAÇÃO DE PARÂMETROS
# ==============================================================================
if [ $# -lt 1 ]; then
    log_error "Uso: $0 <github-repo-url> [branch]"
    echo ""
    echo "Exemplos:"
    echo "  $0 https://github.com/usuario/opa-policies.git"
    echo "  $0 https://github.com/usuario/opa-policies.git main"
    echo "  $0 https://github.com/usuario/opa-policies.git develop"
    exit 1
fi

REPO_URL="$1"
BRANCH="${2:-main}"  # Padrão: main se não especificado

log_info "Repositório: $REPO_URL"
log_info "Branch: $BRANCH"

# ==============================================================================
# PASSO 1: CLONAR REPOSITÓRIO
# ==============================================================================
log_info "Passo 1/5: Clonando repositório..."

# Limpar diretório de trabalho se existir
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Clonar repositório
if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK_DIR/repo"; then
    log_error "Falha ao clonar repositório. Verifique a URL e a branch."
    exit 1
fi

log_success "Repositório clonado com sucesso"

# ==============================================================================
# PASSO 2: VALIDAR ESTRUTURA DO REPOSITÓRIO
# ==============================================================================
log_info "Passo 2/5: Validando estrutura do repositório..."

# Verificar se existe a pasta policies/
if [ ! -d "$WORK_DIR/repo/policies" ]; then
    log_error "Estrutura inválida: pasta 'policies/' não encontrada no repositório"
    log_info "Estrutura esperada:"
    echo "  repo/"
    echo "  ├── policies/"
    echo "  │   └── *.rego"
    echo "  └── manifest.json (opcional)"
    exit 1
fi

# Verificar se existe pelo menos um arquivo .rego
if [ -z "$(find "$WORK_DIR/repo/policies" -name '*.rego' -print -quit)" ]; then
    log_error "Nenhum arquivo .rego encontrado em policies/"
    exit 1
fi

log_success "Estrutura validada"

# ==============================================================================
# PASSO 3: GERAR MANIFEST.JSON
# ==============================================================================
log_info "Passo 3/5: Gerando manifest.json..."

# Gerar versão baseada em timestamp
VERSION="v1-$(date +%Y%m%d-%H%M%S)"
REPO_NAME=$(basename "$REPO_URL" .git)
COMMIT_HASH=$(git -C "$WORK_DIR/repo" rev-parse --short HEAD)

# Criar manifest.json
cat > "$WORK_DIR/repo/manifest.json" << EOF
{
  "revision": "$VERSION-$COMMIT_HASH",
  "roots": ["governance", "polaris", "trino"],
  "metadata": {
    "repository": "$REPO_URL",
    "branch": "$BRANCH",
    "commit": "$COMMIT_HASH",
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "generated_by": "update-opa-bundle.sh"
  }
}
EOF

log_success "Manifest gerado: $VERSION-$COMMIT_HASH"

# Mostrar conteúdo do manifest
log_info "Conteúdo do manifest.json:"
cat "$WORK_DIR/repo/manifest.json" | python3 -m json.tool 2>/dev/null || cat "$WORK_DIR/repo/manifest.json"

# ==============================================================================
# PASSO 4: COMPACTAR BUNDLE
# ==============================================================================
log_info "Passo 4/5: Compactando bundle..."

cd "$WORK_DIR/repo"

# Compactar bundle (manifest.json + policies/)
if ! tar -czf "../$BUNDLE_NAME" manifest.json policies/; then
    log_error "Falha ao compactar bundle"
    exit 1
fi

# Verificar estrutura do bundle
log_info "Estrutura do bundle:"
tar -tzf "../$BUNDLE_NAME"

# Validar sintaxe Rego (se OPA estiver disponível)
if command -v opa &> /dev/null; then
    log_info "Validando sintaxe Rego..."
    if ! opa check policies/; then
        log_error "Erro de sintaxe nos arquivos Rego"
        exit 1
    fi
    log_success "Sintaxe Rego válida"
else
    log_warn "OPA não encontrado, pulando validação de sintaxe"
fi

BUNDLE_SIZE=$(ls -lh "../$BUNDLE_NAME" | awk '{print $5}')
log_success "Bundle compactado: $BUNDLE_SIZE"

# ==============================================================================
# PASSO 5: UPLOAD PARA SEEDWEEDFS (VIA FILER)
# ==============================================================================
log_info "Passo 5/5: Enviando bundle para SeaweedFS Filer..."

# Configurações do Filer (sem autenticação)
FILER_PATH="/buckets/$FILER_BUCKET/$BUNDLE_NAME"

# Verificar se o Filer está acessível
if ! curl -s -o /dev/null -w "%{http_code}" "$FILER_URL/" | grep -q "200"; then
    log_error "Filer não está acessível em $FILER_URL"
    exit 1
fi

# Fazer upload do bundle via curl
if ! curl -s -F "file=@../$BUNDLE_NAME" "$FILER_URL$FILER_PATH" > /dev/null; then
    log_error "Falha ao enviar bundle para Filer"
    exit 1
fi

# Verificar se o arquivo foi enviado
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$FILER_URL$FILER_PATH")
if [ "$HTTP_CODE" != "200" ]; then
    log_error "Bundle não encontrado após upload (HTTP $HTTP_CODE)"
    exit 1
fi

log_success "Bundle enviado para: $FILER_URL$FILER_PATH"

# ==============================================================================
# RESUMO FINAL
# ==============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} BUNDLE ATUALIZADO COM SUCESSO!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📦 Bundle: $BUNDLE_NAME"
echo "🔖 Versão: $VERSION-$COMMIT_HASH"
echo "📍 Localização: $FILER_URL$FILER_PATH"
echo "📏 Tamanho: $BUNDLE_SIZE"
echo ""
echo "🔄 O OPA detectará a mudança automaticamente em 10-30 segundos"
echo ""
echo "📊 Para verificar se o OPA carregou o novo bundle:"
echo "   vagrant ssh seaweedfs-node -c 'sudo journalctl -u opa -n 30 --no-pager | grep -i bundle'"
echo ""
echo "🧪 Para testar no Insomnia:"
echo "   GET http://192.168.56.101:8282/v1/policies"
echo ""