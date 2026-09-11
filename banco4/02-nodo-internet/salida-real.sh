#!/bin/sh

echo "configurando salida a el internet real"

# habilitando routing
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# el DNS real
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf

# recreando la tabla NAT
nft delete table ip salida_real 2>/dev/null || true
nft -f /etc/network/salida-real.nft

# Vincular comando ip-sla y debug-ip-nat en el PATH
ln -sf /etc/network/ip-sla-ring.sh /bin/ip-sla 2>/dev/null || true
ln -sf /etc/network/ip-sla-ring.sh /usr/bin/ip-sla 2>/dev/null || true
ln -sf /etc/network/ip-sla-ring.sh /usr/local/bin/ip-sla 2>/dev/null || true

ln -sf /etc/network/debug-ip-nat.sh /bin/debug-ip-nat 2>/dev/null || true
ln -sf /etc/network/debug-ip-nat.sh /usr/bin/debug-ip-nat 2>/dev/null || true
ln -sf /etc/network/debug-ip-nat.sh /usr/local/bin/debug-ip-nat 2>/dev/null || true

echo "Salida a internet configurada"

# Iniciar supervisor IP SLA en segundo plano si no está corriendo
if ! pgrep -f "ip-sla-ring.sh" >/dev/null 2>&1; then
    nohup /etc/network/ip-sla-ring.sh > /var/log/ip-sla-ring.log 2>&1 &
fi
