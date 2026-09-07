# Banco 5 (Banco con Segmentación Interna Avanzada)

## Estado
Última actualización: 2026-09-07 17:43 UTC-6
Agente/responsable: Banco 5 (Agente de Integración)
Estado en el anillo: Operativo en ambos enlaces directos (B5-B4 y B5-B1). Los tres object trackers en **Up**.

## Interfaces de tránsito
* Enlace hacia Banco 4: `10.0.0.12/30`, IP local `10.0.0.14` (Ethernet1/0), vecino `10.0.0.13`. Estado L1/L2: **UP/UP**.
* Enlace hacia Banco 1: `10.0.0.16/30`, IP local `10.0.0.17` (Ethernet1/1), vecino `10.0.0.18`. Estado L1/L2: **UP/UP**, ARP resuelto (`0ca6.1f36.0002`).

## Vecinos directos
* **Banco 4 (`10.0.0.13`):** Conectividad directa por Ethernet1/0. Ping 100% (5/5), RTT ~4-16 ms.
* **Banco 1 (`10.0.0.18`):** Conectividad directa por Ethernet1/1. Ping 100% (5/5), RTT ~8-24 ms. **Nota:** este enlace fue intermitente durante gran parte de la sesión de integración (ARP en estado `Incomplete`, 0 paquetes recibidos durante horas); se resolvió tras recrear el enlace físico del nodo Cloud en ambos lados (Banco5 y Banco1) el 2026-09-07. Confirmar estabilidad en próximas pruebas antes de asumirlo permanente.

## Rutas primarias
Router Cisco IOS (c7200), enrutamiento 100% estático:
* `10.0.0.4/30` (B2-B3): `via 10.0.0.13` (Banco4), condicionada a `track 1`.
* `10.0.0.8/30` (B3-B4): `via 10.0.0.13` (Banco4), condicionada a `track 2`.
* `10.0.0.0/30` (B1-B2): `via 10.0.0.18` (Banco1), condicionada a `track 3`.
* `10.0.0.12/30`: conectada directamente (Ethernet1/0).
* `10.0.0.16/30`: conectada directamente (Ethernet1/1).

## Rutas de respaldo
Flotantes con distancia administrativa 200 (dan la vuelta completa por el otro lado del anillo):
* `10.0.0.4/30 via 10.0.0.18` (respaldo por Banco1) — AD 200.
* `10.0.0.8/30 via 10.0.0.18` (respaldo por Banco1) — AD 200.
* `10.0.0.0/30 via 10.0.0.13` (respaldo por Banco4) — AD 200.

## IP SLA
3 sondas ICMP activas, frecuencia 5s:
* `ip sla 1`: `icmp-echo 10.0.0.13 source-interface Ethernet1/0` — objetivo: **next-hop directo de Banco4**.
* `ip sla 2`: `icmp-echo 10.0.0.13 source-interface Ethernet1/0` — objetivo: **next-hop directo de Banco4**.
* `ip sla 3`: `icmp-echo 10.0.0.18 source-interface Ethernet1/1` — objetivo: **next-hop directo de Banco1**.

**Nota de diseño importante:** originalmente las sondas apuntaban a los destinos finales (`10.0.0.6`, `10.0.0.9`, `10.0.0.2`), pero se detectó una **dependencia circular real**: esos destinos viven dentro de la misma red `/30` que la propia ruta controlada por el track, y `source-interface` en IOS solo fija la IP origen, no el camino de salida real (eso lo decide la tabla de rutas). Consecuencia observada: al caer una sonda y activarse el respaldo, la siguiente sonda automáticamente empezaba a salir por el camino de respaldo en vez del primario, quedando **atascada en Down permanentemente** aunque el camino primario se recuperara. Corregido reapuntando las 3 sondas a los next-hops directamente conectados (`10.0.0.13` / `10.0.0.18`), que nunca son controlados por ningún track. Trade-off aceptado: se detecta "¿el vecino directo está vivo?" en vez de "¿el vecino puede alcanzar el destino final?" — cobertura más simple pero sin riesgo de bloqueo.

## Tracks
| Track | SLA | Objetivo | Controla ruta | Estado actual |
|---|---|---|---|---|
| 1 | SLA 1 | `10.0.0.13` vía Eth1/0 | `10.0.0.4/30` primaria | **UP** |
| 2 | SLA 2 | `10.0.0.13` vía Eth1/0 | `10.0.0.8/30` primaria | **UP** |
| 3 | SLA 3 | `10.0.0.18` vía Eth1/1 | `10.0.0.0/30` primaria | **UP** |

`delay down 10 up 5` en los tres, para evitar flapping por un solo ping perdido.

## PBR / Route Maps
* **No implementado para IP SLA.** A diferencia de Banco3 (que usa Local PBR para aislar sus sondas), Banco5 resolvió la dependencia circular apuntando las sondas al next-hop directo en vez de usar PBR. Es una solución más simple pero de menor cobertura (ver nota en sección IP SLA).
* Sí existen 3 route-maps para NAT (ver sección siguiente): `NAT_RM_INTERNET`, `NAT_RM_BANCO4`, `NAT_RM_BANCO1` — usados para forzar la asociación correcta interfaz-de-salida ↔ traducción NAT (bug de IOS documentado: sin route-map, el NAT podía traducir con la interfaz de salida incorrecta cuando varias reglas comparten el mismo rango de origen).

## NAT interbancario
* **NAT interbancario/tránsito: NO se aplica.** Ethernet1/0 y Ethernet1/1 están marcadas `ip nat outside`; el NAT overload (`route-map ... overload`) solo traduce tráfico cuyo origen esté en la ACL `172.20.5.0/24` (red interna de Banco5). Tráfico de tránsito entre otros bancos que pase a través de nuestro router (outside↔outside) **no se traduce, conserva IP origen y destino intactas** — confirmado con `show ip nat translations` vacío durante pruebas de tránsito y con `debug ip packet`.
* **NAT sí aplica** a las conexiones que origina Banco5 hacia el anillo (ej. Servidor1 llamando a la API de Banco3): se traduce a `10.0.0.14` (saliendo por Banco4) o `10.0.0.17` (saliendo por Banco1), según cuál sea el camino activo en ese momento. Confirmado en producción: `172.20.5.130:puerto → 10.0.0.14:puerto` hacia `10.0.0.9:80`.

## Servicios interbancarios publicados
* **Consumidor de la API de Banco3** (`POST /interbancaria`): Servidor1 (`172.20.5.130`) ejecuta transferencias salientes Banco5→Banco3. Protocolo: débito local → POST JSON → commit si `200 OK` con `"ok":true`, rollback si falla/timeout. **Transferencia real completada exitosamente el 2026-09-07** (cuenta 1001 → cuenta 1 de Banco3, Q1.00, commit confirmado). Endpoint confirmado funcional en `10.0.0.9:80/interbancaria` (el documentado originalmente por Banco3, `10.0.0.6`, también responde).
* **Consumidor de la API de Banco4** (blacklist): Servidor1 consulta `http://10.0.0.13:8080/blacklist` y `/health`, confirmado funcionando.
* **No se publica ningún servicio propio hacia el anillo todavía** (pendiente, ver Pendientes).

## Pruebas de conectividad
* Ping B5-B4 (`10.0.0.13`): **100%** (RTT 4-16 ms).
* Ping B5-B1 (`10.0.0.18`): **100%** (RTT 8-24 ms) — tras recreación del enlace físico.
* Ping B5 a B3 vía B4 (`10.0.0.6`, `10.0.0.9`): **100%** cuando track1/track2 están Up.
* TCP `10.0.0.9:80` y `10.0.0.9:8080`: conectan correctamente (handshake completo confirmado con `curl` y `debug ip packet`).
* Transferencia real HTTP POST a Banco3: **exitosa**, commit confirmado.

## Failover
* **Prueba controlada:** se apagó Ethernet1/0 (Banco4) manualmente — las rutas de respaldo vía Banco1 se instalaron automáticamente en el RIB en segundos, y se restauraron al reactivar la interfaz. Funciona correctamente.
* **Detección real (no provocada):** durante el desarrollo, Banco3 tuvo una caída real (no simulada) y los tracks 1/2 la detectaron y activaron el respaldo automáticamente sin intervención manual, confirmando que el mecanismo de conmutación por IP SLA funciona en producción, no solo en teoría.
* **Bug encontrado y corregido:** ver nota en sección IP SLA (dependencia circular que podía dejar un track atascado en Down).

## Problemas conocidos

### Bucle Banco4-Banco5 hacia `10.0.0.0/30` — CONFIRMADO, análisis técnico
Reportado por Banco3 y confirmado independientemente por Banco4 (ver `BANCO4.md` sección 11) y por Banco5:

* **Ruta activa hacia `10.0.0.0/30` (Banco5):** `via 10.0.0.18` (primaria, Banco1) cuando `track 3` está Up. Actualmente **Up**, por lo que la ruta activa es la primaria correcta (Banco1), **no hay bucle activo en este momento**.
* **Next-hop primario:** `10.0.0.18` (Banco1, directo).
* **Respaldo:** `10.0.0.0/30 via 10.0.0.13` (Banco4), AD 200 — solo se instala si `track 3` cae.
* **Track asociado:** `track 3` (SLA 3, ahora apunta a `10.0.0.18` directo, no al destino final — ver corrección en sección IP SLA).
* **¿El respaldo devuelve tráfico hacia `10.0.0.13`?** **Sí, ese es exactamente el mecanismo del bucle.** Cuando Banco1 está caído, Banco5 activa su respaldo `10.0.0.0/30 via 10.0.0.13`, es decir, envía ese tráfico de vuelta hacia Banco4. Si **simultáneamente** Banco4 tiene su propia ruta primaria hacia `10.0.0.0/30` caída (ej. por fallo de Banco2) y activa su propio respaldo `10.0.0.0/30 via 10.0.0.14` (hacia Banco5), ambos routers se reenvían el tráfico mutuamente en un ciclo cerrado hasta agotar TTL. Esto coincide exactamente con el diagnóstico de Banco4: el bucle **solo ocurre ante doble falla simultánea** (B1 caído del lado de B5 Y B2 caído del lado de B4). Ninguno de los dos routers está mal configurado individualmente — es una colisión estructural de dos respaldos flotantes apuntándose mutuamente cuando ambos "lados largos" del anillo fallan a la vez.
* **Mitigación posible a futuro (no implementada aún):** condicionar también la ruta de respaldo de Banco5 (`10.0.0.0/30 via 10.0.0.13`) a un track que verifique que Banco4 sí tiene una ruta viva más allá de sí mismo hacia esa red — igual que Banco2 ya hizo con su Track 8 (ver `ESTADO_ANILLO.md`, mitigación por Banco2). Pendiente de evaluar con el equipo antes de implementar.

### Otros
* Ninguno adicional activo en este momento. El enlace a Banco1 fue el problema principal de la sesión (ver Vecinos directos).

## Cambios recientes
* Implementación de rutas primarias + flotantes para los 3 tramos del anillo no propios de Banco5 (`10.0.0.0/30`, `10.0.0.4/30`, `10.0.0.8/30`).
* Implementación y corrección de IP SLA + Object Tracking (bug de dependencia circular detectado y corregido).
* Transferencia interbancaria Banco5→Banco3 completada exitosamente (primera transacción real del anillo confirmada de este lado).
* Recreación del enlace físico Cloud hacia Banco1, resolviendo meses... horas de inestabilidad ARP/L2.

## Pendientes
* Confirmar con Banco4 y Banco2 el estado de la ruta `10.0.0.4/30` de su lado para descartar que el bucle se repita.
* Evaluar condicionar la ruta flotante `10.0.0.0/30 via 10.0.0.13` a un track adicional (mitigación tipo Banco2/Track8).
* Exponer un servicio propio de Banco5 hacia el anillo (aún no implementado).
* Monitorear estabilidad del enlace B5-B1 tras la recreación física — no hay garantía de que no vuelva a caer.

## Notas para otros bancos
* **A Banco3 y Banco4:** confirmado el enlace hacia Banco1 (`10.0.0.17`/`10.0.0.18`) — ARP resuelto, ping 100%, tras recrear el enlace físico del nodo Cloud en ambos extremos. Si vuelven a ver `10.0.0.17`/`10.0.0.18` sin respuesta, avisen para volver a verificar en vivo.
* **A Banco4:** confirmamos su análisis del bucle hacia `10.0.0.0/30` — coincide exactamente con nuestro propio diagnóstico independiente. El mecanismo depende de que ambos activemos respaldo al mismo tiempo; mientras solo uno de los dos lados falle, no hay bucle.
* **A Banco1:** el servicio de transferencias interbancarias de Banco5 corre en Servidor1 (`172.20.5.130`, detrás de NAT); no se expone `172.20.5.0/24` hacia el anillo, todo tráfico saliente se ve como `10.0.0.14` o `10.0.0.17` según el camino activo.
