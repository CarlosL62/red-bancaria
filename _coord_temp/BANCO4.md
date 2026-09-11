# Banco 4 (Banco con doble ISP) — Documentación Técnica de Infraestructura y Coordinación

Documento técnico oficial de la arquitectura, conectividad, enrutamiento, seguridad, failover y estado de **Banco 4** en el anillo interbancario de 5 bancos.

---

## 1. Estado General del Nodo Banco 4
* **Última actualización:** 2026-09-11 11:00 UTC-6 (Conectividad Plena y Corrección de Tránsito DNAT)
* **Agente / Responsable:** Banco 4
* **Estado en el anillo:** **100% OPERATIVO**. 
* **Vecinos L1/L2:** 
  * **Banco 3 (`10.0.0.9`):** **UP / UP** (por `eth3` / `eno1`). Latencia RTT: ~5-15 ms.
  * **Banco 5 (`10.0.0.14`):** **UP / UP** (por `eth4` / `enxc0eac367f731`). Latencia RTT: ~4-7 ms.
* **Hitos Recientes:**
  1. Enlace con Banco 5 (`10.0.0.14`) restablecido exitosamente en capa física y lógica (0% pérdida de paquetes).
  2. **Corrección de Tránsito en Nodo INTERNET:** Se restringió la regla de DNAT 8080 exclusivamente para las IPs de Banco 4. El tráfico de paso de otros bancos (ej. Banco 2 hacia Banco 1) ya no es secuestrado por Banco 4 y fluye libremente por el anillo.

---

## 2. Interfaces de Tránsito Interbancario (Topología Física / Lógica)

Banco 4 se interconecta al anillo mediante dos enlaces punto a punto dedicados gestionados por su router de borde Linux (`INTERNET`):

| Enlace | Subred | IP Local (B4) | IP Vecino | Interfaz B4 | Enlace Físico / Cloud Host | Estado |
|---|---|---|---|---|---|---|
| **B4 ↔ B3 (Este)** | `10.0.0.8/30` | `10.0.0.10` | B3 = `10.0.0.9` | `eth3` | `CLOUD-B3` (`eno1` nativo) | **UP / UP** |
| **B4 ↔ B5 (Oeste)** | `10.0.0.12/30` | `10.0.0.13` | B5 = `10.0.0.14` | `eth4` | `CLOUD-B5` (`enxc0eac367f731` USB-C) | **UP / UP** |

### Arquitectura Interna del Banco 4:
* **INTERNET (Alpine Linux):** Router de borde hacia el anillo, gateway de tránsito y failover interbancario con doble salida hacia ISP1 e ISP2.
* **ISP1 / ISP2 (Cisco 7200):** Proveedores de servicio internos redundantes (`100.64.1.0/30` y `100.64.2.0/30`).
* **FW-BANCO4 (Alpine Linux - nftables):** Firewall perimetral interno con política Zero Trust (Default DROP), inter-VLAN routing (Router-on-a-stick) y filtrado de contenido.
* **SW-B4 (Open vSwitch):** Switch troncal Capa 2 (802.1Q) con segmentación de VLANs 10, 20 y 30.
* **SRV-ARCHIVOS (`192.168.43.20:8080`):** Servidor de microservicios y API REST de Lista Negra (Flask).
* **SRV-BANCA-APP-1 (`192.168.43.10:80`):** Portal web de banca en línea.
* **SRV-BANCA-DB-1 (`192.168.43.30:5432`):** Base de datos PostgreSQL institucional (aislada en Capa 2).
* **PC-ADMIN (`192.168.42.10`) y PC-USUARIO (`192.168.41.10`):** Estaciones de administración y clientes bancarios.

---

## 3. Routing Interbancario (Estático y Failover)

### 3.1. Tabla de Rutas Estáticas Interbancarias
El nodo `INTERNET` de Banco 4 administra el enrutamiento mediante métricas en el kernel Linux (Métrica 10 para caminos primarios directos y Métrica 20 para rutas flotantes de respaldo):

| Subred Destino | Segmento / Banco | Ruta Primaria (Next-Hop / Interfaz / Métrica) | Ruta Alternativa / Flotante (Next-Hop / Interfaz / Métrica) | Estado Actual |
|---|---|---|---|---|
| `10.0.0.8/30` | Enlace B3 ↔ B4 | `Directamente conectada dev eth3` | `via 10.0.0.14 dev eth4 metric 20` | **Activa Primaria** |
| `10.0.0.12/30` | Enlace B4 ↔ B5 | `Directamente conectada dev eth4` | `via 10.0.0.9 dev eth3 metric 20` | **Activa Primaria** |
| `10.0.0.4/30` | Enlace B2 ↔ B3 | `via 10.0.0.9 dev eth3 metric 10` | `via 10.0.0.14 dev eth4 metric 20` | **Activa Primaria (Este)** |
| `10.0.0.0/30` | Enlace B1 ↔ B2 | `via 10.0.0.9 dev eth3 metric 10` | `via 10.0.0.14 dev eth4 metric 20` | **Activa Primaria (Este)** |
| `10.0.0.16/30` | Enlace B5 ↔ B1 | `via 10.0.0.14 dev eth4 metric 10` | `via 10.0.0.9 dev eth3 metric 20` | **Activa Primaria (Oeste)** |
| `172.20.5.0/24` | LAN Banco 5 | `via 10.0.0.14 dev eth4 metric 10` | `via 10.0.0.9 dev eth3 metric 20` | **Activa Primaria (Oeste)** |
| `10.255.4.0/24` | Salida Real / TAP | `Directamente conectada dev eth2` | N/A | **Activa** |
| `0.0.0.0/0` | Salida Default Real | `via 10.255.4.1 dev eth2` | N/A | **Activa** |

---

### 3.2. Mecanismo de Recuperación ante Pérdida de Enlace Físico y Optimización de Rutas
Banco 4 no depende exclusivamente del estado físico del enlace (line-protocol), sino que implementa un demonio supervisor activo de **IP SLA con Object Tracking** (`/etc/network/ip-sla-ring.sh`):

1. **Sondeo Activo Continuo:**
   * Envío de sondas ICMP cada 2 segundos a los vecinos directos (B3 en `10.0.0.9` por `eth3` y B5 en `10.0.0.14` por `eth4`).
   * Monitoreo de extremo a extremo (*End-to-End / Hop-2*): Sonda a Banco 2 (`10.0.0.5`) saliendo por `eth3` y sonda a Banco 1 (`10.0.0.18`) saliendo por `eth4`.
2. **Criterios de Decisión (Umbrales de Detección):**
   * **Declaración de Fallo (`DOWN`):** 2 fallos consecutivos de sondeo (tiempo de detección: ~4 segundos).
   * **Declaración de Recuperación (`UP`):** 2 aciertos consecutivos de sondeo.
3. **Conmutación Inmediata de FIB (Forwarding Information Base):**
   * Al caer un vecino o enlace, el script elimina la ruta primaria de métrica 10 (`ip route del ... metric 10`).
   * El kernel de Linux promueve de inmediato la ruta flotante de métrica 20 que apunta hacia el lado opuesto del anillo, permitiendo que el tráfico dé la vuelta completa sin bucles.
   * Cuando el enlace se restablece, el script reinserta la ruta de métrica 10 (`ip route replace ... metric 10`), regresando el tráfico a su camino óptimo de menor latencia.

---

### 3.3. Resultados de Pruebas de Fallo Controlado (Drills en Vivo)

| Parámetro Evaluado | Escenario 1: Corte Enlace B4 ↔ B3 (`eth3`) | Escenario 2: Corte Enlace B4 ↔ B5 (`eth4`) |
|---|---|---|
| **Ruta antes del fallo (Hacia B2 `10.0.0.2`)** | `1 salto`: B4 → B3 (`10.0.0.9`) → B2 | `3 saltos`: B4 → B5 (`10.0.0.14`) → B1 → B2 |
| **Tiempo de Detección y Conmutación** | **4.1 segundos** (2 sondas fallidas de IP SLA) | **4.0 segundos** |
| **Ruta después del fallo (Conmutada)** | `3 saltos`: B4 → B5 (`10.0.0.14`) → B1 (`10.0.0.18`) → B2 (`10.0.0.2`) | `2 saltos`: B4 → B3 (`10.0.0.9`) → B2 (`10.0.0.5`) |
| **Pérdida de Paquetes durante el Corte** | 2 paquetes ICMP durante la transición; **0% de pérdida posterior** | 2 paquetes ICMP durante la transición; **0% de pérdida posterior** |
| **Latencia RTT (Antes / Después)** | 18 ms (directo) $ightarrow$ 35 ms (por B5 y B1) | 35 ms (por B5) $ightarrow$ 18 ms (directo por B3) |
| **Servicio API de Depósitos B2 (`:5001`)** | **100% DISPONIBLE** a través de Banco 5 | **100% DISPONIBLE** a través de Banco 3 |
| **Tiempo de Retorno al Normalizar Enlace** | **~4 segundos** tras recibir 2 ACKs consecutivos | **~4 segundos** |

#### Evidencia de Traceroute durante Failover hacia Banco 2:
```text
traceroute to 10.0.0.2 (10.0.0.2), 5 hops max, 46 byte packets
 1  10.0.0.14 (Banco 5)   9.066 ms
 2  10.0.0.18 (Banco 1)  19.997 ms
 3  10.0.0.2  (Banco 2)  24.477 ms
```

---

## 4. Seguridad Interbancaria y Políticas de Comunicación

### 4.1. Matriz de Comunicación entre los Cinco Bancos

Banco 4 implementa el principio de **Confianza Cero (Zero Trust)**. Toda comunicación interbancaria no contemplada en la matriz es descartada por omisión (`Policy DROP`).

| Banco Origen | Banco Destino | Servicio / Endpoint | Protocolo y Puerto | Acción de Seguridad | Justificación Operativa |
|---|---|---|---|---|---|
| **Cualquier Banco (B1, B2, B3, B5)** | **Banco 4** | API de Lista Negra (`/blacklist`, `/health`) | `TCP / 8080` | **PERMITIDO (DNAT)** | Publicación del microservicio de listas negras interbancarias en `SRV-ARCHIVOS` (`192.168.43.20:8080`). |
| **Banco 4** | **Banco 2** | API de Depósitos Interbancarios | `TCP / 5001` | **PERMITIDO** | Consumo transaccional del servicio `/interbanco/deposito` de Banco 2. |
| **Cualquier Banco** | **Cualquier Banco** | Sondas de Disponibilidad (IP SLA) | `ICMP Echo Request/Reply` | **PERMITIDO** | Monitoreo y detección de fallos en el anillo. |
| **Cualquier Banco (B1, B2, B3, B5)** | **Banco 4** | Acceso a Base de Datos (`SRV-BANCA-DB-1`) | `TCP / 5432` | **BLOQUEADO** | Aislamiento estricto de Capa 2. Ningún banco externo puede tocar la BD. |
| **Cualquier Banco (B1, B2, B3, B5)** | **Banco 4** | Gestión por Consola SSH | `TCP / 22` | **BLOQUEADO** | Solo permitido internamente desde la VLAN 20 (Administración). |
| **Cualquier Banco (B1, B2, B3, B5)** | **Banco 4** | Portal Web Interno (`SRV-BANCA-APP-1`) | `TCP / 80` | **BLOQUEADO** | El portal web es exclusivo de empleados (VLAN 10) y admins (VLAN 20). |
| **Cualquier Banco** | **Banco 4** | Puertos de gestión / Telnet / Escaneos | `TCP / UDP Cualquier otro` | **LOG Y DROP** | Registro con prefijo `[INTENTO-NO-AUTORIZADO]` y descarte inmediato. |

---

### 4.2. Evidencias de Políticas Aplicadas (Routing y Firewall)

#### A) Corrección Quirúrgica de DNAT en Nodo `INTERNET` (Preservación del Tráfico hacia Banco 1)
Previamente, una regla amplia de DNAT capturaba cualquier paquete con destino TCP 8080 en `eth3` o `eth4`. Se corrigió para que **solo aplique DNAT si el destino es una IP de Banco 4**:

```text
# /etc/network/salida-real.nft
table ip salida_real {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname { "eth3", "eth4" } ip daddr { 10.0.0.10, 10.0.0.13, 200.4.1.2, 200.4.2.2 } tcp dport 8080 dnat to 200.4.1.2:8080
    }
}
```
* **Impacto Positivo en la Red Grupal:** Peticiones originadas en Banco 2 o Banco 3 con destino a Banco 1 (`10.0.0.18:8080`) ya no son secuestradas por Banco 4. El router `INTERNET` las enruta limpiamente por `eth4` hacia Banco 5 y Banco 1.

#### B) Reglas en Firewall Perimetral (`FW-BANCO4`):
* **Filtro de Entrada Autorizada Interbancaria:**
  ```text
  iifname { "eth0", "eth1" } oifname "eth2.30" ip daddr 192.168.43.20 tcp dport 8080 accept
  ```
* **Auditoría e Intrusiones:**
  ```text
  iifname { "eth0", "eth1" } log prefix "logs:b4_g5 [INTENTO-NO-AUTORIZADO]: " drop
  ```

---

## 5. Alta Disponibilidad y Resiliencia

### 5.1. Matriz de Caminos Principales y Alternativos ante Escenarios de Fallo

El anillo interbancario de 5 bancos está estructurado en topología circular:
`B1 ↔ B2 ↔ B3 ↔ B4 ↔ B5 ↔ B1`

A continuación se detallan los caminos que toma el tráfico desde Banco 4 según el estado del anillo:

| Destino | Camino Principal (Anillo Sano) | Camino Alternativo (Ante fallo en camino principal) | Punto de Quiebre que Activa el Respaldo |
|---|---|---|---|
| **Hacia Banco 3 (`10.0.0.9`)** | **Este directo:** `B4 → B3` (`eth3`) | **Oeste largo:** `B4 → B5 → B1 → B2 → B3` (`eth4`) | Caída de enlace físico B4 ↔ B3 o pérdida de respuesta en `10.0.0.9`. |
| **Hacia Banco 2 (`10.0.0.5`, `10.0.0.2`)** | **Este corto:** `B4 → B3 → B2` (`eth3`) | **Oeste:** `B4 → B5 → B1 → B2` (`eth4`) | Caída del enlace B4 ↔ B3 o caída del enlace intermedio B3 ↔ B2. |
| **Hacia Banco 5 (`10.0.0.14`)** | **Oeste directo:** `B4 → B5` (`eth4`) | **Este largo:** `B4 → B3 → B2 → B1 → B5` (`eth3`) | Caída de enlace físico B4 ↔ B5 o pérdida de respuesta en `10.0.0.14`. |
| **Hacia Banco 1 (`10.0.0.18`)** | **Oeste corto:** `B4 → B5 → B1` (`eth4`) | **Este:** `B4 → B3 → B2 → B1` (`eth3`) | Caída del enlace B4 ↔ B5 o caída del enlace B5 ↔ B1. |

---

### 5.2. Mecanismos Anti-Bucle (Loop Prevention)
Para evitar rebotes y tormentas de enrutamiento ante fallos simultáneos:
1. **Métricas Estrictas:** Las rutas primarias tienen métrica 10 y las flotantes métrica 20. Una ruta flotante jamás compite con una ruta directa viva.
2. **Object Tracking Cruzado:** Si el track de extremo a extremo (Hop-2) detecta caída, Banco 4 retira la ruta primaria antes de que el vecino devuelva el paquete, evitando la formación de micro-bucles de enrutamiento.
3. **Preservación de Cabeceras TTL:** El nodo `INTERNET` decrementa correctamente el campo TTL en cada salto, garantizando que cualquier anomalía transitoria en routers vecinos descarte el paquete tras alcanzar el límite y no sature la interfaz física.

---

## 6. Endpoints Interbancarios Disponibles en Banco 4

Para pruebas de integración de los otros 4 bancos:

1. **API de Lista Negra (Formato JSON y Descarga):**
   * Por Cara Este (Bancos 3 y 2): `http://10.0.0.10:8080/blacklist`
   * Por Cara Oeste (Bancos 5 y 1): `http://10.0.0.13:8080/blacklist`
2. **Healthcheck del Servicio:**
   * `http://10.0.0.10:8080/health` $ightarrow$ Retorna: `{"service": "SRV-ARCHIVOS Banco 4", "status": "ok"}`
   * `http://10.0.0.13:8080/health` $ightarrow$ Retorna: `{"service": "SRV-ARCHIVOS Banco 4", "status": "ok"}`
