# Resumen Técnico de FW1 (Firewall Banco 3)

- **Nodo:** FW1 (Alpine Linux 3.18)
- **Rol:** Firewall perimetral e inter-VLAN, router interno del banco
- **Estado:** Verificado en vivo (2026-09-07)

---

## 1. Interfaces de Red

| Interfaz | Función / Destino | Dirección IP / Máscara |
|---|---|---|
| `lo` | Loopback local | `127.0.0.1/8` |
| `eth0` | Enlace punto a punto hacia Router R1 | `172.16.0.1/30` |
| `eth1.10` | Subinterfaz VLAN 10 (Red de Usuarios / Clientes) | `172.16.1.1/24` |
| `eth1.20` | Subinterfaz VLAN 20 (Servidores Web / DMZ) | `172.16.2.1/29` |
| `eth1.30` | Subinterfaz VLAN 30 (Base de Datos) | `172.16.3.1/29` |

---

## 2. Enrutamiento y Reenvío de Paquetes

- **Enrutamiento IP:** `net.ipv4.ip_forward = 1` (configurado en `/etc/sysctl.d/` y activo en memoria).
- **Ruta por defecto:** `default via 172.16.0.2 dev eth0 metric 1 onlink` hacia R1.
- **Rutas de subred conectadas:**
  - `172.16.0.0/30 dev eth0`
  - `172.16.1.0/24 dev eth1.10`
  - `172.16.2.0/29 dev eth1.20`
  - `172.16.3.0/29 dev eth1.30`

---

## 3. Arquitectura del Firewall (nftables)

El servicio `nftables` corre bajo OpenRC en el nivel de ejecución `default`.
La configuración persistente reside en `/etc/nftables.nft`.

### Políticas por defecto
- **`input`:** `drop` (solo se aceptan `lo`, `ct state established,related` e `icmp`).
- **`forward`:** `drop` (aislamiento estricto por defecto).
- **`output`:** `accept`.

### Matriz de Tráfico Permitido en `forward`
1. **Conexiones establecidas/relacionadas:** `ct state established,related accept`.
2. **VLAN 10 (Usuarios) -> WEB01 (`172.16.2.2`):** Puertos TCP 80, 443 permitidos.
3. **WEB01 (`172.16.2.2`) -> DB01 (`172.16.3.2`):** Puerto TCP 5432 (PostgreSQL) permitido.
4. **Internet público (R1 `eth0`) -> WEB01 (`172.16.2.2`):** Puerto TCP 80 permitido.
5. **Interbancario B5 vía B4 (`10.0.0.14`) -> WEB01 (`172.16.2.2`):** Puerto TCP 8081 permitido.
6. **Interbancario B5 vía B1/B2 (`10.0.0.17`) -> WEB01 (`172.16.2.2`):** Puerto TCP 8080 permitido.
7. **Salida DNS (VLANs -> eth0):** UDP/TCP 53 permitido.
8. **Navegación Web (VLANs -> eth0):** TCP 80, 443 permitido, sujeto al set de bloqueo de dominios.
9. **Diagnóstico temporal:** `ip protocol icmp accept`.

---

## 4. Bloqueo de Dominios y Persistencia

- **Lista de dominios restringidos:** `/etc/domain-control/blocked.txt`
  - `facebook.com`
  - `instagram.com`
  - `tiktok.com`
  - `netflix.com`
  - `twitch.tv`
- **Script de actualización:** `/usr/local/sbin/update-domains.sh`
  - Resuelve las IPs de cada dominio mediante `dig +short A` y las añade dinámicamente al conjunto `blocked_domains` de nftables.
- **Regla en nftables:**
  `ip saddr 172.16.1.0/24 ip daddr @blocked_domains tcp dport { 80, 443 } log prefix "DOMAIN_BLOCK: " limit rate 5/minute drop`
- **Estado de persistencia:**
  Actualmente, el script `/usr/local/sbin/update-domains.sh` **no** se encuentra enlazado al arranque del sistema (`/etc/local.d/` está vacío y no hay entrada en crontab). Tras un reinicio, el set `blocked_domains` arranca vacío a menos que se ejecute manualmente el script. La automatización de este script tras el reinicio queda como tarea pendiente sujeta a confirmación.
