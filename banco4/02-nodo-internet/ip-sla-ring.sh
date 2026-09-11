#!/bin/sh
# ==============================================================================
# IP SLA & Object Tracking - Anillo Interbancario (Banco 4)
# Monitoreo Extremo a Extremo (End-to-End SLA)
# - Lado Derecho: Monitorea B3 (10.0.0.9) y B2 (10.0.0.5) saliendo por eth3
# - Lado Izquierdo: Monitorea B5 (10.0.0.14) y B1 (10.0.0.18) saliendo por eth4
# ==============================================================================

# Autovincular comando ip-sla en PATH si no existe
[ -e /bin/ip-sla ] || ln -sf /etc/network/ip-sla-ring.sh /bin/ip-sla 2>/dev/null || true
[ -e /usr/local/bin/ip-sla ] || ln -sf /etc/network/ip-sla-ring.sh /usr/local/bin/ip-sla 2>/dev/null || true

LOG_FILE="/var/log/ip-sla-ring.log"
PID_FILE="/var/run/ip-sla-ring.pid"
STATUS_FILE="/var/run/ip-sla-ring.status"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Subcomando de consulta de estado
if [ "$1" = "status" ]; then
    if [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        echo "IP SLA no ha generado reporte de estado aún o el servicio está detenido."
    fi
    exit 0
fi

# Evitar múltiples instancias
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "ip-sla-ring ya se encuentra en ejecución con PID $OLD_PID"
        exit 0
    fi
fi
echo $$ > "$PID_FILE"

trap 'rm -f "$PID_FILE"; log_msg "IP SLA servicio detenido."; exit 0' INT TERM EXIT

# Asegurar rutas de respaldo flotantes (métrica 20) siempre presentes en kernel
ensure_floating_routes() {
    # Respaldo vía Banco 5 (eth4) para llegar a B2 y B3
    ip route replace 10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20 2>/dev/null || true
    ip route replace 10.0.0.4/30 via 10.0.0.14 dev eth4 metric 20 2>/dev/null || true
    ip route replace 10.0.0.8/30 via 10.0.0.14 dev eth4 metric 20 2>/dev/null || true

    # Respaldo vía Banco 3 (eth3) para llegar a B5 y B1
    ip route replace 10.0.0.16/30 via 10.0.0.9 dev eth3 metric 20 2>/dev/null || true
    ip route replace 10.0.0.12/30 via 10.0.0.9 dev eth3 metric 20 2>/dev/null || true
    ip route replace 172.20.5.0/24 via 10.0.0.9 dev eth3 metric 20 2>/dev/null || true
}

ensure_floating_routes
log_msg "Iniciando servicio de monitoreo IP SLA Extremo a Extremo en Banco 4..."

# Targets
B3_DIRECT_IP="10.0.0.9"
B3_IF="eth3"
B2_E2E_IP="10.0.0.5"

B5_DIRECT_IP="10.0.0.14"
B5_IF="eth4"
B1_E2E_IP="10.0.0.18"

# Variables de estado
B3_STATE="UNKNOWN"
B3_OK_COUNT=0
B3_FAIL_COUNT=0

B2_STATE="UNKNOWN"
B2_OK_COUNT=0
B2_FAIL_COUNT=0

B5_STATE="UNKNOWN"
B5_OK_COUNT=0
B5_FAIL_COUNT=0

B1_STATE="WAITING_INIT"
B1_OK_COUNT=0
B1_FAIL_COUNT=0
B1_E2E_ACTIVE=0

THRESHOLD=2

write_status() {
    cat <<EOF > "$STATUS_FILE"
============================================================
       ESTADO IP SLA EXTREMO A EXTREMO - BANCO 4
============================================================
Fecha / Hora : $(date '+%Y-%m-%d %H:%M:%S')
PID Servicio : $$

[LADO DERECHO - eth3]
- Sonda B3 (10.0.0.9 - Vecino directo)  : [$B3_STATE]
- Sonda B2 (10.0.0.5 - End-to-End via B3): [$B2_STATE]
  -> Rutas B2 (10.0.0.0/30, 10.0.0.4/30): $([ "$B2_STATE" = "UP" ] && echo "DIRECTAS por eth3 (Métrica 10)" || echo "CONMUTADAS por eth4 hacia B5 (Métrica 20)")

[LADO IZQUIERDO - eth4]
- Sonda B5 (10.0.0.14 - Vecino directo) : [$B5_STATE]
- Sonda B1 (10.0.0.18 - End-to-End via B5): [$B1_STATE]
  -> Rutas B5/B1 (10.0.0.16/30, LAN B5) : $([ "$B5_STATE" = "UP" ] && echo "DIRECTAS por eth4 (Métrica 10)" || echo "CONMUTADAS por eth3 hacia B3 (Métrica 20)")
============================================================
EOF
}

while true; do
    # -------------------------------------------------------------
    # 1. Monitoreo Lado Derecho: Vecino Directo B3 (10.0.0.9)
    # -------------------------------------------------------------
    if ping -c 1 -W 1 -I "$B3_IF" "$B3_DIRECT_IP" >/dev/null 2>&1; then
        B3_FAIL_COUNT=0
        B3_OK_COUNT=$((B3_OK_COUNT + 1))
        if [ "$B3_STATE" != "UP" ] && [ "$B3_OK_COUNT" -ge "$THRESHOLD" ]; then
            B3_STATE="UP"
            log_msg "[TRACK-B3] UP: Vecino Banco 3 ($B3_DIRECT_IP) alcanzable por $B3_IF."
            write_status
        fi
    else
        B3_OK_COUNT=0
        B3_FAIL_COUNT=$((B3_FAIL_COUNT + 1))
        if [ "$B3_STATE" != "DOWN" ] && [ "$B3_FAIL_COUNT" -ge "$THRESHOLD" ]; then
            B3_STATE="DOWN"
            log_msg "[TRACK-B3] DOWN: Vecino Banco 3 ($B3_DIRECT_IP) no responde por $B3_IF."
            write_status
        fi
    fi

    # -------------------------------------------------------------
    # 2. Monitoreo Lado Derecho: Extremo a Extremo B2 (10.0.0.5)
    # -------------------------------------------------------------
    if ping -c 1 -W 1 -I "$B3_IF" "$B2_E2E_IP" >/dev/null 2>&1; then
        B2_FAIL_COUNT=0
        B2_OK_COUNT=$((B2_OK_COUNT + 1))
        if [ "$B2_STATE" != "UP" ] && [ "$B2_OK_COUNT" -ge "$THRESHOLD" ]; then
            B2_STATE="UP"
            log_msg "[TRACK-B2-E2E] UP: Banco 2 ($B2_E2E_IP) alcanzable via B3 -> Instalando rutas primarias por $B3_IF (métrica 10)."
            ip route replace 10.0.0.4/30 via "$B3_DIRECT_IP" dev "$B3_IF" metric 10 2>/dev/null || true
            ip route replace 10.0.0.0/30 via "$B3_DIRECT_IP" dev "$B3_IF" metric 10 2>/dev/null || true
            write_status
        fi
    else
        B2_OK_COUNT=0
        B2_FAIL_COUNT=$((B2_FAIL_COUNT + 1))
        if [ "$B2_STATE" != "DOWN" ] && [ "$B2_FAIL_COUNT" -ge "$THRESHOLD" ]; then
            B2_STATE="DOWN"
            log_msg "[TRACK-B2-E2E] DOWN: Banco 2 ($B2_E2E_IP) inalcanzable por $B3_IF -> Retirando rutas por eth3, activando respaldo por eth4 (Banco 5)."
            ip route del 10.0.0.4/30 via "$B3_DIRECT_IP" dev "$B3_IF" metric 10 2>/dev/null || true
            ip route del 10.0.0.0/30 via "$B3_DIRECT_IP" dev "$B3_IF" metric 10 2>/dev/null || true
            write_status
        fi
    fi

    # -------------------------------------------------------------
    # 3. Monitoreo Lado Izquierdo: Vecino Directo B5 (10.0.0.14)
    # -------------------------------------------------------------
    if ping -c 1 -W 1 -I "$B5_IF" "$B5_DIRECT_IP" >/dev/null 2>&1; then
        B5_FAIL_COUNT=0
        B5_OK_COUNT=$((B5_OK_COUNT + 1))
        if [ "$B5_STATE" != "UP" ] && [ "$B5_OK_COUNT" -ge "$THRESHOLD" ]; then
            B5_STATE="UP"
            log_msg "[TRACK-B5] UP: Vecino Banco 5 ($B5_DIRECT_IP) alcanzable por $B5_IF -> Instalando rutas primarias por $B5_IF (métrica 10)."
            ip route replace 10.0.0.16/30 via "$B5_DIRECT_IP" dev "$B5_IF" metric 10 2>/dev/null || true
            ip route replace 172.20.5.0/24 via "$B5_DIRECT_IP" dev "$B5_IF" metric 10 2>/dev/null || true
            write_status
        fi
    else
        B5_OK_COUNT=0
        B5_FAIL_COUNT=$((B5_FAIL_COUNT + 1))
        if [ "$B5_STATE" != "DOWN" ] && [ "$B5_FAIL_COUNT" -ge "$THRESHOLD" ]; then
            B5_STATE="DOWN"
            log_msg "[TRACK-B5] DOWN: Vecino Banco 5 ($B5_DIRECT_IP) no responde por $B5_IF -> Retirando rutas por eth4, activando respaldo por eth3 (Banco 3)."
            ip route del 10.0.0.16/30 via "$B5_DIRECT_IP" dev "$B5_IF" metric 10 2>/dev/null || true
            ip route del 172.20.5.0/24 via "$B5_DIRECT_IP" dev "$B5_IF" metric 10 2>/dev/null || true
            write_status
        fi
    fi

    # -------------------------------------------------------------
    # 4. Monitoreo Lado Izquierdo: Extremo a Extremo B1 (10.0.0.18)
    # Autodetección: Monitorea activamente. Cuando B1 responda por primera vez,
    # toma el control granular de la ruta 10.0.0.16/30.
    # -------------------------------------------------------------
    if ping -c 1 -W 1 -I "$B5_IF" "$B1_E2E_IP" >/dev/null 2>&1; then
        B1_FAIL_COUNT=0
        B1_OK_COUNT=$((B1_OK_COUNT + 1))
        if [ "$B1_STATE" != "UP" ] && [ "$B1_OK_COUNT" -ge "$THRESHOLD" ]; then
            B1_STATE="UP"
            B1_E2E_ACTIVE=1
            log_msg "[TRACK-B1-E2E] UP: Banco 1 ($B1_E2E_IP) activo y alcanzable por $B5_IF -> Monitoreo E2E activado."
            ip route replace 10.0.0.16/30 via "$B5_DIRECT_IP" dev "$B5_IF" metric 10 2>/dev/null || true
            write_status
        fi
    else
        B1_OK_COUNT=0
        B1_FAIL_COUNT=$((B1_FAIL_COUNT + 1))
        if [ "$B1_E2E_ACTIVE" -eq 1 ]; then
            if [ "$B1_STATE" != "DOWN" ] && [ "$B1_FAIL_COUNT" -ge "$THRESHOLD" ]; then
                B1_STATE="DOWN"
                log_msg "[TRACK-B1-E2E] DOWN: Banco 1 ($B1_E2E_IP) inalcanzable por $B5_IF -> Retirando ruta primaria por eth4, conmutando a eth3 (Banco 3)."
                ip route del 10.0.0.16/30 via "$B5_DIRECT_IP" dev "$B5_IF" metric 10 2>/dev/null || true
                write_status
            fi
        fi
    fi

    write_status
    sleep 2
done
