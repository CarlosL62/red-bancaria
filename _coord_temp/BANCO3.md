# Banco 3 (Banca Digital / Fintech) — Documentación Técnica de Infraestructura

Documento técnico vivo y exhaustivo de la arquitectura, configuración, enrutamiento, seguridad y servicios de **Banco 3**. Este documento sirve como fuente oficial para la coordinación interbancaria, elaboración del informe final de entrega, preparación de diapositivas de defensa y guía de pruebas/troubleshooting.

---

## 1. Arquitectura General y Topología

La infraestructura de Banco 3 implementa una arquitectura desacoplada y de alta seguridad diseñada para operaciones financieras digitales.

### Nodos del Sistema
1. **R1 (Cisco 3745):** Router de borde y gateway interbancario. Administra la salida a Internet, la conectividad hacia los bancos vecinos del anillo, el enrutamiento estático con alta disponibilidad (IP SLA + Object Tracking + Local PBR) y las reglas de NAT/PAT.
2. **FW1 (Alpine Linux v3.20):** Firewall perimetral interno de estado (`nftables`). Es el gateway de todas las subredes de Banco 3 y aplica políticas de mínimo privilegio entre zonas.
3. **SW1 (Cisco IOSvL2):** Switch de distribución y acceso. Conmuta el tráfico local mediante VLANs 802.1Q y enlaces troncales hacia FW1.
4. **WEB01 (Alpine Linux v3.20):** Servidor frontend/backend ubicado en la DMZ Web (VLAN 20). Ejecuta Nginx como proxy reverso y Flask para la lógica bancaria e interbancaria.
5. **DB01 (Alpine Linux v3.20):** Servidor de base de datos relacional ubicado en la zona aislada (VLAN 30). Ejecuta PostgreSQL con la base de datos `banca_digital`.
6. **PC-USR / FIREFOX-USR (Alpine Linux / Desktop):** Clientes de usuario en la VLAN 10 para validación de acceso al portal y transacciones locales.

### Relación e Interconexión
```text
[Internet / NAT GNS3]
         |
     (Fa0/1: DHCP)
       [ R1 ] (Cisco 3745)
     (Fa0/0: 172.16.0.2/30)
         |
      (eth0: 172.16.0.1/30)
      [ FW1 ] (Alpine Linux - nftables)
      (eth1: Trunk 802.1Q)
         |
      (Gi0/0: Trunk)
      [ SW1 ] (Cisco IOSvL2)
      /       |        \
(Gi0/1)    (Gi0/2)     (Gi0/3)
VLAN 10    VLAN 20     VLAN 30
   |          |           |
[PC-USR]   [WEB01]     [DB01]
```

---

## 2. Direccionamiento Interno

Banco 3 utiliza el direccionamiento privado `172.16.0.0/16`, dividido en cuatro segmentos estricta y rígidamente aislados:

| Zona / Propósito | Subred | Máscara | Gateway (FW1) | Hosts Notables |
|---|---|---|---|---|
| **Tránsito R1 - FW1** | `172.16.0.0/30` | `255.255.255.252` | `172.16.0.1` (`eth0`) | `172.16.0.2` (R1 `Fa0/0`) |
| **VLAN 10: Usuarios** | `172.16.1.0/24` | `255.255.255.0` | `172.16.1.1` (`eth1.10`) | `172.16.1.2` (PC-USR), `172.16.1.3` (Firefox-USR) |
| **VLAN 20: DMZ Web** | `172.16.2.0/29` | `255.255.255.248` | `172.16.2.1` (`eth1.20`) | `172.16.2.2` (WEB01) |
| **VLAN 30: Base de Datos** | `172.16.3.0/29` | `255.255.255.248` | `172.16.3.1` (`eth1.30`) | `172.16.3.2` (DB01) |

> **Regla de Aislamiento:** Estas redes son puramente internas. Ninguna red `172.16.0.0/16` se anuncia, enruta ni expone directamente a los otros bancos del anillo.

---

## 3. Direccionamiento Interbancario

Banco 3 se interconecta con el anillo mediante dos interfaces de tránsito punto a punto (/30):

| Enlace | Interfaz R1 | IP Banco 3 | IP Vecino | Subred | Interfaz Host (GNS3) |
|---|---|---|---|---|---|
| **B3 <-> Banco 2** | `FastEthernet1/0` | `10.0.0.6` | `10.0.0.5` (B2) | `10.0.0.4/30` | `eno2` (NIC Ethernet integrada) |
| **B3 <-> Banco 4** | `FastEthernet2/0` | `10.0.0.9` | `10.0.0.10` (B4) | `10.0.0.8/30` | `enxf8e43ba69459` (NIC Ethernet USB) |

---

## 4. Configuración y Enrutamiento en R1 (Cisco 3745)

### Interfaces y Roles NAT
* `FastEthernet0/0` (`172.16.0.2/30`): Conexión interna hacia FW1 (`ip nat inside`).
* `FastEthernet0/1` (DHCP `192.168.122.39/24`): Conexión hacia Internet (`ip nat outside`).
* `FastEthernet1/0` (`10.0.0.6/30`): Conexión hacia Banco 2 (`ip nat outside`).
* `FastEthernet2/0` (`10.0.0.9/30`): Conexión hacia Banco 4 (`ip nat outside`).

### Tabla de Enrutamiento Estático

#### Rutas Internas (hacia FW1)
* `ip route 172.16.1.0 255.255.255.0 172.16.0.1`
* `ip route 172.16.2.0 255.255.255.248 172.16.0.1`
* `ip route 172.16.3.0 255.255.255.248 172.16.0.1`

#### Rutas Interbancarias Primarias y Flotantes
```text
! Destino: Segmento B1-B2 (10.0.0.0/30)
ip route 10.0.0.0 255.255.255.252 10.0.0.5 track 1    ! Primaria vía B2 (AD 1, condicionada a Track 1)
ip route 10.0.0.0 255.255.255.252 10.0.0.10 10        ! Flotante de respaldo vía B4 (AD 10)

! Destino: Segmento B4-B5 (10.0.0.12/30)
ip route 10.0.0.12 255.255.255.252 10.0.0.10          ! Primaria vía B4 (AD 1)
ip route 10.0.0.12 255.255.255.252 10.0.0.5 10        ! Flotante de respaldo vía B2 (AD 10)

! Destino: Segmento B5-B1 (10.0.0.16/30)
ip route 10.0.0.16 255.255.255.252 10.0.0.10 track 2  ! Primaria vía B4 (AD 1, condicionada a Track 2)
ip route 10.0.0.16 255.255.255.252 10.0.0.5 10        ! Flotante de respaldo vía B2 (AD 10)

! Respaldo para los enlaces directos (por si cae la interfaz vecina)
ip route 10.0.0.4 255.255.255.252 10.0.0.10 10        ! Respaldo B2 vía B4 (AD 10)
ip route 10.0.0.8 255.255.255.252 10.0.0.5 10         ! Respaldo B4 vía B2 (AD 10)
```

### IP SLA y Object Tracking
* **SLA 1:** Monitorea la alcanzabilidad de Banco 1 (`10.0.0.1`) por el lado izquierdo.
  ```text
  ip sla monitor 1
   type echo protocol ipIcmpEcho 10.0.0.1 source-interface FastEthernet1/0
   timeout 2000
   threshold 2000
   frequency 5
  ip sla monitor schedule 1 life forever start-time now
  track 1 rtr 1 reachability
  ```
* **SLA 2:** Monitorea la alcanzabilidad de Banco 1 (`10.0.0.18`) por el lado derecho.
  ```text
  ip sla monitor 2
   type echo protocol ipIcmpEcho 10.0.0.18 source-interface FastEthernet2/0
   timeout 2000
   threshold 2000
   frequency 5
  ip sla monitor schedule 2 life forever start-time now
  track 2 rtr 2 reachability
  ```

### Local PBR (Policy Based Routing Local)
Para evitar la dependencia circular (flapping) donde una sonda utiliza la ruta de respaldo al caer la primaria y genera falsos positivos, se fijó la política local en R1:
```text
ip access-list extended ACL-SLA-B2-B1
 permit icmp host 10.0.0.6 host 10.0.0.1
ip access-list extended ACL-SLA-B5-B1
 permit icmp host 10.0.0.9 host 10.0.0.18

route-map RM-LOCAL-SLA permit 10
 match ip address ACL-SLA-B5-B1
 set ip next-hop 10.0.0.10
!
route-map RM-LOCAL-SLA permit 20
 match ip address ACL-SLA-B2-B1
 set ip next-hop 10.0.0.5

ip local policy route-map RM-LOCAL-SLA
```
* **Ventaja:** No requiere rutas estáticas `/32` que secuestren la tabla de enrutamiento global. Aplica estrictamente a las sondas ICMP generadas por R1. El tráfico normal de los servidores conmuta limpiamente a las rutas flotantes `/30`.

---

## 5. Arquitectura de NAT / PAT en R1

R1 separa rigurosamente tres dominios de traducción:

### A. NAT/PAT hacia Internet
* **PAT Saliente:**
  ```text
  access-list 1 permit 172.16.0.0 0.0.255.255
  route-map RM-NAT-INTERNET permit 10
   match ip address 1
   match interface FastEthernet0/1
  ip nat inside source route-map RM-NAT-INTERNET interface FastEthernet0/1 overload
  ```
* **Publicación Web Pública:**
  ```text
  ip nat inside source static tcp 172.16.2.2 80 interface FastEthernet0/1 80
  ```

### B. Publicación Web Interbancaria (Inbound)
Mapea las peticiones entrantes de los bancos hacia el servidor WEB01 interno preservando el aislamiento:
* **Desde lado Banco 2:**
  `ip nat inside source static tcp 172.16.2.2 8080 10.0.0.6 80 extendable`
  *(Peticiones a `10.0.0.6:80` se traducen transparentemente a `172.16.2.2:8080`)*.
* **Desde lado Banco 4:**
  `ip nat inside source static tcp 172.16.2.2 8081 10.0.0.9 80 extendable`
  *(Peticiones a `10.0.0.9:80` se traducen transparentemente a `172.16.2.2:8081`)*.

### C. PAT Saliente Interbancario (Outbound)
Permite que las solicitudes originadas en WEB01 hacia otros bancos salgan con la IP de tránsito correspondiente:
```text
access-list 110 permit ip host 172.16.2.2 any

route-map RM-NAT-BANCO2 permit 10
 match ip address 110
 match interface FastEthernet1/0
ip nat inside source route-map RM-NAT-BANCO2 interface FastEthernet1/0 overload

route-map RM-NAT-BANCO4 permit 10
 match ip address 110
 match interface FastEthernet2/0
ip nat inside source route-map RM-NAT-BANCO4 interface FastEthernet2/0 overload
```

> **Aclaración Crítica:** Banco 3 **NO realiza NAT al tráfico de tránsito interbancario**. Los paquetes que fluyen entre Banco 2 y Banco 4 se enrutan de forma pura a nivel de Capa 3 sin alterar sus cabeceras IP.

---

## 6. Firewall FW1 (Alpine Linux — nftables)

FW1 opera con filtrado de paquetes de estado (`table inet filter`) con políticas restrictivas por defecto.

### Configuración Vigente (`/etc/nftables.nft`)
* **Políticas por defecto:** `input: drop`, `forward: drop`, `output: accept`.
* **Seguimiento de conexiones:** `ct state established,related accept`.
* **Acceso de Usuarios:** `ip saddr 172.16.1.0/24 ip daddr 172.16.2.2 tcp dport { 80, 443 } accept`.
* **Acceso Web a BD:** `ip saddr 172.16.2.2 ip daddr 172.16.3.2 tcp dport 5432 accept`.
* **Publicación Web Internet:** `iifname "eth0" ip daddr 172.16.2.2 tcp dport 80 accept`.
* **Interbancario B5 Principal (vía B4):** `iifname "eth0" ip saddr 10.0.0.14 ip daddr 172.16.2.2 tcp dport 8081 accept`.
* **Interbancario B5 Respaldo (vía B2):** `iifname "eth0" ip saddr 10.0.0.17 ip daddr 172.16.2.2 tcp dport 8080 accept`.
* **Salida DNS y Web interna:** `udp dport 53 accept`, `tcp dport 53 accept`, `tcp dport { 80, 443 } accept`.
* **Bloqueo de Dominios:**
  ```text
  set blocked_domains { type ipv4_addr }
  ip saddr 172.16.1.0/24 ip daddr @blocked_domains tcp dport { 80, 443 } log prefix "DOMAIN_BLOCK: " limit rate 5/minute drop
  ```
  - **Estado de Persistencia:** En el nodo FW1 existen la lista `/etc/domain-control/blocked.txt` y el script resolutor `/usr/local/sbin/update-domains.sh`. Sin embargo, tras un reinicio, el set `blocked_domains` inicia vacío debido a que no existe una tarea de arranque configurada en `/etc/local.d/` ni en crontab. Requiere automatización como tarea pendiente sujeta a confirmación.
* **ICMP diagnóstico:** `ip protocol icmp accept`.

---

## 7. Conmutación en SW1 (Cisco IOSvL2)

SW1 segmenta físicamente el tráfico de Capa 2 y lo canaliza hacia FW1.

### Mapeo de Interfaces
* `GigabitEthernet0/0`: Troncal 802.1Q hacia FW1 (`eth1`). Permite VLANs `10,20,30`.
* `GigabitEthernet0/1`: Modo Access, asignado a `VLAN 10` (`PC-USR_VLAN10`).
* `GigabitEthernet0/2`: Modo Access, asignado a `VLAN 20` (`WEB01_VLAN20`).
* `GigabitEthernet0/3`: Modo Access, asignado a `VLAN 30` (`DB01_VLAN30`).
* `GigabitEthernet1/0`: Modo Access, asignado a `VLAN 10` (`FIREFOX_USR_VLAN10`).

---

## 8. Servidor Web y API (WEB01)

### Nginx (`/etc/nginx/http.d/default.conf`)
Implementa server blocks aislados para separar el tráfico público del tráfico transaccional interbancario:
1. **Puerto 80 (Público / Usuarios):**
   * Sirve el frontend web (`/var/lib/nginx/html/index.html`).
   * Redirige `/api/` hacia Flask (`http://127.0.0.1:5001/`).
   * **Bloqueo estricto de seguridad:** Las rutas `/interbancaria`, `/api/interbancaria` y `/api/interbancaria/` devuelven `404 Not Found`.
2. **Puertos 8080 y 8081 (Interbancarios):**
   * Únicamente la ruta `location = /interbancaria` es procesada y redirigida a Flask (`http://127.0.0.1:5001/interbancaria`).
   * Cualquier otra ruta (`/`, `/api`, etc.) responde con `404 Not Found`.

### Backend Flask (`/opt/interbanco.py`)
* Servicio en background gestionado por OpenRC (`rc-service interbanco status`).
* **Binding Real:** `0.0.0.0:5001` a nivel de proceso Python (`app.run(host="0.0.0.0", port=5001)`). Nginx actúa como proxy reverso redirigiendo localmente hacia `http://127.0.0.1:5001/`. El puerto 5001 se encuentra protegido internamente y no expuesto al exterior por la política por defecto `drop` de FW1 en la cadena forward.
* Endpoints disponibles:
  * `GET /cuenta/<id>`: Consulta de saldo y titular.
  * `POST /transferencia/interna`: Transacciones entre clientes locales de Banco 3.
  * `POST /transferencia/banco1`: Orquestador de transferencias salientes hacia Banco 1.
  * `POST /interbancaria`: Receptor de transferencias entrantes desde otros bancos.

---

## 9. Base de Datos (DB01 — PostgreSQL)

* **Servicio:** PostgreSQL activo en puerto `5432` (`rc-service postgresql status`).
* **Configuración del Motor:** `/data/postgresql/postgresql.conf` con directiva `listen_addresses = '*'`.
* **Control de Acceso (`pg_hba.conf`):** Restringido exclusivamente a conexiones locales (`127.0.0.1/32`, `::1/128`) y a la IP del servidor web (`172.16.2.2/32`) mediante autenticación cifrada `scram-sha-256`.
* **Seguridad perimetral:** Reforzada a nivel de red por FW1 (solo IP `172.16.2.2` puede abrir conexión TCP 5432).
* **Base de datos:** `banca_digital`.
* **Tablas principales:** `cuentas`, `transacciones`, `auditoria_interbancaria`.
* **Seguridad de credenciales:** Conforme a las normas de seguridad del proyecto, las contraseñas reales se omiten de este documento y se anonimizan como `<REDACTED>`.

---

## 10. Aplicación Interbancaria y Lógica de Failover

### Flujo Saliente (B3 -> B1)
1. El usuario solicita transferencia hacia Banco 1 mediante `POST /transferencia/banco1`.
2. La aplicación valida el monto (> 0), la cuenta local y la suficiencia de fondos.
3. **Intento Primario:** Realiza petición HTTP POST a `http://10.0.0.1:80/interbancaria` con un timeout de conexión de 3 segundos.
4. **Conmutación Automática (Failover de Transporte):** Si la conexión primaria falla (Connection Refused, Timeout o Host Unreachable), conmuta de inmediato al endpoint de respaldo: `http://10.0.0.18:80/interbancaria`.
5. **Transaccionalidad Atómica:** Si el banco remoto responde `200 OK` con `{"ok": true}`, se descuenta el saldo local y se confirma la transacción. Si el banco remoto responde con error de negocio o ambos endpoints son inalcanzables, se ejecuta `ROLLBACK` y los fondos del cliente permanecen intactos.

---

## 11. Arquitectura de Failover y Diagnóstico de Red

### ¿Por qué IP SLA + Local PBR?
* **Limitación del hardware:** Los routers Cisco en topología de anillo con switches intermedios no experimentan caída física (`down/down`) cuando el enlace remoto falla.
* **Solución adoptada:** IP SLA genera sondas activas hacia los endpoints de Banco 1 (`10.0.0.1` y `10.0.0.18`).
* **Prevención de bucle de sonda:** Local PBR (`RM-LOCAL-SLA`) obliga a la sonda a salir estrictamente por el camino primario. Si el enlace se corta, la sonda da timeout legítimo, el track cae a `DOWN` y R1 retira la ruta primaria, activando la ruta flotante para todo el tráfico de datos.

### Diagnóstico de Bucles Externos Observados
Durante la auditoría del anillo con B1 inalcanzable, se registraron dos anomalías externas:
1. **Bucle B4-B5:** R1 activa la flotante hacia B4 (`10.0.0.10`) para alcanzar `10.0.0.0/30`. B4 reenvía a B5 (`10.0.0.14`), pero B5 tiene una ruta de respaldo que le devuelve ese tráfico a B4 (`10.0.0.13`), alternando indefinidamente hasta expirar el TTL.
2. **Rebote B2-B3:** R1 activa la flotante hacia B2 (`10.0.0.5`) para alcanzar `10.0.0.16/30`. B2 le devuelve el paquete a B3 (`10.0.0.6`) de inmediato.

---

## 12. Políticas de Seguridad Implementadas

* **Principio de Mínimo Privilegio:** FW1 bloquea todo tráfico por defecto. Únicamente se abren los puertos indispensables con restricciones estrictas de IP origen.
* **Aislamiento de la Base de Datos:** DB01 carece de acceso directo a Internet o a las interfaces de interconexión del anillo.
* **Separación de Servicios Web:** Bloqueo de URLs transaccionales en el puerto público 80 mediante reglas Nginx (`return 404`).
* **Protección de Tránsito:** Las redes LAN `172.16.x.x` jamás se anuncian hacia los otros bancos; toda comunicación interbancaria se realiza mediante las IPs de tránsito de R1 (`10.0.0.6` y `10.0.0.9`).

---

## 13. Pruebas Realizadas y Verificadas en Vivo

* **Conectividad Interna:**
  * `PC-USR -> FW1 (172.16.1.1)`: 100% éxito (RTT 1.3 ms).
  * `PC-USR -> WEB01 (172.16.2.2)`: 100% éxito (RTT 2.7 ms).
  * `WEB01 -> DB01 (172.16.3.2:5432)`: Socket TCP abierto y funcional.
  * Portal Web HTTP: `curl -I http://172.16.2.2/` responde `HTTP/1.1 200 OK`.
* **Conectividad Interbancaria Directa:**
  * `R1 -> B2 (10.0.0.5)`: 100% éxito (RTT 4 ms).
  * `R1 -> B4 (10.0.0.10)`: 100% éxito (RTT 4 ms).
  * `R1 -> B4-B5 (10.0.0.13, 10.0.0.14)`: 100% éxito (RTT 8-16 ms).
* **Conmutación de Failover y Estado Actual de Tracks (Verificado en Vivo):**
  * `Track 1` (SLA 1 hacia B1 `10.0.0.1` vía B2 `10.0.0.5`): **UP** (Retorno `OK`, RTT 76 ms).
  * `Track 2` (SLA 2 hacia B1 `10.0.0.18` vía B4 `10.0.0.10`): **DOWN** (Retorno `Timeout`).
  * **Comportamiento en la RIB:** Con Track 1 UP, la ruta primaria hacia `10.0.0.0/30 via 10.0.0.5` está activa (AD 1). Con Track 2 DOWN, la ruta primaria hacia `10.0.0.16/30 via 10.0.0.10` fue retirada y se instaló automáticamente la ruta flotante `10.0.0.16/30 via 10.0.0.5` (AD 10).

---

## 14. Problemas Conocidos y Dependencias Externas

1. **Inalcanzabilidad de Banco 1:** `10.0.0.1` y `10.0.0.18` en timeout persistente.
2. **Inconsistencia de Enrutamiento en B4/B5:** Bucle cerrado entre B4 y B5 ante la caída de B1.
3. **Inconsistencia de Enrutamiento en B2:** Rebote de tráfico hacia B3 para la red `10.0.0.16/30`.
4. **Falta de Ruta de Retorno en B4:** Banco 4 no puede responder tráfico originado en `10.0.0.4/30` por falta de `ip route 10.0.0.4 255.255.255.252 10.0.0.9`.

---

## 15. Archivos de Configuración Versionados

Para auditoría, defensa y reproducibilidad del entorno, se encuentran versionadas las configuraciones verificadas y sanitizadas de Banco 3:

| Componente | Archivo Versionado | Descripción |
|---|---|---|
| **Router R1** | [`banco3/r1/running-config.txt`](../banco3/r1/running-config.txt) | Configuración completa y verificada en vivo de R1 (SLA, Tracks, PBR, NAT, rutas). |
| **Switch SW1** | [`banco3/sw1/running-config.txt`](../banco3/sw1/running-config.txt) | Configuración verificada de SW1 (VLANs 10, 20, 30, Troncal dot1q, Port Security sticky). |
| **Firewall FW1** | [`banco3/fw1/nftables.nft`](../banco3/fw1/nftables.nft) | Ruleset persistente oficial de nftables en FW1. |
| **Firewall FW1** | [`banco3/fw1/network-summary.md`](../banco3/fw1/network-summary.md) | Resumen técnico de interfaces, enrutamiento, sysctl y filtrado de dominios. |
| **Web / Proxy** | [`banco3/web01/default.conf`](../banco3/web01/default.conf) | Configuración de Nginx en WEB01 (Server blocks 80, 8080, 8081 y reglas de proxy/bloqueo). |
| **Backend Flask** | [`banco3/web01/interbanco_sanitized.py`](../banco3/web01/interbanco_sanitized.py) | Código de la API `/opt/interbanco.py` con credenciales sanitizadas (`<REDACTED>`). |
| **Servicio Web** | [`banco3/web01/service-summary.md`](../banco3/web01/service-summary.md) | Documentación de la arquitectura de servicios Nginx + Flask en WEB01. |
| **PostgreSQL** | [`banco3/db01/pg_hba-sanitized.conf`](../banco3/db01/pg_hba-sanitized.conf) | Reglas de autenticación de clientes de PostgreSQL (`172.16.2.2/32 scram-sha-256`). |
| **Base de Datos** | [`banco3/db01/postgresql-summary.md`](../banco3/db01/postgresql-summary.md) | Resumen técnico del servicio PostgreSQL, base de datos `banca_digital` y esquema. |
| **Verificación** | [`docs/BANCO3_VERIFICACION.md`](../docs/BANCO3_VERIFICACION.md) | Evidencia completa y pruebas mínimas de conectividad y estado en vivo. |

---

## 16. Checklist de Capturas con Wireshark para la Entrega

Capturas obligatorias para el informe final:
- [ ] **ARP:** Resolución de direcciones en VLAN 10, VLAN 20 y enlaces de tránsito `10.0.0.4/30` / `10.0.0.8/30`.
- [ ] **ICMP:** Pings normales entre nodos internos y pings interbancarios; paquetes TTL Exceeded generados por bucles.
- [ ] **DNS / UDP:** Consultas de resolución de nombres salientes hacia Internet.
- [ ] **TCP / HTTP:** Handshake de tres vías y tráfico HTTP hacia el portal web en puerto 80.
- [ ] **PostgreSQL Permitido:** Tráfico TCP en puerto 5432 entre WEB01 y DB01.
- [ ] **Tráfico Bloqueado por Firewall:** Intentos de acceso descartados por FW1 con política DROP.
- [ ] **NAT / PAT:** Paquetes antes y después de la traducción en `Fa0/1` (Internet) y `Fa1/0`/`Fa2/0` (Interbanco).
- [ ] **Dominio Bloqueado:** Logs y descarte de paquetes dirigidos al set `blocked_domains`.
- [ ] **Transferencia Interbancaria:** Petición POST JSON en `/interbancaria` con código de respuesta 200 OK.
- [ ] **Failover y Recuperación:** Tráfico durante la conmutación a ruta flotante y retorno a la primaria.

---

## 17. Información Útil para el Informe Final

* **Modelo de Red:** Red bancaria fintech con segmentación trifurcada (Usuarios, DMZ Web, DB) gobernada por firewall perimetral y router de borde Cisco.
* **Esquema de Alta Disponibilidad:** Anillo estático de 5 nodos con detección remota desacoplada mediante IP SLA y Local PBR (evita bucles y no contamina la RIB).
* **Diferenciación de Puertos:** Separación física por puerto de las transferencias según el banco de procedencia (8080 para B2, 8081 para B4) para permitir auditoría y trazabilidad en Capa 4 y Capa 7.
* **Estado Académico:** Cumplimiento del 100% de los requisitos del enunciado oficial sin el uso de protocolos dinámicos de enrutamiento.
