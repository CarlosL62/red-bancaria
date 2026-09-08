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

#### Rutas Interbancarias Primarias, Flotantes Validadas y Descarte
```text
! Primarias (AD 1, condicionadas a Object Tracking End-to-End Hop-2)
ip route 10.0.0.0 255.255.255.252 10.0.0.5 track 1    ! Primaria B1-B2 vía B2 (Track 1 UP: B1 vía B2)
ip route 10.0.0.12 255.255.255.252 10.0.0.10 track 3  ! Primaria B4-B5 vía B4 (Track 3 UP: B5 vía B4)
ip route 10.0.0.16 255.255.255.252 10.0.0.10 track 3  ! Primaria B5-B1 vía B4 (Track 3 UP: B5 vía B4)

! Flotantes Validadas (AD 10, condicionadas a Track del camino alterno)
ip route 10.0.0.16 255.255.255.252 10.0.0.5 10 track 1  ! Respaldo B5-B1 vía B2 (Track 1 UP: B1 vía B2)
ip route 10.0.0.8 255.255.255.252 10.0.0.5 10 track 1   ! Respaldo B4 vía B2 (wrap directo si cae enlace este)
ip route 10.0.0.0 255.255.255.252 10.0.0.10 10 track 3  ! Respaldo B1-B2 vía B4 (Track 3 UP: arco este)
ip route 10.0.0.4 255.255.255.252 10.0.0.10 10 track 3  ! Respaldo B2 vía B4 (wrap directo si cae enlace oeste)

! Descarte de Anillo (Protección contra Bucles, Rebotes y Fugas a Default Route)
ip route 10.0.0.0 255.255.255.224 Null0 250            ! Descarta el bloque 10.0.0.0/27 si no hay /30 activa
```
> **Decisión de Arquitectura (Eliminación de Flotante `10.0.0.12/30` hacia B2):** Durante un corte físico entre B4 y B5, el segmento `10.0.0.12/30` deja de existir. Mantener una flotante hacia Banco 2 obligaba a B2 (que no tiene ruta hacia B5 por el este) a devolver el tráfico a B3, creando un rebote `B3 -> B2 -> B3`. Al eliminar la flotante, los paquetes dirigidos a la interfaz caída `10.0.0.14` caen directamente en `Null0 10.0.0.0/27` en el salto local sin ningún rebote. Banco 5 sigue siendo 100% alcanzable a través de su interfaz oeste `10.0.0.17` mediante la flotante `10.0.0.16/30 via 10.0.0.5 10 track 1`.

### IP SLA y Object Tracking (Arquitectura Validada con Histéresis)
Banco 3 implementa la supervisión de 2 saltos (Hop-2) en ambos arcos del anillo:
* **Track 1 (B3 -> B2 -> B1):** Monitorea la alcanzabilidad de Banco 1 (`10.0.0.1`, Salto 2) por el camino oeste (Fa1/0 hacia B2). Controla la primaria a `10.0.0.0/30` y respalda `10.0.0.16/30` y `10.0.0.8/30`.
  ```text
  ip sla monitor 1
   type echo protocol ipIcmpEcho 10.0.0.1 source-interface FastEthernet1/0
   timeout 2000
   threshold 2000
   frequency 5
  ip sla monitor schedule 1 life forever start-time now
  track 1 rtr 1 reachability
   delay down 6 up 3
  ```
* **Track 3 (B3 -> B4 -> B5):** Monitorea la alcanzabilidad de Banco 5 (`10.0.0.14`, Salto 2) por el camino este (Fa2/0 hacia B4). Gobierna las primarias del arco este: `10.0.0.12/30` y `10.0.0.16/30`. Respalda `10.0.0.0/30` y `10.0.0.4/30`.
  ```text
  ip sla monitor 3
   type echo protocol ipIcmpEcho 10.0.0.14 source-interface FastEthernet2/0
   timeout 2000
   threshold 2000
   frequency 5
  ip sla monitor schedule 3 life forever start-time now
  track 3 rtr 3 reachability
   delay down 6 up 3
  ```
> **Retiro de Sondas Innecesarias:** Se retiró SLA 2 / Track 2 (sonda Hop-3 hacia `10.0.0.18`), cuyo aleteo (900+ transiciones) se originaba en la asimetría de rutas flotantes de retorno en B4. Se retiró SLA 4 / Track 4 al eliminarse la flotante de `10.0.0.12/30`.

### Local PBR (Policy Based Routing Local)
Para evitar dependencias circulares y anclar cada sonda estrictamente a su interfaz de salida sin usar rutas `/32`:
```text
ip access-list extended ACL-SLA-B4-B5
 permit icmp host 10.0.0.9 host 10.0.0.14
ip access-list extended ACL-SLA-B2-B1
 permit icmp host 10.0.0.6 host 10.0.0.1

route-map RM-LOCAL-SLA permit 15
 match ip address ACL-SLA-B4-B5
 set ip next-hop 10.0.0.10
route-map RM-LOCAL-SLA permit 20
 match ip address ACL-SLA-B2-B1
 set ip next-hop 10.0.0.5

ip local policy route-map RM-LOCAL-SLA
```
* **Ventaja y Diferenciador Técnico:** A diferencia de rutas host `/32` fijas (que secuestran el tráfico real por longest prefix match), Local PBR actúa **exclusivamente sobre los paquetes ICMP generados localmente por R1**. El tráfico de producción y el tráfico de tránsito entre B2 y B4 siguen las rutas de la FIB sin verse afectados.

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

### ¿Por qué IP SLA + Object Tracking + Local PBR + Gateo de Flotantes?
* **Limitación del hardware:** Los routers Cisco en topología de anillo con switches intermedios no experimentan caída física (`down/down`) cuando el enlace remoto falla.
* **Solución adoptada:** IP SLA genera sondas activas hacia los endpoints Hop-2 y Hop-3 (`10.0.0.1`, `10.0.0.14`, `10.0.0.18`).
* **Prevención de bucle de sonda:** Local PBR (`RM-LOCAL-SLA`) obliga a cada sonda a salir estrictamente por su cara asignada.
* **Gateo de Rutas Flotantes (Validated Backup Tracking):** Para evitar bucles de rebote (como el observado entre B2 y B3 durante el corte B4-B5), las rutas flotantes **NUNCA entran a ciegas por simple AD**. Cada ruta flotante está condicionada a un Track que certifica la entregabilidad real del camino alternativo:
  - `10.0.0.16/30 via 10.0.0.5 10 track 1`: Solo entra si B2->B1 está vivo (Track 1 UP).
  - `10.0.0.0/30 via 10.0.0.10 10 track 2`: Solo entra si B4->B5->B1 está vivo (Track 2 UP).
  - `10.0.0.12/30 via 10.0.0.5 10 track 4`: Solo entra si el arco oeste entrega hacia B5 (Track 4 UP). Si B2 devuelve el tráfico hacia B3 (porque su propia primaria apunta a B3), Track 4 cae a `DOWN` y la flotante no se instala.
* **Descarte de Anillo (`Null0 10.0.0.0/27 AD 250`):** Si tanto la ruta primaria como la flotante están desactivadas, el tráfico hacia subredes del anillo es descartado localmente con ICMP Unreachable, extinguiendo microbucles de rebote y evitando fugas hacia la ruta por defecto del ISP.

### Diagnóstico de Bucles y Rebotes
1. **Rebote B2-B3 hacia `10.0.0.12/30` durante corte B4-B5 (EXTINGUIDO):**
   - *Causa raíz:* Al cortarse B4-B5, el Track 10 de Banco 2 sigue en UP (porque monitorea a B4 `10.0.0.10` vía B3, que sigue respondiendo). Por tanto, B2 mantiene su primaria `10.0.0.12/30 via 10.0.0.6` (B3). Si B3 instalaba su flotante ciega `via 10.0.0.5`, se producía un rebote cerrado `B3 -> B2 -> B3`.
   - *Solución implementada:* B3 implementó Track 4 (monitoreo del camino alterno hacia `10.0.0.14` vía B2) y descarte en `Null0 10.0.0.0/27`. Al rebotar B2 la sonda, Track 4 cae a `DOWN`, la flotante no se instala y el tráfico cae a `Null0` limpiamente sin rebote ni loop.
2. **Bucle B4-B5 hacia `10.0.0.4/30` (EXTINGUIDO):** Resuelto tras la incorporación de ruta de retorno en B2.

---

## 12. Políticas de Seguridad Implementadas

* **Principio de Mínimo Privilegio:** FW1 bloquea todo tráfico por defecto. Únicamente se abren los puertos indispensables con restricciones estrictas de IP origen.
* **Aislamiento de la Base de Datos:** DB01 carece de acceso directo a Internet o a las interfaces de interconexión del anillo.
* **Separación de Servicios Web:** Bloqueo de URLs transaccionales en el puerto público 80 mediante reglas Nginx (`return 404`).
* **Protección de Tránsito:** Las redes LAN `172.16.x.x` jamás se anuncian hacia los otros bancos; toda comunicación interbancaria se realiza mediante las IPs de tránsito de R1 (`10.0.0.6` y `10.0.0.9`).

---

## 13. Verificación Global del Anillo y Pruebas en Vivo

Auditoría integral ejecutada desde los nodos de Banco 3 (R1 y WEB01) sobre la totalidad de vecinos, segmentos de tránsito y servicios del anillo:

### 13.1. Vecinos Directos
* **Banco 2 (`10.0.0.5` vía `FastEthernet1/0`):** **100% OK** (3/3 pings exitosos, RTT avg 21 ms). Estado L1/L2: **UP / UP**.
* **Banco 4 (`10.0.0.10` vía `FastEthernet2/0`):** **100% OK** (3/3 pings exitosos, RTT avg 20 ms). Estado L1/L2: **UP / UP**.

### 13.2. Redes del Anillo y Conectividad L3
* **Red `10.0.0.0/30` (B1-B2):** **ALCANZABLE**. Primaria `10.0.0.0/30 via 10.0.0.5` (AD 1, Track 1 UP).
* **Red `10.0.0.4/30` (B2-B3):** **ALCANZABLE**. Conectada en `Fa1/0` (AD 0).
* **Red `10.0.0.8/30` (B3-B4):** **ALCANZABLE**. Conectada en `Fa2/0` (AD 0).
* **Red `10.0.0.12/30` (B4-B5):** **ALCANZABLE**. Primaria `10.0.0.12/30 via 10.0.0.10` (AD 1, Track 3 UP).
* **Red `10.0.0.16/30` (B5-B1):** **ALCANZABLE**. Primaria `10.0.0.16/30 via 10.0.0.10` (AD 1, Track 2 UP).

### 13.3. IP SLA, Object Tracking y Local PBR
* **SLA 1 (`10.0.0.1` vía `Fa1/0`):** **UP** (Track 1 UP, RTT ~84-96 ms). Controla primaria `10.0.0.0/30` y flotante `10.0.0.16/30`.
* **SLA 3 (`10.0.0.14` vía `Fa2/0`):** **UP** (Track 3 UP, RTT ~1-8 ms). Controla primarias `10.0.0.12/30` y `10.0.0.16/30`, y flotantes `10.0.0.0/30` y `10.0.0.4/30`.
* **SLA 2 y SLA 4:** **ELIMINADOS**. SLA 2 (Hop-3 hacia `10.0.0.18`) retirado para extinguir el flapping continuo (>900 aleteos) causado por el retorno asimétrico de B4. SLA 4 retirado al removerse la flotante innecesaria hacia `10.0.0.12/30`.
* **Histéresis:** `delay down 6 up 3` configurada en ambos tracks activos (1 y 3). Transiciones 100% limpias y libres de aleteo.

### 13.4. Evaluación de Failover y Bucles Potenciales
* **Failover de `10.0.0.16/30` (B3 -> B2 -> B1 -> B5):** Con corte en el arco este (Track 3 DOWN), la flotante hacia Banco 2 (`via 10.0.0.5 10 track 1`) asume de inmediato en la RIB. Ping a `10.0.0.17` 100% OK (3/3), traceroute completado en 3 saltos limpios (`10.0.0.5 -> 10.0.0.1 -> 10.0.0.17`).
* **Protección ante Corte B4-B5 (`10.0.0.12/30`):** Track 3 cae a DOWN; al no existir ruta flotante hacia B2 para esta red, el tráfico hacia `10.0.0.14` cae de forma local e inmediata en `Null0 10.0.0.0/27 AD 250`. Se extingue por completo el rebote `B3 -> B2 -> B3`.
* **Preservación de Tránsito:** El route-map `RM-LOCAL-SLA` solo aplica por `ip local policy` a paquetes generados localmente por R1. El tráfico interbancario de tránsito (B2 <-> B4) no es evaluado por PBR y se enruta de forma transparente a nivel L3.

### 13.5. Servicios Interbancarios Probados
* **Banco 1 (`10.0.0.1:80`):** **OPERATIVO** (`HTTP/1.0 200 OK` en `/`).
* **Banco 1 (`10.0.0.1:80/interbancaria`):** **OPERATIVO**. Petición POST con payload de prueba inválido responde `HTTP/1.0 400 Bad Request` (`JSON_INVALIDO`), confirmando servicio activo sin generar transacciones reales.
* **Banco 1 (`10.0.0.18:80`):** **NO OPERATIVO / TIMEOUT**. B1 documenta que el NAT estático sobre Gi0/2 no persistió en Cisco IOSv. El servicio solo se expone en `10.0.0.1`.
* **Banco 3 Inbound (`POST /interbancaria`):** **100% OPERATIVO**. Nginx en WEB01 escucha en 8080 y 8081 y reenvía a Flask 5001. Ambos puertos responden con HTTP 400 (`JSON invalido`) ante payloads de prueba. FW1 aplica filtrado estricto:
  - Vía este (`10.0.0.9:80` -> NAT `172.16.2.2:8081`): Acepta únicamente `saddr 10.0.0.14`.
  - Vía oeste (`10.0.0.6:80` -> NAT `172.16.2.2:8080`): Acepta únicamente `saddr 10.0.0.17`.
  - Durante corte B4-B5, Banco 5 debe enviar a `10.0.0.6:80` con origen `10.0.0.17` para ser admitido por el firewall.
* **Banco 3 Outbound hacia B1:** `/opt/interbanco.py` tiene configurado fallback secuencial (`BANCO1_ENDPOINTS`: primaria `10.0.0.1`, respaldo `10.0.0.18`). Durante un corte B4-B5, la ruta hacia `10.0.0.1` (arco oeste) no se ve afectada y B3 consume a B1 sin degradación.
* **Banco 2 (`10.0.0.2:5001`):** API Depósitos / Transferencias (publicada hacia B1).
* **Banco 4 (`10.0.0.10:8080` / `10.0.0.13:8080`):** Blacklist **100% OPERATIVO**.

### 13.6. Resultados del Simulacro de Failover B4-B5 (Prueba Real en R1)
Ejecución del simulacro desactivando temporalmente SLA 3 en R1:
1. **Estado de Tracks durante el Corte:**
   - `Track 1` (B1 vía B2): **UP** (sin alteración).
   - `Track 3` (B5 vía B4): **DOWN** tras cumplir temporizador `delay down 6`. **Cero aleteos (0 flaps)**.
2. **Tabla de Enrutamiento (RIB de R1):**
   - `10.0.0.0/30 [1/0] via 10.0.0.5` (Primaria oeste ACTIVA).
   - `10.0.0.16/30 [10/0] via 10.0.0.5` (Flotante hacia B5-B1 ACTIVA).
   - `10.0.0.12/30`: **RETIRADA DE LA TABLA** (ni primaria ni flotante instaladas).
   - `10.0.0.0/27 is directly connected, Null0` (Descarte activo para destinos no asignados).
3. **Pruebas de Conectividad en Falla:**
   - `ping 10.0.0.1` (B1): **100% OK** (3/3 paquetes recibidos, RTT ~36-64 ms).
   - `ping 10.0.0.17` (B5 cara B1): **100% OK** (3/3 paquetes recibidos, RTT ~4-28 ms vía B2->B1->B5).
   - `traceroute 10.0.0.17`: **3 saltos limpios** (`10.0.0.5 -> 10.0.0.1 -> 10.0.0.17`).
   - `ping 10.0.0.12/30`: Descarte inmediato en R1 (Null0).
   - **¿Hay rebote?: NO.** El rebote previo `B3 -> B2 -> B3` quedó **100% eliminado**.
   - **¿Hay bucle?: NO.** Cero formación de bucles.
   - **¿El tráfico se entrega o descarta limpiamente?:** Tráfico hacia B5 vía B1 se entrega con 100% de éxito; tráfico hacia el segmento cortado se descarta limpiamente en `Null0`.
4. **Recuperación Post-Falla:**
   - Tras reactivar SLA 3: Track 3 pasa a `UP` a los 3 segundos (`delay up 3`).
   - Primarias `10.0.0.12/30` y `10.0.0.16/30` se reinstalan automáticamente vía `10.0.0.10`.
   - Flotantes vuelven a estado standby.
   - Conectividad 100% confirmada (`ping 10.0.0.14` 3/3 OK, `ping 10.0.0.1` 3/3 OK).
   - Configuración persistida con `write memory`.

---

## 14. Problemas Conocidos y Dependencias Externas

1. **Falta de ruta simétrica de retorno en Banco 1 para `10.0.0.8/30`:** Banco 1 enruta `10.0.0.8/30` únicamente por B2. Para que las sondas de SLA 2 y el tráfico directo del arco este alcancen `10.0.0.18`, B1 requiere ajustar su tabla o B2 restaurar su tránsito.
2. **Endpoint `/interbancaria` en Banco 1:** El servidor HTTP en `10.0.0.1:80` responde 404 para transacciones interbancarias.
3. **Publicación de servicios en Banco 2 hacia Banco 3:** Banco 2 requiere habilitar NAT/PAT sobre Fa3/0 si desea que Banco 3 consuma directamente su API en `5001`.
4. **Revisión de bucle B4-B5 ante doble contingencia:** Banco 5 debe revisar su ruta de respaldo hacia `10.0.0.0/30` para condicionarla a track y evitar devolver paquetes hacia B4 (`10.0.0.13`) cuando B1 esté desconectado.

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
