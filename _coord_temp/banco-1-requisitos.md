# Documentación Técnica y Requisitos Interbancarios - Banco 1

Documento técnico oficial de arquitectura, enrutamiento, seguridad y alta disponibilidad de **Banco 1 (Banca minorista con sucursales)** frente a los otros cuatro bancos del sistema en el anillo interbancario de 5 entidades. Datos de la configuración canónica vigente **v8.6** (persistida en config-disk master `IOSv_startup_config.img`).

---

## 1. Routing Interbancario (Estático y Failover)

### Tabla de Rutas Estáticas Interbancarias

| Ruta Principal / Alternativa | Destino (Red/IP) | Próximo Salto (Next-Hop) | Interfaz de Salida | Métrica / Prioridad | Estado / Comentarios |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Conectada (Directa)** | `10.0.0.0/30` (Enlace B1-B2) | Directamente conectada | `Gi0/1` | Métrica 0 (Conectada) | **Activa:** Enlace Oeste con Banco 2. `ip nat outside`. |
| **Conectada (Directa)** | `10.0.0.16/30` (Enlace B5-B1) | Directamente conectada | `Gi0/2` | Métrica 0 (Conectada) | **Activa:** Enlace Este con Banco 5. `ip nat outside`. |
| **Primaria** | `10.0.0.4/30` (Enlace B2-B3) | `10.0.0.2` (Banco 2) | `Gi0/1` | **AD 1 + track 10** (E2E hop-2 sla2 → `10.0.0.6`) | **Activa:** Camino por el arco corto Oeste. |
| **Primaria** | `10.0.0.8/30` (Enlace B3-B4) | `10.0.0.2` (Banco 2) | `Gi0/1` | **AD 1 + track 10** (idem) | **Activa:** Tránsito B1→B2→B3→B4 verificado (traceroute `.10` completa). |
| **Primaria** | `10.0.0.12/30` (Enlace B4-B5) | `10.0.0.17` (Banco 5) | `Gi0/2` | **AD 1 + track 20** (E2E hop-2 sla5 → `10.0.0.13`) | **Activa:** Camino por el arco corto Este. |
| **Flotante (Alternativa)** | `10.0.0.4/30` (Enlace B2-B3) | `10.0.0.17` 20 (Banco 5) | `Gi0/2` | **AD 20 + track 2** (línea Gi0/2) | **Standby:** Pliega el anillo por el arco largo Este ante caída del Oeste. |
| **Flotante (Alternativa)** | `10.0.0.8/30` (Enlace B3-B4) | `10.0.0.17` 20 (Banco 5) | `Gi0/2` | **AD 20 + track 2** (línea Gi0/2) | **Standby:** Respaldo vía B5. |
| **Flotante (Alternativa)** | `10.0.0.12/30` (Enlace B4-B5) | `10.0.0.2` 20 (Banco 2) | `Gi0/1` | **AD 20 + track 1** (línea Gi0/1) | **Standby:** Respaldo vía B2 ante caída del Este. |
| **Flotante (Alternativa)** | `10.0.0.0/30` (Enlace B1-B2, propio) | `10.0.0.17` 20 (Banco 5) | `Gi0/2` | **AD 20 + track 2** (línea Gi0/2) | **Standby:** Wrap del propio segmento Oeste por el Este. |
| **Default** | `0.0.0.0/0` (Internet Real) | `192.168.122.1` | `Gi0/0` | AD 1 | **Activa:** Salida pública (DHCP `192.168.122.237`) con PAT. |
| **Interna** | `172.16.0.0/16` (LAN Banco 1) | `10.10.2.2` (FW interno) | `Gi0/3` | AD 1 | **Activa:** Enlace hacia Firewall interno (`ip nat inside`). |

**Nota antiloop (v8.1):** se eliminó el wrap `10.0.0.16/30 via 10.0.0.2 20 track 1` (wrap del propio segmento Este por el Oeste). En fallo del Este generaba loop B1↔B2: B1 reenviaba `.16/30` a B2 y B2 lo devolvía incesantemente (su track solo exigía a B1 vivo).

---

### Mecanismo de Recuperación (Failover)

- **Enrutamiento 100% estático** (sin protocolos dinámicos, conforme al enunciado). Cada segmento lejano del anillo tiene **primaria por el arco corto (AD 1)** y **flotante por el arco largo (AD 20)** que pliega el anillo.
- **Supervisión End-to-End hop-2 (vecino-del-vecino):**
  - **IP SLA 2** → `10.0.0.6` (Banco 3, vía B2), `source-interface Gi0/1` (origen `10.0.0.1`) → gobierna **track 10** → primarias de `.4/30` y `.8/30`.
  - **IP SLA 5** → `10.0.0.13` (Banco 4, vía B5), `source-interface Gi0/2` (origen `10.0.0.18`) → gobierna **track 20** → primaria de `.12/30`.
  - Frecuencia 5 s, timeout 5000 ms. Histéresis de tracks: `delay down 10 up 5` (tolerante a la flake ICMP de B5).
- **Anclaje de sondas con Local PBR (v8.4), sin rutas `/32`:**
  - ACLs `ACL-SLA-B2-B3` (src `10.0.0.1` → dst `10.0.0.6`) y `ACL-SLA-B5-B4` (src `10.0.0.18` → dst `10.0.0.13`), route-map `RM-LOCAL-SLA` (`set ip next-hop 10.0.0.2` / `10.0.0.17`) e `ip local policy route-map RM-LOCAL-SLA`.
  - **POR QUÉ NO `/32` (v8.3→v8.4):** la ruta fija `/32` por longest-prefix-match secuestraba **todo** el tráfico a la IP exacta del salto 2, no solo la sonda. Comprobado en drill real: con track 20 Down y la flotante `.12/30→10.0.0.2` activa, `ping 10.0.0.13` seguía saliendo por el Este y moría. Con Local PBR, el tráfico real sigue las `/30` con track y conmuta correctamente.
- **Observación del anillo (v8.2):** 5 IP SLAs adicionales (echo 5 s a `.2`/`.6`/`.10`/`.17`/`.13`) monitorizando cada tramo (tracks 3-7 solo observación, sin control de rutas). 5 applets **EEM** `RING_SEG_B1-B2`, `RING_SEG_B2-B3`, `RING_SEG_B3-B4`, `RING_SEG_B1-B5`, `RING_SEG_B4-B5` (evento `track state any`) que registran syslog `%HA_EM-6-LOG: RING_SEG_<SEG>: RING SEG <SEG> track=up|down` ante cada transición.
- **Tracks de soporte de flotantes:** `track 1` (line-protocol `Gi0/1`) y `track 2` (line-protocol `Gi0/2`) gobiernan las flotantes AD 20. Limitación conocida: line-protocol no detecta vecino "muerto en caliente" con L1/L2 sano (caso histórico B5), mitigada por los tracks E2E 10/20.
- **Persistencia:** config canónica **v8.6** en `IOSv_startup_config.img` (master + overlay del nodo), validadas con rearranques limpios (`%CVAC-7-CONFIG_FOUND` + `%CVAC-4-CONFIG_DONE`, 0 `%PARSER`). config-md5 `65319e7291b5076649a2f2a26e78e3ef`, imagen-md5 `ba842bcce419ac76439bf6ca3e94bc8b`.

---

### Pruebas de Fallo Controlado

- **Drill real v8.3 (corte B5-B4, 2026-09-08):**
  - **Tiempo de recuperación:** ~10–15 s (detección por track 20 = IP SLA hop-2 con `delay down 10`, `frequency 5`).
  - **Ruta antes del fallo:** `10.0.0.12/30 via 10.0.0.17` (AD 1, `Gi0/2`) — arco corto Este.
  - **Ruta después del fallo:** `10.0.0.12/30 via 10.0.0.2` (AD 20, `Gi0/1`) — arco largo Oeste.
  - **Cambios en tablas de routing:** con la plantilla original (`/32` de ancla) la RIB retenía la `10.0.0.13/32 via 10.0.0.17` y **no conmutaba** el tráfico real a la IP exacta (longest-prefix). **Corregido en v8.4 con Local PBR**; la `10.0.0.13` queda libre en las rutas `/30` y la conmutación es limpia (`show ip route 10.0.0.13` = `/30`, no `/32`; contadores `show route-map RM-LOCAL-SLA` creciendo).
  - **Pérdida de paquetes:** solo durante la ventana de detección del corte; tras v8.4 la conmutación es limpia. **Re-drill coordinado pendiente** (requiere aprobación para cortes de 30 s por lado y coordinación grupal).
- **Drill de Banco 4 (corte B4-B3, 2026-09-08 ~03:00):** traceroute B4→`10.0.0.5` muere en `10.0.0.18` por **retorno ausente en Banco 2** hacia `10.0.0.12/30` (su track 5 heredaba la flake ICMP de B5) — **no es fallo de B1**; B1 reenvió el arco Oeste al 100% (`sla1/2 → .2/.6` OK).

---

## 2. Seguridad Interbancaria y Políticas de Comunicación

### Matriz de Comunicación (con los otros 4 bancos)

| Banco Destino | Servicios Permitidos | Servicios Bloqueados | Puertos Autorizados | Tráfico Restringido / Observaciones |
| :--- | :--- | :--- | :--- | :--- |
| **Banco 2** (`10.0.0.2` / `.5`) | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito del anillo<br>• Entrante B2→B1: portal `10.0.0.1:80` y blacklist `10.0.0.1:8080`<br>• Saliente B1→B2: `10.0.0.2:5001` (transferencia interbancaria) | • SSH (22)<br>• Resto de puertos del anillo | • `TCP / 80`<br>• `TCP / 8080`<br>• `TCP / 5001` (saliente, pendiente confirmación)<br>• `ICMP` | 8080 permitido para B2 en el FW interno (RAW no lo bloquea). Saliente B1→`10.0.0.2:5001` **PENDIENTE DE CONFIRMACIÓN** (depende de FORWARD del FW interno hacia el anillo). |
| **Banco 3** (`10.0.0.6`) | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito del anillo<br>• `POST /interbancaria` entrante en `10.0.0.1:80` (verificado por B3 con `400 JSON_INVALIDO` ante payload inválido) | • SSH (22)<br>• **TCP 8080 bloqueado en FW interno** para orígenes B3 (`10.0.0.6`) | • `TCP / 80`<br>• `ICMP` | Regla RAW del FW interno deniega 8080 a B3/B4; acceso solo para B2/B5. |
| **Banco 4** (`10.0.0.10` / `.13`) | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito del anillo<br>• Entrante B4→B1: portal `10.0.0.1:80`<br>• Saliente B1→B4: consulta blacklist de B4 en `10.0.0.13:8080`/`10.0.0.10:8080` (Open verificado) | • SSH (22)<br>• **TCP 8080 bloqueado en FW interno** para orígenes B4 (`10.0.0.10`/`.13`) | • `TCP / 80` entrante<br>• `TCP / 8080` saliente hacia B4<br>• `ICMP` | — |
| **Banco 5** (`10.0.0.17` / `.14`) | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito del anillo<br>• Blacklist redundante publicada en la cara Este `10.0.0.18:8080` + portal `10.0.0.1:80` | • SSH (22)<br>• Resto de puertos | • `TCP / 80`<br>• `TCP / 8080`<br>• `ICMP` | B5 consume blacklist de B1; B5 no publica servicios propios. Respuesta ICMP estable en última validación (tracks 6/7/20 Up). |

### Evidencias de Políticas Aplicadas

#### A) NAT de publicación (Router-salida, `show ip nat translations`)
```text
tcp  10.0.0.1:80    172.16.30.5:80    ---  ---   (portal + POST /interbancaria)
tcp  10.0.0.1:8080  172.16.30.6:8080  ---  ---   extendable (blacklist Oeste)
tcp  10.0.0.18:8080 172.16.30.6:8080  ---  ---   extendable (blacklist Este, redundante)
```
- PAT saliente a Internet: ACL 100 (`172.16.0.0/16`, `10.10.2.0/30`) → `interface Gi0/0 overload`; ACL 101 (`172.16.0.0/16`) → `interface Gi0/1 overload`.
- Interfaces: `Gi0/0`, `Gi0/1`, `Gi0/2` = `ip nat outside`; `Gi0/3` = `ip nat inside`.
- **Nota IOSv (técnica validada):** no se pueden publicar dos servicios del mismo `inside local` con la forma `interface X` (el segundo descarta al primero). Se usan globales explícitos + `extendable` (técnica de BANCO3), que sostiene ambos globales en paralelo.

#### B) Firewall interno (`10.10.2.2`, iptables/nftables)
```text
CHAIN FORWARD  policy DROP
  ACCEPT tcp  -i eth2 -s 10.0.0.0/24 --dports 80,8080   (tránsito anillo hacia servicios publicados)
  DROP   all  -i eth2 -dst 10.0.0.0/24                  (cierra tránsito entrante a las /30 del anillo)
  ACCEPT all  eth0 -> eth2                               (LAN sede → anillo, con NAT de origen)
  ACCEPT all  eth1 -> eth2                               (LAN sucursal → anillo)
  ACCEPT RELATED,ESTABLISHED
PREROUTING/NAT
  DNAT eth2 dpt 80   -> 172.16.30.5:80    (portal)
  DNAT eth2 dpt 8080 -> 172.16.30.6:8080  (blacklist)
CHAIN RAW
  DROP 8080 para orígenes B3/B4 (10.0.0.6/.9/.13/.14)   (blacklist solo B2/B5)
  REDIRECT TCP/UDP 53 -> dnsmasq local
```
- Corrección aplicada y persistida (2026-09-08): eliminación de IPs residuales `10.0.0.1/30` y `10.0.0.18/30` en `eth2` del FW (creaban rutas connected fantasma que hacían ARP directo por el enlace equivocado y tiraban el retorno de la blacklist). `start_command` del node blindado con limpieza defensiva + imagen docker `firewall-banco1:clean`.

#### C) Política SSH (administración, no interbancaria)
- Solo los PC de administración pueden originar SSH: `172.16.20.4` (sede, a todo el banco) y `172.16.50.3` (sucursal, solo a sucursal). ACL `SSH-ADMIN` por host exacto + ACLs L3 por segmento (`SSH-L3-SEDE`/`SSH-L3-SUC`) + `access-class` en vty. **El anillo interbancario no origina SSH** (denegado).

#### D) Evidencia real de tráfico permitido/bloqueado
- **Permitido:** curls de Banco 2 a `http://10.0.0.1:8080/api/blacklist` con handshake completo `SYN→SYN-ACK→ACK→GET→HTTP/1.0 200 OK→FIN` (tcpdump en eth2+eth0 del FW, 3 peticiones). Contrato verificado: `GET /api/blacklist` → `{"lista_negra_clientes": [...], "total": 6}`.
- **Bloqueado:** payload de prueba de Banco 3 a `POST /interbancaria` → `400 JSON_INVALIDO` (acceso NO autorizado a operación sin payload válido); puertos de gestión cerrados desde el anillo.

---

## 3. Alta Disponibilidad y Resiliencia

### Caminos Principales y Alternativos

La arquitectura física y lógica conforma un anillo continuo cerrado de cinco nodos:
`[Banco 1] ↔ [Banco 2] ↔ [Banco 3] ↔ [Banco 4] ↔ [Banco 5] ↔ [Banco 1]`

| Escenario Operativo | Destino | Camino Principal (Ruta Nominal) | Camino de Respaldo (Ruta de Failover) | Mecanismo de Activación |
| :--- | :--- | :--- | :--- | :--- |
| **Corte en arco Este** (B4-B5 / `10.0.0.12/30`) | **Banco 4/5 (`10.0.0.13`)** | `B1 → B5 → B4` (2 saltos) | `B1 → B2 → B3 → B4` (3 saltos) | Track 20 DOWN (SLA 5 a `.13` no alcanza vía B5) → flotante `10.0.0.12/30 via 10.0.0.2 AD 20`. |
| **Corte en arco Oeste** (B2-B3 / `.4` y `.8`) | **Banco 3/4 (`10.0.0.6`)** | `B1 → B2 → B3` (2 saltos) | `B1 → B5 → B4 → B3` (3 saltos) | Track 10 DOWN (SLA 2 a `.6` no alcanza vía B2) → flotantes `.4/.8 via 10.0.0.17 AD 20`. |
| **Corte del propio enlace Oeste** (`10.0.0.0/30`) | **Banco 2 (`10.0.0.2`)** | `B1 → B2` (directo) | `B1 → B5 → B4 → B3 → B2` (4 saltos) | Track 1 DOWN → wrap `10.0.0.0/30 via 10.0.0.17 AD 20`. |
| **Caída de vecino con L1/L2 sano** (histórico B5) | **Banco 5 (`10.0.0.17`)** | `B1 → B5` (directo) | `B1 → B2 → B3 → B4 → B5` (4 saltos) | Detectado por **E2E hop-2** (track 20 / SLA 5 a `.13`, no por línea); mitiga la limitación "muerto en caliente". |
| **Servicio blacklist aislado de un lado** | — | `10.0.0.1:8080` (Oeste) | `10.0.0.18:8080` (Este) | Publicación **redundante en ambas caras** (global + `extendable`); ante caída de un arco el servicio persiste por el otro. |

### Resiliencia y Mitigación de Bucles de Enrutamiento

1. **Arquitectura de anillo con failover escalonado:** primarias AD 1 por el arco corto, flotantes AD 20 con track por el arco largo. Sin entradas "primarias" propias: cada segmento alcanzable solo por arco corto y, si cae su track, vira por el arco contrario plegando el anillo.
2. **Flotantes con track (no ciegas):** evita flotantes hacia enlaces muertos (más seguras que las flotantes sin track de la plantilla original de la guía grupal).
3. **Antiloops verificados:**
   - Wrap `10.0.0.16/30 via 10.0.0.2 20` eliminado (loop B1↔B2 en fallo del Este).
   - Ningún next-hop de B1 reenvía tráfico al banco del que proviene (los nexthops flotantes apuntan al arco opuesto).
   - Residual `10.0.0.4 via 10.0.0.2` sin track eliminado (v8.1).
   - Bucle B4-B5 en `10.0.0.4/30` extinguido por el grupo (causa y corrección en `ESTADO_ANILLO.md`).
4. **Monitoreo vectorizado:** tracks 1-2 (línea) sostienen flotantes; tracks 3-7 (IP SLA) observan cada tramo; tracks 10/20 (E2E hop-2) gobiernan redundancia. EEM registra cada transición para auditoría.
5. **Persistencia completa:** rutas, NAT, IP SLA, tracks, PBR y EEM viven en `IOSv_startup_config.img` (v8.6). Validadas con rearranques reales del nodo (`%CVAC-4-CONFIG_DONE`, interfaces UP, tracks 10/20 UP, RIB correcta).