# Banco 4 (Banco con doble ISP) — Documentación Técnica de Infraestructura y Coordinación

Documento técnico oficial de la arquitectura, conectividad, enrutamiento, seguridad y estado vivo de **Banco 4** en el anillo interbancario.

---

## 1. Estado General
* **Última actualización:** 2026-09-07 17:35 UTC-6
* **Agente/responsable:** Banco 4 (Agente de Integración)
* **Estado en el anillo:** Operativo en enlaces directos B4-B3 y B4-B5.

---

## 2. Interfaces de Tránsito Interbancario

Banco 4 se interconecta al anillo mediante dos enlaces físicos/lógicos dedicados gestionados por su router de borde Linux (`INTERNET`):

| Enlace | Subred | IP Local (B4) | IP Vecino | Interfaz B4 | Enlace Físico / Cloud Host |
|---|---|---|---|---|---|
| **B4 ↔ B3** | `10.0.0.8/30` | `10.0.0.10` | B3 = `10.0.0.9` | `eth3` | `CLOUD-B3` (`eno1`) |
| **B4 ↔ B5** | `10.0.0.12/30` | `10.0.0.13` | B5 = `10.0.0.14` | `eth4` | `CLOUD-B5` (`enxc0eac367f731`) |

---

## 3. Vecinos Directos

* **Banco 3 (`10.0.0.9`):** Conectividad directa por `eth3`. Estado L1/L2: **UP / UP**. RTT ~4-17 ms.
* **Banco 5 (`10.0.0.14`):** Conectividad directa por `eth4`. Estado L1/L2: **UP / UP**. RTT ~4-10 ms.

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
* `10.0.0.16/30`: `via 10.0.0.14 dev eth4 metric 10` (camino hacia B5 / B1 por la izquierda).
* `172.20.5.0/24`: `via 10.0.0.14 dev eth4 metric 10` (LAN de Banco 5).

### Rutas Flotantes de Respaldo (Métrica 20)
* Respaldo por Banco 5 (`eth4`):
  * `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20`
  * `10.0.0.4/30 via 10.0.0.14 dev eth4 metric 20`
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
| **Track B2** | `10.0.0.5` por `eth3` | Extremo a Extremo | **DOWN** | Al no responder B2 en `10.0.0.5`, se retiró `10.0.0.4/30` y `10.0.0.0/30` de `eth3`. |
| **Track B5** | `10.0.0.14` por `eth4` | Vecino Directo | **UP** | Enlace B4-B5 sano. |
| **Track B1** | `10.0.0.18` por `eth4` | Extremo a Extremo | **WAITING_INIT** | Sondeo activo. Mantiene ruta a `10.0.0.16/30` por B5 para no desestabilizar hasta recibir primer ping de B1. |

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
  * Banco 4 consume el servicio de depósitos de Banco 2 en `http://10.0.0.2:5001/interbanco/deposito` (probado exitosamente).

---

## 10. Pruebas Recientes de Conectividad

* Ping B4 a B3 (`10.0.0.9`): **100% OK** (RTT ~4-14 ms).
* Ping B4 a B3 interfaz B2 (`10.0.0.6`): **100% OK** (RTT ~10-44 ms forzando salida `eth3`).
* Ping B4 a B5 (`10.0.0.14`): **100% OK** (RTT ~4-10 ms).
* Ping B4 a B5 interfaz B1 (`10.0.0.17`): **100% OK** (RTT ~4-10 ms).
* Ping B4 a B2 (`10.0.0.5`, `10.0.0.2`): **0% (FAIL - Timeout)**. B2 no responde a pings provenientes de `10.0.0.10`.
* Ping B4 a B1 (`10.0.0.18`, `10.0.0.1`): **0% (FAIL - Timeout)**. B1 no responde a pings provenientes de `10.0.0.13` ni `10.0.0.10`.

---

## 11. Análisis del Bucle Reportado hacia `10.0.0.0/30`

Banco 3 reportó haber observado un bucle cerrado entre Banco 4 y Banco 5 hacia `10.0.0.0/30`:

### Diagnóstico Técnico del Bucle:
1. **Ruta primaria configurada:** `10.0.0.0/30 via 10.0.0.9 dev eth3 metric 10` (apunta a Banco 3).
2. **Next-hop primario:** `10.0.0.9` (Banco 3).
3. **Ruta de respaldo:** `10.0.0.0/30 via 10.0.0.14 dev eth4 metric 20` (apunta a Banco 5).
4. **Mecanismo que disparó el bucle:**
   * Banco 2 (`10.0.0.5`) dejó de contestar sondas ICMP.
   * El supervisor IP SLA de Banco 4 declaró `Track B2: DOWN` y retiró la ruta primaria por `eth3`.
   * El tráfico hacia `10.0.0.0/30` conmutó automáticamente a la ruta flotante por `eth4` hacia Banco 5 (`10.0.0.14`).
   * **Simultáneamente:** Banco 1 (`10.0.0.18`) estaba caído o inalcanzable desde Banco 5.
   * Banco 5, al tener caído su enlace primario a B1, conmutó su ruta de `10.0.0.0/30` a su ruta flotante de respaldo que **apunta hacia Banco 4 (`10.0.0.13`)**.
   * **Bucle resultante:** B4 reenvió a B5, y B5 reenvió a B4 (`10.0.0.10 -> 10.0.0.14 -> 10.0.0.13 -> 10.0.0.14...`), generando un bucle cerrado hasta agotar el TTL.
5. **Mitigación y Estado Actual:**
   * El bucle solo ocurre cuando se produce una **doble falla simultánea** (B1 caído en la izquierda Y B2 caído en la derecha), lo que fragmenta el anillo y hace que las rutas de respaldo de B4 y B5 colisionen.
   * Se requiere que Banco 2 restaure/confirme su ruta hacia `10.0.0.8/30 via 10.0.0.6` para que el Track B2 en B4 regrese a `UP`, manteniendo la ruta hacia `10.0.0.0/30` fijada hacia Banco 3.

---

## 12. Problemas Conocidos / Bloqueos Actuales

1. **Falta de ruta de retorno en Banco 2 hacia `10.0.0.8/30`:**
   * Capturas con `tcpdump` en `eth3` confirman que Banco 4 envía `ICMP echo request` hacia `10.0.0.5`, Banco 3 lo reenvía a Banco 2, pero Banco 2 no genera ningún `Echo Reply` hacia `10.0.0.10`.
2. **Inalcanzabilidad de Banco 1 (`10.0.0.18`):**
   * Banco 1 no contesta pings directos desde Banco 5 ni desde Banco 4.

---

## 13. Notas para Otros Bancos

* **A Banco 2:** Por favor verificar en su router:
  `ip route 10.0.0.8 255.255.255.252 10.0.0.6`
  Sin esta ruta, Banco 2 no puede responder a las solicitudes de Banco 4.
* **A Banco 5:** Confirmar cómo maneja su ruta flotante hacia `10.0.0.0/30` cuando B1 está caído para evitar rebotes hacia `10.0.0.13`.
