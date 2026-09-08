# Banco 2 (Banca de inversión)

## Estado
Última actualización: 2026-09-08 (Paso 1 + primaria `10.0.0.12/30` con track 1)
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
ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 1    ! B5 vía B1 (AD 1) [2026-09-08: track 5 -> track 1]
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

## Tracks (estado 2026-09-08, durante drill del grupo)
```text
track 1 rtr 1 reachability   ! B1 directo               -> UP
track 2 rtr 2 reachability   ! B3 directo               -> UP
track 3 rtr 3 reachability   ! B5 vía B1                -> DOWN (B5 sin contestar ICMP)
track 4 rtr 4 reachability   ! B4 vía B3                -> DOWN (drill: B4-B3 cortado)
track 5 list boolean and (obj 1 y 3) ! B1 directo Y B5 vía B1 -> DOWN (sin rutas que lo referencien desde 2026-09-08)
track 6 list boolean and (obj 2 y 4) ! B3 directo Y B4 vía B3 -> DOWN (depende de obj 4)
track 7 rtr 5 reachability   ! B4 vía B1 (gate flotante .8/30) -> DOWN (drill)
track 8 rtr 6 reachability   ! B5 vía B3 (gate flotantes .12/30 y .16/30) -> DOWN
```
> Desde 2026-09-08 la primaria `.12/30` **ya no** depende de `track 5` (AND B1 + B5 vía B1): usa `track 1` (B1 directo). El anillo no tiene "entradas principales": ambas caras (f2/0 → B1 y f3/0 → B3) son entrada y salida y deben quedar listas siempre.

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

## Corrección de alcanzabilidad `10.0.0.12/30` (petición de Banco 4, 2026-09-08)

**Motivo (drill de B4: cable B4-B3 desconectado):** el tráfico de B4 hacia B2 da la vuelta por el este (B5 → B1 → B2) con IP de origen `10.0.0.13` (red `.12/30`). Con la primaria atada a `track 5` (que exigía B5 vía B1), la flake ICMP de B5 (`SLA 3`, hoy 0 éxitos) tumbaba el track 5 y B2 descartaba en `Null0` las respuestas hacia `.13` → el retorno del drill moría en B1 (`10.0.0.18`).

**CAMBIO (aplicado a R-WAN y persistido)**
- `no ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 5`
- `ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 1` (B1 directo)
- `write memory`

**DESPUÉS**
- RIB: `10.0.0.12/30 [1/0] via 10.0.0.1` (instalada; ya no cae a `Null0`).
- Razonamiento: el anillo no tiene "entrada principal"; ambas caras son entrada y salida y deben quedar preparadas. B2 conserva el arco este (B1↔B5) enrutable aun si B5 no contesta ICMP (B1 tiene `.12/30 via 10.0.0.17 track 2` con ARP vivo y escolta el retorno).
- Verificación limpia pendiente (el grupo sigue en drills; arcos este/oeste con tracks 3-8 DOWN en el momento del cambio).

**Coordinación requerida con Banco 1 (evitar rebote):** B1 conserva su flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` (`BANCO1.md`). Para que B2 confíe en B1 (`track 1`) sin riesgo de loop B1↔B2 cuando el enlace este de B1 (Gi0/2→B5) caiga a L2, **B1 debe eliminar o hundir esa flotante** (mismo criterio del fix v8.1 que ya aplicó a `.16/30`). Al aplicar B2 ya no existe ruta que lo devuelva al banco del que proviene, pero el rebote depende del comportamiento de B1.

## Pruebas de conectividad (2026-09-08; post Paso 1 y cambio `.12/30`, durante drill del grupo)
* `B1 directo (10.0.0.1)`: UP — track 1 UP.
* `B3 directo (10.0.0.6)`: UP — track 2 UP.
* `B4 vía B3 (10.0.0.9 / 10.0.0.10)`: UP en entorno estable (Paso 1); hoy DOWN por drill B4-B3 (track 4).
* `B4 vía B1 (10.0.0.10)`: DOWN hoy (track 7) — depende del arco este.
* `B5 vía B1 (10.0.0.17)`: **sin respuesta ICMP** (SLA 3 0 éxitos) — ya no afecta a `.12/30` (usa track 1).
* `B5 vía B3 (10.0.0.17)`: Timeout — track 8 DOWN (oeste hacia B5 no entrega).

## Failover
* Detección con IP SLA 1-6 + object tracking; primarias condicionadas a track (1, 6) y flotantes a track (7, 8). `.12/30` y `.16/30` usan `track 1` (B1 directo) desde 2026-09-08.
* **Protección final:** `Null0 /27` del anillo descarta `10.0.0.0/30`..`10.0.0.16/30` cuando no hay ruta más específica (sin fuga al ISP).
* Nunca se instalan rutas que devuelvan tráfico al banco del que proviene (flotantes a B3 condicionadas a track 8; ruta fija `10.0.0.8/30` apunta a B3, que es el dueño directo de esa red).
* **Dependencia pendiente del `.12/30`:** B1 debe retirar/hundir su flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` para que la confianza de B2 en B1 (`track 1`) no produzca rebote B1↔B2 si el enlace este de B1 (Gi0/2→B5) cae a L2.

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
* **`10.0.0.12/30` ya no depende del flap ICMP de B5 (RESUELTO en B2):** primaria con `track 1` (B1 directo), RIB `[1/0] via 10.0.0.1`. Pendiente validar el retorno del drill de B4 con el arco este sano.
* **Coordinación con B1:** retirar/hundir su flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` (evita rebote B1↔B2 si cae el enlace este de B1).
* **Lado este inestable (raíz):** B5 no contesta ICMP de forma sostenida (también reportado por B1: `.17`/`.13` en 0%). PENDIENTE DE CONFIRMACIÓN POR BANCO 5.
* `10.0.0.8/30`: **RESUELTO** en B2 (ruta fija via B3). Confirmación de B4/B5 del loop B4-B5 extinguido: registrada en ESTADO_ANILLO.
* Endpoint `/interbancaria` de Banco 2 sin implementar/validar.
* Banco 1 reporta residuals de config propia ya limpiados en v8.1 (wrap `.16/30` y ruta `.4/30` sin track) — su acción.

## Cambios recientes
* 2026-09-07 (1): flotantes sin track -> flotantes condicionadas a tracks 7/8; flotantes inertes eliminadas; `write memory`.
* 2026-09-07 (2, aprobado): primaria `10.0.0.16/30` de `track 5` a `track 1`; añadido `Null0 10.0.0.0/27` (AD 250); verificado traceroute a `.18` por el anillo; `write memory`.
* 2026-09-08 (3, aprobado - Paso 1): añadida ruta fija `ip route 10.0.0.8 255.255.255.252 10.0.0.6` para restablecer retorno hacia B4; verificado ping `.9` y `.10` 3/3; tracks 4/6/7 UP; `write memory`.
* 2026-09-08 (4, aprobado - petición de Banco 4): primaria `10.0.0.12/30` de `track 5` a `track 1` (el retorno del drill de B4 no debe depender del ICMP de B5); verificado RIB `[1/0] via 10.0.0.1`; `write memory`. Coordinación pendiente: B1 retirar su flotante `.12/30 via 10.0.0.2`.

## Verificación global del anillo

Verificación 2026-09-07 (pre Paso 1) y 2026-09-08 (post Paso 1), desde R-WAN.

### Vecinos directos
* **IP vecino 1:** `10.0.0.1` (B1, FastEthernet2/0) — ping **5/5**, RTT 8-12 ms.
* **IP vecino 2:** `10.0.0.6` (B3, FastEthernet3/0) — ping **5/5**, RTT 28-48 ms.

### Redes alcanzables
* `10.0.0.0/30` — dest. `10.0.0.1` (B1): **alcanzable**. Conectada f2/0.
* `10.0.0.4/30` — dest. `10.0.0.6` (B3): **alcanzable**. Conectada f3/0.
* `10.0.0.8/30` — dest. `10.0.0.9` y `10.0.0.10`: **alcanzable (post Paso 1)**. Ruta fija AD1 via `10.0.0.6`. Traceroute: `10.0.0.6 -> 10.0.0.10`.
* `10.0.0.12/30` — dest. `10.0.0.13`/`10.0.0.14`: **enrutable siempre** via `10.0.0.1` (track 1) desde 2026-09-08; la entrega real depende del arco este (B1↔B5) y de B5. Ruta primaria AD 1.
* `10.0.0.16/30` — dest. `10.0.0.17`/`10.0.0.18`: **alcanzable** via `10.0.0.1` (track 1). Traceroute a `.18`: 1 salto.

### Redes NO alcanzables
* `10.0.0.12/30`: la ruta ya **no** cae a `Null0` (track 1). Solo resulta inalcanzable cuando B1 (`.1`) no está, o cuando la cadena B1→B5 no entrega (dependencia de B5, raíz del drill).
* Ningún descarte es por loop propio: sin rutas que devuelvan tráfico al banco de origen; todo lo no enrutable cae al `Null0 /27`.

### Rutas activas / primarias / flotantes (estado RIB post Paso 1)
* **Activas relevantes:** `10.0.0.8/30 [1/0] via 10.0.0.6` (fija); `10.0.0.12/30 [1/0] via 10.0.0.1` (track 1); `10.0.0.16/30 [1/0] via 10.0.0.1`; `10.0.0.0/27 → Null0 [250/0]`; `0.0.0.0/0 via 192.168.100.1`; `10.0.0.0/30` y `10.0.0.4/30` conectadas.
* **Primarias:** `.8/30` via `10.0.0.6` (fija y trackeada, ambas activas); `.12/30` via `10.0.0.1` track 1 (UP); `.16/30` via `10.0.0.1` track 1 (UP).
* **Flotantes:** `.8/30` via `10.0.0.1` AD 100 track 7 (UP — no se usa por AD); `.12/30` y `.16/30` via `10.0.0.6` AD 100 track 8 (DOWN); `Null0 /27` AD 250.
* **Rutas que devuelven tráfico al banco de origen:** **ninguna activa**.

### SLA / Tracks (post Paso 1)
| SLA | Destino / camino | Estado (éxitos/fallos) | Track | Coincide con realidad |
|---|---|---|---|---|
| 1 | `10.0.0.1` src f2/0 (B1 directo) | OK | 1 UP | ✔ B1 responde |
| 2 | `10.0.0.6` src f3/0 (B3 directo) | OK | 2 UP | ✔ B3 responde |
| 3 | `10.0.0.17` src f2/0 (B5 vía B1) | Timeout (0 éxitos) | 3 DOWN | ✗ B5 no contesta ICMP; ya **no** gobierna `.12/30` (track 1) |
| 4 | `10.0.0.10` src f3/0 (B4 vía B3) | seg. drill | 4 DOWN | drill B4-B3 en curso |
| 5 | `10.0.0.10` src f2/0 (B4 vía B1) | seg. drill | 7 DOWN | drill arco este en curso |
| 6 | `10.0.0.17` src f3/0 (B5 vía B3) | Timeout | 8 DOWN | ✔ camino oeste hacia B5 no entrega |

### Posibles loops (failover teórico)
* **Correcto:** al caer una primaria, las flotantes no instaladas (track 8 DOWN) y `Null0 /27` descartan; no hay rebote al banco emisor ni fuga al ISP.
* **Loop B2↔B3 hacia `10.0.0.16/30`:** sin activar (track 8 DOWN + ruta fija `.8/30` apunta al dueño directo). B3 debiera condicionar su flotante a un track (coordinación pendiente).
* **Bucle B4↔B5 en `10.0.0.4/30`:** registrado como extinguido por B3/B4/B5 en ESTADO_ANILLO tras el Paso 1.
* **Rebote B1↔B2 hacia `10.0.0.12/30` (por coordinar):** si el enlace este de B1 (Gi0/2→B5) cae a L2, la flotante vigente de B1 `10.0.0.12/30 via 10.0.0.2 20 track 1` devolvería el paquete a B2, que con `track 1` lo reenviaría a B1 (loop). Evitable retirando/hundiendo esa flotante en B1.
* **Deadlock circular oeste:** **resuelto** desde B2 con la ruta fija a `10.0.0.8/30`.

### Servicios probados (solo TCP, sin transacciones)
* `10.0.0.1:80` y `:8080` (B1 portal/app): **Open**.
* `10.0.0.6:80` (B3 `/interbancaria`): sin respuesta desde B2 (candidato: FW de B3 no autoriza origen B2). PENDIENTE DE CONFIRMACIÓN POR BANCO 3.
* `10.0.0.13:8080` (B4 blacklist, este): **Open**.
* `10.0.0.10:8080` (B4 blacklist, oeste): ahora enrutable (Paso 1); prueba TCP no re-ejecutada.
* `10.0.0.17:8080` (B5): Connection refused (sin servicio en 8080).

### Problemas pendientes
1. Coordinar con B1 la retirada de su flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` (B2 ya confía en `track 1`).
2. Estabilizar la respuesta ICMP de B5 (raíz del tapón del drill de B4; B1 reporta `.17`/`.13` en 0%).
3. B3 no abre TCP 80 al origen B2 (confirmar reglas FW/NAT).
4. `/interbancaria` de B2 por definir (publicación `10.0.0.2:5001` viva).
5. Revalidar, con el anillo estable, el drill de B4 y el retorno `10.0.0.12/30`.

## Pendientes
* Coordinar con B1 la retirada de su flotante `10.0.0.12/30 via 10.0.0.2` (B2 ya confía en `track 1`).
* Revalidar, con el anillo estable, el drill de B4 y el retorno `10.0.0.12/30` por el arco este.
* Confirmar estabilización de la respuesta ICMP de B5 (B1/B5).
* Confirmar servicio publicado (`10.20.1.34:5001`) y endpoint `/interbancaria`.

## Mensajes / peticiones para otros bancos (2026-09-08)

### → Banco 4 (solicitante del cambio)
Aplicado en R-WAN el retorno que pediste:
```
no ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 5
ip route 10.0.0.12 255.255.255.252 10.0.0.1 track 1
write memory
```
* **Qué:** la primaria `10.0.0.12/30` pasó de depender de `track 5` (AND "B1 vivo **y** B5 vía B1") a depender solo de `track 1` (B1 directo). Verificado: RIB `10.0.0.12/30 [1/0] via 10.0.0.1` (instalada, ya no cae a `Null0`).
* **Por qué:** en tu drill del cable B4-B3, tu tráfico da la vuelta por el este (B5 → B1 → B2) con origen `10.0.0.13`. Como B5 no responde ICMP de forma sostenida, el track 5 se caía y B2 descartaba tus respuestas en `Null0` → el retorno moría en B1. El track 1 solo exige a B1, el vecino directo por donde vuelve tu tráfico.
* **Por qué es la solución correcta:** el anillo no tiene "entradas principales"; cada cara es entrada y salida y debe quedar lista siempre. Dejar el retorno de `10.0.0.12/30` rehén del ICMP de un nodo lejano viola ese principio. Con track 1, B1 escolta el retorno con su propia tabla (`10.0.0.12/30 via 10.0.0.17 track 2` + ARP vivo), sin depender de que B5 conteste ping.
* **Solicitud:** re-probar con el anillo estable que el traceroute a `10.0.0.5` complete los 4 saltos (`.14 → .18 → .2 → .5`).

### → Banco 1 (acción solicitada)
* **Qué:** `10.0.0.12/30` en B2 pasó de `track 5` a `track 1` (B1 directo), por petición de B4. Confirmé tu config: `10.0.0.12/30 via 10.0.0.17 track 2` con Gi0/2 UP y ARP vivo, así que puedes escoltar el retorno del drill de B4 aunque B5 no conteste ICMP. Es el mismo criterio que ya usa `.16/30`.
* **Por qué:** tu diagnóstico era correcto: el tapón del drill de B4 era el `track 5` de B2 (AND B1 + B5-vía-B1), rehén de la flake ICMP de B5. Lo corrijo dejando la ruta dependiente solo del vecino directo (B1).
* **Por qué es la solución correcta:** es el cambio mínimo que arregla el retorno de B4 **sin tocar** tus rutas, sin Null0, sin SLAs nuevos y sin loops. Ambas caras del anillo quedan listas permanentemente.
* **Tu parte (para dejarla a prueba de rebotes):** retirar/hundir tu flotante
  ```
  no ip route 10.0.0.12 255.255.255.252 10.0.0.2 20 track 1
  ```
  Si tu enlace este (Gi0/2 → B5) cae a L2 con la config actual, esa flotante devuelve `.12/30` a B2, y B2 (con track 1) se lo regresa a ti → **rebote B1↔B2**. Es el mismo mecanismo del loop que ya eliminaste en v8.1 con el wrap `.16/30`. Con tu línea fuera, en caída este el paquete muere en tu router con ICMP unreachable y el anillo nunca devuelve tráfico a su origen.

### → Banco 5 (causa raíz)
* **Qué:** B2 cambió `10.0.0.12/30` de `track 5` (AND B1 + B5-vía-B1) a `track 1` (B1 directo). Este cambio **enmascara** la causa raíz: tu nodo no responde ICMP de forma sostenida (`10.0.0.17`/`.14`), y eso tumbaba el track de B2, que descartaba el retorno hacia `10.0.0.13` en `Null0` — rompiendo el drill del retorno este.
* **Por qué conviene:** el anillo entrega IP + ARP vivo pero no contesta sondas (B1 reporta 0% a `.17`, IP SLA 4/5 sin éxitos pese a Link UP). Dejar el retorno de un segmento dependiente de tu ICMP no es sostenible.
* **Solicitud:** estabilizar la respuesta ICMP en `10.0.0.17` y `10.0.0.14` (revisar rate-limit/ACL/forward, o el retorno de tus respuestas cayendo a otra ruta). Con tu ICMP estable se desbloquea de raíz el tramo este y los tracks del grupo dejan de flapear.

### → Banco 3 (coordinador)
Para tu consolidación de ESTADO_ANILLO:
* **Cambio B2 (2026-09-08):** primaria `10.0.0.12/30` de `track 5` (AND B1 + B5-vía-B1) a `track 1` (B1 directo), petición de B4 para el retorno de su drill. Verificado RIB `[1/0] via 10.0.0.1`, persistido.
* **Impacto matriz:** `.12/30` ahora siempre enrutable desde B2 por B1. Para que sea a prueba de rebotes, B1 debe retirar su flotante `10.0.0.12/30 via 10.0.0.2 20 track 1` (misma lógica que su fix v8.1 de `.16/30`) — ya se lo solicitó. Pedido: reflejar ambos puntos (cambio B2 + acción pendiente B1) en la consolidación.
* **Contexto adicional:** B2 ya enruta y responde `10.0.0.8/30` vía `10.0.0.6` (ruta fija, Paso 1).