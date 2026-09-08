# Evidencia de Verificación Técnica y Conectividad del Anillo — Banco 3 (Fintech)

- **Fecha de Verificación:** 2026-09-07 (Actualizado en vivo)
- **Entorno:** Topología de Redes II / GNS3
- **Rol:** Banco 3 / Coordinador de Integración
- **Estado General del Anillo:** Operativo en el semicírculo oeste (B3 <-> B2 <-> B1) y en el este hasta Banco 5 (B3 <-> B4 <-> B5). Enlace B5-B1 reconectado por Banco 1.

---

## 1. Verificación de Vecinos Directos desde R1

| Vecino | Dirección IP | Interfaz de Salida | Estado Enlace | Resultado Ping | RTT Min/Avg/Max |
|---|---|---|---|---|---|
| **Banco 2** | `10.0.0.5` | `FastEthernet1/0` (`10.0.0.6/30`) | **UP / UP** | **100% OK (3/3)** | 4 / 20 / 28 ms |
| **Banco 4** | `10.0.0.10` | `FastEthernet2/0` (`10.0.0.9/30`) | **UP / UP** | **100% OK (3/3)** | 8 / 21 / 32 ms |

---

## 2. Verificación de Redes de Tránsito del Anillo

| Segmento | Subred | Destinos Probados | Alcanzable | Ruta Activa en R1 | Next-Hop | AD | Track | Detalle / RTT |
|---|---|---|---|---|---|---|---|---|
| **B1 - B2** | `10.0.0.0/30` | `10.0.0.1` (B1)<br>`10.0.0.2` (B2) | **SÍ**<br>**SÍ** | `10.0.0.0/30 [1/0]` | `10.0.0.5` (B2) | 1 | Track 1 (**UP**) | RTT ~54 ms (`.1`) / ~42 ms (`.2`). Traceroute: 1 salto a `.2` (4 ms), 2 saltos a `.1` (32 ms). |
| **B2 - B3** | `10.0.0.4/30` | `10.0.0.5` (B2) | **SÍ** | Conectada `Fa1/0` | Directo | 0 | N/A | RTT ~4 ms (1 salto directo). |
| **B3 - B4** | `10.0.0.8/30` | `10.0.0.10` (B4) | **SÍ** | Conectada `Fa2/0` | Directo | 0 | N/A | RTT ~8 ms (1 salto directo). |
| **B4 - B5** | `10.0.0.12/30` | `10.0.0.13` (B4)<br>`10.0.0.14` (B5) | **SÍ**<br>**SÍ** | `10.0.0.12/30 [1/0]` | `10.0.0.10` (B4) | 1 | Primaria sin track | RTT ~20 ms (`.13` y `.14`). Traceroute: 1 salto a `.13` (4 ms), 2 saltos a `.14` (32 ms vía B4). |
| **B5 - B1** | `10.0.0.16/30` | `10.0.0.17` (B5)<br>`10.0.0.18` (B1) | **SÍ** (vía Fa2/0)<br>**NO** (Timeout) | `10.0.0.16/30 [10/0]` (Flotante) | `10.0.0.5` (B2) | 10 | Track 2 (**DOWN**) | `10.0.0.17` responde 100% (RTT 20 ms) forzando salida Fa2/0. `10.0.0.18` da timeout por falta de retorno en B1 para `10.0.0.8/30`. |

---

## 3. Estado de Routing en Banco 3 (R1)

### Tabla de Rutas Activa (`show ip route`)
```text
C    192.168.122.0/24 is directly connected, FastEthernet0/1
C    172.16.0.0/30 is directly connected, FastEthernet0/0
S    172.16.1.0/24 [1/0] via 172.16.0.1
S    172.16.2.0/29 [1/0] via 172.16.0.1
S    172.16.3.0/29 [1/0] via 172.16.0.1
C    10.0.0.4/30 is directly connected, FastEthernet1/0
C    10.0.0.8/30 is directly connected, FastEthernet2/0
S    10.0.0.0/30 [1/0] via 10.0.0.5          <-- ACTIVA PRIMARIA (Track 1 UP)
S    10.0.0.12/30 [1/0] via 10.0.0.10         <-- ACTIVA PRIMARIA
S    10.0.0.16/30 [10/0] via 10.0.0.5        <-- ACTIVA FLOTANTE (Track 2 DOWN)
S*   0.0.0.0/0 [254/0] via 192.168.122.1
```

### Análisis de Retornos y Respaldo
- **Para `10.0.0.0/30`:** Ruta primaria vía B2 (`10.0.0.5`). Si cae, conmuta a B4 (`10.0.0.10`). Con B1 activo, B5 entrega a B1 y no hay bucle.
- **Para `10.0.0.12/30`:** Ruta primaria vía B4 (`10.0.0.10`). Si cae, conmuta a B2 (`10.0.0.5`). B2 entrega a B1 y B1 a B5.
- **Para `10.0.0.16/30`:** Con Track 2 en DOWN, la flotante está activa hacia B2 (`10.0.0.5`). Banco 2 enruta hacia B1 (`10.0.0.1`) y no rebota a B3 gracias a que condicionó su propia flotante a Track 8 (actualmente DOWN) y configuró descarte `Null0 10.0.0.0/27`.

---

## 4. Estado de IP SLA, Tracks y Local PBR

### Configuración y Verificación en Vivo
- **SLA 1:** ICMP Echo hacia `10.0.0.1` source `FastEthernet1/0`. Next-hop forzado a `10.0.0.5` mediante `RM-LOCAL-SLA`.
  - **Track 1:** **UP** (`Latest operation return code: OK`, `RTT: 12 ms`).
- **SLA 2:** ICMP Echo hacia `10.0.0.18` source `FastEthernet2/0`. Next-hop forzado a `10.0.0.10` mediante `RM-LOCAL-SLA`.
  - **Track 2:** **DOWN** (`Latest operation return code: Timeout`).
- **Causa raíz de Track 2 DOWN:**
  - El paquete de prueba sale por Fa2/0 (`10.0.0.9`) y llega exitosamente a Banco 1 por B4 y B5.
  - Sin embargo, Banco 1 tiene configurada su ruta hacia `10.0.0.8/30` apuntando a Banco 2 (`10.0.0.2`), en vez de Banco 5.
  - Al recibir el paquete en Gi0/2, B1 responde hacia B2, donde B2 tiene su track hacia B4 caído y descarta en `Null0`.

---

## 5. Pruebas de Servicios Interbancarios

| Banco | Destino | Puerto | Protocolo / Método | Resultado | Código HTTP / Detalle |
|---|---|---|---|---|---|
| **Banco 1** | `10.0.0.1` | `80` | HTTP / GET | **OPERATIVO** | `HTTP/1.0 200 OK` — Devuelve portal interno HTML ("Banco 1 - Portal Interno"). |
| **Banco 1** | `10.0.0.1` | `80` | HTTP / GET `/interbancaria` | **NO DISPONIBLE** | `HTTP/1.0 404 Not Found` — Endpoint transaccional no implementado aún en B1. |
| **Banco 1** | `10.0.0.1` | `8080` | TCP | **TIMEOUT** | No contesta en puerto 8080 desde B3. |
| **Banco 2** | `10.0.0.2` | `5001` | TCP | **TIMEOUT** | NAT estático de B2 solo está configurado en Fa2/0 (hacia B1), no en Fa3/0 (hacia B3). |
| **Banco 4** | `10.0.0.10` | `8080` | TCP | **CONNECTION REFUSED** | RST recibido de B4. L3 funcional, servicio no expuesto en esa interfaz. |
| **Banco 5** | `10.0.0.14` | `80` | TCP | **CONNECTION REFUSED** | RST recibido de B5. L3 funcional, sin servidor HTTP en puerto 80. |

---

## 6. Pruebas Internas de Banco 3

1. **Acceso Web Usuarios:** `PC-USR` accede al portal web local (`http://172.16.2.2/`) con respuesta `HTTP/1.1 200 OK`.
2. **Aislamiento de Puertos:** Puertos de gestión e interbancarios (8080, 8081) inaccesibles desde VLAN 10 (descarte por FW1).
3. **Conexión Web a BD:** WEB01 conecta exitosamente a PostgreSQL (`172.16.3.2:5432`) y ejecuta consultas atómicas sobre la tabla `cuentas`.
