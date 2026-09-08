# Banco 2 (Banca de inversión)

## Estado
Última actualización: 2026-09-07
Agente/responsable: Agente Banco 2 (R-WAN)

## Interfaces de tránsito
* Enlace hacia Banco 1: `10.0.0.0/30 (10.0.0.2)` en `FastEthernet2/0`
* Enlace hacia Banco 3: `10.0.0.4/30 (10.0.0.5)` en `FastEthernet3/0`

Interfaces adicionales (no interbancarias):
* `FastEthernet0/0`: `192.168.100.10/24` (hacia ISP / Internet; gateway `192.168.100.1`)
* `FastEthernet1/0`: `10.20.0.1/30` (hacia R-LAN, LAN interna `10.20.0.0/16`)

## Vecinos directos
* **Banco 1:** `10.0.0.1` (FastEthernet2/0).
* **Banco 3:** `10.0.0.6` (FastEthernet3/0).

## Rutas primarias
```text
ip route 10.0.0.0 255.255.255.252 10.0.0.1 track 1     ! B1 directo (AD 1)
ip route 10.0.0.8 255.255.255.252 10.0.0.6 track 6     ! B4 vía B3 (AD 1)
ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 5    ! B5 vía B1 (AD 1)
ip route 10.0.0.16 255.255.255.252 10.0.0.1 track 1    ! B5-B1 vía B1 (AD 1) [2026-09-07]
ip route 0.0.0.0 0.0.0.0 192.168.100.1                  ! Default hacia ISP
ip route 10.20.0.0 255.255.0.0 10.20.0.2                ! LAN interna hacia R-LAN
```

## Rutas de respaldo (flotantes condicionadas a track)
```text
ip route 10.0.0.8 255.255.255.252 10.0.0.1 100 track 7 ! B4 vía B1 (resp. de B3)
ip route 10.0.0.12 255.255.255.252 10.0.0.6 100 track 8 ! B5 vía B3 (resp. de B1)
ip route 10.0.0.16 255.255.255.252 10.0.0.6 100 track 8 ! B5-B1 vía B3 (resp. de B1)
ip route 10.0.0.0 255.255.255.224 Null0 250             ! descarte del anillo [2026-09-07]
```
> Las flotantes **no** se instalan si su track está Down. Así no se envía tráfico a un vecino que no puede entregar el destino.
> El `Null0` cubre los cinco enlaces del anillo (`10.0.0.0/27`); solo actúa cuando no existe ruta más específica, evitando que tráfico interbancario se filtre al ISP por el default.

## IP SLA
Período de sonda 5 s, timeout 1000 ms, agendadas `life forever start-time now`:
```text
ip sla monitor 1: type echo 10.0.0.1  source-interface FastEthernet2/0   ! B1 directo
ip sla monitor 2: type echo 10.0.0.6  source-interface FastEthernet3/0   ! B3 directo
ip sla monitor 3: type echo 10.0.0.17 source-interface FastEthernet2/0   ! B5 vía B1
ip sla monitor 4: type echo 10.0.0.10 source-interface FastEthernet3/0   ! B4 vía B3
ip sla monitor 5: type echo 10.0.0.10 source-interface FastEthernet2/0   ! B4 vía B1
ip sla monitor 6: type echo 10.0.0.17 source-interface FastEthernet3/0   ! B5 vía B3
```

## Tracks
```text
track 1 rtr 1 reachability   ! B1 directo               -> UP (RTT ~15 ms)
track 2 rtr 2 reachability   ! B3 directo               -> UP
track 3 rtr 3 reachability   ! B5 vía B1                -> UP (post-reconexión cable este B1-B5)
track 4 rtr 4 reachability   ! B4 vía B3                -> DOWN
track 5 list boolean and (obj 1 y 3) ! B1 directo Y B5 vía B1 -> UP
track 6 list boolean and (obj 2 y 4) ! B3 directo Y B4 vía B3 -> DOWN
track 7 rtr 5 reachability   ! B4 vía B1 (gate flotante .8/30) -> DOWN
track 8 rtr 6 reachability   ! B5 vía B3 (gate flotantes .12/30 y .16/30) -> DOWN
```

## PBR / Route Maps
Ninguno configurado. No hay `ip policy route-map`, ni route-maps aplicados a interfaces, ni `ip local policy`.

## NAT interbancario
* `FastEthernet2/0` (10.0.0.2) y `FastEthernet3/0` (10.0.0.5): interfaces **outside**.
* `FastEthernet0/0` (192.168.100.10) y `FastEthernet1/0` (10.20.0.1): interfaces **inside**.
```text
access-list 101 permit ip 10.20.0.0 0.0.255.255 any     ! LAN interna saliente
access-list 102 permit ip 10.20.0.0 0.0.255.255 any

ip nat inside source list 101 interface FastEthernet2/0 overload   ! PAT saliente hacia B1
ip nat inside source list 102 interface FastEthernet3/0 overload   ! PAT saliente hacia B3
ip nat inside source static tcp 10.20.1.34 5001 interface FastEthernet2/0 5001  ! publicación
```
> ACLs 1, 101, 102, 199 definidas localmente pero **no** aplicadas con `ip access-group` (solo se usan en NAT).

## Servicios interbancarios publicados
* Publicación TCP `10.0.0.2:5001` -> `10.20.1.34:5001` (estática). Estado del servicio interno: PENDIENTE DE CONFIRMACIÓN POR BANCO 2.
* Endpoint HTTP `/interbancaria`: PENDIENTE DE CONFIRMACIÓN POR BANCO 2.

## Pruebas de conectividad (2026-09-07, verificación posterior al cambio)
* `B1 directo (10.0.0.1)`: UP — SLA 1 RTT ~15 ms, track 1 UP.
* `B5 vía B1 (10.0.0.17)`: UP — ping 5/5 (RTT ~20 ms), track 3 UP (cable este B1-B5 reconectado por Banco 1).
* `traceroute 10.0.0.18` (B1 lado este): **1 hop por el anillo** `10.0.0.1` (ya no sale al ISP).
* `B4 vía B3 (10.0.0.10)`: Timeout (SLA 4, track 4/6 DOWN).
* `B4 vía B1 (10.0.0.10)`: Timeout (SLA 5, track 7 DOWN).
* `B5 vía B3 (10.0.0.17)`: Timeout (SLA 6, track 8 DOWN) — el lado oeste (B3-B4-B5) sigue sin resolver.

## Failover
* Detección con IP SLA 1-6 + object tracking; primarias condicionadas a track (1, 5, 6) y flotantes a track (7, 8).
* **Protección final:** `Null0 /27` del anillo: si no hay ruta utilizable, el tráfico `10.0.0.0/30`..`10.0.0.16/30` se descarta localmente en vez de filtrarse a Internet por el default.
* Con el estado actual, `10.0.0.16/30` y `10.0.0.12/30` se enrutan por B1 (arco corto); `10.0.0.8/30` (enlace B3-B4) no tiene camino y cae al `Null0`.

## ATENCIÓN: rebote hacia `10.0.0.16/30` (reportado por Banco 3) — RESUELTO
**Ruta activa en este momento:** `10.0.0.16/30` via `10.0.0.1` (track 1) — instalada en RIB.

| Parámetro | Valor |
|---|---|
| Next-hop primario | `10.0.0.1` (B1), AD 1 |
| Track asociado a la primaria | `track 1` (B1 directo) — solo exige a B1, no a B5 |
| Next-hop de respaldo | `10.0.0.6` (B3), AD 100 |
| Track asociado al respaldo | `track 8` (B5 vía B3) |
| Protección final | `Null0 10.0.0.0/27` (AD 250) |

**Cambio aplicado 2026-09-07 (aprobado por usuario):**
1. La primaria a `10.0.0.16/30` pasó de `track 5` (exigía B1 **y** B5 vía B1) a `track 1` (solo exige B1). `10.0.0.18` es la **propia interfaz de B1**, así que con B1 vivo la ruta debe estar activa. Antes, con track 5 Down, la ruta ausente hacía que `traceroute 10.0.0.18` saliera por el default al ISP (`192.168.100.1 -> 192.168.1.1 -> 10.93.192.1 -> * * *`).
2. Se añadió `Null0` `/27` del anillo para que ningún tráfico interbancario se filtre a Internet cuando no haya camino.

**Por qué podía volver a `10.0.0.6`:** el respaldo de `10.0.0.16/30` apunta a B3; si se activaba (track 8 Up) mientras B3 tenía su flotante hacia `10.0.0.5` activa para la misma red, ambos se devolvían el paquete (`10.0.0.5 <-> 10.0.0.6`) hasta agotar TTL. Eso requería redundancia mutua simultánea; con la flotante condicionada a track 8 y el `Null0` final, Banco 2 **ya no rebota** ni filtra esa red.

## Problemas conocidos
* **Lado oeste sin resolver:** B3-B4 (track 4), B4 vía B1 (track 7) y B5 vía B3 (track 8) siguen DOWN. `10.0.0.8/30` (enlace B3-B4) no es alcanzable por ningún camino y cae al `Null0`. Implicaría que B4/B5 lado B3 no responden o falta ruta de retorno. PENDIENTE DE CONFIRMACIÓN POR BANCO 4 y BANCO 5.
* Ruta de retorno en B4 para `10.0.0.4/30` vía `10.0.0.9`: sigue sin confirmarse (PENDIENTE DE CONFIRMACIÓN POR BANCO 4). Es causal probable del fallo SLA 4/6.
* Endpoint `/interbancaria` de Banco 2 sin implementar/validar.
* Banco 1 reporta residuals de config propia (`ip route 10.0.0.4` sin track) — su acción.

## Cambios recientes
* 2026-09-07 (1): flotantes sin track -> flotantes condicionadas a tracks 7/8; flotantes inertes eliminadas; `write memory`.
* 2026-09-07 (2, aprobado): primaria `10.0.0.16/30` de `track 5` a `track 1`; añadido `Null0 10.0.0.0/27` (AD 250); verificado traceroute a `.18` por el anillo y ping a `.17` 5/5; `write memory`.

## Verificación global del anillo

Verificación realizada 2026-09-07 desde R-WAN (solo diagnóstico; sin cambios de red).

### Vecinos directos
* **IP vecino 1:** `10.0.0.1` (B1, FastEthernet2/0) — ping **5/5**, RTT 8-12 ms.
* **IP vecino 2:** `10.0.0.6` (B3, FastEthernet3/0) — ping **5/5**, RTT 28-48 ms.

### Redes alcanzables
* `10.0.0.0/30` — dest. `10.0.0.1` (B1): **alcanzable**. Ruta: conectada f2/0. Next-hop: directo.
* `10.0.0.4/30` — dest. `10.0.0.6` (B3): **alcanzable**. Ruta: conectada f3/0. Next-hop: directo.
* `10.0.0.12/30` — dest. `10.0.0.13` (B4) y `10.0.0.14` (B5): **alcanzable** (2/2, RTT 20-28 ms). Ruta: estática AD1 via `10.0.0.1` (track 5). Next-hop: `10.0.0.1`. Traceroute: `10.0.0.1 -> 10.0.0.17 -> 10.0.0.13` (arco este, sin loop).
* `10.0.0.16/30` — dest. `10.0.0.17` (B5) y `10.0.0.18` (B1): **alcanzable** (2/2, RTT 4-8 ms). Ruta: estática AD1 via `10.0.0.1` (track 1). Next-hop: `10.0.0.1`. Traceroute a `.18`: 1 salto `10.0.0.1`.

### Redes NO alcanzables
* `10.0.0.8/30` — dest. `10.0.0.9` y `10.0.0.10` (B4 cara oeste): **no alcanzable** (timeout 0/1). Ruta activa: `Null0 10.0.0.0/27` (AD 250, descarte local). Primaria via `10.0.0.6` (track 6) y flotante via `10.0.0.1` (track 7) **no instaladas** (tracks DOWN). Traceroute: sin salto (descarte local, no sale al ISP).

### Rutas activas / primarias / flotantes (estado actual de la RIB)
* **Activas relevantes:** `10.0.0.12/30 [1/0] via 10.0.0.1`; `10.0.0.16/30 [1/0] via 10.0.0.1`; `10.0.0.0/27 → Null0 [250/0]`; `0.0.0.0/0 via 192.168.100.1`; `10.0.0.0/30` y `10.0.0.4/30` conectadas.
* **Primarias:** `.8/30` via `10.0.0.6` track 6 (DOWN); `.12/30` via `10.0.0.1` track 5 (UP); `.16/30` via `10.0.0.1` track 1 (UP).
* **Flotantes:** `.8/30` via `10.0.0.1` AD 100 track 7 (DOWN); `.12/30` y `.16/30` via `10.0.0.6` AD 100 track 8 (DOWN); `Null0 /27` AD 250 (UP).
* **Rutas que devuelven tráfico al banco de origen:** **ninguna activa**. Las flotantes hacia B3 (`10.0.0.6`) están condicionadas a track 8 y no están instaladas; el `Null0` descarta lo no enrutable.

### SLA / Tracks (coherencia con conectividad real)
| SLA | Destino / camino | Estado (éxitos/fallos) | Track | Coincide con realidad |
|---|---|---|---|---|
| 1 | `10.0.0.1` src f2/0 (B1 directo) | OK (496/0) | 1 UP | ✔ B1 responde (ping 5/5) |
| 2 | `10.0.0.6` src f3/0 (B3 directo) | OK (497/0) | 2 UP | ✔ B3 responde (ping 5/5) |
| 3 | `10.0.0.17` src f2/0 (B5 vía B1) | OK (117/381 hist.) | 3 UP | ✔ B5 responde; flapeó antes de reconexión del cable este |
| 4 | `10.0.0.10` src f3/0 (B4 vía B3) | Timeout (0/499) | 4 DOWN | ✔ B4 no responde en .10 por el oeste |
| 5 | `10.0.0.10` src f2/0 (B4 vía B1) | Timeout (0/231) | 7 DOWN | ✔ B4 no responde en .10 ni por el este (aunque .13 sí responde) |
| 6 | `10.0.0.17` src f3/0 (B5 vía B3) | Timeout (0/233) | 8 DOWN | ✔ camino oeste no entrega; B5 solo responde por el este |

### Posibles loops (failover teórico, sin cortes)
* **Correcto hoy:** al caer una primaria vía B1, las flotantes no se instalan (track 8 DOWN) y el tráfico cae al `Null0`; no hay rebote hacia el banco emisor ni fuga al ISP.
* **Riesgo loop B2↔B3 hacia `10.0.0.16/30`:** si llegaran a activarse simultáneamente la flotante de B2 vía B3 (track 8 UP) y la flotante de B3 vía B2 (track 2 de B3 DOWN), se devolverían el paquete (`10.0.0.5 <-> 10.0.0.6`). Hoy no ocurre (track 8 DOWN). Acción: que B3 condicione su flotante a un track, igual que B2.
* **Bucle B4↔B5 (documentado por B3/B4):** se dispara con doble falla simultánea (B1 inalcanzable Y B2 inalcanzable). Con el este convergido (B1 arriba) no se ha reproducido; depende de las flotantes de B4/B5.
* **Deadlock circular lado oeste (bloqueante):** B2 no responde a las sondas de B4 hacia `10.0.0.5`/`10.0.0.10` porque `10.0.0.8/30` no tiene ruta activa (track 6 DOWN); y el track 4 de B2 (B4 vía B3) no sube porque B4 no contesta en `10.0.0.10` (su Track B2 quedó DOWN y B4 retiró sus primarias `10.0.0.4/30` y `10.0.0.0/30` por `eth3`). Ambas dependen una de la otra: se requiere ruptura unilateral coordinada (p. ej. ruta fija de retorno en B4 o temporal sin track en B2) para converger el oeste.

### Servicios probados (solo TCP, sin transacciones)
* `10.0.0.1:80` (B1 portal): **Open**.
* `10.0.0.1:8080` (B1 app): **Open**.
* `10.0.0.6:80` (B3 `/interbancaria`): **sin respuesta** — vecino directo ICMP OK, pero TCP 80 silencioso (candidato: Firebase/FW de B3 no autoriza origen B2). PENDIENTE DE CONFIRMACIÓN POR BANCO 3.
* `10.0.0.13:8080` (B4 blacklist, cara este): **Open**.
* `10.0.0.10:8080` (B4 blacklist, cara oeste): **sin respuesta** (`Null0`).
* `10.0.0.17:8080` (B5): **Connection refused** (host vivo, sin servicio en 8080).
* Nota: B4 reporta que consume nuestro servicio en `http://10.0.0.2:5001/interbanco/deposito` (probado exitosamente). B1 reporta `/interbancaria` → 404 (pendiente de implementar).

### Problemas pendientes
1. `10.0.0.8/30` inalcanzable desde B2 (deadlock circular oeste B2↔B4 + B4 no responde en `10.0.0.10`).
2. SLA 3 inestable historial (117/381): B5 vía B1 flapeó; ya OK tras reconexión del cable este.
3. B3 no abre TCP 80 al origen B2 (confirmar reglas FW/NAT de B3).
4. `/interbancaria` de B2 (`10.0.0.2:5001`) publicado; estado del endpoint interno por validar (B2).
5. Coordinar con B3 (flotante `10.0.0.16/30` con track) y con B4/B5 (flotantes del bucle este) para eliminar riesgos de loop residuales.

## Pendientes
* Confirmar convergencia del lado oeste (B3/B4/B5) para restablecer `10.0.0.8/30` y los respaldos por B3.
* Confirmar estado del servicio publicado (`10.20.1.34:5001`) y endpoint `/interbancaria`.
* Revalidar con Banco 1/3 la estabilidad de `10.0.0.1` y `10.0.0.18` (cable este reconectado).

## Notas para otros bancos
* **Banco 1:** rutas flotantes de B2 hacia `10.0.0.16/30` ya no rebotan (track 8 + `Null0`). `10.0.0.18` es alcanzable desde B2 por el anillo. Pendiente validar `/interbancaria`.
* **Banco 3:** su SLA a `10.0.0.18` por B4 (sonda 2) y la flotante de B3 hacia `10.0.0.5` para `10.0.0.16/30` deberían re-evaluarse: ahora B2 enruta `.16/30` por B1 y el lado oeste no entrega.
* **Banco 4/5:** se solicita confirmar rutas de retorno (`10.0.0.4/30` vía `10.0.0.9` en B4) y el estado de las interfaces `10.0.0.10`/`10.0.0.13`/`10.0.0.14`, porque el lado B3 de B2 no converge.