# Banco 2 (Banca de inversión)

## Estado
Última actualización: 2026-09-08 (Paso 1 ESTADO_ANILLO aplicado)
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
ip route 10.0.0.8 255.255.255.252 10.0.0.6     ! B4 vía B3 SIN track (fija, Paso 1) [2026-09-08]
ip route 10.0.0.0 255.255.255.252 10.0.0.1 track 1     ! B1 directo (AD 1)
ip route 10.0.0.8 255.255.255.252 10.0.0.6 track 6     ! B4 vía B3 (AD 1, redundante con la fija)
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
> La ruta fija a `10.0.0.8/30` (sin track) tiene precedencia por ser más específica que el `/27` y garantiza que B2 responda al tráfico proveniente de B4 (rompe el deadlock circular del lado oeste).

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

## Tracks (estado post Paso 1, 2026-09-08)
```text
track 1 rtr 1 reachability   ! B1 directo               -> UP
track 2 rtr 2 reachability   ! B3 directo               -> UP
track 3 rtr 3 reachability   ! B5 vía B1                -> DOWN (flapeando; SLA3 154/107)
track 4 rtr 4 reachability   ! B4 vía B3                -> UP (post Paso 1)
track 5 list boolean and (obj 1 y 3) ! B1 directo Y B5 vía B1 -> DOWN (obj3 DOWN)
track 6 list boolean and (obj 2 y 4) ! B3 directo Y B4 vía B3 -> UP
track 7 rtr 5 reachability   ! B4 vía B1 (gate flotante .8/30) -> UP (post Paso 1)
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
* ESTADO_ANILLO registra que B4 consume `http://10.0.0.2:5001/interbanco/deposito` (probado exitosamente por B4).

## Corrección de alcanzabilidad `10.0.0.8/30` (Paso 1 ESTADO_ANILLO, 2026-09-08)

**ANTES**
- ruta `10.0.0.8/30`: **ausente** (caía a `Null0 10.0.0.0/27` AD 250). Primaria `via 10.0.0.6 track 6` DOWN y flotante `via 10.0.0.1 track 7` DOWN.
- causa del descarte: **deadlock circular lado oeste** — B2 no respondía a B4 por no tener ruta a `10.0.0.8/30`, y el track 4 de B2 no subía porque B4 no contestaba en `10.0.0.10` (su Track B2 quedó DOWN y retiró sus primarias `10.0.0.4/30` y `10.0.0.0/30` por `eth3`). Resultado: B4 activaba su respaldo hacia B5 y B5 devolvía la red → loop B4↔B5 en `10.0.0.4/30`.

**CAMBIO**
- aplicado: `ip route 10.0.0.8 255.255.255.252 10.0.0.6` (sin track, AD 1), persistido con `write memory`.
- configuración resultante: ruta fija a B3 coexistiendo con la primaria trackeada (mismo next-hop) y la flotante (track 7).

**DESPUÉS**
- ruta instalada: `10.0.0.8/30 [1/0] via 10.0.0.6` (RIB activa).
- ping `10.0.0.9` (B3 cara B4): **3/3**, RTT 24-32 ms.
- ping `10.0.0.10` (B4 cara oeste): **3/3**, RTT 60-64 ms (antes timeout).
- traceroute `10.0.0.10`: `10.0.0.6 -> 10.0.0.10` (B2→B3→B4, sin loop).
- tracks propios: 4, 6 y 7 pasaron a **UP** (retorno de B4 funcional). SLA 4/5 ahora OK.
- Track B2 de Banco 4: **no confirmado directamente** (sin consola de B4). Evidencia indirecta: B4 responde en `10.0.0.10` y el retorno converge → indicativo de Track B2 UP.
- loop B4-B5 en `10.0.0.4/30`: **no confirmado directamente**; según ESTADO_ANILLO se extingue al subir Track B2 de B4 (esperar confirmación de B4/B5).

## Pruebas de conectividad (2026-09-08, post Paso 1)
* `B1 directo (10.0.0.1)`: UP — track 1 UP.
* `B3 directo (10.0.0.6)`: UP — track 2 UP.
* `B4 vía B3 (10.0.0.9 / 10.0.0.10)`: **UP** — ping 3/3 (24-64 ms) via ruta fija; track 4 UP.
* `B4 vía B1 (10.0.0.10)`: **UP** — track 7 UP (SLA 5 responde).
* `B5 vía B1 (10.0.0.17)`: **flapeando** — SLA 3 (154/107), track 3 DOWN en el último chequeo; `.12/30` quedó temporalmente en `Null0`.
* `B5 vía B3 (10.0.0.17)`: Timeout — track 8 DOWN (oeste hacia B5 no entrega).

## Failover
* Detección con IP SLA 1-6 + object tracking; primarias condicionadas a track (1, 5, 6) y flotantes a track (7, 8).
* **Protección final:** `Null0 /27` del anillo descarta `10.0.0.0/30`..`10.0.0.16/30` cuando no hay ruta más específica (sin fuga al ISP).
* Nunca se instalan rutas que devuelvan tráfico al banco del que proviene (flotantes a B3 condicionadas a track 8; ruta fija `10.0.0.8/30` apunta a B3, que es el dueño directo de esa red).

## ATENCIÓN: rebote hacia `10.0.0.16/30` (reportado por Banco 3) — RESUELTO
**Ruta activa:** `10.0.0.16/30` via `10.0.0.1` (track 1).
| Parámetro | Valor |
|---|---|
| Next-hop primario | `10.0.0.1` (B1), AD 1 |
| Track asociado a la primaria | `track 1` (B1 directo) |
| Next-hop de respaldo | `10.0.0.6` (B3), AD 100 |
| Track asociado al respaldo | `track 8` (B5 vía B3) |
| Protección final | `Null0 10.0.0.0/27` (AD 250) |

La flotante hacia B3 está condicionada a track 8; con el tráfico de evitación, Banco 2 no rebota ni filtra esa red.

## Problemas conocidos
* **Lado este inestable (pre-existente):** SLA 3 (B5 vía B1) flapeando (154/107) → track 3/5 Down intermitente → `10.0.0.12/30` cae a `Null0` de forma intermitente. Vínculo B1-B5 (cable este) sigue intermitente según B1. PENDIENTE DE CONFIRMACIÓN POR BANCO 1.
* `10.0.0.8/30`: **RESUELTO** en B2 (ruta fija via B3). Falta confirmación de B4/B5 de que su Track B2 subió y el loop B4-B5 se extinguió.
* `10.0.0.14`/`10.0.0.13` (B4-B5) alcanzable solo cuando el arco este no flapea.
* Endpoint `/interbancaria` de Banco 2 sin implementar/validar.
* Banco 1 reporta residuals de config propia (`ip route 10.0.0.4` sin track) — su acción.

## Cambios recientes
* 2026-09-07 (1): flotantes sin track -> flotantes condicionadas a tracks 7/8; flotantes inertes eliminadas; `write memory`.
* 2026-09-07 (2, aprobado): primaria `10.0.0.16/30` de `track 5` a `track 1`; añadido `Null0 10.0.0.0/27` (AD 250); verificado traceroute a `.18` por el anillo; `write memory`.
* 2026-09-08 (3, aprobado - Paso 1): añadida ruta fija `ip route 10.0.0.8 255.255.255.252 10.0.0.6` para restablecer retorno hacia B4; verificado ping `.9` y `.10` 3/3; tracks 4/6/7 UP; `write memory`.

## Verificación global del anillo

Verificación 2026-09-07 (pre Paso 1) y 2026-09-08 (post Paso 1), desde R-WAN.

### Vecinos directos
* **IP vecino 1:** `10.0.0.1` (B1, FastEthernet2/0) — ping **5/5**, RTT 8-12 ms.
* **IP vecino 2:** `10.0.0.6` (B3, FastEthernet3/0) — ping **5/5**, RTT 28-48 ms.

### Redes alcanzables
* `10.0.0.0/30` — dest. `10.0.0.1` (B1): **alcanzable**. Conectada f2/0.
* `10.0.0.4/30` — dest. `10.0.0.6` (B3): **alcanzable**. Conectada f3/0.
* `10.0.0.8/30` — dest. `10.0.0.9` y `10.0.0.10`: **alcanzable (post Paso 1)**. Ruta fija AD1 via `10.0.0.6`. Traceroute: `10.0.0.6 -> 10.0.0.10`.
* `10.0.0.12/30` — dest. `10.0.0.13`/`10.0.0.14`: **fluctuante** (arco este flapeando; funciona cuando SLA3/track5 UP). Ruta primaria via `10.0.0.1` (track 5).
* `10.0.0.16/30` — dest. `10.0.0.17`/`10.0.0.18`: **alcanzable** via `10.0.0.1` (track 1). Traceroute a `.18`: 1 salto.

### Redes NO alcanzables
* `10.0.0.12/30` de forma **intermitente** (a `Null0`) por el flap del arco este (SLA3/track5); ningún descarte es por loop: todo cae al `Null0 /27`.

### Rutas activas / primarias / flotantes (estado RIB post Paso 1)
* **Activas relevantes:** `10.0.0.8/30 [1/0] via 10.0.0.6` (fija); `10.0.0.16/30 [1/0] via 10.0.0.1`; `10.0.0.0/27 → Null0 [250/0]`; `0.0.0.0/0 via 192.168.100.1`; `10.0.0.0/30` y `10.0.0.4/30` conectadas; `10.0.0.12/30` según estado del track 5.
* **Primarias:** `.8/30` via `10.0.0.6` (fija y trackeada, ambas activas); `.12/30` via `10.0.0.1` track 5 (DOWN en el último chequeo); `.16/30` via `10.0.0.1` track 1 (UP).
* **Flotantes:** `.8/30` via `10.0.0.1` AD 100 track 7 (UP — no se usa por AD); `.12/30` y `.16/30` via `10.0.0.6` AD 100 track 8 (DOWN); `Null0 /27` AD 250.
* **Rutas que devuelven tráfico al banco de origen:** **ninguna activa**.

### SLA / Tracks (post Paso 1)
| SLA | Destino / camino | Estado (éxitos/fallos) | Track | Coincide con realidad |
|---|---|---|---|---|
| 1 | `10.0.0.1` src f2/0 (B1 directo) | OK | 1 UP | ✔ B1 responde |
| 2 | `10.0.0.6` src f3/0 (B3 directo) | OK | 2 UP | ✔ B3 responde |
| 3 | `10.0.0.17` src f2/0 (B5 vía B1) | Flap (154/107) | 3 DOWN | ✗ intermitente: B5 responde a veces; cable este B1-B5 inestable |
| 4 | `10.0.0.10` src f3/0 (B4 vía B3) | OK | 4 UP | ✔ post Paso 1 |
| 5 | `10.0.0.10` src f2/0 (B4 vía B1) | OK | 7 UP | ✔ post Paso 1 (retorno de B4 convergido) |
| 6 | `10.0.0.17` src f3/0 (B5 vía B3) | Timeout | 8 DOWN | ✔ camino oeste hacia B5 no entrega |

### Posibles loops (failover teórico)
* **Correcto:** al caer una primaria, las flotantes no instaladas (track 8 DOWN) y `Null0 /27` descartan; no hay rebote al banco emisor ni fuga al ISP.
* **Loop B2↔B3 hacia `10.0.0.16/30`:** sin activar (track 8 DOWN + ruta fija `.8/30` apunta al dueño directo). B3 debiera condicionar su flotante a un track (coordinación pendiente).
* **Bucle B4↔B5 en `10.0.0.4/30`:** se origina por Track B2 de B4 en DOWN; con B2 respondiendo (Paso 1) debería extinguirse. **Pendiente de confirmación por B4/B5.**
* **Deadlock circular oeste:** **resuelto** desde B2 con la ruta fija a `10.0.0.8/30`.

### Servicios probados (solo TCP, sin transacciones)
* `10.0.0.1:80` y `:8080` (B1 portal/app): **Open**.
* `10.0.0.6:80` (B3 `/interbancaria`): sin respuesta desde B2 (candidato: FW de B3 no autoriza origen B2). PENDIENTE DE CONFIRMACIÓN POR BANCO 3.
* `10.0.0.13:8080` (B4 blacklist, este): **Open**.
* `10.0.0.10:8080` (B4 blacklist, oeste): ahora enrutable (Paso 1); prueba TCP no re-ejecutada.
* `10.0.0.17:8080` (B5): Connection refused (sin servicio en 8080).

### Problemas pendientes
1. Confirmar reactivación del Track B2 de B4 y extinción del loop B4-B5 (B4/B5).
2. Estabilizar arco este (SLA3/B5 vía B1, cable este B1-B5 intermitente).
3. B3 no abre TCP 80 al origen B2 (confirmar reglas FW/NAT).
4. `/interbancaria` de B2 por definir (publicación `10.0.0.2:5001` viva).

## Pendientes
* Confirmar con B4/B5 si Track B2 subió y el loop `10.0.0.4/30` desapareció.
* Coordinar estabilización del arco este (B1/B5).
* Confirmar servicio publicado (`10.20.1.34:5001`) y endpoint `/interbancaria`.

## Notas para otros bancos
* **Banco 3:** B2 ya enruta y responde `10.0.0.8/30` vía `10.0.0.6` (ruta fija). Confirmar si su SLA 2 y retorno a `.18` mejoran con el retorno de B4.
* **Banco 4:** esperamos que su Track B2 (sonda a `10.0.0.5`) pase a UP y restablezca primarias por `eth3`, eliminando el loop con B5. Por favor confirmar.
* **Banco 1/B5:** coordinar estabilización del cable este (SLA 3 flap de B2/tráfico B5 vía B1).