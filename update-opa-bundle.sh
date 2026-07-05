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
S3_BUCKET="opa-policies"
S3_KEY="bundle.tar.gz"
S3_ENDPOINT="http://192.168.56.101:8333"

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

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK_DIR/repo"; then
    log_error "Falha ao clonar repositório. Verifique a URL e a branch."
    exit 1
fi

log_success "Repositório clonado com sucesso"

# ==============================================================================
# PASSO 2: VALIDAR ESTRUTURA DO REPOSITÓRIO
# ==============================================================================
log_info "Passo 2/5: Validando estrutura do repositório..."

if [ ! -d "$WORK_DIR/repo/policies" ]; then
    log_error "Estrutura inválida: pasta 'policies/' não encontrada no repositório"
    log_info "Estrutura esperada:"
    echo "  repo/"
    echo "  └── policies/"
    echo "      └── *.rego"
    exit 1
fi

if [ -z "$(find "$WORK_DIR/repo/policies" -name '*.rego' -print -quit)" ]; then
    log_error "Nenhum arquivo .rego encontrado em policies/"
    exit 1
fi

log_success "Estrutura validada"

# ==============================================================================
# PASSO 3: GERAR .manifest
# ==============================================================================
log_info "Passo 3/5: Gerando .manifest..."

VERSION="v1-$(date +%Y%m%d-%H%M%S)"
REPO_NAME=$(basename "$REPO_URL" .git)
COMMIT_HASH=$(git -C "$WORK_DIR/repo" rev-parse --short HEAD)

cat > "$WORK_DIR/repo/.manifest" << EOF
{
  "revision": "$VERSION-$COMMIT_HASH",
  "roots": ["trino"],
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

log_info "Conteúdo do .manifest:"
cat "$WORK_DIR/repo/.manifest" | python3 -m json.tool 2>/dev/null || cat "$WORK_DIR/repo/.manifest"

# ==============================================================================
# PASSO 4: COMPACTAR BUNDLE
# ==============================================================================
log_info "Passo 4/5: Compactando bundle..."

cd "$WORK_DIR/repo"

if ! tar -czf "../$BUNDLE_NAME" .manifest policies/; then
    log_error "Falha ao compactar bundle"
    exit 1
fi

log_info "Estrutura do bundle:"
tar -tzf "../$BUNDLE_NAME"

if command -v opa &> /dev/null; then
    log_info "Validando sintaxe Rego..."
    if ! opa check policies/; then
        log_error "Erro de sintaxe nos arquivos Rego"
        exit 1
    fi
    log_success "Sintaxe Rego válida"
else
    log_warn "OPA não encontrado localmente, pulando validação de sintaxe"
fi

BUNDLE_SIZE=$(ls -lh "../$BUNDLE_NAME" | awk '{print $5}')
log_success "Bundle compactado: $BUNDLE_SIZE"

# ==============================================================================
# PASSO 5: UPLOAD PARA SEAWEEDFS (VIA S3 API)
# ==============================================================================
log_info "Passo 5/5: Enviando bundle para SeaweedFS via S3 API..."

if ! command -v aws &> /dev/null; then
    log_error "AWS CLI não encontrado. Instale com: sudo apt-get install awscli"
    exit 1
fi

if ! aws sts get-caller-identity --endpoint-url "$S3_ENDPOINT" > /dev/null 2>&1; then
    log_warn "Credenciais não validadas via STS (não suportado pelo SeaweedFS)."
    log_info "Assumindo credenciais configuradas via 'aws configure'."
fi

log_info "Enviando bundle via S3 API..."
if ! aws --endpoint-url "$S3_ENDPOINT" s3 cp "../$BUNDLE_NAME" "s3://$S3_BUCKET/$S3_KEY" --no-progress; then
    log_error "Falha ao enviar bundle"
    log_info "💡 Dica: verifique se executou 'aws configure' com as credenciais do SeaweedFS"
    exit 1
fi

log_info "Verificando arquivo no S3..."
if ! aws --endpoint-url "$S3_ENDPOINT" s3 ls "s3://$S3_BUCKET/$S3_KEY"; then
    log_error "Bundle não encontrado após upload"
    exit 1
fi

log_success "Bundle enviado para: s3://$S3_BUCKET/$S3_KEY"

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
echo "📍 Localização: s3://$S3_BUCKET/$S3_KEY"
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