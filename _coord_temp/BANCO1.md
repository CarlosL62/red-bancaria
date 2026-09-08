# Banco 1 (Banca minorista con sucursales)

## Estado
Última actualización: 2026-09-07 (evidencia del nodo capturada en vivo)
Agente/responsable: Agente Banco 1

## Verificación global del anillo
Verificación diagnóstica (2026-09-07, solo lectura, sin cambios de red) ejecutada desde el nodo B1 contra toda la topología del anillo.

### Vecinos directos
* **Banco 2:** `10.0.0.2` — ping **100%** (RTT 16-30 ms). ARP `ca01.d8af.0038`.
* **Banco 5:** `10.0.0.17` — ping **100%** (RTT 10-13 ms). ARP `ca01.aa69.001d`.

### Redes /30 del anillo (destino probado → alcanzable)
| Red | Destino probado | Alcanzable | Ruta activa (RIB) | Next-hop | Traza |
|---|---|---|---|---|---|
| `10.0.0.0/30` (B1-B2) | `10.0.0.2` | **SÍ** (100%) | Conectada | Gi0/1 (directo) | 1 hop |
| `10.0.0.4/30` (B2-B3) | `10.0.0.5` (B2) / `10.0.0.6` (B3) | **SÍ** (100% c/u; .6 ~55 ms) | Estática AD 1 | `10.0.0.2` | `10.0.0.2 → 10.0.0.6` |
| `10.0.0.8/30` (B3-B4) | `10.0.0.9` / `10.0.0.10` | **NO** (0%) | Estática AD 1 (track 1) | `10.0.0.2` | 1: `10.0.0.2` 2: `10.0.0.2 !H` → **B2 devuelve Host Unreachable** |
| `10.0.0.12/30` (B4-B5) | `10.0.0.13` (B4) / `10.0.0.14` (B5) | **SÍ** (100%; .13 ~19 ms) | Estática AD 1 | `10.0.0.17` | `10.0.0.17 → 10.0.0.13` (completa) |
| `10.0.0.16/30` (B5-B1) | `10.0.0.17` | **SÍ** (100%) | Conectada | Gi0/2 (directo) | 1 hop |

Nota: **B4 (10.0.0.13) es alcanzable por el arco este** (vía B5, traza completa), pero el segmento `10.0.0.8/30` (B3-B4) NO se alcanza por el arco oeste porque **Banco 2 no enruta hacia `.8/30`** (responde ICMP `!H` en el traceroute). PENDIENTE DE CONFIRMACIÓN POR BANCO 2/3/4.

### Rutas activas (instaladas en RIB)
* `10.0.0.4/30`→`10.0.0.2` (AD1), `10.0.0.8/30`→`10.0.0.2` (AD1), `10.0.0.12/30`→`10.0.0.17` (AD1), default→`192.168.122.1`, `172.16.0.0/16`→`10.10.2.2`.
* Ninguna ruta de B1 reenvía tráfico al banco del que proviene; los nexthops flotantes apuntan al arco opuesto (fold de anillo intencional, AD20).
* Residual config: `ip route 10.0.0.4 via 10.0.0.2` (sin track) duplicada — sin efecto en RIB. PENDIENTE limpieza.

### IP SLA / Tracks
* **SLA: ninguno configurado** (eliminados; sustituidos por tracks de línea).
* Track 1 (Gi0/1, oeste/B2): **Up**. Track 2 (Gi0/2, este/B5): **Up**. El estado coincide con la conectividad real de los vecinos directos.

### Failover (teoría, sin cortes)
* Corte este (track 2 DOWN): `10.0.0.12/30` vira a `10.0.0.2` (AD20) — dirección correcta.
* Corte oeste (track 1 DOWN): `10.0.0.4`/`10.0.0.8` viran a `10.0.0.17` (AD20) — dirección correcta.
* Riesgos detectados:
  1. `10.0.0.8/30` ya está **inalcanzable por arco oeste hoy** (B2 `!H`) pese a tener la primaria instalada → "ruta muerta en caliente". PENDIENTE DE CONFIRMACIÓN POR BANCO 2/3.
  2. Loop B4-B5 hacia `10.0.0.0/30` (reportado por B3 ante caída simultánea de B1): **no reproducible con B1 activo** (.13/.14/.17 OK). Requiere drill coordinado para confirmar.
  3. Dependencia: si cae Gi0/1, B1 reenviará `10.0.0.0/30` hacia B5; B5 debe reenviar hacia B2/B3 y no devolver a B1. PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
* Drill de corte no ejecutado (requiere aprobación).

### Servicios interbancarios probados (solo TCP, sin transacciones)
* `10.0.0.6:80` (B3, servicio interbancario): **TIME-OUT** (ICMP sí responde, TCP 80 no). PENDIENTE DE CONFIRMACIÓN POR BANCO 3 (¿ACL/política de origen?).
* `10.0.0.9/.10:80` (B3-B4): UNREACH (coherente con `.8/30` caído).
* `10.0.0.5:80` (B2), `10.0.0.13/.14/.17:80` (B4/B5/B5-B1): **REFUSED** (nada publicado en 80).
* Ningún endpoint `/interbancaria` de otra entidad respondió desde B1 en esta verificación.

### Problemas pendientes
* `10.0.0.8/30` (B3-B4) inalcanzable vía B2 (`!H`).
* TCP `10.0.0.6:80` (B3) sin respuesta — PENDIENTE B3.
* `ESTADO_ANILLO.md` sigue listando "timeout B1" en `.1`/`.18` — datos stale; re-probar con B2/B3/B5.
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
* `10.0.0.16/30` via `10.0.0.2 20` track 1 (wrap del propio segmento este por el oeste)

Lógica: sin "entrada primaria" (es un anillo). Cada segmento lejano se alcanza por el arco corto (AD 1) y, si cae su track, vira por el arco contrario (AD 20) plegando el anillo.

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
Realizadas 2026-09-07 desde el nodo (ping 2/2 salvo indicación):
* ping `10.0.0.2` (B2): 100%, ~5 ms.
* ping `10.0.0.5` (interfaz lejana de B2): 100%, ~5 ms.
* ping `10.0.0.6` (**B3**, vía B2): 100%, ~87 ms — tránsito del anillo oeste OK y bidireccional.
* ping `10.0.0.17` (B5): 100%, ~10 ms.
* ping `10.0.0.14` (interfaz lejana de B5): 100%, ~10 ms.
* ping `10.0.0.13` (**B4**, vía B5): 100%, ~17 ms — tránsito del anillo este OK y bidireccional.
* ARP vivos de `10.0.0.2` y `10.0.0.17`.
* Respuesta ICMP de B1 a sondas externas: **PENDIENTE DE CONFIRMACIÓN POR BANCO 2/3/5** (no es posible originar la sonda desde el propio nodo).

## Failover
* Diseño por tracks de línea (independiente de ICMP): corte este (Gi0/2) → `10.0.0.12/30` vira a `10.0.0.2` (flotante); corte oeste (Gi0/1) → `10.0.0.4/8` y wraps viran vía `10.0.0.17`.
* Drill de corte real: **PENDIENTE DE CONFIRMACIÓN** — no ejecutado (requiere aprobación para `shutdown` temporal de interfaz).
* Bucles reportados por B3 (B4-B5 hacia `10.0.0.0/30`; B2-B3 hacia `10.0.0.16/30`) correspondían al estado previo (B1 caído / cable este intermitente). Con B1 activo y rutas v7, **PENDIENTE de re-probar en coordinación**.

## Problemas conocidos
* `ESTADO_ANILLO.md` (B3) lista `10.0.0.1`/`10.0.0.18` timeout y sus SLA DOWN — información **STALE** (anterior a la reconexión del cable este). Requiere re-ejecución de sondas.
* Cable físico este (B5) fue intermitente: Gi0/2 recibía 0 tramas pese a recibirse en el adaptador del host. Reconectado 2026-09-07 → Gi0/2 recibe y ARP resuelto.
* `/interbancaria` → HTTP 404 (ver servicios).
* Residual en running-config: `ip route 10.0.0.4 ... via 10.0.0.2` (sin `track`), mismo nexthop/AD que la trackeada → sin efecto en RIB. PENDIENTE limpieza (requiere aprobación + re-persistir).
* IOSv: segundo estático NAT con global `10.0.0.18` no persiste.

## Cambios recientes
* 2026-09-07: redefinición de rutas de anillo v7 (arco corto/largo + wraps) y tracks `line-protocol`; SLA eliminados.
* 2026-09-07: reconexión del cable físico del enlace este (B5).

## Pendientes
* Definir/implementar el endpoint `/interbancaria` y validarlo desde B2/B5.
* Drill de failover autorizado (corte de 30 s por lado).
* Limpieza del residual de ruta `10.0.0.4` sin track (con aprobación).
* Revalidar conectividad ICMP hacia B1 desde B2/B3/B5.

## Notas para otros bancos
* **B3 (coordinador):** re-ejecutar sus sondas SLA/PBR hacia B1; el nodo responde ICMP y los segmentos están UP. Ver `Pruebas de conectividad`.
* **B2/B5:** confirmar sus rutas flotantes hacia `10.0.0.0/30` (B5) y `10.0.0.16/30` (B2) para evitar rebotes/bucles ahora que B1 está activo.
* **B2:** acceso interbancario publicado en `10.0.0.1:80` y `10.0.0.1:8080`.