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
ip route 10.0.0.16 255.255.255.252 10.0.0.1 track 5    ! B5-B1 vía B1 (AD 1)
ip route 0.0.0.0 0.0.0.0 192.168.100.1                  ! Default hacia ISP
ip route 10.20.0.0 255.255.0.0 10.20.0.2                ! LAN interna hacia R-LAN
```

## Rutas de respaldo (flotantes condicionadas a track)
```text
ip route 10.0.0.8 255.255.255.252 10.0.0.1 100 track 7 ! B4 vía B1 (resp. de B3)
ip route 10.0.0.12 255.255.255.252 10.0.0.6 100 track 8 ! B5 vía B3 (resp. de B1)
ip route 10.0.0.16 255.255.255.252 10.0.0.6 100 track 8 ! B5-B1 vía B3 (resp. de B1)
```
> Las flotantes **no** se instalan si su track está Down. Así se evita rebotar tráfico hacia un vecino que no puede entregar el destino.

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
track 1 rtr 1 reachability   ! B1 directo               -> UP
track 2 rtr 2 reachability   ! B3 directo               -> UP
track 3 rtr 3 reachability   ! B5 vía B1                -> DOWN
track 4 rtr 4 reachability   ! B4 vía B3                -> DOWN
track 5 list boolean and (obj 1 y 3) ! B1 directo Y B5 vía B1 -> DOWN
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
* No se ha confirmado aún el endpoint HTTP `/interbancaria` equivalente al de los demás bancos. PENDIENTE DE CONFIRMACIÓN POR BANCO 2.

## Pruebas de conectividad
* `B1 directo (10.0.0.1)`: inestable / no responde establemente (SLA 1 con fallos; B1 flapeando). Track 3/5 DOWN.
* `B3 directo (10.0.0.6)`: UP (SLA 2 OK, track 2 UP).
* `B4 vía B1 (10.0.0.10)`: Timeout (SLA 5: 0 éxitos / ~682 fallos).
* `B5 vía B1 (10.0.0.17)`: Timeout (SLA 3: 0 éxitos).
* `B4 vía B3 (10.0.0.10)`: Timeout (SLA 4: 0 éxitos / ~700+ fallos).
* `B5 vía B3 (10.0.0.17)`: Timeout (SLA 6: 0 éxitos / ~682 fallos).

## Failover
* Detección de fallo con IP SLA 1-6 + object tracking; rutas primarias condicionadas a track (1, 5, 6) y flotantes condicionadas a track (7, 8).
* Cuando cae un track, la ruta primaria asociada se retira de la tabla y solo se instala la flotante si su propio track está Up.
* **Resultado:** con la caída actual de B1, la tabla no tiene ruta hacia `10.0.0.16/30`; Banco 2 **no** reenvía ese tráfico hacia B3.

## ATENCIÓN: posible rebote hacia `10.0.0.16/30` (reportado por Banco 3)
**Ruta activa en este momento hacia `10.0.0.16/30`:** NINGUNA (`show ip route 10.0.0.16` -> "Subnet not in table"). track 5 y track 8 están DOWN.

| Parámetro | Valor |
|---|---|
| Next-hop primario | `10.0.0.1` (B1), AD 1 |
| Track asociado a la primaria | `track 5` (boolean AND: B1 directo Y B5 vía B1) |
| Next-hop de respaldo | `10.0.0.6` (B3), AD 100 |
| Track asociado al respaldo | `track 8` (B5 vía B3) |

**Por qué el tráfico podría volver a `10.0.0.6`:**
1. El respaldo para `10.0.0.16/30` apunta a `10.0.0.6` (B3). Si B1 cae (track 5 DOWN) pero B5 sigue siendo alcanzable vía B3 (track 8 UP), Banco 2 instala la flotante y envía el tráfico hacia B3. Eso es redundancia válida **solo si** B3 no lo devuelve.
2. **Riesgo de rebote mutuo:** si en ese mismo momento B3 tiene activa su propia flotante hacia `10.0.0.5` para la misma red (al detectar a B1 inalcanzable por su lado y apuntar su respaldo a Banco 2), los dos bancos se devuelven el paquete alternando `10.0.0.5 -> 10.0.0.6 -> 10.0.0.5 ...` hasta agotar TTL. Esa es la traza reportada por Banco 3.
3. **Estado actual:** no ocurre, porque track 8 está DOWN (SLA 6 a B5 vía B3 en Timeout). Con track 8 Down la flotante no se instala y Banco 2 descarta el tráfico a `10.0.0.16/30` en vez de rebotarlo hacia B3.
4. La observación de Banco 3 corresponde a la configuración **anterior** de Banco 2, que tenía una flotante sin track para `10.0.0.16/30`; se instalaba en cuanto caía la primaria y Banco 2 rebotaba el tráfico hacia B3. Corregido el 2026-09-07 con flotantes condicionadas a track.

**Acción recomendada (requiere aprobación y no ejecutada):** coordinar con Banco 3 que su flotante hacia `10.0.0.5` para `10.0.0.16/30` quede también condicionada a un track de alcanzabilidad real, para eliminar el rebote mutuo cuando haya redundancia activa en ambos lados.

## Problemas conocidos
* Banco 1 (`10.0.0.1` y `10.0.0.18`) inalcanzable/inestable desde Banco 2; B1 flapeando. PENDIENTE DE CONFIRMACIÓN POR BANCO 1.
* Fallo end-to-end vía ambos sentidos hacia B4/B5 (SLAs 3-6 en timeout). PENDIENTE DE CONFIRMACIÓN POR BANCO 4 y BANCO 5.
* Bucle B4-B5 hacia `10.0.0.0/30` documentado por Banco 3 (B5 devuelve tráfico a B4). PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
* Ruta de retorno faltante en B4 para `10.0.0.4/30` vía `10.0.0.9` (impide respuestas hacia B2). PENDIENTE DE CONFIRMACIÓN POR BANCO 4.

## Cambios recientes
* 2026-09-07: Se reemplazaron las rutas flotantes **sin** track por flotantes **condicionadas a track** (7 y 8) y se eliminaron flotantes inertes, eliminando el rebote de `10.0.0.8/30`, `10.0.0.12/30` y `10.0.0.16/30` hacia B1/B3. Se guardó con `write memory`.

## Pendientes
* Confirmar estado del servicio publicado (`10.20.1.34:5001`) y del endpoint `/interbancaria`.
* Confirmar con Banco 1 la estabilidad de `10.0.0.1`.
* Coordinar con Banco 3 la condición de track sobre su flotante hacia `10.0.0.16/30`.

## Notas para otros bancos
* Banco 2 usa flotantes condicionadas a track: no envía tráfico a un vecino que no puede entregarlo.
* Se solicita a B4 confirmar `ip route 10.0.0.4 255.255.255.252 10.0.0.9` para responder tráfico de B2.
* Se solicita a B5 revisar su ruta hacia `10.0.0.0/30` para no devolver tráfico a B4 (bucle B4-B5).
* Se solicita a B3 confirmar la condición de su flotante hacia `10.0.0.5` para `10.0.0.16/30` (evita rebote mutuo).