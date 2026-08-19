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

# FUNCOES DAS OPCOES DO MENU (GERAIS)

# SNGREP - apenas sinalizacao SIP (porta 5060), sem RTP.
# Mais leve: filtro BPF 'port 5060' aplicado no nivel do libpcap.
abrir_sngrep() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}SNGREP - Sinalizacao SIP${RESET}"
    linha
    echo -e "${CIANO}${NEGRITO}Digite um parametro de busca (opcional)${RESET}"
    echo "Exemplo: numero de telefone ou IP"
    linha
    read -p "Parametro: " filtro </dev/tty
    clear

    # -d any captura em TODAS as interfaces de rede simultaneamente
    # (util neste ambiente, onde cada trunk SIP-I fica em uma interface diferente)
    if [ -n "$filtro" ]; then
        echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d any \"${filtro}\" port 5060${RESET}"
        sudo sngrep -f /etc/sngrep/sngreprc -d any "$filtro" port 5060
    else
        echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d any port 5060${RESET}"
        sudo sngrep -f /etc/sngrep/sngreprc -d any port 5060
    fi

    esperar
}

# SNGREP - captura COM RTP (audio). Aba separada de proposito, ja que
# consome mais CPU/RAM e nao deve ser o padrao do dia a dia.
abrir_sngrep_rtp() {
    clear
    linha
    echo -e "${CIANO}${NEGRITO}SNGREP - Captura com RTP (Audio)${RESET}"
    echo -e "${AMARELO}Aviso: Capturar RTP consome mais recursos (CPU/RAM).${RESET}"
    echo -e "${AMARELO}Sem um filtro, a captura pega TODO o trafego de midia de TODAS as interfaces.${RESET}"
    linha
    echo -e "${CIANO}${NEGRITO}Digite um parametro de busca (opcional, mas recomendado)${RESET}"
    echo "Exemplo: numero de telefone ou IP"
    linha
    read -p "Parametro: " filtro </dev/tty
    clear

    # -d any captura em TODAS as interfaces de rede simultaneamente.
    # Flag -r ativa a captura de RTP e remove o filtro 'port 5060'.
    if [ -n "$filtro" ]; then
        echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d any -r \"${filtro}\"${RESET}"
        sudo sngrep -f /etc/sngrep/sngreprc -d any -r "$filtro"
    else
        echo -e "${AZUL}Executando: ${VERDE}sudo sngrep -f /etc/sngrep/sngreprc -d any -r${RESET}"
        sudo sngrep -f /etc/sngrep/sngreprc -d any -r
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
        echo -e "${VERMELHO}[9]${RESET} - Voltar ao Menu Principal"
        linha
        echo ""

        opcao_op=""
        read -p $'\e[36mEscolha uma opcao:\e[0m ' opcao_op </dev/tty
        case "$opcao_op" in
            1) verificar_status_opensips ;;
            2) reiniciar_opensips ;;
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
    cpu_usage=$(awk '/^cpu / {u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t; system("sleep 0.5")} else printf "%.1f", (u-u1)*100/(t-t1)}' /proc/stat /proc/stat)
    echo "Uso de CPU: ${cpu_usage}%"
    opensipsstat=$(systemctl is-active opensips &> /dev/null && echo -e "${VERDE}Ativo" || echo -e "${VERMELHO}Falhou")
    echo -e "Opensips: $opensipsstat${RESET}"
    echo ""
    linha
    echo ""
    echo -e "${CIANO}[1]${RESET} - Abrir SNGREP (sinalizacao)"
    echo -e "${CIANO}[2]${RESET} - Abrir SNGREP com RTP (audio)"
    echo -e "${CIANO}[3]${RESET} - Menu OpenSIPS"
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
        2) abrir_sngrep_rtp ;;
        3) menu_opensips ;;
        4) abrir_htop ;;
        5) realizar_ping ;;
        6) realizar_mtr ;;
        9) sair_menu ;;
        "") continue ;;
        *) echo -e "${VERMELHO}Opcao invalida!${RESET}" ; sleep 1.2 ; clear ;;
    esac
done
