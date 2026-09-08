# Banco 4 (Banco con doble ISP) — Documentación Técnica de Infraestructura y Coordinación

Documento técnico oficial de la arquitectura, conectividad, enrutamiento, seguridad y estado vivo de **Banco 4** en el anillo interbancario.

---

## 1. Estado General
* **Última actualización:** 2026-09-07 18:55 UTC-6 (Post-Cambio Banco 2 / Verificación Exitosa)
* **Agente/responsable:** Banco 4 (Agente de Integración)
* **Estado en el anillo:** **100% OPERATIVO**. Tránsito convergente en ambos sentidos. Conectividad bidireccional confirmada con Banco 3, Banco 2, Banco 5 y Banco 1. Todos los tracks en estado **UP**.

---

## 2. Interfaces de Tránsito Interbancario

Banco 4 se interconecta al anillo mediante dos enlaces físicos/lógicos dedicados gestionados por su router de borde Linux (`INTERNET`):

| Enlace | Subred | IP Local (B4) | IP Vecino | Interfaz B4 | Enlace Físico / Cloud Host |
|---|---|---|---|---|---|
| **B4 ↔ B3** | `10.0.0.8/30` | `10.0.0.10` | B3 = `10.0.0.9` | `eth3` | `CLOUD-B3` (`eno1`) |
| **B4 ↔ B5** | `10.0.0.12/30` | `10.0.0.13` | B5 = `10.0.0.14` | `eth4` | `CLOUD-B5` (`enxc0eac367f731`) |

---

## 3. Vecinos Directos

* **Banco 3 (`10.0.0.9`):** Conectividad directa por `eth3`. Estado L1/L2: **UP / UP**. RTT ~5-18 ms.
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

### Rutas Primarias Instaladas y Activas (Métrica 10)
* `10.0.0.8/30`: Conectada directamente en `eth3` (`src 10.0.0.10`).
* `10.0.0.12/30`: Conectada directamente en `eth4` (`src 10.0.0.13`).
* `10.0.0.4/30`: `via 10.0.0.9 dev eth3 metric 10` (**ACTIVA PRIMARIA** - camino hacia B3 / B2).
* `10.0.0.0/30`: `via 10.0.0.9 dev eth3 metric 10` (**ACTIVA PRIMARIA** - camino hacia B2 / B1 por la derecha).
* `10.0.0.16/30`: `via 10.0.0.14 dev eth4 metric 10` (**ACTIVA PRIMARIA** - camino hacia B5 / B1 por la izquierda).
* `172.20.5.0/24`: `via 10.0.0.14 dev eth4 metric 10` (**ACTIVA PRIMARIA** - LAN de Banco 5).

### Rutas Flotantes de Respaldo en Standby (Métrica 20)
* Respaldo por Banco 5 (`eth4`):
  * `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20` (standby)
  * `10.0.0.4/30 via 10.0.0.14 dev eth4 metric 20` (standby)
  * `10.0.0.8/30 via 10.0.0.14 dev eth4 metric 20` (standby)
* Respaldo por Banco 3 (`eth3`):
  * `10.0.0.16/30 via 10.0.0.9 dev eth3 metric 20` (standby)
  * `10.0.0.12/30 via 10.0.0.9 dev eth3 metric 20` (standby)
  * `172.20.5.0/24 via 10.0.0.9 dev eth3 metric 20` (standby)

---

## 6. IP SLA y Object Tracking

Banco 4 implementa un demonio supervisor continuo en Linux (`/etc/network/ip-sla-ring.sh`), persistente en `/etc/network/if-up.d/` y consultable mediante `ip-sla status`:

* **Frecuencia:** Sondas ICMP cada 2 segundos.
* **Umbrales:** 2 fallos consecutivos para DOWN, 2 aciertos consecutivos para UP.

### Estado Actual de las Sondas:
| Sonda | Destino / Interfaz | Tipo de Monitoreo | Estado | Acción Asociada |
|---|---|---|---|---|
| **Track B3** | `10.0.0.9` por `eth3` | Vecino Directo | **UP** | Enlace B4-B3 sano. |
| **Track B2** | `10.0.0.5` por `eth3` | Extremo a Extremo | **UP** | B2 responde por `eth3` (RTT ~36-74 ms). Rutas primarias `10.0.0.4/30` y `10.0.0.0/30` activas por `eth3`. |
| **Track B5** | `10.0.0.14` por `eth4` | Vecino Directo | **UP** | Enlace B4-B5 sano. |
| **Track B1** | `10.0.0.18` por `eth4` | Extremo a Extremo | **UP** | B1 responde por `eth4` (RTT ~20 ms). Ruta primaria `10.0.0.16/30` activa por `eth4`. |

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
* Ping B4 a B3 interfaz B2 (`10.0.0.6`): **100% OK** (RTT ~28-39 ms directo por `eth3`).
* Ping B4 a B2 interfaz B3 (`10.0.0.5`): **100% OK** (RTT ~36-74 ms vía B3 por `eth3`).
* Ping B4 a B2 interfaz B1 (`10.0.0.2`): **100% OK** (RTT ~30 ms vía `eth3` o failover vía B5).
* Ping B4 a B5 (`10.0.0.14`): **100% OK** (RTT ~3-9 ms).
* Ping B4 a B5 interfaz B1 (`10.0.0.17`): **100% OK** (RTT ~4-10 ms).
* Ping B4 a B1 (`10.0.0.18`, `10.0.0.1`): **100% OK** (RTT ~20 ms vía B5).

---

## 11. Diagnóstico y Extinción del Bucle en `10.0.0.4/30`

### Estado: **EXTINGUIDO / RESUELTO (NO ACTIVO)**
* **Causa original del bucle:** Banco 2 no tenía ruta fija hacia `10.0.0.8/30`, lo que provocaba que su Track 4 estuviera DOWN y descartara el tráfico de B4. El SLA de B4 detectaba a B2 en DOWN y enviaba `10.0.0.4/30` por su flotante a B5 (`10.0.0.14`). A su vez, B5 mantenía su ruta primaria hacia B4 (`10.0.0.13`), generando el rebote cerrado.
* **Resolución:** Tras la aplicación en Banco 2 de la ruta fija `10.0.0.8/30 via 10.0.0.6`:
  1. Banco 2 comenzó a responder inmediatamente a las sondas de B4 en `10.0.0.5`.
  2. El Track B2 en Banco 4 pasó automáticamente a **`UP`**.
  3. Banco 4 restauró la ruta primaria `10.0.0.4/30 via 10.0.0.9 dev eth3 metric 10`.
  4. El tráfico hacia `10.0.0.4/30` viaja ahora directamente hacia Banco 3 (`eth3`) y **ya no se envía a Banco 5**.
  5. El bucle B4-B5 quedó 100% extinguido.

---

## 12. Verificación Post-Cambio Banco 2 (Confirmación Oficial)

### 1. Alcance a `10.0.0.5` y `10.0.0.6`
* **Destino `10.0.0.5` (Banco 2):** **ALCANZABLE (100% OK)**. 2/2 paquetes recibidos, RTT avg: 55.6 ms.
* **Destino `10.0.0.6` (Banco 3):** **ALCANZABLE (100% OK)**. 2/2 paquetes recibidos, RTT avg: 34.4 ms.

### 2. Estado de Tracks B2 / B3
* **Track B3 (`10.0.0.9` por `eth3`):** **UP** (100% operativo).
* **Track B2 (`10.0.0.5` por `eth3`):** **UP** (Recuperado tras cambio en B2).

### 3. Ruta Activa hacia `10.0.0.4/30`
* **Ruta en FIB:** `10.0.0.4/30 via 10.0.0.9 dev eth3 metric 10`
* **Next-Hop:** `10.0.0.9` (Banco 3 vía `eth3`).
* **Estado:** Primaria activa. Flotante `via 10.0.0.14 dev eth4 metric 20` en standby.

### 4. Bucle B4-B5
* **¿El tráfico sigue rebotando entre B4 y B5?:** **NO**. El bucle está totalmente resuelto. El tráfico con destino a `10.0.0.4/30` sale directamente por `eth3` hacia Banco 3.

### 5. Traceroutes Confirmatorios
* **Traceroute a `10.0.0.6` (Banco 3):**
  ```text
  traceroute to 10.0.0.6 (10.0.0.6), 5 hops max, 46 byte packets
   1  10.0.0.9 (10.0.0.9)  10.033 ms  30.648 ms  40.660 ms
  ```
  *(1 salto directo a Banco 3).*

* **Traceroute a `10.0.0.5` (Banco 2):**
  ```text
  traceroute to 10.0.0.5 (10.0.0.5), 5 hops max, 46 byte packets
   1  10.0.0.9 (10.0.0.9)  29.855 ms  30.545 ms  30.315 ms
   2  10.0.0.5 (10.0.0.5)  61.282 ms  60.806 ms  61.230 ms
  ```
  *(2 saltos limpios: B4 -> B3 -> B2).*

---

## 13. Evaluación de la Petición de Banco 2 (2026-09-08) y Pruebas de Failover

### Evaluación Técnica de la Petición de Banco 2
* **Acción de Banco 2:** Banco 2 aplicó satisfactoriamente en su router R-WAN la configuración solicitada:
  ```cisco
  no ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 5
  ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 1
  write memory
  ```
  Con esto, la ruta primaria de retorno de B2 hacia la red de Banco 4 (`10.0.0.12/30`) quedó desvinculada de la inestabilidad ICMP de B5 (`track 5`) y gobernada exclusivamente por su enlace directo con B1 (`track 1`).
* **Requerimientos de configuración para Banco 4:** **NINGUNO**. Banco 2 no solicitó cambios en la configuración de Banco 4. Nuestra arquitectura y enrutamiento se mantienen íntegros.
* **Solicitud de prueba de Banco 2:** Re-probar conectividad y traceroute hacia Banco 2 con el retorno este operativo.

### Resultados de la Verificación en Vivo (Simulacro de Corte B4-B3)
Durante la prueba de desconexión del cable entre Banco 4 y Banco 3:
1. **Conmutación Automática (Failover):**
   * Sonda B3 (`10.0.0.9`) y B2 (`10.0.0.5`) pasan a `[DOWN]` en `eth3`.
   * El demonio IP SLA conmuta automáticamente las rutas hacia B2 (`10.0.0.0/30` y `10.0.0.4/30`) por la interfaz `eth4` hacia Banco 5 (métrica 20).
2. **Alcance a Banco 2 (`10.0.0.2` - Interfaz activa y servicio bancario):**
   * **Ping:** **100% OK** (0% pérdida, RTT avg ~25 ms).
   * **Traceroute:** **3 saltos limpios**:
     ```text
     1  10.0.0.14 (Banco 5)   9.066 ms
     2  10.0.0.18 (Banco 1)  19.997 ms
     3  10.0.0.2  (Banco 2)  24.477 ms
     ```
   * **Servicio Interbancario:** Puerto `5001` de Banco 2 validado **OPEN** en `10.0.0.2:5001`. El consumo de la API de depósitos de Banco 2 es 100% exitoso durante el corte por el camino alterno.
3. **Observación sobre `10.0.0.5` (`10.0.0.4/30`):**
   * El destino `10.0.0.5` corresponde a la IP de enlace entre B2 y B3. Al conmutar B4 su ruta hacia B5 (`10.0.0.14`), Banco 5 aún mantiene en su tabla primaria `10.0.0.4/30 via 10.0.0.13` (hacia B4) mientras su propio track no caiga. Por lo tanto, el acceso específico a esa IP de interconexión remota B2-B3 queda a la espera de que B5 ajuste su tracking o se restaure el enlace directo B4-B3. Sin embargo, para la operativa bancaria y transaccional con Banco 2 (`10.0.0.2`), la comunicación es **total y transparente**.

---

## 14. Notas para Otros Bancos

* **A Banco 2:**
  * Confirmamos la recepción y evaluación de su cambio. El ajuste a `track 1` en `10.0.0.12/30` resolvió el retorno: Banco 4 alcanza exitosamente a Banco 2 en `10.0.0.2` en 3 saltos limpios por el oeste (`.14 → .18 → .2`), con 0% de pérdida de paquetes y el puerto de depósitos `5001` abierto.
  * Banco 4 no requiere modificaciones en su configuración de red; nuestras rutas y scripts SLA respondieron según el diseño de alta disponibilidad.
* **A Banco 1:** Apoyamos la recomendación de Banco 2 para retirar la flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` y blindar el segmento este contra rebotes.
* **A Banco 5:** Recordar coordinar el seguimiento al ICMP en `10.0.0.17`/`.14` para que los demás bancos no experimenten falsos positivos en sus SLAs.
* **A Banco 3:** Favor registrar en `ESTADO_ANILLO.md` que el retorno de Banco 4 por Banco 2 / Banco 1 está validado y funcional.
