# Estado Global del Anillo Interbancario

Consolidación técnica oficial del estado del anillo de interconexión entre las 5 instituciones bancarias. Mantenido por Banco 3 en calidad de coordinador de integración.

---

## Topología
Topología física y lógica en anillo cerrado:
`[BANCO 1] <---> [BANCO 2] <---> [BANCO 3] <---> [BANCO 4] <---> [BANCO 5] <---> [BANCO 1]`

---

## Direccionamiento (Tabla Oficial de Enlaces de Tránsito)

| Segmento | Subred | IP Nodo A | IP Nodo B | Propósito |
|---|---|---|---|---|
| **B1 - B2** | `10.0.0.0/30` | B1 = `10.0.0.1` | B2 = `10.0.0.2` | Enlace interbancario B1-B2 |
| **B2 - B3** | `10.0.0.4/30` | B2 = `10.0.0.5` | B3 = `10.0.0.6` | Enlace interbancario B2-B3 |
| **B3 - B4** | `10.0.0.8/30` | B3 = `10.0.0.9` | B4 = `10.0.0.10` | Enlace interbancario B3-B4 |
| **B4 - B5** | `10.0.0.12/30` | B4 = `10.0.0.13` | B5 = `10.0.0.14` | Enlace interbancario B4-B5 |
| **B5 - B1** | `10.0.0.16/30` | B5 = `10.0.0.17` | B1 = `10.0.0.18` | Enlace interbancario B5-B1 |

---

## Estado de Enlaces

| Enlace | Segmento | Estado L1/L2 | Conectividad ICMP | Observaciones |
|---|---|---|---|---|
| B1 - B2 | `10.0.0.0/30` | PENDIENTE DE CONFIRMACIÓN POR BANCO 1 Y 2 | Fallando (`10.0.0.1` timeout) | B2 responde en `10.0.0.5`, pero no se llega a B1 |
| B2 - B3 | `10.0.0.4/30` | UP / UP | 100% operativo | `10.0.0.5` <-> `10.0.0.6` RTT ~4-16 ms |
| B3 - B4 | `10.0.0.8/30` | UP / UP | 100% operativo | `10.0.0.9` <-> `10.0.0.10` RTT ~4-14 ms |
| B4 - B5 | `10.0.0.12/30` | UP / UP | 100% operativo | `10.0.0.13` <-> `10.0.0.14` RTT ~8-18 ms |
| B5 - B1 | `10.0.0.16/30` | PENDIENTE DE CONFIRMACIÓN POR BANCO 5 Y 1 | Fallando (`10.0.0.17/18` timeout) | B5 responde en 10.0.0.14, enlace a B1 no responde |

---

## Routing

* **Banco 3:** Enrutamiento estático de anillo completo con primarias AD 1 y flotantes AD 10 implementadas, auditadas y con Local PBR para IP SLA.
* **Banco 2:** Enrutamiento estático en Cisco 3745. Primarias AD 1. Flotantes de respaldo con AD 100 condicionadas a tracks (Tracks 7 y 8) para evitar rebotar tráfico cuando el destino está inalcanzable.
* **Banco 4:** Enrutamiento estático en router Linux (`INTERNET`). Rutas primarias con métrica 10 y rutas flotantes de respaldo con métrica 20. Tránsito puro sin NAT entre interfaces del anillo.
* **Banco 1:** PENDIENTE DE CONFIRMACIÓN POR BANCO 1.
* **Banco 5:** PENDIENTE DE CONFIRMACIÓN POR BANCO 5.

---

## IP SLA / Tracks

* **Banco 3:**
  * SLA 1 (`10.0.0.1` vía Fa1/0 con Local PBR a `10.0.0.5`): **UP** (B1 alcanzable en 10.0.0.1 vía B2 con RTT ~76ms; ruta primaria 10.0.0.0/30 activa en RIB).
  * SLA 2 (`10.0.0.18` vía Fa2/0 con Local PBR a `10.0.0.10`): **DOWN** (Timeout hacia 10.0.0.18; ruta flotante 10.0.0.16/30 vía B2 instalada en RIB).
* **Banco 2:**
  * SLAs 1-6 activos. Track 1 (B1 directo) = UP (inestable/flapeando). Track 2 (B3 directo) = UP. Tracks 3, 4, 5, 6, 7, 8 = DOWN. Flotantes hacia B3 no se instalan al estar Track 8 en DOWN.
* **Banco 4:**
  * Demonio `/etc/network/ip-sla-ring.sh` (sondas cada 2s). Track B3 = UP. Track B5 = UP. Track B2 = DOWN. Track B1 = WAITING_INIT.
* **Banco 1, 5:** PENDIENTE DE CONFIRMACIÓN POR CADA BANCO.

---

## Problemas Activos

1. **Inalcanzabilidad de Banco 1:** Ni `10.0.0.1` (lado B2) ni `10.0.0.18` (lado B5) responden a pings interbancarios.
2. **Corte o falla de enrutamiento en B5-B1:** `10.0.0.17` y `10.0.0.18` no responden desde B3.

---

## Loops Detectados

1. **Bucle entre Banco 4 y Banco 5 hacia `10.0.0.0/30` (`10.0.0.1` y `10.0.0.2`):**
   * *Traza observada:* `10.0.0.10 -> 10.0.0.14 -> 10.0.0.10 -> 10.0.0.14 ...`
   * *Causa:* B4 reenvía hacia B5. B5, al no tener salida hacia B1, conmuta a una ruta flotante que devuelve el tráfico hacia B4 (`10.0.0.13`), generando bucle cerrado hasta expirar TTL.
2. **Rebote directo entre Banco 2 y Banco 3 hacia `10.0.0.16/30` (`10.0.0.17` y `10.0.0.18`):**
   * *Traza observada originalmente:* `10.0.0.5 -> 10.0.0.6 -> *`
   * *Estado actual:* **MITIGADO POR BANCO 2**. Banco 2 condicionó su ruta flotante a Track 8. Al estar Track 8 en DOWN, la flotante no se instala en su tabla y Banco 2 descarta el tráfico en vez de devolverlo a B3.

---

## Pruebas Recientes

* Pings directos B3-B2 (`10.0.0.5`): **100%** (2/2, 4 ms).
* Pings directos B3-B4 (`10.0.0.10`): **100%** (2/2, 4 ms).
* Pings B3 a B4-B5 (`10.0.0.13`, `10.0.0.14`): **100%** (2/2, 8-16 ms).
* Pings a B1 (`10.0.0.1`, `10.0.0.18`): **0%** (Timeout).
* Pings a B5-B1 (`10.0.0.17`): **0%** (Timeout).

---

## Coordinación Pendiente

* **Banco 1:** Confirmar estado de interfaces `10.0.0.1` y `10.0.0.18`, y estado de su servicio HTTP `/interbancaria`.
* **Banco 2:** Confirmar configuración de rutas para `10.0.0.8/30`, `10.0.0.12/30` y `10.0.0.16/30` para evitar rebotes hacia B3.
* **Banco 4:** Confirmar ruta de retorno hacia `10.0.0.4/30` (`via 10.0.0.9`) para permitir respuestas a B2.
* **Banco 5:** Confirmar rutas hacia `10.0.0.0/30` y verificar por qué se devuelve el tráfico hacia B4 en caso de fallo hacia B1.

---

## Historial Breve
* **2026-09-07:** Implementación de Local PBR en Banco 3 para aislar sondas SLA 1 y SLA 2 sin romper failover ni generar flapping. Auditoría completa de Banco 3 realizada. Confirmada recuperación de alcanzabilidad de B1 por el enlace B2 (Track 1 UP). Consolidación de estados confirmados por Banco 2 y Banco 4: mitigación de rebote en B2 y diagnóstico del bucle B4-B5 ante doble fallo simultáneo.

---

## Última Actualización
* **Fecha:** 2026-09-07 17:40 UTC-6
* **Responsable:** Agente Banco 3 (Coordinador de Integración)
