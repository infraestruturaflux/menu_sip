#!/bin/bash
# CORES E ESTILOS
RESET="\e[0m"
NEGRITO="\e[1m"
VERDE="\e[32m"
VERMELHO="\e[31m"
AMARELO="\e[33m"
AZUL="\e[34m"
CIANO="\e[36m"
CINZA="\e[90m"

# === BLINDAGEM ANTI-LOOP (Termius e clientes SSH similares) ===
exec </dev/tty
exec >/dev/tty
exec 2>/dev/tty

stty -echo 2>/dev/null
sleep 2
while read -t 0.05 -n 100 _ </dev/tty 2>/dev/null; do :; done
stty echo 2>/dev/null

# Corrige backspace em clientes SSH que enviam DEL (0x7f) ao inves de BS (0x08)
# Sem isso, apertar backspace mostra "^H" na tela em vez de apagar.
stty erase '^?' 2>/dev/null
# === FIM DA BLINDAGEM ===

# FUNCOES DE APOIO
linha() {
    echo -e "${CIANO}${NEGRITO}===================================${RESET}"
}

esperar() {
    echo ""
    read -p $'\e[33mPressione ENTER para voltar...\e[0m' _ </dev/tty
    clear
}

# FUNCOES DE GERENCIAMENTO DE FIREWALL
FIREWALL_FILE="/etc/init.d/rc.firewall"

# Detecta automaticamente em qual chain os marcadores estao.
# Procura o ultimo "iptables -A <chain>" ANTES do marcador INICIO.
# Se nao encontrar, usa INPUT como fallback.
detectar_chain() {
    local linha_inicio
    linha_inicio=$(grep -n "IPS LIBERADOS PELO MENU - INICIO" "$FIREWALL_FILE" 2>/dev/null | head -1 | cut -d: -f1)

    if [ -z "$linha_inicio" ]; then
        echo "INPUT"
        return
    fi

    local chain
    chain=$(head -n "$linha_inicio" "$FIREWALL_FILE" | grep -oE "iptables\s+-A\s+\S+" | tail -1 | awk '{print $NF}')

    if [ -z "$chain" ]; then
        echo "INPUT"
    else
        echo "$chain"
    fi
}

adicionar_ip_firewall() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Digite o IP para adicionar ao firewall:${RESET}"
    linha
    read -p "IP: " ip </dev/tty

    if [ -z "$ip" ]; then
        echo -e "${VERMELHO}IP nao informado.${RESET}"
        esperar
        return
    fi

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        echo -e "${VERMELHO}IP invalido! Use o formato X.X.X.X ou X.X.X.X/YY${RESET}"
        esperar
        return
    fi

    IP_PURO="${ip%/*}"
    IFS='.' read -ra OCT <<< "$IP_PURO"
    for o in "${OCT[@]}"; do
        if [ "$o" -gt 255 ] || [ "$o" -lt 0 ]; then
            echo -e "${VERMELHO}IP invalido! Cada numero deve estar entre 0 e 255${RESET}"
            esperar
            return
        fi
    done

    if grep -q "$ip" "$FIREWALL_FILE"; then
        echo -e "${AMARELO}IP ja existe no firewall.${RESET}"
        esperar
        return
    fi

    CHAIN=$(detectar_chain)

    # Solicita ticket e cliente (opcionais)
    echo ""
    echo -e "${CIANO}Numero do ticket${RESET} (opcional, pode deixar vazio)"
    read -p "TK #: " ticket </dev/tty

    echo ""
    echo -e "${CIANO}Nome do cliente${RESET} (opcional, pode deixar vazio)"
    read -p "Cliente: " cliente </dev/tty

    # Monta o comentario apenas se tiver informacao
    comentario=""
    if [ -n "$ticket" ] && [ -n "$cliente" ]; then
        comentario="# TK #${ticket} - ${cliente}"
    elif [ -n "$ticket" ]; then
        comentario="# TK #${ticket}"
    elif [ -n "$cliente" ]; then
        comentario="# ${cliente}"
    fi

    # Tela de confirmacao
    echo ""
    linha
    echo -e "${AMARELO}Resumo da liberacao:${RESET}"
    echo -e "  IP:      ${VERDE}${ip}${RESET}"
    echo -e "  Chain:   ${VERDE}${CHAIN}${RESET}"
    if [ -n "$comentario" ]; then
        echo -e "  Coment.: ${VERDE}${comentario}${RESET}"
    else
        echo -e "  Coment.: ${CINZA}(sem comentario)${RESET}"
    fi
    linha
    read -p "Confirma? (s/N): " confirma </dev/tty

    if ! [[ "$confirma" =~ ^[Ss]$ ]]; then
        echo -e "${AMARELO}Operacao cancelada.${RESET}"
        esperar
        return
    fi

    # Adiciona no firewall - se tiver comentario, insere ele + regra iptables
    if [ -n "$comentario" ]; then
        # Escapa caracteres especiais do sed no comentario
        comentario_escapado=$(echo "$comentario" | sed 's/[\/&]/\\&/g')
        sudo sed -i "/IPS LIBERADOS PELO MENU - INICIO/a \        ${comentario_escapado}\n        iptables -A ${CHAIN} -s $ip -j ACCEPT" "$FIREWALL_FILE"
    else
        sudo sed -i "/IPS LIBERADOS PELO MENU - INICIO/a \        iptables -A ${CHAIN} -s $ip -j ACCEPT" "$FIREWALL_FILE"
    fi

    echo -e "${VERDE}IP adicionado ao firewall com sucesso (chain: ${CHAIN}).${RESET}"

    echo -e "${AZUL}Reiniciando firewall...${RESET}"
    if sudo "$FIREWALL_FILE" restart > /dev/null 2>&1; then
        echo -e "${VERDE}Firewall reiniciado com sucesso!${RESET}"
    else
        echo -e "${VERMELHO}Erro ao reiniciar firewall. Contate o admin.${RESET}"
    fi
    esperar
}

remover_ip_firewall() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Digite o IP para remover do firewall:${RESET}"
    linha
    read -p "IP: " ip </dev/tty

    if [ -z "$ip" ]; then
        echo -e "${VERMELHO}IP nao informado.${RESET}"
        esperar
        return
    fi

    if grep -q "$ip" "$FIREWALL_FILE"; then
        echo ""
        echo -e "${AMARELO}IP a remover: ${VERDE}${ip}${RESET}"

        comentario_ip=$(awk -v ip="$ip" '
            match($0, /^[[:space:]]*#/) {
                s = $0
                sub(/^[[:space:]]*#[[:space:]]*/, "", s)
                com = s
                next
            }
            $0 ~ ("iptables -A .* -s " ip " -j ACCEPT") {
                if (com != "") print com
                com = ""
                exit
            }
            !match($0, /^[[:space:]]*$/) { com = "" }
        ' "$FIREWALL_FILE")

        if [ -n "$comentario_ip" ]; then
            echo -e "${AMARELO}Comentario:   ${CINZA}${comentario_ip}${RESET}"
        fi

        read -p "Confirma? (s/N): " confirma </dev/tty

        if ! [[ "$confirma" =~ ^[Ss]$ ]]; then
            echo -e "${AMARELO}Operacao cancelada.${RESET}"
            esperar
            return
        fi

        TMPFILE=$(mktemp)
        awk -v ip="$ip" '
            match($0, /^[[:space:]]*#/) {
                pending = $0
                next
            }
            $0 ~ ("iptables -A .* -s " ip " -j ACCEPT") {
                pending = ""
                next
            }
            {
                if (pending != "") {
                    print pending
                    pending = ""
                }
                print $0
            }
            END {
                if (pending != "") print pending
            }
        ' "$FIREWALL_FILE" | sudo tee "$TMPFILE" > /dev/null
        sudo cp "$TMPFILE" "$FIREWALL_FILE"
        rm -f "$TMPFILE"

        echo -e "${VERDE}IP removido do firewall.${RESET}"

        echo -e "${AZUL}Reiniciando firewall...${RESET}"
        if sudo "$FIREWALL_FILE" restart > /dev/null 2>&1; then
            echo -e "${VERDE}Firewall reiniciado com sucesso!${RESET}"
        else
            echo -e "${VERMELHO}Erro ao reiniciar firewall. Contate o admin.${RESET}"
        fi
    else
        echo -e "${AMARELO}IP nao encontrado no firewall.${RESET}"
    fi
    esperar
}

buscar_ip_firewall() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Digite o IP para buscar no firewall:${RESET}"
    linha
    read -p "IP: " ip </dev/tty

    if [ -z "$ip" ]; then
        echo -e "${VERMELHO}IP nao informado.${RESET}"
        esperar
        return
    fi

    if grep -q "$ip" "$FIREWALL_FILE"; then
        echo -e "${VERDE}IP esta no firewall.${RESET}"
    else
        echo -e "${VERMELHO}IP nao esta no firewall.${RESET}"
    fi
    esperar
}

listar_ips_firewall() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}IPs liberados no firewall:${RESET}"
    linha
    echo ""

    total=0
    resultado=$(awk '
        match($0, /^[[:space:]]*#/) {
            s = $0
            sub(/^[[:space:]]*#[[:space:]]*/, "", s)
            comentario_pendente = s
            next
        }
        match($0, /^[[:space:]]*iptables[[:space:]]+-A[[:space:]]+[^[:space:]]+[[:space:]]+-s[[:space:]]+[^[:space:]]+.*-j[[:space:]]+ACCEPT/) {
            chain = ""
            ip = ""
            for (i=1; i<=NF; i++) {
                if ($i == "-A") chain = $(i+1)
                if ($i == "-s") ip = $(i+1)
            }
            if (chain != "" && ip != "") {
                if (comentario_pendente != "") {
                    printf "%s|%s|%s\n", chain, ip, comentario_pendente
                } else {
                    printf "%s|%s|\n", chain, ip
                }
            }
            comentario_pendente = ""
            next
        }
        !match($0, /^[[:space:]]*$/) {
            comentario_pendente = ""
        }
    ' "$FIREWALL_FILE")

    total=$(echo "$resultado" | grep -c .)

    if [ "$total" -eq 0 ]; then
        echo -e "${AMARELO}Nenhum IP liberado encontrado no firewall.${RESET}"
    else
        echo "$resultado" | sort -t'|' -k2 -V | awk -F'|' -v c="\033[36m" -v v="\033[32m" -v g="\033[90m" -v r="\033[0m" '
        {
            n = NR
            chain = $1
            ip = $2
            comentario = $3
            if (comentario != "") {
                printf "  %3d) %s%-12s%s -> %s%-20s%s  %s%s%s\n", n, c, chain, r, v, ip, r, g, comentario, r
            } else {
                printf "  %3d) %s%-12s%s -> %s%-20s%s\n", n, c, chain, r, v, ip, r
            }
        }'

        echo ""
        echo -e "${VERDE}Total: ${total} IP(s) liberado(s).${RESET}"
    fi

    esperar
}

reiniciar_firewall() {
    clear
    linha
    echo -e "${AMARELO}Tem certeza que deseja reiniciar o firewall?${RESET}"
    read -p "Confirma? (s/N): " confirma </dev/tty

    if ! [[ "$confirma" =~ ^[Ss]$ ]]; then
        echo -e "${AMARELO}Operacao cancelada.${RESET}"
        esperar
        return
    fi

    echo -e "${AZUL}Reiniciando firewall...${RESET}"
    if sudo "$FIREWALL_FILE" restart > /dev/null 2>&1; then
        echo -e "${VERDE}Firewall reiniciado com sucesso!${RESET}"
    else
        echo -e "${VERMELHO}Erro ao reiniciar firewall. Contate o admin.${RESET}"
    fi
    esperar
}

# SUBMENU FIREWALL
menu_firewall() {
    while true; do
        clear
        linha
        echo -e "${NEGRITO}       ${CIANO}[FLUX]${RESET} MENU FIREWALL        ${RESET}"
        linha
        echo ""
        echo -e "${CIANO}[1]${RESET} - Adicionar IP"
        echo -e "${CIANO}[2]${RESET} - Listar IPs"
        echo -e "${CIANO}[3]${RESET} - Buscar IP no Firewall"
        echo -e "${CIANO}[4]${RESET} - Remover IP"
        echo -e "${CIANO}[5]${RESET} - Reiniciar Firewall"
        echo -e "${VERMELHO}[9]${RESET} - Voltar ao Menu Principal"
        linha
        echo ""

        opcao_firewall=""
        read -p $'\e[36mEscolha uma opcao:\e[0m ' opcao_firewall </dev/tty
        case "$opcao_firewall" in
            1) adicionar_ip_firewall ;;
            2) listar_ips_firewall ;;
            3) buscar_ip_firewall ;;
            4) remover_ip_firewall ;;
            5) reiniciar_firewall ;;
            9) return ;;
            "") continue ;;
            *) echo -e "${VERMELHO}Opcao invalida!${RESET}" ; sleep 1.2 ;;
        esac
    done
}

# FUNCOES DAS OPCOES DO MENU (GERAIS)
abrir_sngrep() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Opcoes do SNGREP${RESET}"
    linha
    echo -e "${CIANO}Deseja capturar pacotes RTP (Audio)?${RESET}"
    echo -e "${AMARELO}Aviso: Capturar RTP consome mais recursos (CPU/RAM).${RESET}"
    read -p "Capturar RTP? (s/N): " rtp_opt </dev/tty
    echo ""
    linha
    echo -e "${CIANO}${NEGRITO}Digite um parametro de busca (opcional)${RESET}"
    echo "Exemplo: numero de telefone ou IP"
    linha
    read -p "Parametro: " filtro </dev/tty
    clear
    # Verifica se o usuario digitou 's' ou 'S' para capturar RTP
    if [[ "$rtp_opt" =~ ^[Ss]$ ]]; then
        # COM RTP: Adiciona a flag -r e remove o filtro 'port 5060'
        if [ -n "$filtro" ]; then
            echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d ens192 -r \"${filtro}\"${RESET}"
            sudo sngrep -f /etc/sngrep/sngreprc -d ens192 -r "$filtro"
        else
            echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d ens192 -r${RESET}"
            sudo sngrep -f /etc/sngrep/sngreprc -d ens192 -r
        fi
    else
        # SEM RTP: Mantem sem a flag -r e com o filtro 'port 5060' para economizar recursos
        if [ -n "$filtro" ]; then
            echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d ens192 \"${filtro}\" port 5060${RESET}"
            sudo sngrep -f /etc/sngrep/sngreprc -d ens192 "$filtro" port 5060
        else
            echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d ens192 port 5060${RESET}"
            sudo sngrep -f /etc/sngrep/sngreprc -d ens192 port 5060
        fi
    fi

    esperar
}

abrir_htop() {
    clear
    echo -e "${AZUL}${NEGRITO}Abrindo HTOP...${RESET}"
    htop
    esperar
}

realizar_ping() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Digite o IP ou dominio para o PING${RESET}"
    echo "Exemplo: 8.8.8.8"
    linha
    read -p "Destino: " destino </dev/tty
    clear

    if [ -n "$destino" ]; then
        echo -e "${AZUL}Executando: ${VERDE}ping ${destino}${RESET}"
        ping -c 4 "$destino"
    else
        echo -e "${VERMELHO}Necessario informar um IP ou dominio!${RESET}"
        sleep 1
    fi
    esperar
}

realizar_mtr() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Digite o IP ou dominio para o MTR${RESET}"
    echo "Exemplo: 8.8.8.8"
    linha
    read -p "Destino: " destino </dev/tty
    clear

    if [ -n "$destino" ]; then
        echo -e "${AZUL}Executando: ${VERDE}mtr ${destino}${RESET}"
        mtr "$destino" -i 1
    else
        echo -e "${VERMELHO}Necessario informar um IP ou dominio!${RESET}"
        sleep 1
    fi
    esperar
}

# FUNCOES OPENSIPS
verificar_status_opensips() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Status do OpenSIPS${RESET}"
    linha
    echo ""
    sudo systemctl status opensips --no-pager -l
    echo ""

    if systemctl is-active opensips &> /dev/null; then
        echo -e "${VERDE}OpenSIPS esta ATIVO.${RESET}"
        esperar
    else
        echo -e "${VERMELHO}OpenSIPS esta PARADO/FALHOU.${RESET}"
        echo ""
        read -p $'\e[33mDeseja reiniciar o OpenSIPS agora? (s/N): \e[0m' reiniciar </dev/tty
        if [[ "$reiniciar" =~ ^[Ss]$ ]]; then
            echo -e "${AZUL}Reiniciando OpenSIPS...${RESET}"
            if sudo systemctl restart opensips; then
                sleep 1
                if systemctl is-active opensips &> /dev/null; then
                    echo -e "${VERDE}OpenSIPS reiniciado com sucesso e esta ATIVO.${RESET}"
                else
                    echo -e "${VERMELHO}Comando executado, porem OpenSIPS continua PARADO. Contate o admin.${RESET}"
                fi
            else
                echo -e "${VERMELHO}Erro ao reiniciar o OpenSIPS. Contate o admin.${RESET}"
            fi
        else
            echo -e "${AMARELO}Operacao cancelada.${RESET}"
        fi
        esperar
    fi
}

reiniciar_opensips() {
    clear
    linha
    echo -e "${AMARELO}Tem certeza que deseja reiniciar o OpenSIPS?${RESET}"
    echo -e "${AMARELO}Isso pode derrubar chamadas/registros em andamento.${RESET}"
    read -p "Confirma? (s/N): " confirma </dev/tty

    if ! [[ "$confirma" =~ ^[Ss]$ ]]; then
        echo -e "${AMARELO}Operacao cancelada.${RESET}"
        esperar
        return
    fi

    echo -e "${AZUL}Reiniciando OpenSIPS...${RESET}"
    if sudo systemctl restart opensips; then
        sleep 1
        if systemctl is-active opensips &> /dev/null; then
            echo -e "${VERDE}OpenSIPS reiniciado com sucesso!${RESET}"
        else
            echo -e "${VERMELHO}Comando executado, porem OpenSIPS continua PARADO. Contate o admin.${RESET}"
        fi
    else
        echo -e "${VERMELHO}Erro ao reiniciar o OpenSIPS. Contate o admin.${RESET}"
    fi
    esperar
}

# Abre o arquivo de interfaces em modo somente leitura, sem permitir que o
# usuario informe caminho/parametro algum. O comando e' fixo de proposito.
editar_interfaces_opensips() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}Editor: /etc/opensips/interfaces.cfg${RESET}"
    echo -e "${AMARELO}Atencao: altere com cuidado. Salve com Ctrl+O e saia com Ctrl+X.${RESET}"
    linha
    echo ""
    read -p $'\e[33mPressione ENTER para abrir o arquivo no nano...\e[0m' _ </dev/tty
    sudo nano /etc/opensips/interfaces.cfg
    esperar
}

# SUBMENU OPENSIPS
menu_opensips() {
    while true; do
        clear
        linha
        echo -e "${NEGRITO}       ${CIANO}[FLUX]${RESET} MENU OPENSIPS        ${RESET}"
        linha
        echo ""
        echo -e "${CIANO}[1]${RESET} - Ver Status do OpenSIPS"
        echo -e "${CIANO}[2]${RESET} - Reiniciar OpenSIPS"
        echo -e "${CIANO}[3]${RESET} - Editar interfaces.cfg"
        echo -e "${VERMELHO}[9]${RESET} - Voltar ao Menu Principal"
        linha
        echo ""

        opcao_op=""
        read -p $'\e[36mEscolha uma opcao:\e[0m ' opcao_op </dev/tty
        case "$opcao_op" in
            1) verificar_status_opensips ;;
            2) reiniciar_opensips ;;
            3) editar_interfaces_opensips ;;
            9) return ;;
            "") continue ;;
            *) echo -e "${VERMELHO}Opcao invalida!${RESET}" ; sleep 1.2 ;;
        esac
    done
}

sair_menu() {
    clear
    exit 0
}

# MENU PRINCIPAL
mostrar_menu() {
    clear
    linha
    echo -e "${RESET}${NEGRITO}    ${CIANO}[FLUX]${RESET} MENU DE FERRAMENTAS - SIP-I        ${RESET}"
    linha
    echo ""
    echo "      INFORMACOES DA MAQUINA"
    host=$(hostname)
    echo "Hostname: $host "
    memory_info=$(free -m | grep Mem)
    memory_used=$(echo $memory_info | awk '{print $3}')
    memory_total=$(echo $memory_info | awk '{print $2}')
    memory_percentage=$(((memory_used * 100) / memory_total))
    echo "Memoria em uso: $memory_percentage%"
    df -h / | awk 'NR==2 {printf "Espaco em uso: %s\n", $5}'
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/,/./')
    cpu_usage=$(echo "scale=1; 100 - $cpu_idle" | bc)
    echo "Uso de CPU: ${cpu_usage}%"
    opensipsstat=$(systemctl is-active opensips &> /dev/null && echo -e "${VERDE}Ativo" || echo -e "${VERMELHO}Falhou")
    echo -e "Opensips: $opensipsstat${RESET}"
    echo ""
    linha
    echo ""
    echo -e "${CIANO}[1]${RESET} - Abrir SNGREP"
    echo -e "${CIANO}[2]${RESET} - Menu OpenSIPS"
    echo -e "${CIANO}[3]${RESET} - Gerenciar Firewall"
    echo -e "${CIANO}[4]${RESET} - Abrir HTOP"
    echo -e "${CIANO}[5]${RESET} - Realizar PING"
    echo -e "${CIANO}[6]${RESET} - Realizar MTR"
    echo -e "${VERMELHO}[9]${RESET} - Sair"
    echo ""
    linha
    echo ""
}

# LOOP PRINCIPAL
while true; do
    mostrar_menu
    opcao=""
    read -p $'\e[36mEscolha uma opcao:\e[0m ' opcao </dev/tty
    case "$opcao" in
        1) abrir_sngrep ;;
        2) menu_opensips ;;
        3) menu_firewall ;;
        4) abrir_htop ;;
        5) realizar_ping ;;
        6) realizar_mtr ;;
        9) sair_menu ;;
        "") continue ;;
        *) echo -e "${VERMELHO}Opcao invalida!${RESET}" ; sleep 1.2 ; clear ;;
    esac
done