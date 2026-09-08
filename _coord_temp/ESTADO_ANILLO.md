# Estado Global del Anillo Interbancario (Consolidación Oficial)

Consolidación técnica oficial del estado del anillo de interconexión entre las 5 instituciones bancarias. Mantenido por Banco 3 en calidad de coordinador de integración.

- **Fecha de Consolidación:** 2026-09-08 00:00 UTC-6 (Fase 1: Validación de Anillo Sano en Estado Normal)
- **Estado General:** Anillo físico 100% UP. Tránsito L3 100% convergente y estable. Los 5 bancos (B1, B2, B3, B4, B5) cuentan con mecanismos de supervisión End-to-End Hop-2 activos. La auditoría de línea base desde Banco 3 confirma conectividad total a todas las IPs de tránsito del anillo (8/8 destinos exitosos con 0% de pérdidas) y rutas primarias puras en todas las tablas de enrutamiento (sin flotantes activas). Todos los bucles están extinguidos. El anillo se encuentra en estado óptimo de línea base.

---

## 1. Topología Física y Direccionamiento

```text
[BANCO 1] <--- 10.0.0.0/30 ---> [BANCO 2] <--- 10.0.0.4/30 ---> [BANCO 3]
    ^                                                                 |
    |                                                            10.0.0.8/30
10.0.0.16/30                                                          |
    |                                                                 v
[BANCO 5] <------------------ 10.0.0.12/30 ------------------> [BANCO 4]
```

### Tabla Oficial de Enlaces de Tránsito Directos
| Segmento | Subred | IP Nodo A | IP Nodo B | Estado L1/L2 | Conectividad ICMP | Estado Operativo |
|---|---|---|---|---|---|---|
| **B1 - B2** | `10.0.0.0/30` | B1: `10.0.0.1` (Gi0/1) | B2: `10.0.0.2` (Fa2/0) | **UP / UP** | 100% OK (~5-15 ms) | **OPERATIVO** |
| **B2 - B3** | `10.0.0.4/30` | B2: `10.0.0.5` (Fa3/0) | B3: `10.0.0.6` (Fa1/0) | **UP / UP** | 100% OK (~4-16 ms) | **OPERATIVO** |
| **B3 - B4** | `10.0.0.8/30` | B3: `10.0.0.9` (Fa2/0) | B4: `10.0.0.10` (eth3) | **UP / UP** | 100% OK (~4-18 ms) | **OPERATIVO** |
| **B4 - B5** | `10.0.0.12/30` | B4: `10.0.0.13` (eth4) | B5: `10.0.0.14` (Eth1/0) | **UP / UP** | 100% OK (~4-16 ms) | **OPERATIVO** |
| **B5 - B1** | `10.0.0.16/30` | B5: `10.0.0.17` (Eth1/1) | B1: `10.0.0.18` (Gi0/2) | **UP / UP** | 100% OK (~8-12 ms) | **OPERATIVO** (Recreado) |

---

## 2. Estado de Conectividad por Red /30 del Anillo

| Red /30 | Segmento | Estado Global | Diagnóstico y Comportamiento de Enrutamiento |
|---|---|---|---|
| **`10.0.0.0/30`** | B1 - B2 | **ALCANZABLE** | Alcanzable desde los 5 bancos. B3 llega por B2 (Track 1 UP). B4 llega por B3 (Track B2 UP, primaria activa por `eth3`). B5 llega por B1 (Track 3 UP). |
| **`10.0.0.4/30`** | B2 - B3 | **ALCANZABLE (LOOP RESUELTO)** | Bucle B4-B5 **100% extinguido**. B4 recuperó su Track B2 a UP y restauró su primaria `via 10.0.0.9 dev eth3 metric 10` (flotante a B5 en standby). B5 confirmó traza limpia de 2 saltos a `10.0.0.6` (`10.0.0.13 -> 10.0.0.9`) y ping 100% a `10.0.0.5` y `10.0.0.6`. |
| **`10.0.0.8/30`** | B3 - B4 | **ALCANZABLE (RESTAURADO)** | B2 añadió ruta fija `10.0.0.8/30 via 10.0.0.6` (Paso 1). B1 y B2 ya transitan hacia B4 por el oeste (Track 4/7 UP en B2). B3 y B5 comunican 100%. |
| **`10.0.0.12/30`** | B4 - B5 | **ALCANZABLE** | Totalmente alcanzable desde los 5 bancos en ambos sentidos del anillo. |
| **`10.0.0.16/30`** | B5 - B1 | **ALCANZABLE** | Enlace físico y tránsito operativo. Al restaurar B2 el retorno a `10.0.0.8/30`, las respuestas de B1 a las sondas de B3 se reciben con éxito. Track 2 de B3 se mantiene UP y su ruta primaria está activa en la RIB. |

---

## 3. Matriz de Conectividad Interbancaria (Ping L3 entre Nodos de Borde)

| Origen \ Destino | B1 (`10.0.0.1` / `.18`) | B2 (`10.0.0.2` / `.5`) | B3 (`10.0.0.6` / `.9`) | B4 (`10.0.0.10` / `.13`) | B5 (`10.0.0.14` / `.17`) |
|---|---|---|---|---|---|
| **Banco 1** | — | **OK** (`.2`, 5 ms) | **OK** (`.6`, 87 ms vía B2) | **OK** (`.10` vía B2-B3; `.13`, 17 ms) | **OK** (`.17`, 10 ms) |
| **Banco 2** | **OK** (`.1`, 15 ms) | — | **OK** (`.6`, 4 ms) | **OK** (`.10` vía B3, Track 4 UP) | **OK** (`.17`, 20 ms vía B1) |
| **Banco 3** | **OK** (`.1`, 36 ms vía B2; `.18`, 24 ms) | **OK** (`.5`, 4 ms) | — | **OK** (`.10`, 8 ms) | **OK** (`.14` y `.17` vía B4) |
| **Banco 4** | **OK** (`.1` y `.18` vía B5, 20 ms) | **OK** (`.5`, 55 ms vía B3; `.2`, 30 ms) | **OK** (`.9` y `.6`, 34 ms vía eth3) | — | **OK** (`.14` y `.17`, 6 ms) |
| **Banco 5** | **OK** (`.18`, 8 ms; `.2`, 28 ms vía B1) | **OK** (`.2` vía B1; `.5`, 28-60 ms vía B4) | **OK** (`.6`, 12-40 ms; `.9`, 20-32 ms vía B4) | **OK** (`.13`, 4 ms) | — |

---

## 4. Comparativa de Routing, IP SLA y Tracks por Banco

| Banco | Router / SO | Primarias / Flotantes | IP SLA / Sondas | Tracks Activos | Estado de Tracks |
|---|---|---|---|---|---|
| **Banco 1** | Cisco IOSv | Primarias AD 1 / Flotantes AD 20 (trackeadas) | SLAs 2 y 5 al Hop 2 (ICMP echo cada 5s) + host routes /32 | Tracks 10 y 20 (`delay down 10 up 5`) | **Tracks 10 y 20 UP (100% OPERATIVO)** |
| **Banco 2** | Cisco 3745 | Primarias AD 1 / Flotantes AD 100 | SLAs 10 y 20 al Hop 2 (ICMP echo cada 3s) + host routes /32 | Tracks 10 y 20 (`delay down 6 up 3`) | **Tracks 10 y 20 UP (100% OPERATIVO)** |
| **Banco 3** | Cisco 3745 | Primarias AD 1 / Flotantes AD 10 con Track + Null0 /27 (AD 250) + Local PBR | SLAs 1 y 3 al Hop 2 (ICMP echo cada 5s por Fa1/0 y Fa2/0) | Tracks 1 y 3 (`delay down 6 up 3`) | **Tracks 1 y 3 UP (100% OPERATIVO, 0 aleteo)** |
| **Banco 4** | Linux (Alpine) | Primarias Métrica 10 / Flotantes Métrica 20 (sin NAT tránsito) | Script `ip-sla-ring.sh` (sondas cada 2s) | Tracks B3, B2, B5, B1 | **Tracks B3, B2, B5, B1 UP (100% OPERATIVO)** |
| **Banco 5** | Cisco IOSv | Primarias AD 1 / Flotantes AD 200 + Local PBR (`RM-LOCAL-SLA`) | SLAs 10 y 20 al Hop 2 (ICMP echo cada 5s forzadas por PBR) | Tracks 10 y 20 | **Tracks 10 y 20 UP (100% OPERATIVO)** |

---

## 5. Diagnóstico de Bucles (Loops) y Rebotes

### 5.1. Bucle en `10.0.0.4/30` (Banco 4 <-> Banco 5) — RESUELTO / EXTINGUIDO
- **Estado Previo:** Traza `10.0.0.13 -> 10.0.0.14 -> 10.0.0.13 -> 10.0.0.14 ...` (TTL agotado por rebote mutuo entre B4 y B5).
- **Causa Raíz Resuelta:** Banco 2 añadió la ruta fija `10.0.0.8/30 via 10.0.0.6` (Paso 1), permitiendo responder a las sondas de Banco 4.
- **Confirmación Oficial con Evidencia Directa:**
  - **Banco 4:** Track B2 pasó a **UP**. Ping a `10.0.0.5` 100% OK (55.6 ms), ping a `10.0.0.6` 100% OK (34.4 ms). Restauró primaria `10.0.0.4/30 via 10.0.0.9 dev eth3 metric 10`. Flotante por B5 quedó en standby y ya no se reenvía a B5.
  - **Banco 5:** Alcanza `10.0.0.5` (100% OK, 28-60 ms) y `10.0.0.6` (100% OK, 12-40 ms). Traceroute a `10.0.0.6` completado en 2 saltos limpios (`10.0.0.13 -> 10.0.0.9`) sin rebote.
- **Resultado:** Bucle 100% extinguido. Anillo en convergencia completa y estable.

### 5.2. Bucle Potencial: `10.0.0.0/30` (Banco 4 <-> Banco 5 ante Doble Contingencia)
- **Mecanismo:** Si B1 cae del lado este (B5) y B2 cae del lado oeste (B4), ambos bancos activarían en simultáneo sus flotantes cruzadas para `10.0.0.0/30` (`via 10.0.0.13` y `via 10.0.0.14`).
- **Estado actual:** **INACTIVO**, porque B1 está activo en `10.0.0.18` y B5 entrega hacia B1.

### 5.3. Rebote `10.0.0.16/30` (Banco 2 <-> Banco 3): **RESUELTO**
- Banco 2 condicionó su flotante de retorno hacia B3 a su `Track 8` (actualmente DOWN) y agregó descarte en `Null0 10.0.0.0/27`. Banco 2 ya no devuelve el paquete hacia Banco 3.

### 5.4. Eliminación Definitiva de Rebote `10.0.0.12/30` (Banco 3 <-> Banco 2 durante Corte B4-B5) — RESUELTO
- **Diagnóstico y Corrección Aplicada en Banco 3:**
  1. **Retiro de Flotante Artificial:** Se eliminó la ruta flotante `10.0.0.12/30 via 10.0.0.5 10 track 4`. Durante un corte de `10.0.0.12/30`, el segmento no existe; cualquier intento de desviarlo hacia B2 generaba rebote porque B2 enruta `10.0.0.12/30` hacia el sur.
  2. **Eliminación de Sondas con Aleteo / Sin Uso:** Se eliminó SLA 2 / Track 2 (Hop-3 hacia `10.0.0.18`), cuyo flapping continuo (>900 transiciones) derivaba del retorno asimétrico de B4. Se eliminó SLA 4 / Track 4 al suprimirse la flotante de `10.0.0.12/30`.
  3. **Consolidación de Tracks Hop-2:** Track 3 (`10.0.0.14` vía B4) gobierna ambas primarias del este (`10.0.0.12/30` y `10.0.0.16/30`). Track 1 (`10.0.0.1` vía B2) gobierna la primaria del oeste (`10.0.0.0/30`) y la flotante de respaldo (`10.0.0.16/30 via 10.0.0.5 10 track 1`).
  4. **Descarte Local:** `10.0.0.0/27 Null0 250`.
- **Evidencia del Simulacro de Corte Real en B3:**
  - Track 3 cae limpiamente a DOWN (`delay down 6`). **0 flaps**.
  - `10.0.0.12/30` cae directamente en `Null0 10.0.0.0/27`. **CERO rebotes hacia B2**.
  - `10.0.0.16/30` conmuta limpiamente a `10.0.0.5` (Track 1 UP).
  - Ping a `10.0.0.17` (Banco 5): **100% OK** (3/3 recibidos). Traceroute en 3 saltos limpios (`10.0.0.5 -> 10.0.0.1 -> 10.0.0.17`).
  - Al restaurar: Track 3 sube a UP (`delay up 3`) y primarias se reinstalan instantáneamente.

---

## 6. Estado de Servicios Interbancarios Publicados

| Banco | IP / Puerto Publicado | Endpoint / Recurso | Estado | Observaciones |
|---|---|---|---|---|
| **Banco 1** | `10.0.0.1:80` | `GET /` | **OPERATIVO** | Portal web interno responde `HTTP/1.0 200 OK`. |
| **Banco 1** | `10.0.0.1:80` | `POST /interbancaria` | **OPERATIVO** | Verificado desde B3: responde `HTTP/1.0 400 Bad Request` (`JSON_INVALIDO`) ante payload de prueba sin transacciones reales. `10.0.0.18:80` inactivo (NAT no persistió en IOSv). |
| **Banco 2** | `10.0.0.2:5001` | API Depósitos / Transferencias | **PARCIAL** | Abierto hacia Banco 1 y Banco 4 (vía B1). Inaccesible desde B3 (falta NAT en Fa3/0). |
| **Banco 3** | `10.0.0.6:80` / `10.0.0.9:80` | `POST /interbancaria` | **100% OPERATIVO** | Puertos 8080 y 8081 verificados en WEB01. FW1 acepta origen `10.0.0.14` en 8081 (este) y origen `10.0.0.17` en 8080 (oeste). |
| **Banco 4** | `10.0.0.10:8080` / `10.0.0.13:8080` | `GET /blacklist`, `/health` | **100% OPERATIVO** | Consumido exitosamente por Banco 5 en `10.0.0.13:8080`. |
| **Banco 5** | N/A | Transaccional saliente | **CONSUMIDOR OK** | Actúa como cliente de B3 y B4; durante corte B4-B5 debe usar `10.0.0.6:80` con origen `10.0.0.17`. |

---

## 7. Estado de Migración a Supervisión End-to-End (Hop-2)

Todos los bancos han consolidado sus mecanismos de supervisión de extremo a extremo:
* **Banco 1 (Cisco IOSv):** Configuración v8.4 con SLAs 2 y 5 (Hop-2) + Tracks 10 y 20 (`delay down 10 up 5`) y Local PBR (`RM-LOCAL-SLA`). Estado: **UP**.
* **Banco 2 (Cisco 3745):** Reconstrucción completa E2E con SLAs 10 y 20 + Tracks 10 y 20 (`delay down 6 up 3`), Local PBR para sondas y `Null0 /27`. Estado: **UP**.
* **Banco 3 (Cisco 3745):** Arquitectura limpia Hop-2 con SLAs 1 y 3 (ICMP a `10.0.0.1` y `10.0.0.14`), Local PBR (`RM-LOCAL-SLA` seq 15 y 20), Tracks 1 y 3 (`delay down 6 up 3`), sin rutas flotantes hacia enlaces cortados y descarte `Null0 10.0.0.0/27 AD 250`. Flapping erradicado. Estado: **UP**.
* **Banco 4 (Linux Alpine):** Demonio supervisor nativo con socket bind (`ping -I ethX`) gobernando Tracks B3, B2, B5, B1. Estado: **UP**.
* **Banco 5 (Cisco IOSv):** Esquema E2E con Local PBR (`RM-LOCAL-SLA` seq 10 y 20) gobernando Tracks 10 y 20. Estado: **UP**.

---

## 8. Fases de Validación del Anillo Interbancario

### Fase 1: Validación del Anillo en Estado Normal (Línea Base Sano) — COMPLETADA
* **Conectividad L3:** 100% de alcanzabilidad en los 5 enlaces /30 y hacia todas las IPs de tránsito interbancario (8/8 destinos auditados desde B3 con 0% de pérdidas y RTT promedio < 35 ms).
* **Tablas de Enrutamiento:** Todas las rutas primarias instaladas en la FIB. Ninguna ruta flotante activa en estado de reposo.
* **Bucles:** Cero bucles activos. Traza limpia de 2 saltos hacia el arco oeste (B3 -> B2 -> B1) y 2 saltos hacia el arco este (B3 -> B4 -> B5).
* **Supervisión:** Todos los tracks convergidos en UP y estables sin aleteos.

### Fase 2: Pruebas de Failover Controladas (Drills) — EN EJECUCIÓN / VALIDADO
1. **Simulacro de Corte B4-B5 (`10.0.0.12/30`):**
   - **Resultado:** Detección automática por Tracks 2 y 3 (`DOWN`). Retiro automático de primarias.
   - **Conmutación limpia:** Tráfico hacia Banco 5 (`10.0.0.17`) y Banco 1 (`10.0.0.1`) conmuta automáticamente a la ruta de respaldo vía Banco 2 (`10.0.0.5 AD 10 track 1`) con 100% de éxito (3 saltos: `.5 -> .1 -> .17`).
   - **Extinción de rebote:** Tráfico hacia el enlace cortado (`10.0.0.12/30`) se descarta en `Null0` local sin rebotar hacia Banco 2 ni formar bucles.
   - **Restauración:** Retorno automático e instantáneo a rutas primarias al normalizar el enlace. Sincronización y persistencia completadas.
