#!/bin/bash

# --- Configurações Dinâmicas (tentativa de ler do zabbix_agentd.conf) ---
AGENT_CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
ZABBIX_PORT="10051" # Porta padrão do Zabbix Trapper, geralmente não muda

# Função para extrair valor do zabbix_agentd.conf
# Argumentos: $1 = Chave (ex: Hostname), $2 = Arquivo de Configuração
get_zabbix_config() {
    local key="$1"
    local config_file="$2"
    local value
    # Garante que estamos pegando a linha descomentada e o valor correto
    value=$(grep -E "^\s*${key}\s*=" "$config_file" | sed -e "s/.*${key}\s*=\s*//" -e 's/\s*#.*//' | head -n 1)
    echo "$value"
}

echo "Info: Tentando ler configurações do $AGENT_CONFIG_FILE..."

# Obter Hostname do agente
CONFIG_HOSTNAME=$(get_zabbix_config "Hostname" "$AGENT_CONFIG_FILE")
if [ -z "$CONFIG_HOSTNAME" ]; then
    echo "Erro: Hostname não encontrado ou não configurado em $AGENT_CONFIG_FILE. Verifique o parâmetro 'Hostname'." >&2
    # Definir um fallback ou sair
    # HOSTNAME_IN_ZABBIX="fallback-hostname" # Exemplo de fallback
    exit 1 # Ou sair se for crítico
else
    HOSTNAME_IN_ZABBIX="$CONFIG_HOSTNAME"
    echo "Info: Usando Hostname do agente: $HOSTNAME_IN_ZABBIX"
fi

# Obter Zabbix Server/Proxy do parâmetro ServerActive
# ServerActive é mais apropriado pois é para onde o agente envia dados ativamente
CONFIG_SERVER_ACTIVE_LINE=$(get_zabbix_config "ServerActive" "$AGENT_CONFIG_FILE")
if [ -z "$CONFIG_SERVER_ACTIVE_LINE" ]; then
    echo "Erro: ServerActive não encontrado ou não configurado em $AGENT_CONFIG_FILE. Verifique o parâmetro 'ServerActive'." >&2
    echo "      Este parâmetro deve apontar para o Zabbix Server ou Zabbix Proxy." >&2
    # Definir um fallback ou sair
    # ZABBIX_SERVER_ADDRESS="fallback-server-ip" # Exemplo de fallback
    exit 1 # Ou sair se for crítico
else
    # Pegar o primeiro servidor da lista (caso haja múltiplos separados por vírgula)
    FIRST_SERVER_ACTIVE_ENTRY=$(echo "$CONFIG_SERVER_ACTIVE_LINE" | cut -d, -f1)
    # Extrair apenas o IP/hostname, ignorando a porta se especificada (ex: server:port)
    # zabbix_sender usará ZABBIX_PORT para o destino
    ZABBIX_SERVER_ADDRESS=$(echo "$FIRST_SERVER_ACTIVE_ENTRY" | cut -d: -f1)

    if [ -z "$ZABBIX_SERVER_ADDRESS" ]; then
        echo "Erro: Não foi possível extrair um endereço de ServerActive válido de '$CONFIG_SERVER_ACTIVE_LINE'." >&2
        exit 1
    fi
    ZABBIX_SERVER="$ZABBIX_SERVER_ADDRESS"
    echo "Info: Usando Zabbix Server/Proxy (de ServerActive): $ZABBIX_SERVER na porta $ZABBIX_PORT para trappers."
fi


# --- Configurações Fixas do Script ---
SPEEDTEST_CMD="/usr/bin/speedtest"
SPEEDTEST_ARGS="--accept-license --accept-gdpr --format=json"
SENDER_INPUT_FILE="/tmp/speedtest_metrics_for_zabbix.txt" # Arquivo temporário para dados do sender
ZABBIX_SENDER_CMD="/usr/bin/zabbix_sender" # Caminho para o zabbix_sender

# --- Verificar dependências ---
if ! command -v jq &> /dev/null; then
    echo "Erro: 'jq' não encontrado. Por favor, instale jq (ex: sudo dnf install -y jq)." >&2
    exit 1
fi
if ! command -v "$SPEEDTEST_CMD" &> /dev/null; then
    echo "Erro: '$SPEEDTEST_CMD' não encontrado." >&2
    exit 1
fi
if ! command -v "$ZABBIX_SENDER_CMD" &> /dev/null; then
    echo "Erro: '$ZABBIX_SENDER_CMD' não encontrado. Verifique o caminho ou instale zabbix-sender." >&2
    exit 1
fi

# --- Executar Speedtest ---
echo "Executando speedtest..."
JSON_OUTPUT=$($SPEEDTEST_CMD $SPEEDTEST_ARGS)
SPEEDTEST_EXIT_CODE=$?

if [ $SPEEDTEST_EXIT_CODE -ne 0 ] || [ -z "$JSON_OUTPUT" ] || ! echo "$JSON_OUTPUT" | jq -e . > /dev/null 2>&1; then
    echo "Erro: Speedtest falhou (código $SPEEDTEST_EXIT_CODE) ou não retornou JSON válido." >&2
    # Opcional: Enviar um valor de erro para um item trapper específico de 'status'
    # $ZABBIX_SENDER_CMD -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$HOSTNAME_IN_ZABBIX" -k speedtest.execution.status -o 1
    exit 1
fi
echo "Speedtest concluído. Processando JSON..."

# --- Extrair Valores do JSON usando jq ---
DOWNLOAD_BYTES_PER_SEC=$(echo "$JSON_OUTPUT" | jq -r '.download.bandwidth // 0')
UPLOAD_BYTES_PER_SEC=$(echo "$JSON_OUTPUT" | jq -r '.upload.bandwidth // 0')
PING_LATENCY=$(echo "$JSON_OUTPUT" | jq -r '.ping.latency // 0')
PING_JITTER=$(echo "$JSON_OUTPUT" | jq -r '.ping.jitter // 0')

# Converter para bps (Bytes * 8)
DOWNLOAD_BPS=$(awk -v val="$DOWNLOAD_BYTES_PER_SEC" 'BEGIN { printf "%.0f", val * 8 }')
UPLOAD_BPS=$(awk -v val="$UPLOAD_BYTES_PER_SEC" 'BEGIN { printf "%.0f", val * 8 }')

echo "Valores extraídos: Download=${DOWNLOAD_BPS}bps, Upload=${UPLOAD_BPS}bps, Ping=${PING_LATENCY}ms, Jitter=${PING_JITTER}ms"

# --- Preparar arquivo de entrada para zabbix_sender ---
# As chaves aqui devem corresponder às chaves dos itens Trapper no Zabbix Server
cat <<EOF > "$SENDER_INPUT_FILE"
"$HOSTNAME_IN_ZABBIX" speedtest.download.actual_bps $DOWNLOAD_BPS
"$HOSTNAME_IN_ZABBIX" speedtest.upload.actual_bps $UPLOAD_BPS
"$HOSTNAME_IN_ZABBIX" speedtest.ping.latency_ms $PING_LATENCY
"$HOSTNAME_IN_ZABBIX" speedtest.ping.jitter_ms $PING_JITTER
EOF
# Opcional: Enviar o status de execução bem-sucedida para um item de status
# echo "\"$HOSTNAME_IN_ZABBIX\" speedtest.execution.status 0" >> "$SENDER_INPUT_FILE"


# --- Enviar dados para o Zabbix Server ---
echo "Enviando dados para $ZABBIX_SERVER (Host: $HOSTNAME_IN_ZABBIX)..."
$ZABBIX_SENDER_CMD -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$HOSTNAME_IN_ZABBIX" -i "$SENDER_INPUT_FILE"
SENDER_EXIT_CODE=$?

if [ $SENDER_EXIT_CODE -eq 0 ]; then
    echo "Dados enviados com sucesso para o Zabbix."
else
    echo "Erro ao enviar dados para o Zabbix. Código de saída do zabbix_sender: $SENDER_EXIT_CODE" >&2
    echo "Verifique se o host '$HOSTNAME_IN_ZABBIX' existe no Zabbix Server/Proxy '$ZABBIX_SERVER'," >&2
    echo "se as chaves dos itens trapper estão corretas e se a porta $ZABBIX_PORT está acessível." >&2
    # Para debug mais detalhado, descomente a linha abaixo e execute o script manualmente:
    $ZABBIX_SENDER_CMD -vv -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$HOSTNAME_IN_ZABBIX" -i "$SENDER_INPUT_FILE"
fi

# Opcional: Limpar o arquivo temporário após o envio
rm "$SENDER_INPUT_FILE"

exit $SENDER_EXIT_CODE
