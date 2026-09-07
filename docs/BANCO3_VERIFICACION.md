# Evidencia de Verificación Técnica — Banco 3 (Fintech)

- **Fecha de Verificación:** 2026-09-07
- **Entorno:** Topología de Redes II / GNS3
- **Estado Global:** En Producción / Totalmente Operativo a nivel local e interbancario primario hacia B2

---

## 1. Verificación del Router de Borde (R1)

### 1.1. Interfaces y Asignación de IPs
```text
FastEthernet0/0: 172.16.0.2/30   (Enlace interno FW1 - ip nat inside)
FastEthernet0/1: 192.168.122.39/24 (Salida Internet DHCP - ip nat outside)
FastEthernet1/0: 10.0.0.6/30     (Enlace interbancario Banco 2 - ip nat outside)
FastEthernet2/0: 10.0.0.9/30     (Enlace interbancario Banco 4 - ip nat outside)
```

### 1.2. Estado de IP SLA y Tracking
- **SLA 1:** Monitorea `10.0.0.1` (B1) saliendo por `FastEthernet1/0`.
- **SLA 2:** Monitorea `10.0.0.18` (B1) saliendo por `FastEthernet2/0`.
- **Local Policy:** `RM-LOCAL-SLA` fuerza el tráfico ICMP de SLA al next-hop correspondiente evitando loops de routing.

Salida de `show track`:
```text
Track 1
  Response Time Reporter 1 reachability
  Reachability is Up
  Latest operation return code: OK
  Latest RTT (millisecs): 76
  Tracked by: STATIC-IP-ROUTING 0

Track 2
  Response Time Reporter 2 reachability
  Reachability is Down
  Latest operation return code: Timeout
  Tracked by: STATIC-IP-ROUTING 0
```

### 1.3. Tabla de Enrutamiento Activa en R1 (`show ip route`)
```text
Gateway of last resort is 192.168.122.1 to network 0.0.0.0

C    192.168.122.0/24 is directly connected, FastEthernet0/1
C    172.16.0.0/30 is directly connected, FastEthernet0/0
S    172.16.1.0/24 [1/0] via 172.16.0.1
S    172.16.2.0/29 [1/0] via 172.16.0.1
S    172.16.3.0/29 [1/0] via 172.16.0.1
C    10.0.0.4/30 is directly connected, FastEthernet1/0
C    10.0.0.8/30 is directly connected, FastEthernet2/0
S    10.0.0.0/30 [1/0] via 10.0.0.5          <-- RUTA PRIMARIA ACTIVA (Track 1 UP)
S    10.0.0.12/30 [1/0] via 10.0.0.10
S    10.0.0.16/30 [10/0] via 10.0.0.5        <-- RUTA FLOTANTE ACTIVA (Track 2 DOWN conmuto via B2)
S*   0.0.0.0/0 [254/0] via 192.168.122.1
```

### 1.4. Reglas de NAT y PAT
- **Internet:** PAT dinámico sobre Fa0/1 y DNAT TCP 80 hacia `172.16.2.2:80`.
- **Banco 2:** PAT dinámico sobre Fa1/0 y DNAT TCP 8080 hacia `172.16.2.2:8080`.
- **Banco 4:** PAT dinámico sobre Fa2/0 y DNAT TCP 8081 hacia `172.16.2.2:8081`.

---

## 2. Verificación del Firewall (FW1)

### 2.1. Interfaces y Enrutamiento
- `eth0`: `172.16.0.1/30`
- `eth1.10`: `172.16.1.1/24` (VLAN 10 Usuarios)
- `eth1.20`: `172.16.2.1/29` (VLAN 20 Web)
- `eth1.30`: `172.16.3.1/29` (VLAN 30 Database)
- `net.ipv4.ip_forward = 1`
- Ruta por defecto: `172.16.0.2` (R1).

### 2.2. Reglas del Cortafuegos (`nftables`)
- Política por defecto: `drop` en cadenas `input` y `forward`.
- Tráfico permitido:
  - Usuarios (`172.16.1.0/24`) -> WEB01 (`172.16.2.2`): puertos TCP 80, 443.
  - Servidor Web (`172.16.2.2`) -> Servidor BD (`172.16.3.2`): puerto TCP 5432.
  - Internet (`eth0`) -> WEB01 (`172.16.2.2`): puerto TCP 80.
  - Interbancario B5 vía B4 (`10.0.0.14`) -> WEB01: puerto TCP 8081.
  - Interbancario B5 vía B1/B2 (`10.0.0.17`) -> WEB01: puerto TCP 8080.
  - Salida DNS y Web para redes internas.
  - Bloqueo de dominios restringidos mediante set `@blocked_domains`.

---

## 3. Verificación del Conmutador (SW1)

- **VLANs Activas:**
  - VLAN 10: `USUARIOS`
  - VLAN 20: `WEB`
  - VLAN 30: `DATABASE`
- **Troncal Gi0/0:** 802.1Q con VLANs 10, 20, 30 permitidas.
- **Seguridad de Puertos (Port Security):**
  - Gi0/1 (PC-USR): `switchport port-security`, modo `restrict`, MAC sticky `0cde.5edb.0000`.
- **Spanning Tree:** Rapid-PVST.

---

## 4. Verificación del Servidor Web y Backend (WEB01)

- **Nginx:**
  - Puerto 80: Sirve frontend web y expone `/api/` hacia Flask local. Bloquea rutas interbancarias (`/interbancaria`).
  - Puertos 8080 y 8081: Reciben peticiones interbancarias y enrutan a `/interbancaria` en Flask local.
- **Backend Flask (`/opt/interbanco.py`):**
  - Proceso activo bajo OpenRC (`rc-service interbanco status` = started).
  - Escuchando en `0.0.0.0:5001`.
  - Conexión hacia base de datos en `172.16.3.2:5432` operativa.

---

## 5. Verificación de la Base de Datos (DB01)

- **PostgreSQL:**
  - Escuchando en puerto 5432 (`listen_addresses = '*'`).
  - `pg_hba.conf`: Restringe acceso remoto exclusivamente a `172.16.2.2/32` (WEB01) con `scram-sha-256`.
  - Base de datos `banca_digital` operativa con tabla `cuentas`.

---

## 6. Resultados de Pruebas Mínimas de Conectividad

1. **Acceso al portal HTTP desde PC-USR (`172.16.1.10`):**
   ```text
   $ curl -I -s --connect-timeout 3 http://172.16.2.2
   HTTP/1.1 200 OK
   Server: nginx
   Content-Type: text/html
   ```
2. **Aislamiento de puertos de gestión/interbancarios desde PC-USR:**
   ```text
   $ curl -I -s --connect-timeout 3 http://172.16.2.2:8080 (Timeout / Descartado por FW1)
   $ curl -I -s --connect-timeout 3 http://172.16.2.2:8081 (Timeout / Descartado por FW1)
   ```
3. **Conectividad WEB01 a DB01:**
   ```text
   $ nc -z -v -w 2 172.16.3.2 5432
   172.16.3.2 (172.16.3.2:5432) open
   ```
4. **Consulta API Flask a Base de Datos:**
   ```text
   $ curl -s http://127.0.0.1:5001/cuenta/1
   {"cuenta":{"id":1,"saldo":1761.0,"titular":"Cliente Banco 3 A"},"ok":true}
   ```
