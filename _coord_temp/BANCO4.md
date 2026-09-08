# Banco 4 (Banco con doble ISP) — Documentación Técnica de Infraestructura y Coordinación

Documento técnico oficial de la arquitectura, conectividad, enrutamiento, seguridad y estado vivo de **Banco 4** en el anillo interbancario.

---

## 1. Estado General
* **Última actualización:** 2026-09-07 17:55 UTC-6
* **Agente/responsable:** Banco 4 (Agente de Integración)
* **Estado en el anillo:** Operativo en enlaces directos B4-B3 y B4-B5. Conectividad interbancaria confirmada hacia Banco 5, Banco 1 y Banco 2 vía B5.

---

## 2. Interfaces de Tránsito Interbancario

Banco 4 se interconecta al anillo mediante dos enlaces físicos/lógicos dedicados gestionados por su router de borde Linux (`INTERNET`):

| Enlace | Subred | IP Local (B4) | IP Vecino | Interfaz B4 | Enlace Físico / Cloud Host |
|---|---|---|---|---|---|
| **B4 ↔ B3** | `10.0.0.8/30` | `10.0.0.10` | B3 = `10.0.0.9` | `eth3` | `CLOUD-B3` (`eno1`) |
| **B4 ↔ B5** | `10.0.0.12/30` | `10.0.0.13` | B5 = `10.0.0.14` | `eth4` | `CLOUD-B5` (`enxc0eac367f731`) |

---

## 3. Vecinos Directos

* **Banco 3 (`10.0.0.9`):** Conectividad directa por `eth3`. Estado L1/L2: **UP / UP**. RTT ~4-18 ms.
* **Banco 5 (`10.0.0.14`):** Conectividad directa por `eth4`. Estado L1/L2: **UP / UP**. RTT ~3-10 ms.

---

## 4. Arquitectura Interna de Banco 4

Banco 4 opera con una arquitectura de alta disponibilidad con doble ISP y router Linux de tránsito:
* **INTERNET (Alpine Linux):** Router de borde hacia el anillo y gateway de tránsito con doble homing a ISP1 e ISP2.
* **ISP1 / ISP2 (Cisco 7200):** Proveedores de servicio internos redundantes (`100.64.1.0/30` y `100.64.2.0/30`).
* **FW-BANCO4 (Alpine Linux - nftables):** Firewall de seguridad perimetral interno con conmutación por script de failover.
* **SRV-ARCHIVOS (`192.168.43.20:8080`):** Servidor de archivos y API REST de Lista Negra (Blacklist).
* **SRV-BANCA-APP-1 (`192.168.42.20:5000`):** Aplicación de Banca Web.
* **SRV-BANCA-DB-1 (`192.168.42.10:5432`):** Base de Datos PostgreSQL.
* **PC-USUARIO (`192.168.41.10`):** Cliente de pruebas bancarias.

---

## 5. Tabla de Enrutamiento (Rutas Primarias y Flotantes)

El nodo `INTERNET` gestiona el enrutamiento interbancario del kernel Linux mediante métricas (métrica 10 para caminos primarios, métrica 20 para flotantes de respaldo):

### Rutas Primarias (Métrica 10)
* `10.0.0.8/30`: Conectada directamente en `eth3` (`src 10.0.0.10`).
* `10.0.0.12/30`: Conectada directamente en `eth4` (`src 10.0.0.13`).
* `10.0.0.4/30`: `via 10.0.0.9 dev eth3 metric 10` (camino hacia B3 / B2).
* `10.0.0.0/30`: `via 10.0.0.9 dev eth3 metric 10` (camino hacia B2 / B1 por la derecha).
* `10.0.0.16/30`: `via 10.0.0.14 dev eth4 metric 10` (camino hacia B5 / B1 por la izquierda - **ACTIVA**).
* `172.20.5.0/24`: `via 10.0.0.14 dev eth4 metric 10` (LAN de Banco 5 - **ACTIVA**).

### Rutas Flotantes de Respaldo (Métrica 20)
* Respaldo por Banco 5 (`eth4`):
  * `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20` (**ACTIVA** por failover de Track B2)
  * `10.0.0.4/30 via 10.0.0.14 dev eth4 metric 20` (**ACTIVA** por failover de Track B2)
  * `10.0.0.8/30 via 10.0.0.14 dev eth4 metric 20`
* Respaldo por Banco 3 (`eth3`):
  * `10.0.0.16/30 via 10.0.0.9 dev eth3 metric 20`
  * `10.0.0.12/30 via 10.0.0.9 dev eth3 metric 20`
  * `172.20.5.0/24 via 10.0.0.9 dev eth3 metric 20`

---

## 6. IP SLA y Object Tracking

Banco 4 implementa un demonio supervisor continuo en Linux (`/etc/network/ip-sla-ring.sh`), persistente en `/etc/network/if-up.d/` y consultable mediante `ip-sla status`:

* **Frecuencia:** Sondas ICMP cada 2 segundos.
* **Umbrales:** 2 fallos consecutivos para DOWN, 2 aciertos consecutivos para UP.

### Estado Actual de las Sondas:
| Sonda | Destino / Interfaz | Tipo de Monitoreo | Estado | Acción Asociada |
|---|---|---|---|---|
| **Track B3** | `10.0.0.9` por `eth3` | Vecino Directo | **UP** | Enlace B4-B3 sano. |
| **Track B2** | `10.0.0.5` por `eth3` | Extremo a Extremo | **DOWN** | Al no responder B2 en `10.0.0.5` vía `eth3`, se retiraron `10.0.0.4/30` y `10.0.0.0/30` de `eth3`. Respaldo activo por `eth4`. |
| **Track B5** | `10.0.0.14` por `eth4` | Vecino Directo | **UP** | Enlace B4-B5 sano. |
| **Track B1** | `10.0.0.18` por `eth4` | Extremo a Extremo | **UP** | B1 responde por `eth4` (~20 ms). Ruta primaria `10.0.0.16/30` activa. |

---

## 7. PBR / Route Maps
* **No implementado:** Banco 4 no aplica Policy-Based Routing en su nodo de borde interbancario; el reenvío se basa estrictamente en la tabla de rutas IP del kernel.

---

## 8. NAT / PAT Interbancario

* **Router Puro de Tránsito:** Banco 4 **NO aplica NAT, PAT ni Masquerade** a los paquetes que transitan entre el anillo (`eth3` y `eth4`). Se preservan íntegramente las direcciones IP de origen y destino de todos los bancos.
* **Reenvío IP:** `net.ipv4.ip_forward = 1` activo en `INTERNET`.
* **NAT Perimetral Exclusivo:** Solo se aplica masquerade en `eth2` hacia la salida a Internet real (`10.255.4.0/24`) y DNAT en `FW-BANCO4` para publicar el puerto 8080.

---

## 9. Servicios Interbancarios Publicados

* **Servicio de Lista Negra (Blacklist):**
  * Servidor Flask en puerto `8080` (publicado por DNAT hacia `192.168.43.20:8080`).
  * URLs de acceso:
    * Desde Banco 3: `http://10.0.0.10:8080/blacklist`
    * Desde Banco 5: `http://10.0.0.13:8080/blacklist`
    * Healthcheck: `http://10.0.0.10:8080/health`
* **Consumo de Servicios:**
  * Banco 4 consume el servicio de depósitos de Banco 2 en `http://10.0.0.2:5001/interbanco/deposito` (probado exitosamente, puerto 5001 validado abierto).

---

## 10. Pruebas Recientes de Conectividad

* Ping B4 a B3 (`10.0.0.9`): **100% OK** (RTT ~5-18 ms).
* Ping B4 a B3 interfaz B2 (`10.0.0.6`): **100% OK** (RTT ~10-44 ms forzando salida `eth3`).
* Ping B4 a B5 (`10.0.0.14`): **100% OK** (RTT ~3-9 ms).
* Ping B4 a B5 interfaz B1 (`10.0.0.17`): **100% OK** (RTT ~4-10 ms).
* Ping B4 a B1 (`10.0.0.18`, `10.0.0.1`): **100% OK** (RTT ~20 ms vía B5).
* Ping B4 a B2 (`10.0.0.2`): **100% OK** (RTT ~30 ms vía B5 -> B1 -> B2).
* Ping B4 a B2 (`10.0.0.5`): **0% (FAIL - Timeout)** vía `eth3`.

---

## 11. Análisis del Bucle Reportado hacia `10.0.0.0/30`

Banco 3 reportó haber observado un bucle cerrado entre Banco 4 y Banco 5 hacia `10.0.0.0/30`:

### Diagnóstico Técnico del Bucle:
1. **Ruta primaria configurada en B4:** `10.0.0.0/30 via 10.0.0.9 dev eth3 metric 10` (apunta a Banco 3).
2. **Next-hop primario:** `10.0.0.9` (Banco 3).
3. **Ruta de respaldo en B4:** `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20` (apunta a Banco 5).
4. **Mecanismo que disparó el bucle:**
   * Banco 2 (`10.0.0.5`) dejó de contestar sondas ICMP.
   * El supervisor IP SLA de Banco 4 declaró `Track B2: DOWN` y retiró la ruta primaria por `eth3`.
   * El tráfico hacia `10.0.0.0/30` conmutó automáticamente a la ruta flotante por `eth4` hacia Banco 5 (`10.0.0.14`).
   * **Simultáneamente:** Banco 1 (`10.0.0.18`) estaba caído o inalcanzable desde Banco 5.
   * Banco 5, al tener caído su enlace primario a B1, conmutó su ruta de `10.0.0.0/30` a su ruta flotante de respaldo que **apuntaba hacia Banco 4 (`10.0.0.13`)**.
   * **Bucle resultante:** B4 reenvió a B5, y B5 reenvió a B4 (`10.0.0.10 -> 10.0.0.14 -> 10.0.0.13 -> 10.0.0.14...`), generando un bucle cerrado hasta agotar el TTL.
5. **Mitigación y Estado Actual:**
   * El bucle solo ocurre cuando se produce una **doble falla simultánea** (B1 caído en la izquierda Y B2 caído en la derecha).
   * **En este momento el bucle NO existe**, puesto que Banco 1 recuperó conectividad con Banco 5: Banco 5 reenvía el tráfico hacia Banco 1 en vez de regresarlo a Banco 4.

---

## 12. Verificación Global del Anillo

### A. Vecinos Directos
* **Vecino 1 (Banco 3):** `10.0.0.9` por `eth3` -> **100% OK** (RTT avg: 18.0 ms).
* **Vecino 2 (Banco 5):** `10.0.0.14` por `eth4` -> **100% OK** (RTT avg: 6.3 ms).

### B. Todas las Redes /30 del Anillo
* **Red `10.0.0.0/30` (B1-B2):**
  * Destinos probados: `10.0.0.1` (B1) y `10.0.0.2` (B2).
  * Alcanzable: **SÍ**.
  * Ruta activa: `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20` (conmutada por failover vía B5).
  * Next-hop: `10.0.0.14` (Banco 5).
  * RTT / Saltos: ~20 ms hacia `10.0.0.1` (2 saltos) / ~30 ms hacia `10.0.0.2` (3 saltos: B4 -> B5 -> B1 -> B2).
* **Red `10.0.0.4/30` (B2-B3):**
  * Destinos probados: `10.0.0.5` (B2 hacia B3) / `10.0.0.6` (B3 hacia B2).
  * Alcanzable: **NO** hacia `10.0.0.5` desde B4. (`10.0.0.6` responde en B3 forzando `eth3`, pero la ruta general está conmutada hacia B5 donde no hay entrega a `.5`).
  * Ruta activa: `10.0.0.4/30 via 10.0.0.14 dev eth4 metric 20`.
  * Next-hop: `10.0.0.14` (Banco 5).
  * Traceroute resumido: B4 (`10.0.0.13`) -> B5 (`10.0.0.14`) -> timeout (*).
* **Red `10.0.0.8/30` (B3-B4):**
  * Destino probado: `10.0.0.9` (B3).
  * Alcanzable: **SÍ**.
  * Ruta activa: `10.0.0.8/30 dev eth3 proto kernel scope link src 10.0.0.10`.
  * Next-hop: Directo (`eth3`).
  * RTT: ~5 ms (1 salto).
* **Red `10.0.0.12/30` (B4-B5):**
  * Destino probado: `10.0.0.14` (B5).
  * Alcanzable: **SÍ**.
  * Ruta activa: `10.0.0.12/30 dev eth4 proto kernel scope link src 10.0.0.13`.
  * Next-hop: Directo (`eth4`).
  * RTT: ~3 ms (1 salto).
* **Red `10.0.0.16/30` (B5-B1):**
  * Destinos probados: `10.0.0.17` (B5) y `10.0.0.18` (B1).
  * Alcanzable: **SÍ**.
  * Ruta activa: `10.0.0.16/30 via 10.0.0.14 dev eth4 metric 10`.
  * Next-hop: `10.0.0.14` (Banco 5).
  * RTT: ~20 ms (2 saltos: B4 -> B5 -> B1).

### C. Routing y Rutas Activas
* **Rutas primarias (Métrica 10):**
  * `10.0.0.8/30 dev eth3` (directa)
  * `10.0.0.12/30 dev eth4` (directa)
  * `10.0.0.4/30 via 10.0.0.9 dev eth3 metric 10` (Track B2)
  * `10.0.0.0/30 via 10.0.0.9 dev eth3 metric 10` (Track B2)
  * `10.0.0.16/30 via 10.0.0.14 dev eth4 metric 10` (Track B1 - **ACTIVA**)
  * `172.20.5.0/24 via 10.0.0.14 dev eth4 metric 10` (LAN B5 - **ACTIVA**)
* **Rutas flotantes (Métrica 20):**
  * `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20` (**ACTIVA** por failover de Track B2)
  * `10.0.0.4/30 via 10.0.0.14 dev eth4 metric 20` (**ACTIVA** por failover de Track B2)
  * `10.0.0.8/30 via 10.0.0.14 dev eth4 metric 20`
  * `10.0.0.16/30 via 10.0.0.9 dev eth3 metric 20`
  * `10.0.0.12/30 via 10.0.0.9 dev eth3 metric 20`
  * `172.20.5.0/24 via 10.0.0.9 dev eth3 metric 20`
* **Rutas actualmente instaladas en FIB del kernel:**
  * `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20`
  * `10.0.0.4/30 via 10.0.0.14 dev eth4 metric 20`
  * `10.0.0.8/30 dev eth3 proto kernel scope link src 10.0.0.10`
  * `10.0.0.12/30 dev eth4 proto kernel scope link src 10.0.0.13`
  * `10.0.0.16/30 via 10.0.0.14 dev eth4 metric 10`
  * `172.20.5.0/24 via 10.0.0.14 dev eth4 metric 10`
* **Retorno hacia el banco emisor:** Ninguna ruta de B4 devuelve tráfico hacia el mismo banco del que provino en operación normal.

### D. IP SLA / Tracks
* **Track B3 (10.0.0.9 vía eth3):** **UP** (coincide con conectividad real; RTT ~5 ms).
* **Track B2 (10.0.0.5 vía eth3):** **DOWN** (coincide con conectividad real; B2 no responde por Fa3/0 a pings de B4). Controla primarias de `10.0.0.4/30` y `10.0.0.0/30`.
* **Track B5 (10.0.0.14 vía eth4):** **UP** (coincide con conectividad real; RTT ~3 ms).
* **Track B1 (10.0.0.18 vía eth4):** **UP** (coincide con conectividad real; B1 restableció conectividad, RTT ~20 ms). Controla primaria de `10.0.0.16/30`.

### E. Evaluación de Failover y Loops Potenciales
* **Comportamiento de Failover:**
  * El failover de B2 hacia B5 está **operativo**: B4 alcanza `10.0.0.2` (B2) a través de B5 y B1 con RTT de 30 ms.
  * El failover de B1 hacia B3 apunta a `10.0.0.9 dev eth3`.
* **Riesgo de Loop Detectado:**
  * **Red afectada:** `10.0.0.0/30`
  * **Bancos implicados:** Banco 4 y Banco 5.
  * **Secuencia:** Ocurre exclusivamente ante **doble falla simultánea** (B1 caído en el oeste Y B2 caído en el este). Si B1 cae, B5 conmuta a B4 (`10.0.0.13`); si B2 cae, B4 conmuta a B5 (`10.0.0.14`). El tráfico rebota B4 <-> B5 hasta expirar TTL.
  * **Estado actual:** **INACTIVO / NO OCURRE**, ya que el enlace B5-B1-B2 está arriba y B5 no está devolviendo el tráfico a B4.

### F. Servicios Interbancarios Probados
* **Banco 2 (`10.0.0.2:5001`):**
  * Puerto: `5001` (TCP)
  * Resultado: **EXITOSO / OPEN** (puerto abierto, validado vía TCP desde B4 cruzando B5 y B1).
* **Banco 3 (`10.0.0.9:80`):**
  * Puerto: `80` (TCP)
  - Resultado: **TIMEOUT** (acorde a diseño de seguridad de B3, el puerto 80 público está filtrado en tránsito).
* **Banco 4 (Servicio propio expuesto):**
  * API Blacklist: `http://10.0.0.10:8080/blacklist` y `http://10.0.0.13:8080/blacklist` (100% operativo).

### G. Problemas Pendientes
1. **Track B2 en DOWN por `eth3`:** Banco 2 tiene su `Track 4 (B4 vía B3)` en DOWN según su documentación, lo que hace que su ruta `10.0.0.8/30 via 10.0.0.6` no se instale y descarte respuestas directas por Fa3/0 hacia `Null0`.
2. Restablecer la alcanzabilidad directa B4-B3-B2 para que B4 regrese sus rutas primarias a `eth3`.

---

## 13. Notas para Otros Bancos

* **A Banco 2:** Por favor verificar en su router:
  `ip route 10.0.0.8 255.255.255.252 10.0.0.6`
  Sin esta ruta, Banco 2 no puede responder a las solicitudes directas de Banco 4 por Fa3/0.
* **A Banco 5:** Confirmar cómo maneja su ruta flotante hacia `10.0.0.0/30` cuando B1 está caído para evitar rebotes hacia `10.0.0.13`.
