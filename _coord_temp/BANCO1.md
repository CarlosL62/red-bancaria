# Banco 1 (Banca minorista con sucursales)

## Estado
Última actualización: 2026-09-08 (post-rearranque limpio del nodo con config v8.1 y re-verificación del anillo)
Agente/responsable: Agente Banco 1

## Verificación global del anillo
Re-verificación completa (2026-09-08 ~00:25-00:35 UTC-6, post-rearranque limpio del nodo con config durable v8.1) ejecutada desde el nodo B1.

### Estado del nodo (post-rearranque limpio con config-disk v8.1)
* Rearranque real del nodo B1 (GNS3 stop→start) el 2026-09-08 para validar persistencia: `%CVAC-7-CONFIG_FOUND` + `%CVAC-4-CONFIG_DONE` desde `ios_config.txt` (v8.1), **sin errores de parser**.
* Interfaces tras boot limpio: Gi0/0 `192.168.122.237/24` (DHCP), Gi0/1 `10.0.0.1/30`, Gi0/2 `10.0.0.18/30`, Gi0/3 `10.10.2.1/30` — **todas UP/UP**.
* Tracks: **Track 1 (Gi0/1) UP**, **Track 2 (Gi0/2) UP**.
* Rutas estáticas instaladas (running-config y RIB): 7 del anillo sin wrap `.16` ni residual + default + `172.16.0.0/16` — exactamente la config v8.1.

### Vecinos directos (2026-09-08, post-restart)
* **Banco 2 (`10.0.0.2`):** ping **100%** (RTT 8-31 ms). ARP `ca01.d8af.0038`. Link Gi0/1 UP.
* **Banco 5 (`10.0.0.17`):** ping **0%** (0/2). Link Gi0/2 UP/UP y track 2 UP, pero B5 **no responde ICMP** en `10.0.0.17`. PENDIENTE DE CONFIRMACIÓN POR BANCO 5 (B5.md reportaba operativo a las 17:43 UTC-6; su nodo dejó de responder después).

### Redes /30 del anillo (destino probado → alcanzable, 2026-09-08)
| Red | Destino probado | Alcanzable | Ruta activa (RIB) | Next-hop | Traza |
|---|---|---|---|---|---|
| `10.0.0.0/30` (B1-B2) | `10.0.0.2` | **SÍ** (100%) | Conectada | Gi0/1 (directo) | 1 hop |
| `10.0.0.4/30` (B2-B3) | `10.0.0.5` / `10.0.0.6` | **SÍ** (100% c/u; .6 ~47-68 ms) | Estática AD 1 | `10.0.0.2` | `10.0.0.2 → 10.0.0.6` |
| `10.0.0.8/30` (B3-B4) | `10.0.0.9` / `10.0.0.10` | **SÍ** (100%; .10 traza completa) | Estática AD 1 (track 1) | `10.0.0.2` | `10.0.0.2 → 10.0.0.6 → 10.0.0.10` |
| `10.0.0.12/30` (B4-B5) | `10.0.0.13` (B4) / `10.0.0.14` (B5) | **NO** (0%) | Estática AD 1 (track 2) | `10.0.0.17` | — B5 no responde en el arco este |
| `10.0.0.16/30` (B5-B1) | `10.0.0.17` | **NO** (0%) | Conectada | Gi0/2 (directo) | 1 salto sin respuesta |

Cambio importante vs 2026-09-07: **el segmento `10.0.0.8/30` (B3-B4) ya es alcanzable por el arco oeste** (traceroute a `10.0.0.10` completa: B1→B2→B3→B4). Banco 2 dejó de descartar esa red (sus tracks 4/6/sondas debieron de recuperarse; sus docs `BANCO2.md`/`ESTADO_ANILLO.md` están desactualizadas a ese respecto). El estado pendiente real de B1 es el **arco este (B5): `10.0.0.17`/`.14`/`.13` no responden**.

### Rutas activas (instaladas en RIB, 2026-09-08)
* `10.0.0.4/30`→`10.0.0.2` (AD1, track 1), `10.0.0.8/30`→`10.0.0.2` (AD1, track 1), `10.0.0.12/30`→`10.0.0.17` (AD1, track 2), default→`192.168.122.1`, `172.16.0.0/16`→`10.10.2.2`.
* Ninguna ruta de B1 reenvía tráfico al banco del que proviene; nexthops flotantes apuntan al arco opuesto (fold de anillo intencional AD20).
* **Residual eliminado**: ya no existe la `ip route 10.0.0.4 ... 10.0.0.2` sin track (limpiada en el fix) ni el wrap `10.0.0.16/30 via 10.0.0.2 20 track 1` (riesgo de loop B1↔B2).

### IP SLA / Tracks (2026-09-08)
* **SLA: ninguno configurado** (sustituidos por tracks de línea).
* Track 1 (Gi0/1, oeste/B2): **Up** — coincide con conectividad real (.2 responde).
* Track 2 (Gi0/2, este/B5): **Up a nivel de línea**, aunque B5 no responde ICMP → ruta hacia `.12/30` queda "muerta en caliente" (envía a `.17` que no contesta). Limitación del diseño line-protocol (solo detecta L1/L2 del enlace, no la salud del vecino).

### Failover (teoría, sin cortes) — 2026-09-08
* Corte este (track 2 DOWN): `10.0.0.12/30` vira a `10.0.0.2` (AD20) — dirección correcta.
* Corte oeste (track 1 DOWN): `10.0.0.4`/`10.0.0.8` viran a `10.0.0.17` (AD20) — dirección correcta.
* Riesgos detectados:
  1. **Arco este B5 sin respuesta hoy** (`.17`/`.14`/`.13`): con track 2 Up la ruta a `.12/30` sigue enviando a B5 aunque esté caído. Al caer track 2, la flotante a `10.0.0.2` cubriría `.12/30`. PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
  2. Loop B4-B5 hacia `10.0.0.0/30` y `.4/30` (reportado por B3/B5/B4 ante doble falla simultánea): **no evaluable desde B1 ahora** porque el arco este (B5) no responde; el arco oeste está limpio (traza completa a B4). Requiere que B5 vuelva a responder para coordinar drill.
  3. Dependencia: si cae Gi0/1, B1 reenviará `10.0.0.0/30` hacia B5; B5 debe reenviar hacia B2/B3 y no devolver a B1. PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
* El wrap propio `10.0.0.16/30 via 10.0.0.2 20 track 1` fue **eliminado** (evita loop B1↔B2 cuando cae el este, ver "Cambios recientes"). La flotante `10.0.0.0/30 via 10.0.0.17 20 track 2` (wrap del propio segmento oeste) se conserva.
* Drill de corte no ejecutado (requiere aprobación).

### Servicios interbancarios probados desde B1 (solo TCP, sin transacciones)
* `10.0.0.6:80` (B3): **TIME-OUT** (ICMP responde, TCP 80 no) en verificaciones previas. PENDIENTE B3.
* `10.0.0.9/:80`, `10.0.0.10:80` (B3-B4): previamente UNREACH; hoy el destino `.9/.10` sí responde ICMP pero el puerto 80 no se re-probó tras el restart. PENDIENTE DE CONFIRMACIÓN POR BANCO 3/4.
* `10.0.0.5:80` (B2): REFUSED; `10.0.0.13/.14/.17:80` (B4/B5): hoy sin respuesta porque B5 está mudo.
* Ningún endpoint `/interbancaria` de otra entidad respondió desde B1 (el propio endpoint de B1 sigue pendiente de definición, ver Servicios).

### Problemas pendientes (2026-09-08)
* **Arco este: B5 (`10.0.0.17`/`.14`) y vía él `.13` no responden** desde B1 pese a link/track UP. PENDIENTE B5.
* B4 (`.10`) alcanzable por el arco oeste; `.13` (B4-B5) NO por el este. PENDIENTE B4/B5.
* `.12/30` "muerto en caliente": primaria apunta a `.17` (B5) mudo. PENDIENTE B5.
* TCP `10.0.0.6:80` (B3) sin respuesta — PENDIENTE B3.
* `ESTADO_ANILLO.md`/`BANCO2.md` desactualizados respecto al arco oeste (B1→B2→B3→B4 ya funciona) y aún no reflejan el fix v8.1 de B1 ni el estado "B5 mudo".
* Drill de failover coordinado pendiente.

## Interfaces de tránsito
* **Gi0/1:** `10.0.0.1/30` — enlace hacia **Banco 2** (`10.0.0.0/30`). Estado: **UP/UP**. ARP de `10.0.0.2` resuelto (`ca01.d8af.0038`). `ip nat outside`.
* **Gi0/2:** `10.0.0.18/30` — enlace hacia **Banco 5** (`10.0.0.16/30`). Estado: **UP/UP**. ARP de `10.0.0.17` resuelto (`ca01.aa69.001d`). `ip nat outside`.
* **Gi0/3:** `10.10.2.1/30` — hacia **FW interno** (`10.10.2.2`). UP/UP. `ip nat inside`.
* **Gi0/0:** `192.168.122.237/24` (DHCP) — uplink exterior (PAT saliente). UP/UP. `ip nat outside`.

## Vecinos directos
* **Banco 2 (`10.0.0.2`):** ARP OK, ICMP 100% (RTT ~5 ms).
* **Banco 5 (`10.0.0.17`):** ARP OK, ICMP 100% (RTT ~10 ms).

## Rutas primarias (AD 1, con track)
* `10.0.0.4/30` (B2-B3) via `10.0.0.2` track 1
* `10.0.0.8/30` (B3-B4) via `10.0.0.2` track 1
* `10.0.0.12/30` (B4-B5) via `10.0.0.17` track 2
* `0.0.0.0/0` via `192.168.122.1` (Gi0/0)
* `172.16.0.0/16` via `10.10.2.2` (Gi0/3, interno)

## Rutas de respaldo (flotantes AD 20, con track)
* `10.0.0.4/30` via `10.0.0.17 20` track 2
* `10.0.0.8/30` via `10.0.0.17 20` track 2
* `10.0.0.12/30` via `10.0.0.2 20` track 1
* `10.0.0.0/30` via `10.0.0.17 20` track 2 (wrap del propio segmento oeste por el este)

> **Eliminado en v8.1 (2026-09-07/08):** `10.0.0.16/30 via 10.0.0.2 20 track 1` (wrap del propio segmento este por el oeste). En fallo del este, ese wrap generaba loop B1↔B2: B1 reenviaba `.16/30` a B2 y B2 (por su track 3, que solo exige a B1 vivo) lo devolvía a B1 incesantemente. Eliminado y verificado por boot-test de persistencia.

Lógica: sin "entrada primaria" (es un anillo). Cada segmento lejano se alcanza por el arco corto (AD 1) y, si cae su track, vira por el arco contrario (AD 20) plegando el anillo. La config canónica vigente es **v8.1** (persistida en el config-disk `IOSv_startup_config.img`, no solo en overlay).

## IP SLA
* **Ninguno configurado (eliminados).** En IOSv, el scheduler del SLA resultó *single-shot* (no re-ejecuta pese a `frequency`) y los vecinos no responden ICMP echo a sondas. Se sustituyó por tracks de línea de interfaz.

## Tracks
* `track 1` interface `GigabitEthernet0/1` line-protocol — **Up** (oeste/B2)
* `track 2` interface `GigabitEthernet0/2` line-protocol — **Up** (este/B5)

## PBR / Route Maps
* Ninguno.

## NAT interbancario
* Publicación: `ip nat inside source static tcp 172.16.30.5 80 interface Gi0/1 80` (global `10.0.0.1:80`) y `... tcp 172.16.30.6 8080 interface Gi0/1 8080` (global `10.0.0.1:8080`).
* PAT saliente: ACL 100 (`172.16.0.0/16`, `10.10.2.0/30`) → `interface Gi0/0 overload`; ACL 101 (`172.16.0.0/16`) → `interface Gi0/1 overload` (salida hacia el anillo oeste).
* Interfaces: Gi0/0, Gi0/1, Gi0/2 = `ip nat outside`; Gi0/3 = `ip nat inside`.
* NOTA: en pruebas, un segundo estático con global explícito `10.0.0.18:80/8080` se aceptó al vuelo pero **no persistió** en running-config (IOSv). Los servicios quedan publicados bajo `10.0.0.1`.
* FW interno (10.10.2.2): FORWARD DROP salvo reglas puntuales; DNAT 80/8080 hacia `172.16.30.5`/`172.16.30.6`; REDIRECT de DNS 53 a dnsmasq.

## Servicios interbancarios publicados
* `http://10.0.0.1/` → `172.16.30.5:80` — portal interno "Banco 1 - Portal Interno" (HTTP 200 en `/`).
* `10.0.0.1:8080` → `172.16.30.6:8080` — responde; Banco 2 accedió a `10.0.0.1:8080` en prueba previa (traducción NAT viva registrada).
* **`/interbancaria`: PENDIENTE DE CONFIRMACIÓN** — el endpoint devolvió **HTTP 404** tanto en `172.16.30.5:80` como en `172.16.30.6:8080`. Falta definir/implementar ese recurso (¿path del portal o servicio aparte?).

## Pruebas de conectividad
Re-verificación 2026-09-08 post-restart (ping 2/2 con `repeat 2 timeout 2`, salvo indicación):
* ping `10.0.0.2` (B2): 100%, RTT 8-31 ms — enlace oeste UP.
* ping `10.0.0.5` (interfaz lejana de B2): 100%.
* ping `10.0.0.6` (**B3**, vía B2): 100%, ~47-68 ms — tránsito del anillo oeste OK.
* ping `10.0.0.9` / `10.0.0.10` (**B3 / B4**): 100% (RTT ~60-121 ms a `.10`) — **`10.0.0.8/30` (B3-B4) ya transita por B2/B3**; traceroute `.10` completa: B1→`.2`→`.6`→`.10`.
* ping `10.0.0.17` (B5): **0% (0/2)** — enlace Gi0/2 UP pero B5 no responde. PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
* ping `10.0.0.13` (B4, vía B5) / `10.0.0.14` (B5): **0% (0/2)** — arco este inaccesible por B5 mudo.
* ping `10.10.2.2` (FW interno): 100% (~1 ms).
* ARP vivos: `10.0.0.2` (`ca01.d8af.0038`). B5 sin ARP válido en uso (Gi0/2 arriba, sin respuesta).
* Respuesta ICMP de B1 a sondas externas: **PENDIENTE DE CONFIRMACIÓN POR BANCO 2/3/5** (no es posible originar la sonda desde el propio nodo).

## Failover
* Diseño por tracks de línea (independiente de ICMP): corte este (Gi0/2) → `10.0.0.12/30` vira a `10.0.0.2` (flotante); corte oeste (Gi0/1) → `10.0.0.4/8` y wrap `.0/30` viran vía `10.0.0.17`.
* **Fix v8.1 (2026-09-07/08):** eliminado el wrap `10.0.0.16/30 via 10.0.0.2 20 track 1` (loop B1↔B2 en fallo este) y el residual `10.0.0.4 via 10.0.0.2` sin track. Config regenerada y persistida en el config-disk (v8.1), validada con rearranque real limpio.
* Drill de corte real: **PENDIENTE DE CONFIRMACIÓN** — no ejecutado (requiere aprobación para `shutdown` temporal de interfaz).
* Bucles B4-B5 reportados por B3/B4/B5 (`.0/30` y `.4/30`, ante doble falla simultánea B1+B2): con B1 activo y arco oeste sano no se observan desde B1; hoy el arco este (B5) está mudo y no permite re-probar. PENDIENTE de coordinación con B4/B5.

## Problemas conocidos
* `ESTADO_ANILLO.md` (B3) y `BANCO2.md` desactualizados: siguen sin reflejar que `10.0.0.8/30` (B3-B4) YA es alcanzable por el arco oeste desde B1 (B1→B2→B3→B4), ni el fix v8.1 de B1, ni el estado "B5 mudo" en el este.
* Arco este: Gi0/2 UP pero B5 (`10.0.0.17`) no responde ICMP → `.13`/`.14` inalcanzables desde B1 (PENDIENTE DE CONFIRMACIÓN POR BANCO 5).
* `/interbancaria` → HTTP 404 (ver servicios).
* IOSv: segundo estático NAT con global `10.0.0.18` no persiste.
* Limitación track line-protocol: no detecta caída de vecino con L1/L2 sano (ver "muerto en caliente" de `.12/30`).

## Cambios recientes
* 2026-09-07: redefinición de rutas de anillo v7 (arco corto/largo + wraps) y tracks `line-protocol`; SLA eliminados.
* 2026-09-07: reconexión del cable físico del enlace este (B5).
* 2026-09-07/08: **fix de config → versión canónica v8.1**: eliminado el wrap `10.0.0.16/30 via 10.0.0.2 20 track 1` (riesgo de loop B1↔B2) y el residual `ip route 10.0.0.4 via 10.0.0.2` sin track; añadido `no shutdown` explícito en Gi0/0-3 para rearranques limpios. Inyectado en el config-disk `IOSv_startup_config.img` (master + overlay del nodo).
* 2026-09-08: **rearranque real limpio del nodo B1** para validar persistencia (CVAC CONFIG_FOUND/DONE desde flash2, sin parser errors; interfaces UP, tracks UP, rutas v8.1). Durante el apagado (~2 min) el anillo quedó sin tránsito ni presencia de B1; operación restaurada.
* 2026-09-08: re-verificación del anillo post-restart → arco oeste completo OK (B1→B2→B3→B4, incl. `10.0.0.8/30` que antes daba `!H`); arco este B5 mudo (PENDIENTE B5).

## Pendientes
* Definir/implementar el endpoint `/interbancaria` y validarlo desde B2/B5.
* Drill de failover autorizado (corte de 30 s por lado).
* Confirmar con Banco 5 su estado (nodo sin responder en `10.0.0.17`/`.14` pese a enlace y track UP).
* Revalidar conectividad ICMP hacia B1 desde B2/B3/B5 y actualización de `ESTADO_ANILLO.md` (B3) con el arco oeste sano.

## Notas para otros bancos
* **B3 (coordinador):** re-ejecutar sus sondas SLA/PBR hacia B1 y hacia `.8/30`: el nodo responde ICMP, el arco oeste hasta `.10` (B4) está operativo y B1 ya no tiene dead-route hacia `.8/30`. `ESTADO_ANILLO.md` debe actualizarse (arco oeste OK, B5 mudo, fix v8.1 de B1). El requerimiento de su Paso 2 (`ip route 10.0.0.8 ... 10.0.0.17 20 track 2`) ya está satisfecho en B1 desde v7 (y en v8.1 permanece).
* **B2:** confirmar corrección del estado de sus tracks 4/6 (el tráfico B1→B4 vía `.8/30` YA transita por B2/B3; sus docs siguen listando Null0).
* **B5:** POR FAVOR confirmar su nodo: desde B1 el enlace Gi0/2 está UP pero `10.0.0.17` no responde (0/2), afectando `.13`/`.14` y dejando `.12/30` "muerto en caliente". B5.md reportaba operatividad a las 17:43 UTC-6.
* **B4:** por `.13` (interfaz hacia B5) inalcanzable desde el arco este; el `.10` (hacia B3) es alcanzable vía oeste. Confirmar sostenibilidad de su failover Track B2 (según su doc, DOWN) — el oeste ya devuelve tráfico.
* **B2:** acceso interbancario publicado en `10.0.0.1:80` y `10.0.0.1:8080`. Estado de publicación JSON/API: PENDIENTE DE DEFINICIÓN (ver Servicios).