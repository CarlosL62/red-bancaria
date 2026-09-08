# Banco 2 (Banca de inversión)

## Estado
Última actualización: 2026-09-08 (reconstrucción IP SLA/tracks/rutas siguiendo GUIA_SONDEO_END_TO_END.md de Banco 4)
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

## Rutas primarias (E2E, según GUIA_SONDEO_END_TO_END.md de Banco 4)
```text
ip route 10.0.0.8 255.255.255.252 10.0.0.6 track 10    ! B4 vía B3 (E2E: vecino del vecino)
ip route 10.0.0.12 255.255.255.252 10.0.0.6 track 10   ! B5 vía B3 (E2E) — hacia B4/B5 por el sur
ip route 10.0.0.16 255.255.255.252 10.0.0.1 track 20   ! B5-B1 vía B1 (E2E: vecino del vecino)
ip route 10.0.0.10 255.255.255.255 10.0.0.6    ! host /32 para amarrar la sonda SLA 10
ip route 10.0.0.17 255.255.255.255 10.0.0.1    ! host /32 para amarrar la sonda SLA 20
ip route 0.0.0.0 0.0.0.0 192.168.100.1                  ! Default hacia ISP
ip route 10.20.0.0 255.255.0.0 10.20.0.2                ! LAN interna hacia R-LAN
```
> Las host routes `/32` (LPM máximo) fuerzan a la sonda a salir estrictamente por su cara, evitando el "comportamiento trampa" de Cisco FIB (la sonda usando la flotante y cerrando el track). Son las únicas rutas fijas sin track.

## Rutas de respaldo (flotantes, AD 100 — sin track, según la guía)
```text
ip route 10.0.0.8 255.255.255.252 10.0.0.1 100  ! B4 vía B1 (respaldo este)
ip route 10.0.0.12 255.255.255.252 10.0.0.1 100 ! B5/B4 vía B1 (respaldo este)
ip route 10.0.0.16 255.255.255.252 10.0.0.6 100 ! B5-B1 vía B3 (respaldo sur)
ip route 10.0.0.0 255.255.255.224 Null0 250     ! descarte del anillo (protección final) [2026-09-07]
```
> Las flotantes existen siempre pero quedan inactivas por AD; asumen instantáneamente cuando el track de la primaria la retira. El `Null0 /27` evita que tráfico interbancario se filtre al ISP solo si no hay ruta más específica.

## IP SLA (reconstruidos E2E, 2026-09-08)
Reemplaza los 6 SLAs + tracks boolean anteriores. Período de sonda 3 s, timeout/threshold 1000 ms, agendadas `life forever start-time now`:
```text
ip sla monitor 10: type echo 10.0.0.10 source-interface FastEthernet3/0  ! B4 vía B3 (E2E sur)
ip sla monitor 20: type echo 10.0.0.17 source-interface FastEthernet2/0  ! B5 vía B1 (E2E norte)
```
> El objetivo del sondeo ya no es solo el vecino directo (salto 1), sino el **vecino del vecino** (salto 2): B4 (10.0.0.10) y B5 (10.0.0.17). Cada sonda está amarrada a su cara con host route `/32`.

## Tracks (reconstruidos E2E, 2026-09-08)
```text
track 10 rtr 10 reachability   ! B4 vía B3 (E2E sur)   -> UP
track 20 rtr 20 reachability   ! B5 vía B1 (E2E norte) -> UP
track 10/20: delay down 6 up 3 (histéresis para amortiguar flaps)
```
> Histéresis `delay down 6 up 3`: el track necesita 6 s de fallos para bajar y 3 s de aciertos para subir, evitando flapping.

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
* ESTADO_ANILLO registra que B4 consume `http://10.0.0.2:5001/interbanco/deposito` (probado exitosamente por B4).

## Corrección de alcanzabilidad `10.0.0.8/30` (Paso 1 ESTADO_ANILLO, 2026-09-08)

**ANTES**
- ruta `10.0.0.8/30`: **ausente** (caía a `Null0 10.0.0.0/27` AD 250). Primaria `via 10.0.0.6 track 6` DOWN y flotante `via 10.0.0.1 track 7` DOWN.
- causa del descarte: **deadlock circular lado oeste** — B2 no respondía a B4 por no tener ruta a `10.0.0.8/30`, y el track 4 de B2 no subía porque B4 no contestaba en `10.0.0.10` (su Track B2 quedó DOWN y retiró sus primarias `10.0.0.4/30` y `10.0.0.0/30` por `eth3`). Resultado: B4 activaba su respaldo hacia B5 y B5 devolvía la red → loop B4↔B5 en `10.0.0.4/30`.

**CAMBIO 1 (ruta fija, remplazada luego)**
- aplicado (Paso 1): `ip route 10.0.0.8 255.255.255.252 10.0.0.6` (sin track, AD 1), persistido con `write memory`.

**CAMBIO 2 (2026-09-08, reconstrucción E2E)**
- Eliminada la ruta fija sin track. `10.0.0.8/30` vuelve a ser primaria E2E: `ip route 10.0.0.8 255.255.255.252 10.0.0.6 track 10` (sonda B4 vía B3).

**DESPUÉS (post reconstrucción E2E)**
- ruta instalada: `10.0.0.8/30 [1/0] via 10.0.0.6 track 10` (RIB activa).
- ping `10.0.0.10` (B4 cara oeste): **3/3**, RTT 56-64 ms (antes timeout).
- tracks: 10 UP (B4 vía B3), 20 UP (B5 vía B1).
- Track B2 de Banco 4: no confirmable directamente (sin consola de B4); evidencia indirecta: B4 responde en `10.0.0.10` y `10.0.0.13`.

## Corrección de la sonda E2E norte/sur (reconstrucción, 2026-09-08)

**Motivo (reporte del usuario):** durante el drill de corte B3-B4, la detección a 2 saltos (track 4 = B4 vía B3) SÍ bajaba, pero el tráfico seguía saliendo por `10.0.0.6` porque la ruta fija sin track de `10.0.0.8/30` (Paso 1) no respetaba el estado de los tracks. Además, la antigua sonda del arco este apuntaba a `10.0.0.10` (interfaz del enlace caído), que jamás responde cuando B4 derriba ese enlace, aunque B4 siga vivo por el este (`10.0.0.13` responde).

**CAMBIO (por decisión del usuario y siguiendo GUIA_SONDEO_END_TO_END.md de B4)**
- Se reconstruyó todo el esquema de monitoreo desde cero (ver "IP SLA", "Tracks", "Rutas primarias/backup").
- Las sondas E2E se anclaron con host routes `/32`: `10.0.0.10/32 via 10.0.0.6` (B4 por el sur) y `10.0.0.17/32 via 10.0.0.1` (B5 por el norte).
- Histéresis `delay down 6 up 3` en tracks 10/20.

**DESPUÉS**
- Sin rutas fijas de tránsito sin track; primarias E2E trackeadas y flotantes AD100. Al cortar B3-B4, track 10 (sonda B4 vía B3) baja y se retiran las primarias `.8/30` y `.12/30` via B3, asumiendo las AD100 via B1.
- Verificación limpia del drill pendiente (grupo en drill; validar que track 10 baje y la flotante AD100 via B1 tome el tráfico).

## Pruebas de conectividad (2026-09-08; post reconstrucción E2E)
* `B1 directo (10.0.0.1)`: UP.
* `B3 directo (10.0.0.6)`: UP.
* `B4 vía B3 (10.0.0.10)`: **UP** — ping 3/3 (56-64 ms), track 10 UP.
* `B4 este (10.0.0.13)`: **UP** — ping 3/3 (52-64 ms), traceroute `10.0.0.6 -> 10.0.0.13`.
* `B5 vía B1 (10.0.0.17)`: **UP** — track 20 UP (19 éxitos).
* Tracks: 10 UP, 20 UP. Flotantes AD100 inactivas (primarias E2E activas).

## Failover (nuevo esquema E2E, 2026-09-08)
* Detección con IP SLA 10/20 E2E + object tracking 10/20 (histéresis 6s down / 3s up). Sondas amarradas con host routes `/32`.
* Primarias E2E: `.8/30` y `.12/30` via B3 (`track 10`); `.16/30` via B1 (`track 20`).
* Si cae el camino sur (sonda 10.0.0.10 via B3), las primarias `.8/30` y `.12/30` se retiran y asumen las flotantes AD100 via B1 (este).
* Si cae el camino norte (sonda 10.0.0.17 via B1), `.16/30` se retira y asume la flotante AD100 via B3 (sur).
* **Protección final:** `Null0 /27` del anillo descarta `10.0.0.0/30`..`10.0.0.16/30` cuando no hay ruta más específica (sin fuga al ISP).
* A diferencia del esquema anterior, ahora **no hay rutas fijas sin track** para tránsito de anillo (solo las `/32` de sondas), por lo que la conmutación la decide el monitoreo E2E del vecino del vecino.

## ATENCIÓN: sección obsoleta (rebote `10.0.0.16/30`) — SUPERSEDIDA 2026-09-08
El esquema anterior usaba flotantes condicionadas a track; el actual (GUIA B4) usa primarias E2E trackeadas y flotantes AD100 sin track. La tabla antigua queda solo como referencia.
| Parámetro | Valor actual (2026-09-08) |
|---|---|
| Next-hop primario `.16/30` | `10.0.0.1` (B1), AD 1, track 20 (E2E B5 vía B1) |
| Next-hop respaldo `.16/30` | `10.0.0.6` (B3), AD 100 |
| Protección final | `Null0 10.0.0.0/27` (AD 250) |

## Problemas conocidos
* **Economía del cambio:** la reconstrucción E2E (SLA 10/20, tracks 10/20, host routes /32, primarias + AD100) reemplaza al esquema anterior de 6 SLAs/tracks boolean/Null0-cargado. Verificado: tracks UP, RIB correcta, ping B4 oeste 3/3 (56-64 ms) y B4 este (10.0.0.13) 3/3 vía B3.
* **Dependencia de respuesta ICMP de B5/B4 para el track E2E:** si un nodo no contesta ICMP de forma sostenida pero sí reenvía IP, el track E2E de esa cara puede bajar aunque el camino funcione (riesgo latente, mismo reporte histórico de B5).
* **Lado este inestable (raíz):** B5 no contesta ICMP de forma sostenida (reportado histórico por B1: `.17`/`.13` en 0%). PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
* `10.0.0.8/30`: alcanzable E2E (track 10 UP, ping 10.0.0.10 3/3).
* Endpoint `/interbancaria` de Banco 2 sin implementar/validar.

## Cambios recientes
* 2026-09-07 (1): flotantes sin track -> flotantes condicionadas a tracks 7/8; flotantes inertes eliminadas; `write memory`.
* 2026-09-07 (2, aprobado): primaria `10.0.0.16/30` de `track 5` a `track 1`; añadido `Null0 10.0.0.0/27` (AD 250); verificado traceroute a `.18` por el anillo; `write memory`.
* 2026-09-08 (3, aprobado - Paso 1): añadida ruta fija `ip route 10.0.0.8 255.255.255.252 10.0.0.6` para restablecer retorno hacia B4; verificado ping `.9` y `.10` 3/3; tracks 4/6/7 UP; `write memory`.
* 2026-09-08 (4, aprobado - petición de Banco 4): primaria `10.0.0.12/30` de `track 5` a `track 1` (el retorno del drill de B4 no debe depender del ICMP de B5); verificado RIB `[1/0] via 10.0.0.1`; `write memory`. Coordinación pendiente: B1 retirar su flotante `.12/30 via 10.0.0.2`.
* 2026-09-08 (5, aprobado - reconstrucción E2E según GUIA_SONDEO_END_TO_END.md de B4): eliminados SLAs 1-6, tracks 1-8, rutas viejas y la ruta fija `.8/30`; nuevos SLA 10/20 E2E (B4 vía B3, B5 vía B1), tracks 10/20 con histéresis (delay down 6 up 3), host routes `/32` para amarrar sondas, primarias E2E y flotantes AD100 sin track; `write memory`; verificado tracks UP, RIB, pings.

## Verificación global del anillo

Verificación 2026-09-08 (post reconstrucción E2E), desde R-WAN.

### Vecinos directos
* **IP vecino 1:** `10.0.0.1` (B1, FastEthernet2/0) — ping **OK**.
* **IP vecino 2:** `10.0.0.6` (B3, FastEthernet3/0) — ping **OK**.

### Redes alcanzables
* `10.0.0.0/30` — dest. `10.0.0.1` (B1): **alcanzable**. Conectada f2/0.
* `10.0.0.4/30` — dest. `10.0.0.6` (B3): **alcanzable**. Conectada f3/0.
* `10.0.0.8/30` — dest. `10.0.0.9` y `10.0.0.10`: **alcanzable (E2E)**. Primaria via `10.0.0.6` track 10. Ping `10.0.0.10` 3/3 (56-64 ms).
* `10.0.0.12/30` — dest. `10.0.0.13`/`10.0.0.14`: **alcanzable (E2E)** via `10.0.0.6` track 10. Ping `10.0.0.13` 3/3 (52-64 ms), traceroute `10.0.0.6 -> 10.0.0.13`.
* `10.0.0.16/30` — dest. `10.0.0.17`/`10.0.0.18`: **alcanzable (E2E)** via `10.0.0.1` track 20.

### Rutas que devuelven tráfico al banco de origen
* **Ninguna activa** en condiciones normales. Las flotantes AD100 por el lado contrario solo asumen si su primaria E2E se retira.

### SLA / Tracks (post reconstrucción E2E)
| SLA | Destino / camino E2E | Estado (éxitos/fallos) | Track | Coincide con realidad |
|---|---|---|---|---|
| 10 | `10.0.0.10` src f3/0 (B4 vía B3) | 18 éxitos/1 fallo | 10 UP | ✔ B4 responde por el sur |
| 20 | `10.0.0.17` src f2/0 (B5 vía B1) | 19 éxitos/0 fallos | 20 UP | ✔ B5 responde por el norte |

### Posibles loops (failover teórico)
* **Correcto:** al caer la sonda E2E de una cara, la primaria correspondiente se retira y la flotante AD100 de la otra cara asume; `Null0 /27` descarta si tampoco hay flotante. No hay rebote al banco emisor mientras el destino sea alcanzable por la ruta alternativa.
* **A vigilar (coordinación):** flotantes AD100 sin track pueden instalar una ruta aunque su next-hop de respaldo no tenga salida real (riesgo residual del diseño de la guía; el `Null0 /27` no la supera por AD). Pendiente evaluar con el coordinador.
* **Deadlock circular oeste:** **resuelto** — la primaria E2E `.8/30` via B3 (track 10) permanece instalada mientras B4 responda por el sur.

### Servicios probados (solo TCP, sin transacciones)
* `10.0.0.1:80` y `:8080` (B1 portal/app): **Open**.
* `10.0.0.6:80` (B3 `/interbancaria`): sin respuesta desde B2 (candidato: FW de B3 no autoriza origen B2). PENDIENTE DE CONFIRMACIÓN POR BANCO 3.
* `10.0.0.13:8080` (B4 blacklist, este): **Open**.
* `10.0.0.10:8080` (B4 blacklist, oeste): ahora enrutable (Paso 1); prueba TCP no re-ejecutada.
* `10.0.0.17:8080` (B5): Connection refused (sin servicio en 8080).

### Problemas pendientes
1. Coordinar con B4/coordinador si las flotantes AD100 sin track de la guía requieren gateo por track (riesgo de instalar ruta por next-hop sin salida real).
2. Estabilizar la respuesta ICMP de B5 (raíz latente; B1 reportó `.17`/`.13` en 0% históricamente).
3. B3 no abre TCP 80 al origen B2 (confirmar reglas FW/NAT).
4. `/interbancaria` de B2 por definir (publicación `10.0.0.2:5001` viva).
5. Re-validar en drill real de corte B3-B4 que track 10 baje y asuma la flotante AD100 por B1 (vector del bug reportado hoy).

## Pendientes
* Validar con el drill que la sonda E2E (B4 vía B3) baje correctamente y la flotante AD100 vía B1 asuma el tráfico de `10.0.0.8/30` (el problema reportado hoy por el usuario).
* Coordinar con B4/coordinador el gateo por track de las flotantes (diseño de la guía).
* Confirmar estabilización de la respuesta ICMP de B5 (B1/B5).
* Confirmar servicio publicado (`10.20.1.34:5001`) y endpoint `/interbancaria`.

## Mensajes / peticiones para otros bancos (2026-09-08)

### → Banco 4 (solicitante del cambio)
Aplicado en R-WAN el esquema completo de tu guía (GUIA_SONDEO_END_TO_END.md), reconstruido desde cero:
```
! Host routes /32 (anclan sondas)
ip route 10.0.0.10 255.255.255.255 10.0.0.6
ip route 10.0.0.17 255.255.255.255 10.0.0.1
! SLAs E2E (vecino del vecino)
ip sla monitor 10: icmp-echo 10.0.0.10 source-interface FastEthernet3/0  (freq 3)
ip sla monitor 20: icmp-echo 10.0.0.17 source-interface FastEthernet2/0  (freq 3)
! Tracks con histéresis
track 10 rtr 10 reachability; delay down 6 up 3
track 20 rtr 20 reachability; delay down 6 up 3
! Primarias E2E
ip route 10.0.0.8 255.255.255.252 10.0.0.6 track 10
ip route 10.0.0.12 255.255.255.252 10.0.0.6 track 10
ip route 10.0.0.16 255.255.255.252 10.0.0.1 track 20
! Flotantes AD100 (sin track, según guía)
ip route 10.0.0.8 255.255.255.252 10.0.0.1 100
ip route 10.0.0.12 255.255.255.252 10.0.0.1 100
ip route 10.0.0.16 255.255.255.252 10.0.0.6 100
write memory
```
* **Qué:** se eliminó todo el esquema IP SLA/tracks anterior (SLAs 1-6, tracks 1-8, rutas trackeadas, ruta fija `.8/30`) y se montó el E2E de tu guía tal cual.
* **Validación:** tracks 10 y 20 **UP**; ping `10.0.0.10` 3/3 y `10.0.0.13` 3/3 (vía B3); traceroute a `.13` = `10.0.0.6 -> 10.0.0.13`.
* **Nota de sintaxis:** nuestro R-WAN usa IOS antiguo (`ip sla monitor N` en lugar de `ip sla N`), se adaptó manteniendo exactamente la misma lógica E2E.
* **Solicitud:** re-probar tu drill de corte B3-B4; ahora track 10 (B4 vía B3) debe bajar y la flotante AD100 via B1 asume. Confirmar por favor.

### → Banco 1 (cambio de diseño)
* **Qué:** B2 reemplazó todo su esquema IP SLA/tracks por el de la guía de B4 (E2E): primarias `.8/30` y `.12/30` via B3 (track 10 = B4 vía B3) y `.16/30` via B1 (track 20 = B5 vía B1); flotantes AD100 por el lado contrario.
* **Tu parte (revisar con tu propia guía):** ya no dependemos de tu flotante `10.0.0.12/30 via 10.0.0.2` para el retorno del drill de B4, pero el diseño ahora exige que **tú** apliques el mismo esquema E2E de tu plantilla en la guía (`track 10` = B3 vía B2, `track 20` = B4 vía B5). Confirmar por favor que aplicaste tu plantilla.
* **Nota:** con flotantes AD100 sin track (diseño de la guía), si el next-hop alterno no tiene salida real podría instalarse ruta sin entrega — tema de coordinación global, no solo de B2.

### → Banco 5 (causa raíz latente)
* **Qué:** el nuevo esquema E2E de B2 sondea `10.0.0.17` (B5 vía B1, track 20). Hoy respondes bien (19 éxitos), pero históricamente tu nodo dejó de contestar ICMP de forma sostenida y eso tumbaba los tracks anteriores.
* **Solicitud:** asegurar respuesta ICMP estable en `10.0.0.17`/`10.0.0.14`, que es lo que gobierna la cara norte de B2 (`.16/30`) y la cara este de B1/B4.

### → Banco 3 (coordinador)
Para tu consolidación de ESTADO_ANILLO:
* **Cambio B2 (2026-09-08):** reconstrucción completa IP SLA/tracks/rutas según GUIA_SONDEO_END_TO_END.md de B4. Nuevo esquema: SLAs 10/20 E2E, tracks 10/20 con histéresis (6s/3s), host routes `/32` para sondas, primarias E2E (`8/30`+`12/30` via B3, `16/30` via B1) y flotantes AD100 sin track.
* **Pedido:** reflejar el cambio; y evaluar con B4 si el diseño de flotantes AD100 sin track necesita gateo por track (riesgo residual de instalar ruta sin salida real si el next-hop alterno cae).