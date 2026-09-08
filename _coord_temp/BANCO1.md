# Banco 1 (Banca minorista con sucursales)

## Estado
Última actualización: 2026-09-08 (config v8.3 E2E + endpoint `/interbancaria` implementado y probado)
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
* **Banco 5 (`10.0.0.17`):** link Gi0/2 **UP/UP**, track 2 UP, **ARP resuelto** (`ca01.aa69.001d`, ARPA, Gi0/2) → B5 tiene presencia L2 viva. Pero **ICMP no responde de forma sostenida**: ping **0%** en batería de sondeos (incluir ~60-90 s de observación), IP SLA 4/5 (op4→`.17`, op5→`.13`) **sin nuevos éxitos** en ventana de 60 s (contador estancado en 181 éxitos históricos). Intermitencia previa **persiste** (B5 respondió ~00:58 y puntos aislados, hoy 0%). PENDIENTE DE CONFIRMACIÓN POR BANCO 5.

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
* `ESTADO_ANILLO.md`/`BANCO2.md` desactualizados respecto al arco oeste (B1→B2→B3→B4 ya funciona) y aún no reflejan el fix v8.1 de B1 ni el estado este "B5 flapeando".
* Drill de failover coordinado pendiente.

## Interfaces de tránsito
* **Gi0/1:** `10.0.0.1/30` — enlace hacia **Banco 2** (`10.0.0.0/30`). Estado: **UP/UP**. ARP de `10.0.0.2` resuelto (`ca01.d8af.0038`). `ip nat outside`.
* **Gi0/2:** `10.0.0.18/30` — enlace hacia **Banco 5** (`10.0.0.16/30`). Estado: **UP/UP**. ARP de `10.0.0.17` resuelto (`ca01.aa69.001d`). `ip nat outside`.
* **Gi0/3:** `10.10.2.1/30` — hacia **FW interno** (`10.10.2.2`). UP/UP. `ip nat inside`.
* **Gi0/0:** `192.168.122.237/24` (DHCP) — uplink exterior (PAT saliente). UP/UP. `ip nat outside`.

## Vecinos directos
* **Banco 2 (`10.0.0.2`):** ARP OK, ICMP 100% (RTT ~5 ms).
* **Banco 5 (`10.0.0.17`):** ARP OK, ICMP 100% (RTT ~10 ms).

## Rutas primarias (AD 1, con track E2E v8.3)
* `10.0.0.4/30` (B2-B3) via `10.0.0.2` track 10 (sla2 → `10.0.0.6` B3 = E2E 2 saltos)
* `10.0.0.8/30` (B3-B4) via `10.0.0.2` track 10 (idem)
* `10.0.0.12/30` (B4-B5) via `10.0.0.17` track 20 (sla5 → `10.0.0.13` B4 = E2E 2 saltos)
* `0.0.0.0/0` via `192.168.122.1` (Gi0/0)
* `172.16.0.0/16` via `10.10.2.2` (Gi0/3, interno)
* Host routes `/32` de sondas (evitan fuga circular del SLA por el arco opuesto): `10.0.0.6/32 → 10.0.0.2`, `10.0.0.13/32 → 10.0.0.17`
* Track 1/2 (line-protocol) ya no gobiernan primarias; quedan como soporte de flotantes y observación E2E no controla redundancia con ellos.

## Rutas de respaldo (flotantes AD 20, con track)
* `10.0.0.4/30` via `10.0.0.17 20` track 2
* `10.0.0.8/30` via `10.0.0.17 20` track 2
* `10.0.0.12/30` via `10.0.0.2 20` track 1
* `10.0.0.0/30` via `10.0.0.17 20` track 2 (wrap del propio segmento oeste por el este)

> **Eliminado en v8.1 (2026-09-07/08):** `10.0.0.16/30 via 10.0.0.2 20 track 1` (wrap del propio segmento este por el oeste). En fallo del este, ese wrap generaba loop B1↔B2: B1 reenviaba `.16/30` a B2 y B2 (por su track 3, que solo exige a B1 vivo) lo devolvía a B1 incesantemente. Eliminado y verificado por boot-test de persistencia.

Lógica: sin "entrada primaria" (es un anillo). Cada segmento lejano se alcanza por el arco corto (AD 1) y, si cae su track, vira por el arco contrario (AD 20) plegando el anillo. La config canónica vigente es **v8.2** (persistida en el config-disk `IOSv_startup_config.img`, no solo en overlay).

## Sondas remotas hacia B1 (otros bancos → nuestras IPs)
Confirmado en documentación de los vecinos (2026-09-07/08):
* **B2 → `10.0.0.1`** (SLA 1, cada 5 s, nuestra Gi0/1 oeste). Controla su ruta a `10.0.0.0/30`.
* **B3 → `10.0.0.1`** (SLA 1, vía Fa1/0/B2) y **`10.0.0.18`** (SLA 2, vía B4/B5 por el este), con Local PBR. Controlan sus primarias a `10.0.0.0/30` y `10.0.0.16/30`.
* **B4 → `10.0.0.18`** (Track B1, cada 2 s, vía B5). Controla su primaria a `10.0.0.16/30`.
* **B5 → `10.0.0.18`** (SLA 3, cada 5 s). Controla su ruta a `10.0.0.0/30`.
* Nuestro nodo responde los sondeos (ICMP a sus IPs por defecto). Evidencia `show ip traffic`: cientos de `echo` recibidos / `echo reply` enviados desde el boot.
* Hoy solo reciben los del **arco oeste** (B2/B3 a `.1`): los del este (B3/B4/B5 hacia `.18`) dependen de que B5 esté vivo y estable.

## IP SLA
* **Uso en routing (v8.3, E2E):** los SLAs **2 y 5 (echo a `.6`/`.13` = vecino-del-vecino)** gobiernan las primarias del ring a través de los tracks 10/20 (failover por alcance de 2 saltos, no por línea).
  * sla2 → `10.0.0.6` (B3, vía B2) + `/32 via 10.0.0.2` → track 10 → primarias de `.4/30` y `.8/30`.
  * sla5 → `10.0.0.13` (B4, vía B5) + `/32 via 10.0.0.17` → track 20 → primaria de `.12/30`.
  * Histéresis de tracks 10/20: `delay down 10 up 5` (inmune a la flake ICMP de B5).
  * La guía `docs/GUIA_SONDEO_END_TO_END.md` (B4) proponía SLAs 10/20 con `frequency 3`; se reutilizaron los SLAs 2/5 existentes (mismo destino, `frequency 5`) para no duplicar sondas.
* **IP SLA de observación (v8.2):** 5 sondas ICMP echo cada 5 s para monitorear los tramos del anillo (tracks 3-7, solo observación). El scheduler **sí re-ejecuta** en este IOSv (contador de éxitos crece en vivo).
* `show ip sla statistics` / `show track brief` dan el estado de cada tramo en un vistazo.

## Tracks
* `track 1` interface `GigabitEthernet0/1` line-protocol — **Up** (oeste/B2)
* `track 2` interface `GigabitEthernet0/2` line-protocol — **Up** (este/B5)
* `track 3` ip sla 1 (`10.0.0.2` B1-B2) — **Up** (observación)
* `track 4` ip sla 2 (`10.0.0.6` B2-B3) — **Up** (observación)
* `track 5` ip sla 3 (`10.0.0.10` B3-B4) — **Up** (observación)
* `track 6` ip sla 4 (`10.0.0.17` B1-B5) — **Up**
* `track 7` ip sla 5 (`10.0.0.13` B4-B5) — **Up**
* `track 10` ip sla 2 (`10.0.0.6` B3) reachability — **Up** — gobierna primarias de `.4/30` y `.8/30` (E2E oeste)
* `track 20` ip sla 5 (`10.0.0.13` B4) reachability — **Up** — gobierna primaria de `.12/30` (E2E este)
* Los tracks 3-7 son **solo observación** (no referenciados por ninguna `ip route`); los tracks 10/20 sí controlan failover (v8.3 E2E).

## Log de observación del anillo (EEM, v8.2)
* 5 applets EEM (`RING_SEG_B1-B2`, `RING_SEG_B2-B3`, `RING_SEG_B3-B4`, `RING_SEG_B1-B5`, `RING_SEG_B4-B5`), un evento por applet (`event track <n> state any`), registradas en `show event manager policy registered`.
* Ante cada transición de track emiten syslog `%HA_EM-6-LOG: RING_SEG_<SEG>: RING SEG <SEG> track=up|down`. Verificado en vivo en el boot de v8.2:
  `*Sep 8 01:08:06.876: %HA_EM-6-LOG: RING_SEG_B1-B2: RING SEG B1-B2 track=up` (y B2-B3, B3-B4).
* **Ojo IOSv:** la variable EEM `$_track_name` **NO existe** en este IOS (genera `%HA_EM-3-FMPD_UNKNOWN_ENV`+`%HA_EM-3-FMPD_ERROR`); por eso las applets usan etiquetas literales y solo `$_track_state`, que sí funciona.
* Los mensajes de transición nativos `%TRACK-6-STATE` del tracking también quedan en el buffer (`show logging`).

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
* **`/interbancaria`: IMPLEMENTADO** en `172.16.30.5:80` (POST). Ver sección "Endpoint `/interbancaria`". Antes devolvía HTTP 404 en GET y 400 en JSON sin `cuenta_origen`.

## Endpoint `/interbancaria` (implementado 2026-09-08)
* **Arquitectura real usada** (sin inventar servicio nuevo): aplicación propia `web_server.py` (`http.server` de Python stdlib) en el `Servidor-web` (`172.16.30.5:80`, Tiny Core), con backend de cuentas vía API HTTP `172.16.30.4:5000` (`/cuentas`, `/deposito`). Publicado al anillo por el NAT estático existente del router: **`http://10.0.0.1:80/interbancaria`** (no se abrió ningún puerto adicional ni servicios internos).
* **Contrato mínimo aplicado:**
  * `POST /interbancaria`, JSON `{"cuenta_destino": <id>, "monto": <cantidad>}` + opcionales `{"cuenta_origen": <ref>, "banco_origen": <ref>}` (solo eco).
  * **200** → `{"ok": true, "estado": "exito", "mensaje": "acreditacion interbancaria aceptada y aplicada", "cuenta_destino": <id>, "cuenta_destino_nombre": <nombre>, "monto": <monto>, "saldo": <saldo>}` + eco de `cuenta_origen`/`banco_origen` si se enviaron.
  * **400** → `{"ok": false, "codigo": "JSON_INVALIDO"}` (JSON no parseable) o `{"ok": false, "codigo": "DATOS_INVALIDOS"}` (falta `cuenta_destino`, `monto` no numérico o `≤ 0`).
  * **404** → `{"ok": false, "codigo": "CUENTA_DESTINO_INEXISTENTE"}` (destino no está en `/cuentas`).
  * **500** → `{"ok": false, "codigo": "ERROR_BD"}` (backend de cuentas inalcanzable) o `{"ok": false, "codigo": "ACREDITACION_FALLIDA"}` (fallo al acreditar).
* **Semántica entrante (solo acredita):** el endpoint **acredita** `monto` en `cuenta_destino` (sin débito local; el descuento lo hace el banco emisor). La acreditación usa `POST /deposito` con `empleado_id: 2` (compatible con el backend).
* **Persistencia:** cambio desplegado **offline** sobre el disco del `Servidor-web`: nuevo `mydata.tgz` (Tiny Core) dentro del filesystem; el disco del nodo se convirtió a **qcow2 autocontenido** (`hda_disk.qcow2`, backup previo `hda_disk.qcow2.bak_v9`). El VM fue rearrancado con el nuevo disco y el server ya sirve el nuevo contrato.
* **Pruebas ejecutadas (2026-09-08, desde firewall interno `10.10.2.2`):**
  * `GET /` → 200 (portal); `GET /interbancaria` → 404 (solo POST).
  * `POST` JSON inválido → 400; `POST {"cuenta_destino":"1","monto":-3}` → 400.
  * `POST {"cuenta_destino":"99","monto":5}` → 404.
  * `POST {"cuenta_destino":"1","monto":5,...}` → 200 `ok:true`, saldo cuenta 1 (Juan Perez): **500.00 → 505.00**; segunda petición → **510.00** (crédito **exactamente una vez por petición**, verificado contra `/cuentas`).
* **Limitaciones:** SSH a `172.16.30.5` bloqueado por política del FW interno → despliegue mediante parcheo de disco; consola GNS3 del `Servidor-web` inestable (datos rompen la sesión). Pendiente validación de una transferencia coordinada real desde B2/B3/B5 (no ejecutada por instrucción).

## Pruebas de conectividad
Re-verificación 2026-09-08 post-restart (ping 2/2 con `repeat 2 timeout 2`, salvo indicación):
* ping `10.0.0.2` (B2): 100%, RTT 8-31 ms — enlace oeste UP.
* ping `10.0.0.5` (interfaz lejana de B2): 100%.
* ping `10.0.0.6` (**B3**, vía B2): 100%, ~47-68 ms — tránsito del anillo oeste OK.
* ping `10.0.0.9` / `10.0.0.10` (**B3 / B4**): 100% (RTT ~60-121 ms a `.10`) — **`10.0.0.8/30` (B3-B4) ya transita por B2/B3**; traceroute `.10` completa: B1→`.2`→`.6`→`.10`.
* ping `10.0.0.17` (B5): **0% sostenido** en batería de sondeos (2026-09-08, ~90 s de observación; aislados aciertos previos ~00:58). Tras el rearranque v8.2 (01:07) y en la re-verificación de hoy, timeout. PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
* ping `10.0.0.13` (B4, vía B5) / `10.0.0.14` (B5): **0%** en el arco este mientras B5 no responde (hubo respuestas puntuales ~00:58).
* ping `10.10.2.2` (FW interno): 100% (~1 ms).
* ARP vivos: `10.0.0.2` (`ca01.d8af.0038`, Gi0/1) y `10.0.0.17` (**`ca01.aa69.001d`**, Gi0/2) — B5 resuelve ARP (presencia L2) aunque no responde ICMP; `10.0.0.18` es la IP propia.
* Respuesta ICMP de B1 a sondas externas: **PENDIENTE DE CONFIRMACIÓN POR BANCO 2/3/5** (no es posible originar la sonda desde el propio nodo).

### Drill de B4 (2026-09-08 ~03:00-03:15): ping a `10.0.0.5` con enlace B4-B3 cortado
* Escenario reportado por B4: ping/traceroute a `10.0.0.5` (interfaz de B2 hacia B3) con el enlace `10.0.0.8/30` (B4-B3) desconectado para probar failover; el traceroute de B4 **se queda en `10.0.0.18`** (interfaz este de B1).
* Evidencia B1 (live): sla1/2 → `.2`/`.6` OK (oeste sano); sla3 → `.10` (B4 oeste) **0 éxitos** (enlace B4-B3 cortado, coincide con el drill); sla4 → `.17` (B5) **flapeando** (52→55 éxitos acumulados; RTT 6-11 ms en los intentos que responde, timeout en los demás; track 6 Down ~03:12); sla5 → `.13` (B4 este) **flapeando** (track 7 Down ~03:11, EEM `RING_SEG_B4-B5 track=down`). Ping `10.0.0.5` desde B1: **100%**. Ruta `10.0.0.4/30 via 10.0.0.2` Gi0/1 y CEF a `.5` correctos.
* Interpretación: el camino de ida B4→B5→B1(`.18`)→B2→`.5` **funciona** (B1 reenvía por el oeste; `.5` responde). El traceroute muere en `.18` por el **retorno**: B2 no tiene ruta instalada hacia `10.0.0.12/30` (segmento fuente de B4-este). Según BANCO2.md, su primaria `10.0.0.12/30 via 10.0.0.1` está condicionada a su **track 5 = AND(B1 directo, B5 vía B1)**, y "B5 vía B1" (su SLA a `.17`) está **DOWN/flapeando por la inestabilidad ICMP de B5** (SLA3 154/107) → track 5 Down → ruta no instalada; su flotante `via 10.0.0.6 track 8` (B5 vía B3) también Down. Sin ruta a `.12/30`, **B2 descarta las respuestas** (echo y time-exceeded) hacia el origen de B4 → nada vuelve más allá del último salto que el propio B1 puede responder (`.18`). **No es un fallo de B1.**
* Recomendación a B2: re-chequear su SLA3/`.17` y evaluar condicionar `.12/30 via 10.0.0.1` **solo a su track 1 (B1 directo)**, no a "B5 vía B1": B1 ya tiene `.12/30 via 10.0.0.17 track 2` (line-protocol, ARP vivo) y puede escoltar el retorno aunque B5 no conteste ping. Recomendación a B5: estabilizar la respuesta ICMP (raíz de la flake del tramo este).

## Failover
* **Diseño E2E v8.3 (2026-09-08):** failover por alcance de vecino-del-vecino (guía `docs/GUIA_SONDEO_END_TO_END.md` acordada por el grupo).
  * Corte este (track 20 DOWN, no se alcanza `.13` vía B5) → primaria `.12/30` cae → flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` asume (dirección correcta).
  * Corte oeste (track 10 DOWN, no se alcanza `.6` vía B2) → primarias `.4/30` `.8/30` caen → flotantes `via 10.0.0.17 20 track 2` asumen.
  * Host routes `/32` amarran las sondas a su camino (evitan el flapping circular de IOS descrito en la guía).
  * Flotantes conservan AD 20 **con track** (v8.1-8.2) — más seguras que las flotantes sin track de la plantilla de la guía.
* **Fix v8.1 (2026-09-07/08):** eliminado el wrap `10.0.0.16/30 via 10.0.0.2 20 track 1` (loop B1↔B2 en fallo este) y el residual `10.0.0.4 via 10.0.0.2` sin track. Config regenerada y persistida en el config-disk (v8.1), validada con rearranque real limpio.
* **Coordinación B2 (`.12/30`):** la flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` **se conserva** en B1. En el esquema E2E del grupo B2 debe enrutar `.12/30` por su arco oeste (vía B3) cuando no por B1, por lo que **no** hay rebote B1↔B2 (requisito: que B2 migre a E2E según la guía). PENDIENTE DE CONFIRMACIÓN POR BANCO 2.
* Drill de corte real: **PENDIENTE** — no ejecutado (requiere aprobación para `shutdown` temporal de interfaz y coordinación grupal).

## Problemas conocidos
* `ESTADO_ANILLO.md` (B3) y `BANCO2.md` desactualizados: siguen sin reflejar que `10.0.0.8/30` (B3-B4) YA es alcanzable por el arco oeste desde B1 (B1→B2→B3→B4), ni el fix v8.1 + observación v8.2 de B1, ni el estado este "B5 flapeando".
* Arco este: Gi0/2 UP y ARP de B5 vivo, pero `10.0.0.17` no responde ICMP de forma sostenida → `.13`/`.14` inalcanzables desde B1 y `.12/30` "muerto en caliente" (PENDIENTE DE CONFIRMACIÓN POR BANCO 5).
* `/interbancaria` → implementado (ya no 404; ver sección Endpoint).
* IOSv: segundo estático NAT con global `10.0.0.18` no persiste.
* Limitación track line-protocol: no detecta caída de vecino con L1/L2 sano (ver "muerto en caliente" de `.12/30`).

## Cambios recientes
* 2026-09-07: redefinición de rutas de anillo v7 (arco corto/largo + wraps) y tracks `line-protocol`; SLA eliminados.
* 2026-09-07: reconexión del cable físico del enlace este (B5).
* 2026-09-07/08: **fix de config → versión canónica v8.1**: eliminado el wrap `10.0.0.16/30 via 10.0.0.2 20 track 1` (riesgo de loop B1↔B2) y el residual `ip route 10.0.0.4 via 10.0.0.2` sin track; añadido `no shutdown` explícito en Gi0/0-3 para rearranques limpios. Inyectado en el config-disk `IOSv_startup_config.img` (master + overlay del nodo).
* 2026-09-08: **rearranque real limpio del nodo B1** para validar persistencia (CVAC CONFIG_FOUND/DONE desde flash2, sin parser errors; interfaces UP, tracks UP, rutas v8.1). Durante el apagado (~2 min) el anillo quedó sin tránsito ni presencia de B1; operación restaurada.
* 2026-09-08: re-verificación del anillo post-restart → arco oeste completo OK (B1→B2→B3→B4, incl. `10.0.0.8/30` que antes daba `!H`); arco este B5 **flapeando** (PENDIENTE B5).
* 2026-09-08: **config v8.2 — observación del anillo**: 5 IP SLAs (echo 5 s a `.2`/`.6`/`.10`/`.17`/`.13`) + tracks 3-7 (sin control de rutas) + 5 applets EEM `RING_SEG_*` que loguean transición por tramo. Persistida en config-disk y validada con rearranque limpio (CVAC CONFIG_DONE, sin `%PARSER`; EEM `%HA_EM-6-LOG: RING SEG ... track=up` en arco oeste; tracks 6-7 Down al no responder B5).
* 2026-09-08: **Objetivo 1 — re-verificación B1-B5**: Gi0/2 UP/UP, track 2 UP, ruta conectada `10.0.0.16/30`, ARP `.17` presente (`ca01.aa69.001d`) pero ICMP **0% sostenido** y IP SLA 4/5 sin nuevos éxitos en ventana de 60 s. La intermitencia del arco este persiste (NO corregida: sin aprobación para cambios de red y el nivel de línea está sano).
* 2026-09-08: **Objetivo 2 — endpoint `/interbancaria` implementado y probado** en `172.16.30.5:80` y publicado en `http://10.0.0.1:80/interbancaria` (despliegue offline del `web_server.py` vía `mydata.tgz`; disco del node convertido a qcow2 autocontenido `.bak_v9` como backup). Pruebas 200/400/404, saldo acreditado una vez por petición.
* 2026-09-08 ~03:15: **diagnóstico del drill de B4** (ping a `10.0.0.5` con enlace B4-B3 cortado): traceroute muere en `10.0.0.18` por **ruta de retorno ausente en B2** hacia `10.0.0.12/30` (su track 5 hereda la flake ICMP de B5). B1 verificado sano (enganche oeste 100%). Ver sección "Drill de B4".
* 2026-09-08 ~23:00: **config v8.3 — End-to-End (vecino del vecino) según `docs/GUIA_SONDEO_END_TO_END.md`**: tracks 10/20 (reusan sla2→`.6` y sla5→`.13`, histéresis down 10/up 5) ahora gobiernan las primarias; rutas host `/32` amarran las sondas (`10.0.0.6/32 via 10.0.0.2`, `10.0.0.13/32 via 10.0.0.17`). Aplicado en vivo, validado (tracks 10/20 UP, RIB `.4/.8→.2`, `.12→.17`), persistido en config-disk (master `IOSv_startup_config.img` + overlay del nodo regenerado) y **validado con rearranque limpio** (CVAC CONFIG_DONE, tracks 10/20 UP, `/32` en RIB, rutas E2E instaladas, ping a `.2`/`.6`/`.13`/`.17` 100%).

## Pendientes
* Endpoint `/interbancaria` implementado y probado localmente; **pendiente** validación coordinada real desde B2/B3/B5 (sin transferencia interbancaria real por instrucción) y definir conciliación contable si el emisor envía `cuenta_origen` no local (solo eco por ahora).
* Drill de failover autorizado (corte de 30 s por lado) — ahora el failover es E2E (tracks 10/20); el drill validaría que los cortes disparan los tracks correctos y las flotantes asumen con histéresis.
* B5 confirmado respondiendo en la última validación (ICMP `.17`/`.13` 100%, tracks 6/7/20 Up post-boot v8.3) y su doc reporta E2E Hop-2 activo — **cerrado el PENDIENTE previo** de "B5 mudo"; si reaparece la flake, condiciona el track 20 (E2E este).
* Confirmar con Banco 2 que migró su `.12/30` a E2E (debe dejar de depender del track 5 AND B1+B5-vía-B1, ver drill de B4) para que la flotante `10.0.0.12/30 via 10.0.0.2` de B1 sea segura sin rebote.
* B3 coordinaría la adopción E2E grupal y actualizar `ESTADO_ANILLO.md` (sondas vecino-del-vecino por banco, tabla maestra de la guía).

## Notas para otros bancos
* **B4 (coordinador E2E):** B1 **adoptó** el esquema de `docs/GUIA_SONDEO_END_TO_END.md` (config v8.3, validada con rearranque limpio). Adaptaciones vs la plantilla: (1) se reutilizaron los SLAs 2/5 existentes en vez de crear sla10/20 (`frequency 5` en vez de 3); (2) histéresis down 10/up 5 (en vez de 6/3) para tolerar la flake ICMP de B5; (3) **flotantes con track** (AD 20 trackeadas, no sin-track como la plantilla) para evitar flotantes ciegas. Portabilidad de la guía al grupo: **confirmada en B1**.
* **Evaluación Hop-3 (vecino del vecino del vecino) — conclusión B1:** en este anillo de 5 nodos **no aporta** monitorear el tercer salto (`.10`/`.9` desde B1): cada enlace ya queda cubierto por el par correspondiente (B2 valida `.10`; B5 valida `.9`; B3/B4 también) y Hop-2 duplica la cobertura de todo el anillo. Agregar sondas Hop-3 añadiría ruido, latencia de convergencia y dependencia de la salud de un banco extra sin información nueva. B1 mantiene Hop-2 (lo coordinado); desestimamos Hop-3 por redundancia estructural (documentado para el grupo).
* **B3 (coordinador):** re-ejecutar sus sondas SLA/PBR hacia B1 y hacia `.8/30`: el nodo responde ICMP, el arco oeste hasta `.10` (B4) está operativo y B1 ya no tiene dead-route hacia `.8/30`. `ESTADO_ANILLO.md` debe actualizarse (arco oeste OK, B5 flapeando, fix v8.1 + observación v8.2 + E2E v8.3 de B1). El requerimiento de su Paso 2 (`ip route 10.0.0.8 ... 10.0.0.17 20 track 2`) ya está satisfecho en B1 desde v7 (y en v8.3 permanece).
* **B2:** confirmar corrección del estado de sus tracks 4/6 (el tráfico B1→B4 vía `.8/30` YA transita por B2/B3; sus docs siguen listando Null0).
* **B5:** tras el rearranque v8.3 de B1 (2026-09-08 ~23:00) su nodo **responde ICMP de forma sostenida**: ping a `10.0.0.17` y `10.0.0.13` **100%**, tracks 6/7/20 **Up** (sla5→`.13` 529 OK/32 fail). Coincide con su doc (`_coord_temp/BANCO5.md`), que adoptó E2E Hop-2 (SLAs 10/20 + Local PBR, `delay down 10 up 5`) el 2026-09-07 23:07 UTC-6, y con `ESTADO_ANILLO.md` (tracks 10/20 UP). La flake histórica del arco este queda documentada en secciones anteriores; no observada en la última validación.
* **B4:** por `.13` (interfaz hacia B5) inalcanzable desde el arco este; el `.10` (hacia B3) es alcanzable vía oeste. Confirmar sostenibilidad de su failover Track B2 (según su doc, DOWN) — el oeste ya devuelve tráfico.
* **B2 (drill B4):** re-chequear su SLA3 a `10.0.0.17` (B5 responde a B1 intermitente: RTT 6-11 ms cuando lo hace). Para que el failover B4→este complete, B2 necesita ruta a `10.0.0.12/30` para el retorno; su track 5 (AND B1+B5-vía-B1) queda rehén de la flake ICMP de B5. Proponemos condicionar `.12/30 via 10.0.0.1` a **track 1 (B1 directo)** — y en el esquema E2E del grupo migrar `.12/30` a su arco oeste (vía B3) cuando no por B1. B1 confirma su `.12/30 via 10.0.0.17 track 20` (E2E a `.13`) listo.
* **B5:** la raíz del tapón del drill de B4 es la inestabilidad de su respuesta ICMP: sus ramas hacia B1 (`10.0.0.17`) y B4 (`10.0.0.13`) flapean (EEM de B1 registra up/down repetidos, p.ej. 02:25-03:12; sla4→`.17` responde intermitente y sla5→`.13` igual). Estabilizar ICMP desbloquea el retorno `10.0.0.12/30` en B2.
* **B4 (drill):** una vez B2/B5 estables, re-ejecutar y confirmar; hops esperados del traceroute a `10.0.0.5`: `.14` (B5) → `.18` (B1) → `.2` (B2) → `.5` (destino).
* **B2:** acceso interbancario publicado en `10.0.0.1:80` → `172.16.30.5:80` (portal + endpoint `/interbancaria` implementado, ver sección Endpoint) y `10.0.0.1:8080` → `172.16.30.6:8080`.