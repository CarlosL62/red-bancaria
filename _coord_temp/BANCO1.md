# Banco 1 (Banca minorista con sucursales)

## Estado
Última actualización: 2026-09-09 (config v8.6 persistida: **política SSH refinada host-based "solo PCs admin"** — ACLs por host exacto + password de gestión rotado + cliente SSH verificado en ambos PCs admin + configuración persistida en config-disk master `IOSv_startup_config.img` v8.6 y validada con rearranque real del nodo). **Cajas de caja operativas con Firefox y usuario OS `admin` (sede `.10.4` y sucursal `.40.3`)** — re-imagen de la sucursal a TC6+Firefox y endurecimiento de la imagen sede (identidad autocontenida). Sin cambios de red (NAT/rutas/tracks/servicios intactos).
Agente/responsable: Agente Banco 1

## Política de acceso SSH (SOLO PCs de administración) — REFINADA y APLICADA 2026-09-09

### Regla aprobada por el usuario (refinamiento host-based, 2026-09-09)
* **Solo los PCs admin pueden originar SSH**: PC de administración de sede `172.16.20.4` (admin-sede) → SSH a **todo el banco** (sede + sucursal + Router-salida).
* PC de administración de sucursal `172.16.50.3` (admin-sucursal) → SSH **solo a su propia sucursal** (caja `172.16.40.0/28`, Router-sucursal-1 `172.16.50.1`, Switch-sucursal-1 `172.16.50.10`).
* **Ninguna otra fuente puede originar SSH**: routers, cajas, servidores, redes interbancarias → DENEGADO. La regla sustituye a la versión anterior por redes `172.16.20.0/24`/`172.16.50.0/24`; ahora es por **host exacto** (solo los PCs admin).
* Alcance: toda la topología. Enforce central en routers (ACL L3 por segmento outbound) + access-class por dispositivo (ACL standard en vty).

### Implementación en los 6 dispositivos IOS de la LAN
* Password de gestión **rotado a 4170** en los 6 IOS (2026-09-09): `username admin privilege 15 secret <pw>` + `enable secret <pw>` (secrets tipo 5 verificados). Valor exacto solo en `/tmp/opencode/.ssh_admin_b1.txt` (fuera del repo). `ip domain-name banco1.local`; `ip ssh version 2`; `crypto key generate rsa`.
* `line vty 0 4`: `login local` + `transport input ssh` + `access-class <SSH-ADMIN> in`.
* ACL **`SSH-ADMIN`** (standard, por host):
  * Sede (Router-1, Router-2, Switch-sede, Router-salida): `10 permit 172.16.20.4` + `20 deny any`.
  * Sucursal (Router-sucursal, Switch-sucursal): `10 permit 172.16.20.4` + `20 permit 172.16.50.3` + `30 deny any`.
* ACL **`SSH-L3-SEDE`** (extended, aplicada **out** en Gi0/0.10, Gi0/0.20, Gi0/0.30 de Router-1 y Router-2): `permit tcp host 172.16.20.4` → cada segmento de la sede (`172.16.10.0/28`, `172.16.20.0/24`, `172.16.30.0/29`) `eq 22`; `deny tcp any` → esos tres `eq 22`; `permit ip any any` (no interfiere el tráfico de negocio).
* ACL **`SSH-L3-SUC`** (extended, aplicada **out** en Gi0/0.40 y Gi0/0.50 de Router-sucursal): `permit tcp host 172.16.20.4` → `172.16.40.0/28` y `172.16.50.0/24` `eq 22`; `permit tcp host 172.16.50.3` → `172.16.40.0/28` y `172.16.50.0/24` `eq 22`; `deny tcp any` → ambos `eq 22`; `permit ip any any`.
* SVI de gestión en switches: Switch-sede `Vlan20 172.16.20.10/24` (gw `172.16.20.1`); Switch-sucursal `Vlan50 172.16.50.10/24` (gw `172.16.50.1`).
* **PCs admin identificados:** admin-sede = `172.16.20.4` (consola GNS3 5028); admin-sucursal = `172.16.50.3` (MAC `0ca6.4674.0000`, shell vía SSH tc@.50.3); caja-sucursal = `172.16.40.3` (MAC `0c8b.b62d.0000`, VNC).
* **Cliente SSH en los PCs admin (verificado, SIN inyección):**
  * admin-sede: `openssh` instalado vía `tce-load -wi openssh` (mirror `https://mirrors.dotsrc.org/tinycorelinux/`); `/usr/local/bin/ssh`, `scp`, `ssh-keygen` presentes (OpenSSH_6.7p1).
  * admin-sucursal: el disco base `linux-tinycore-11.1.qcow2` **ya incluye `openssh.tcz` en `/tce/onboot.lst`** y la partición persistente (`mydata.tgz`) arranca sshd con IP `172.16.50.3` y gw `172.16.50.1` → cliente SSH disponible sin cambio.
* Router-salida (persistido v8.6): SSH+ACL host-based + password 4170, **sin tocar** NAT/rutas/tracks/servicios.

### Matriz de validación v8.6 (2026-09-09, tráfico transitado real + login SSH real)
| # | Origen → Destino:22 | Esperado | Resultado |
|---|---|---|---|
| 1 | admin-sede (172.16.20.4) → Switch-sede (.20.10) | PERMITIDO | **OK** (login SSH `admin`/4170 → prompt `Switch-sede-central#` + `show clock`) |
| 2 | admin-sede → Router-1 (.20.2) | PERMITIDO | **OK** (login SSH real OK, prompt `Router-1-sede-central#`) |
| 3 | admin-sede → Router-2 (.20.3) | PERMITIDO | **OK** (login SSH real OK, prompt `Router-2-sede-central#`) |
| 4 | admin-sede → Router-salida (10.10.2.1) | PERMITIDO | **OK** (login SSH real OK, `SSH Enabled - version 2.0` post-reload v8.6) |
| 5 | admin-sede → Switch-sucursal (.50.10) | PERMITIDO | **OK** (login SSH real OK, prompt `Switch-sucursal-1#`) |
| 6 | admin-sede → Router-sucursal (.50.1) | PERMITIDO | **OK** (login SSH real OK, prompt `Router-sucursal-1#`) |
| 7 | admin-sede → Servidor-web (.30.5) | PERMITIDO | **PARCIAL** (nc RC=0/banner; login real usa credenciales OS TinyCore del host, no `admin` — servicio Linux, fuera del alcance IOS) |
| 8 | Router-1 (172.16.20.2) → Switch-sede / R2 / Router-salida / Servidor-web / Switch-suc | DENEGADO | **OK** (todo DENEGADO — origen router no permitido) |
| 9 | Router-sucursal (172.16.50.1) → Switch-suc / Caja-suc | DENEGADO | **OK** (DENEGADO) |
| 10 | admin-sucursal (172.16.50.3) → Switch-suc (.50.10) / Router-suc (.50.1) | PERMITIDO | **OK** (login SSH real admin/4170 desde la shell del OS de admin-sucursal → prompt `Switch-sucursal-1#`/`Router-sucursal-1#` + `show clock` OK en ambos) |
| 11 | caja-sede / caja-sucursal / servidor → SSH | DENEGADO | **OK** (ACL host-based: solo `.20.4`/`.50.3` permitidos) |
| 12 | admin-sucursal (172.16.50.3) → Servidor-web sede (.30.5) | DENEGADO | **OK** (`No route` — SSH-L3-SEDE en Router-1; jamás se solicitó password) |
| 13 | admin-sucursal (172.16.50.3) → Switch-sede (.20.10) | DENEGADO | **OK** (`No route` — SSH-L3-SEDE en Router-1; jamás se solicitó password) |

### Notas de validación
* Login SSH desde admin-sede contra los 6 IOS con password 4170: **OK en los 6** (entrada directa a prompt `#` por privilege 15 + `show clock` ejecutado). Confirmado tras el rearranque v8.6 del Router-salida.
* **Acceso al shell de admin-sucursal (172.16.50.3):** la consola serial del nodo (telnet 5012) bootea a GUI sin getty → shell del OS alcanzada vía `ssh tc@172.16.50.3` desde admin-sede (credenciales OS TinyCore `tc`/`tc`). Desde esa shell se ejecutaron los SSH reales con origen `.50.3`.
* **Validación admin-sucursal completa (2026-09-09):** `.50.3` → `.50.10`/`.50.1` LOGIN OK (`#` + `show clock`); `.50.3` → `.30.5`/`.20.10` DENEGADO (`No route`, SSH-L3-SEDE de Router-1). Cierra el PENDIENTE de confirmación de acceso de la sucursal.
* El tráfico **originado por el propio router NO atraviesa sus ACLs outbound en IOS** (los casos origen-router se validaron transitando y/o con routers remotos; coherente con la matriz).

## Cajas de caja (OS con Firefox, usuario `admin`) — 2026-09-09
* **caja-sede `172.16.10.4`** y **caja-sucursal `172.16.40.3`** ahora idénticas: TinyCore con **Firefox**, usuario OS `admin`/4170 (uid 1002), sshd en cada boot, getty serial `ttyS0` (`gns3`/`gns3`), IP/gw propios aplicados por `bootlocal.sh`.
* Imágenes registradas en GNS3 (md5 real en sidecar `.md5sum`):
  * `linux-tinycore-caja-sede-ssh.img` — md5 `dea376c364240db5bcf59424f79db1f3`. **Endurecida 2026-09-09**: la base anterior solo tenía `etc/shadow` en su mydata (sin `admin`) — si GNS3 regeneraba el overlay (hash distinto), la sede perdía `admin`. Ahora la imagen es autocontenida (passwd/shadow/group reales extraídos de la sede viva + `home/admin` + entradas en `.filetool.lst`).
  * `linux-tinycore-caja-suc-firefox.img` — md5 `a683c234f4f05b6b0b8f00ca1877458e`. Reemplaza al intento previo sobre base TC11 (`linux-tinycore-caja-suc-ssh.qcow2`): TC11 no trae navegador y su `ttyS0` no levantaba getty. Se partió de la base caja-sede (mydata de ronda funcional + identidad de usuario clonada) y solo se cambió la IP a `.40.3` (gw `.40.1`).
* Nodos: caja-sede (`e5a409b1`) hda **`ide`**, RAM 256; caja-sucursal (`ad8bb62d`) hda **`ide`** (el base TC6 no porta a virtio; se igualó al de la sede), RAM **512** (Firefox).
* Método (offline, sin tocar red): edición del `mydata.tgz` vía `debugfs` en la partición (offset de 32 sectores) → sector/escribe en la imagen raw cruda → `dd` de vuelta; password `admin` en shadow (**DES** `QybpzxVPEy.yE` = 4170), homóloga a la sede.
* **Verificación 2026-09-09 (real, desde admin-sede):** ping a `172.16.40.3` OK; `ssh admin@172.16.40.3` con 4170 → `uid=1002(admin)`, `inet addr:172.16.40.3`; serial de la caja-suc muestra login (`Core Linux ... box login`). Sede: `ssh admin@172.16.10.4` → `uid=1002(admin)`, `inet 172.16.10.4` tras re-imagen endurecida. Portal `http://172.16.30.5` responde HTML "Banco 1 - Portal Interno" desde la red → la caja-suc puede abrirlo con Firefox por VNC `:5905` (pendiente de confirmación visual por el usuario).

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

## Rutas primarias (AD 1, con track E2E)
* `10.0.0.4/30` (B2-B3) via `10.0.0.2` track 10 (sla2 → `10.0.0.6` B3 = E2E 2 saltos)
* `10.0.0.8/30` (B3-B4) via `10.0.0.2` track 10 (idem)
* `10.0.0.12/30` (B4-B5) via `10.0.0.17` track 20 (sla5 → `10.0.0.13` B4 = E2E 2 saltos)
* `0.0.0.0/0` via `192.168.122.1` (Gi0/0)
* `172.16.0.0/16` via `10.10.2.2` (Gi0/3, interno)
* **Anclaje de sondas (v8.4): Local PBR** (`ip local policy route-map RM-LOCAL-SLA`) — **sin rutas `/32`** (eliminadas en v8.4; ver IP SLA).
* Track 1/2 (line-protocol) ya no gobiernan primarias; quedan como soporte de flotantes y observación E2E no controla redundancia con ellos.

## Rutas de respaldo (flotantes AD 20, con track)
* `10.0.0.4/30` via `10.0.0.17 20` track 2
* `10.0.0.8/30` via `10.0.0.17 20` track 2
* `10.0.0.12/30` via `10.0.0.2 20` track 1
* `10.0.0.0/30` via `10.0.0.17 20` track 2 (wrap del propio segmento oeste por el este)

> **Eliminado en v8.1 (2026-09-07/08):** `10.0.0.16/30 via 10.0.0.2 20 track 1` (wrap del propio segmento este por el oeste). En fallo del este, ese wrap generaba loop B1↔B2: B1 reenviaba `.16/30` a B2 y B2 (por su track 3, que solo exige a B1 vivo) lo devolvía a B1 incesantemente. Eliminado y verificado por boot-test de persistencia.

Lógica: sin "entrada primaria" (es un anillo). Cada segmento lejano se alcanza por el arco corto (AD 1) y, si cae su track, vira por el arco contrario (AD 20) plegando el anillo. La config canónica vigente es **v8.6** (persistida en el config-disk `IOSv_startup_config.img`, no solo en overlay; config-md5 `65319e7291b5076649a2f2a26e78e3ef`, imagen-md5 `ba842bcce419ac76439bf6ca3e94bc8b`).

## Sondas remotas hacia B1 (otros bancos → nuestras IPs)
Confirmado en documentación de los vecinos (2026-09-07/08):
* **B2 → `10.0.0.1`** (SLA 1, cada 5 s, nuestra Gi0/1 oeste). Controla su ruta a `10.0.0.0/30`.
* **B3 → `10.0.0.1`** (SLA 1, vía Fa1/0/B2) y **`10.0.0.18`** (SLA 2, vía B4/B5 por el este), con Local PBR. Controlan sus primarias a `10.0.0.0/30` y `10.0.0.16/30`.
* **B4 → `10.0.0.18`** (Track B1, cada 2 s, vía B5). Controla su primaria a `10.0.0.16/30`.
* **B5 → `10.0.0.18`** (SLA 3, cada 5 s). Controla su ruta a `10.0.0.0/30`.
* Nuestro nodo responde los sondeos (ICMP a sus IPs por defecto). Evidencia `show ip traffic`: cientos de `echo` recibidos / `echo reply` enviados desde el boot.
* Hoy solo reciben los del **arco oeste** (B2/B3 a `.1`): los del este (B3/B4/B5 hacia `.18`) dependen de que B5 esté vivo y estable.

## IP SLA
* **Uso en routing (v8.4, E2E):** los SLAs **2 y 5 (echo a `.6`/`.13` = vecino-del-vecino)** gobiernan las primarias del ring a través de los tracks 10/20 (failover por alcance de 2 saltos, no por línea).
  * sla2 → `10.0.0.6` (B3), `source-interface Gi0/1` (origen `10.0.0.1`) → track 10 → primarias de `.4/30` y `.8/30`.
  * sla5 → `10.0.0.13` (B4), `source-interface Gi0/2` (origen `10.0.0.18`) → track 20 → primaria de `.12/30`.
  * **Anclaje por Local PBR (v8.4, recomendación de `docs/GUIA_SONDEO_END_TO_END_BANCO5.md`):** ACLs `ACL-SLA-B2-B3` (src `10.0.0.1`→dst `10.0.0.6`) y `ACL-SLA-B5-B4` (src `10.0.0.18`→dst `10.0.0.13`) + route-map `RM-LOCAL-SLA` (`set ip next-hop 10.0.0.2` / `10.0.0.17`) + `ip local policy route-map RM-LOCAL-SLA`. Solo ancla las sondas (ICMP originadas por el router con fuente = IP de cara); el tráfico real sigue las rutas `/30` con track/respaldo.
  * **POR QUÉ se eliminaron las rutas `/32` (v8.3):** la ruta fija `/32` por longest-prefix-match secuestraba **todo** el tráfico a la IP exacta, no solo la sonda. Comprobado en drill real (B1→corte B5-B4): con track 20 Down y la flotante `.12/30→.2` activa, un `ping 10.0.0.13` seguía saliendo por el este (`10.0.0.17`) y moría (primer salto `.17`, no `.2`). Con PBR esa IP exacta queda libre y el tráfico real conmuta correctamente.
  * Histéresis de tracks 10/20: `delay down 10 up 5` (inmune a la flake ICMP de B5).
  * Reutilizados SLAs 2/5 (`frequency 5`, timeout 5000) en vez de sla10/20 con `frequency 3` de la plantilla de B4.
* **IP SLA de observación (v8.2):** 5 sondas ICMP echo cada 5 s para monitorear los tramos del anillo (tracks 3-7, solo observación). El scheduler **sí re-ejecuta** en este IOSv (contador de éxitos crece en vivo).
* `show ip sla statistics` / `show track brief` dan el estado de cada tramo en un vistazo. `show route-map RM-LOCAL-SLA` muestra contadores de "Policy routing matches" creciendo (prueba de que el PBR ancla solo las sondas).

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
* Los tracks 3-7 son **solo observación** (no referenciados por ninguna `ip route`); los tracks 10/20 sí controlan failover (E2E).

## Log de observación del anillo (EEM, v8.2)
* 5 applets EEM (`RING_SEG_B1-B2`, `RING_SEG_B2-B3`, `RING_SEG_B3-B4`, `RING_SEG_B1-B5`, `RING_SEG_B4-B5`), un evento por applet (`event track <n> state any`), registradas en `show event manager policy registered`.
* Ante cada transición de track emiten syslog `%HA_EM-6-LOG: RING_SEG_<SEG>: RING SEG <SEG> track=up|down`. Verificado en vivo en el boot de v8.2:
  `*Sep 8 01:08:06.876: %HA_EM-6-LOG: RING_SEG_B1-B2: RING SEG B1-B2 track=up` (y B2-B3, B3-B4).
* **Ojo IOSv:** la variable EEM `$_track_name` **NO existe** en este IOS (genera `%HA_EM-3-FMPD_UNKNOWN_ENV`+`%HA_EM-3-FMPD_ERROR`); por eso las applets usan etiquetas literales y solo `$_track_state`, que sí funciona.
* Los mensajes de transición nativos `%TRACK-6-STATE` del tracking también quedan en el buffer (`show logging`).

## PBR / Route Maps
* Ninguno.

## NAT interbancario
* Publicación: `ip nat inside source static tcp 172.16.30.5 80 interface Gi0/1 80` (global `10.0.0.1:80`) y la blacklist redundante por ambas caras con global explícito + `extendable`: `ip nat inside source static tcp 172.16.30.6 8080 10.0.0.1 8080 extendable` y `... 10.0.0.18 8080 extendable` (globales `10.0.0.1:8080` y `10.0.0.18:8080`).
* PAT saliente: ACL 100 (`172.16.0.0/16`, `10.10.2.0/30`) → `interface Gi0/0 overload`; ACL 101 (`172.16.0.0/16`) → `interface Gi0/1 overload` (salida hacia el anillo oeste).
* Interfaces: Gi0/0, Gi0/1, Gi0/2 = `ip nat outside`; Gi0/3 = `ip nat inside`.
* NOTA: en pruebas, un segundo estático con global explícito `10.0.0.18:80/8080` se aceptó al vuelo pero **no persistió** en running-config (IOSv). Los servicios quedan publicados bajo `10.0.0.1`.
* FW interno (10.10.2.2): FORWARD DROP salvo reglas puntuales; DNAT 80/8080 hacia `172.16.30.5`/`172.16.30.6`; REDIRECT de DNS 53 a dnsmasq.

## Servicios interbancarios publicados
* `http://10.0.0.1/` → `172.16.30.5:80` — portal interno "Banco 1 - Portal Interno" (HTTP 200 en `/`).
* `10.0.0.1:8080` → `172.16.30.6:8080` — responde; Banco 2 accedió a `10.0.0.1:8080` en prueba previa (traducción NAT viva registrada).
* **Blacklist redundante en AMBAS caras (2026-09-08 ~09:59):** `10.0.0.1:8080` (oeste, B2) y `10.0.0.18:8080` (este, B5/B4) → ambas `172.16.30.6:8080`, **funcionando en paralelo** con la forma global explícito + `extendable`:
  ```
  ip nat inside source static tcp 172.16.30.6 8080 10.0.0.1 8080 extendable
  ip nat inside source static tcp 172.16.30.6 8080 10.0.0.18 8080 extendable
  ```
  Técnica tomada de BANCO3 (mismo servidor interno por dos globales distintos). La forma previa `interface Gi0/2` **no servía**: al intentar agregar el este, IOSv **descartaba el estático oeste** del mismo `inside local` (regresión: `10.0.0.1:8080` dejó de responder). Con global+`extendable` IOSv sostiene ambos. Confirmado en `show ip nat translations` (dos entradas `10.0.0.1:8080` y `10.0.0.18:8080`) y persistido con `write memory`. **PENDIENTE DE CONFIRMACIÓN POR BANCO 2/5/4:** validación E2E real desde cada nodo (retorno este sale por default `via 10.10.2.1`; FW sin ruta fantasma `10.0.0.16/30`).
* **`/interbancaria`: IMPLEMENTADO** en `172.16.30.5:80` (POST). Ver sección "Endpoint `/interbancaria`". Antes devolvía HTTP 404 en GET y 400 en JSON sin `cuenta_origen`.
 * **Saliente a B2:** ver sección "Apartado Transferencia a otro banco (Banco 2)". **PENDIENTE DE CONFIRMACIÓN POR BANCO 1 y B2** (conectividad + API contract).

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

## Apartado "Transferencia a otro banco (Banco 2)" (portal web, 2026-09-08)
* **Objetivo cumplido:** el portal interno (`172.16.30.5:80`, publicado `10.0.0.1:80`) muestra el apartado **"Transferencia a otro banco (Banco 2 - Inversiones)"** en los dashboards de **cajero y admin** (formulario: cuenta origen Banco 1, cuenta destino Banco 2, monto).
 * **Funcionamiento:** `POST /interbanco` valida la cuenta origen contra `/cuentas` del DB interno; si es válida, invoca el endpoint saliente de B2 `http://10.0.0.2:5001/interbanco/deposito` (`timeout 30`) y renderiza el resultado en el dashboard (feedback HTML de éxito/error). **PENDIENTE DE CONFIRMACIÓN POR BANCO 2:** los parámetros enviados (`cuenta_destino`/`monto`/`cuenta_origen`) asumen la misma sintaxis que `/interbancaria` de B1; la API real de B2 en `/interbanco/deposito` no fue verificada desde su lado — puede esperar nombres, tipos o estructura JSON distintos. Probar con `curl` directo o revisar el código de B2 antes de validar la integración.
 * **Integración con B2:** la llamada saliente desde B1 **no conecta** aún (`Banco 2 rechazo la operacion: no se pudo conectar al Banco 2`) — el `Servidor-web` (LAN `172.16.30.5`, GW `10.10.2.1`) no alcanza `10.0.0.2:5001`. La ruta depende de que el FW interno (`10.10.2.2`) permita el tráfico hacia `10.0.0.0/30` o que el `Servidor-web` tenga un route hacia `10.0.0.0/30` vía `10.10.2.1`. **PENDIENTE DE CONFIRMACIÓN POR BANCO 1 y B2:** (1) verificar reglas de FORWARD en el FW interno hacia `10.0.0.0/30` y (2) confirmar que B2 recibe y responde correctamente (NAT/ruta de retorno).
* **Despliegue (offline, sin cambio de red):**
  * `web_server.py` v10 → **v12** con: card B2 en ambos dashboards, handler `/interbanco` con feedback HTML, y dedupe del `/interbancaria` entrante. Bug corregido en v12: `dashboard_admin` usaba `opciones` sin definirlo (rompía el dashboard admin con excepción que colgaba la petición).
  * Empaque en `mydata.tgz` del Tiny Core (`Servidor-web`); disco del nodo regenerado como **qcow2 autocontenido** (`hda_disk.qcow2`; backups `hda_v11_disk.qcow2`, `hda_disk_v9_prev.qcow2`).
  * **Autostart implementado:** `/opt/bootlocal.sh` en la partición persistente lanza `web_server.py` en cada boot (se detectó que el servidor **no** arrancaba solo tras un rearranque limpio).
* **Verificación (2026-09-08, desde red interna FW 172.16.30.x):** GET `/dashboard?rol=cajero|admin` → card B2 presente con cuentas pobladas (Juan Perez/Maria Lopez/Cliente Sucursal); POST `/interbanco` con cuenta origen inexistente → "la cuenta origen no existe en los clientes de Banco 1"; con cuenta origen válida → intenta B2 y devuelve "no se pudo conectar al Banco 2" (dependencia externa). `/` → 200 login "Banco 1 - Portal Interno".

## Blacklist publicada en `10.0.0.1:8080` (diagnóstico 2026-09-08 ~01:30-02:20)
* **Síntoma reportado por B2:** `curl http://10.0.0.1:8080/api/blacklist` respondía a ~01:10 (JSON con 6 clientes); ahora el cliente se queda colgado. B2 probó desde sus fuentes `10.0.0.2` y `10.0.0.5`.
* **Servicio sano:** `172.16.30.6:8080` responde OK desde la LAN del FW (`{"lista_negra_clientes": [...], "total": 6}`).
* **FW interno descartado como causa:** DNAT `eth2 dpt:8080 → 172.16.30.6:8080` presente; FORWARD (policy DROP) acepta `-s 10.0.0.0/24 -i eth2 --dports 80,8080`; RAW solo bloquea 8080 para B3/B4 (`10.0.0.6/.9/.13/.14`), no para B2/B5. **Prueba concluyente:** SYN originado desde el router con fuente `10.0.0.250` (Loopback temporal dentro de `10.0.0.0/24`) hacia `10.0.0.1:8080` → el FW reenvió a `.6` y `172.16.30.6:8080` respondió SYN-ACK (tcpdump en eth2 del FW). Routing/forwarding/NAT del FW **sanos**.
* **NAT del router (límite conocido):** solo existen los estáticos `10.0.0.1:80→172.16.30.5:80` y `10.0.0.1:8080→172.16.30.6:8080` (ligados a Gi0/1 y en `10.0.0.1`, publicado por la cara oeste). Gi0/2 es `ip nat outside` y existe DNAT en el FW para `10.0.0.18:8080`, pero el segundo estático `10.0.0.18` **no persiste en IOSv** → **la cara este `10.0.0.18:8080` no publica servicio** (connection refused; el 404 transitorio visto por B2 fue un estático en memoria ya expirado).
* **Observación:** el SYN originado por el propio router (telnet a `10.0.0.1:8080` con fuente `10.10.2.1`/`10.0.0.1`) no completa en el router (responde RST porque su fuente no coincide con el estático, cuyo global es `10.0.0.1`); **no es representativo del tráfico real de B2** (fuente `.2`/`.5`).
* **CAUSA RAIZ ENCONTRADA y CORREGIDA (2026-09-08 ~09:05): rutas `connected` residuales en el FW interno.** El FW tenía IPs residuales en `eth2` (`10.0.0.1/30` y `10.0.0.18/30`, además de la correcta `10.10.2.2/30`), que creaban rutas connected `10.0.0.0/30 dev eth2` y `10.0.0.16/30 dev eth2`. El retorno de `172.16.30.6` hacia `10.0.0.2` (B2) casaba en esa connected residual → el FW intentaba **ARP directo de `10.0.0.2` por eth2** (enlace equivocado `10.10.2.x`) → FAILED (evidencia `ip neigh`: `10.0.0.2 dev eth2 probes 6 FAILED`) → el SYN-ACK de `.6` se tiraba y B2 veía colgado el curl. La prueba con fuente `10.0.0.250` funcionaba porque `.250` NO cae en esa `/30` residual y salía por default via `10.10.2.1`.
  * **Corrección aprobada y aplicada (read-only del router; cambio solo en FW):** `ip addr del 10.0.0.1/30 dev eth2` y `ip addr del 10.0.0.18/30 dev eth2`. Tras el cambio `ip route get 10.0.0.2` → `via 10.10.2.1 dev eth2` (correcto).
  * **Validación E2E (tcpdump FW eth2+eth0, 3 curls de B2):** handshake completo `SYN→SYN-ACK→ACK→GET /api/blacklist→HTTP/1.0 200 OK→FIN` en los dos sentidos (09:05:37, :49, :59). **B2 accede de nuevo a `http://10.0.0.1:8080/api/blacklist`.**
  * **PERSISTENCIA RESUELTA (2026-09-08 ~09:30):** el acceso a `http://10.0.0.1:8080/api/blacklist` sigue funcional y el fix ya **sobrevive a rearranques del FW/node GNS3**. Detalle en "Cambios recientes" (~09:30): start_command del node blindado con limpieza defensiva + validación con recreación real del contenedor.

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
* IOSv/NAT: NO se pueden publicar dos servicios con el mismo `inside local` usando la forma `interface X` (el segundo descarta al primero — comprobado ~09:51, regresión en `10.0.0.1:8080`). SOLUCIÓN validada: usar **global IP explícito + `extendable`** (`ip nat inside source static tcp <local> <lp> <global> <gp> extendable`), que IOSv sí sostiene en paralelo para distintos globales — comprobado ~09:59 (blacklist por `10.0.0.1:8080` y `10.0.0.18:8080`). Técnica ya usada por BANCO3.
* Limitación track line-protocol: no detecta caída de vecino con L1/L2 sano (ver "muerto en caliente" de `.12/30`).

## Cambios recientes
* 2026-09-09: **cajas de caja convergidas (re-imagen de la sucursal y endurecimiento de la sede).** caja-sucursal `172.16.40.3` re-imagenada desde la base Firefox/TC6 de la sede (misma identidad de usuarios: `admin`/4170 uid 1002, `gns3`/`gns3`, `tc` sin password) con IP `.40.3`/gw `.40.1`; nodo GNS3 `ad8bb62d` apuntado a `linux-tinycore-caja-suc-firefox.img` (md5 `a683c234...`), hda `ide`, RAM 200→**512**; overlay regenerado y arranque verificado (serial `box login`, SSH `admin` uid 1002, ping, portal `172.16.30.5` OK). caja-sede endurecida: imagen `linux-tinycore-caja-sede-ssh.img` reconstruida con identidad autocontenida (md5 `dea376c3...`, propiedad GNS3 corregida del valor stale a ambos md5 reales), rearrancada y verificada (SSH `admin` uid 1002, IP `.10.4`, serial login OK). Imagen TC11 intermedia `linux-tinycore-caja-suc-ssh.qcow2` retirada (sin Firefox y sin getty serial). Sin cambios de red.
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
* 2026-09-08: **validación negativa v8.3 (drill B5-B4 desconectado):** detectado el efecto secundario de las rutas `/32` de la plantilla original (longest-prefix-match): con track 20 Down y la flotante `.12/30→10.0.0.2` activa, `ping 10.0.0.13` **no** conmutaba — seguía saliendo por `10.0.0.17` (primer salto `.17`, luego timeout) porque la `/32` fija secuestraba el tráfico real a esa IP exacta. Es exactamente el riesgo documentado por Banco 5 en `docs/GUIA_SONDEO_END_TO_END_BANCO5.md`.
* 2026-09-08 ~06:05: **config v8.4 — reemplazo del anclaje `/32` por Local PBR** (recomendación de la guía de B5, igual que la técnica ya usada en B3/B5): `no ip route 10.0.0.6/32` y `no ip route 10.0.0.13/32`; `source-interface Gi0/1`/`Gi0/2` en sla2/sla5 (recreados porque en IOSv "Entry already running cannot be modified"); ACLs `ACL-SLA-B2-B3`/`ACL-SLA-B5-B4` (solo `icmp host <nuestra IP> por cara` → destino salto 2), route-map `RM-LOCAL-SLA` (`set ip next-hop` 10.0.0.2/10.0.0.17) e `ip local policy route-map RM-LOCAL-SLA`. Tras el disco el tráfico real a la IP exacta sigue las `/30` con track (prueba: `show ip route 10.0.0.13` = `/30`, no `/32`; contadores `show route-map` creciendo). **Persistido en config-disk (master) y validado con rearranque limpio**: `%CVAC-4-CONFIG_DONE`, 0 `%PARSER`, tracks 10/20 UP, sla2/sla5 con `source-interface` correcto, PBR activo. Checksum master: `0f6a5826e4a293d1dc0e6d872b13afee`.
* 2026-09-08: **portal v12 desplegado** (Bug `opciones` en `dashboard_admin` corregido; card B2 en cajero y admin; handler `/interbanco` → intenta `10.0.0.2:5001/interbanco/deposito` con timeout 30; autostart vía `/opt/bootlocal.sh` en la partición persistente para que el servidor arranque solo tras reboot). Verificado desde la LAN del FW. Ver sección "Apartado Transferencia a otro banco (Banco 2)".
* 2026-09-08 ~02:00-02:20: **diagnóstico acceso B2 → blacklist `10.0.0.1:8080`**: servicio `.6:8080` sano; FW interno descartado (reenvío verificado con tcpdump: SYN `10.0.0.250 → 172.16.30.6:8080` reenviado y SYN-ACK de vuelta); camino oeste de B1 verificado de extremo a extremo. Hipótesis abierta: fuente `.5`/arco este (entra por Gi0/2 sin estático persistente) o egreso propio de B2. Ver sección "Blacklist publicada en `10.0.0.1:8080`". PENDIENTE B2 (prueba en vivo).
* 2026-09-08 ~09:05: **CAUSA RAIZ blacklist B2 resuelta — rutas connected residuales en FW interno (eth2 con `10.0.0.1/30` y `10.0.0.18/30`)** hacían ARP directa fallida de `10.0.0.2` por el enlace equivocado y tiraba el retorno del servicio. Fix aprobado: `ip addr del 10.0.0.1/30 dev eth2` + `ip addr del 10.0.0.18/30 dev eth2`. Validado E2E: 3 curls de B2 completos con `HTTP/1.0 200 OK` (tcpdump FW eth2+eth0).
* 2026-09-08 ~09:30: **persistencia del fix de blacklist (PENDIENTE previo cerrado).** Blindado el node GNS3 `Firewall-sede-central` (id `19e41051-e264-458d-99f2-96149755e9e7`) vía API del server GNS3: el `start_command` (FIREWALL v6) ahora arranca con limpieza defensiva `ip addr del` de las residuales (`10.0.0.1/30` dev eth2, `10.0.0.18/30` dev eth2 y dev eth3) + `ip route del` de `10.0.0.0/30` / `10.0.0.16/30`, antes de aplicar las IPs v6. También se retiró en vivo el residual `10.0.0.18/30` de eth3 (ruta fantasma `10.0.0.16/30 dev eth3` sin cable). Se creó además imagen docker dedicada `firewall-banco1:clean` (commit del contenedor corregido; NO se sobrescribió `alpine:latest`, usada por `Practica4`). **Validado con arranque limpio real del contenedor** (GNS3 lo recreó como `6cd96bb35e12`): IPs solo `172.16.0.2/30`-`172.16.1.2/30`-`10.10.2.2/30`, sin residuales en eth2/eth3, `ip route get 10.0.0.2` → `via 10.10.2.1 dev eth2`, iptables FORWARD/NAT v6 presentes.
* 2026-09-08 ~09:51: **blacklist publicada también por la cara este (`10.0.0.18:8080`)** en `Router-salida` (consola GNS3): primer intento `ip nat inside source static tcp 172.16.30.6 8080 interface GigabitEthernet0/2 8080`. **Regresión detectada:** la forma `interface` hizo que IOSv descartara el estático oeste del mismo inside-local → `10.0.0.1:8080` dejó de responder.
* 2026-09-08 ~09:59: **fix redundancia ambas caras (regresión corregida):** reemplazados por la forma global explícito + `extendable` (técnica de BANCO3): `ip nat inside source static tcp 172.16.30.6 8080 10.0.0.1 8080 extendable` y `ip nat inside source static tcp 172.16.30.6 8080 10.0.0.18 8080 extendable`. IOSv sostiene ambos globales con mismo inside-local (a diferencia de la forma `interface`). `write memory` OK; confirmado en running-config y `show ip nat translations` (2 entradas). Blacklist redundante disponible en `http://10.0.0.1:8080/api/blacklist` (B2) y `http://10.0.0.18:8080/api/blacklist` (B5/B4).
* 2026-09-08 ~04:20: **persistencia en config-disk master (v8.5).** Inyectadas las 2 líneas de blacklist redundante en `IOSv_startup_config.img` (master) vía mtools (sin sudo): `ios_config.txt` actualizado (3 estáticos) + `ios_config_checksum` recalculado = md5 del config (`a7c01b137fbb1f40b2204125af5524da`). Backup del master previo: `IOSv_startup_config.img.bak_v8.4041705`. Actualizado `hdb_disk_image_md5sum` del node `Router-salida` en `Proyecto_1.gns3` (de `bc605651...` a `9b0e066c...`) para que GNS3 regenere el overlay con el master nuevo al rearrancar el node (backup del .gns3: `.bak_md5update`; backup del overlay previo: `hdb_disk.qcow2.bak_antes_persist`).
* 2026-09-08 ~04:35: **boot-test de persistencia completado (v8.5 validado).** Node `Router-salida` parado, overlay `hdb_disk.qcow2` eliminado (backup `hdb_disk.qcow2.bak_antes_regen`), node arrancado → GNS3 recreó overlay nuevo (`qemu-img create` backing al master v8.5). Al bootear: `%CVAC-7-CONFIG_FOUND` + `%CVAC-4-CONFIG_DONE` desde flash2, **sin parser errors**. Running-config muestra las 3 estáticas NAT: portal `172.16.30.5:80` (Gi0/1) + blacklist redundante `172.16.30.6:8080` → `10.0.0.1:8080 extendable` (oeste) y `10.0.0.18:8080 extendable` (este). `show ip nat translations` confirma 3 entradas (`10.0.0.1:80`, `10.0.0.1:8080`, `10.0.0.18:8080` → `172.16.30.5/6`). La redundancia de la blacklist en ambas caras **persiste tras rearranque limpio**.
* 2026-09-09: **política SSH refinada host-based "solo PCs admin" + password 4170 (v8.0 de acceso, cambio de gestión sin tocar red).** Password `admin`/`enable` rotado a **4170** en los 6 IOS (usuario `admin` privilege 15; secrets tipo 5 verificados). ACLs por host exacto: `SSH-ADMIN` sede (R1/R2/SW-SEDE/RSALIDA) = `permit host 172.16.20.4` + `deny any`; sucursal (RS/SUC/SW-SUC) = `permit host 172.16.20.4` + `permit host 172.16.50.3` + `deny any`. ACLs L3 refinadas: `SSH-L3-SEDE` (R1/R2 out .10/.20/.30) `permit tcp host 172.16.20.4`→cada segmento eq22 y `SSH-L3-SUC` (R-SUC out .40/.50) con `permit tcp host 172.16.20.4` y `permit tcp host 172.16.50.3`→sucursal eq22, + `deny tcp any` + `permit ip any any`. `write memory` en los 6. Descubierto admin-sucursal = `172.16.50.3` (MAC `0ca6.4674.0000`; caja-suc = `172.16.40.3` MAC `0c8b.b62d.0000`) vía ARP. Cliente SSH: admin-sede instalado por el usuario (tce-load openssh); **admin-sucursal ya lo trae** (openssh.tcz en onboot.lst del base linux-tinycore-11.1.qcow2) → sin inyección.
* 2026-09-09: **validación v8.5→v8.6 de acceso.** Login SSH real desde admin-sede con 4170 → prompt `#` (privilege 15) + `show clock` en los 6 IOS OK (Switch-sede, Router-1, Router-2, Router-salida, Switch-sucursal, Router-sucursal). Denegaciones origen-router verificadas: R1 (172.16.20.2) → Switch-sede/R2/Router-salida/Servidor-web/Switch-suc **DENEGADO**; R-SUC (172.16.50.1) → Switch-suc/Caja-suc **DENEGADO**. admin-sucursal: PENDIENTE DE CONFIRMACIÓN (login real desde su VNC no ejecutado; permit host `.50.3` instalado).
* 2026-09-09: **persistencia Router-salida en config-disk master v8.6 (boot-test + rearranque real validados).** Regenerado `IOSv_startup_config.img` desde running-config real (incluye: enable/username secret 4170, `ip ssh version 2`, ACL standard `SSH-ADMIN` con `permit 172.16.20.4`, `line vty 0 4` con `access-class SSH-ADMIN in` + `login local` + `transport input ssh`; NAT/rutas/tracks/EEM del anillo invariantes). Método: extracción config v8.6 (`ios_config.txt`, sin banners/prompts) + `ios_config_checksum` = md5 del txt + escritura vía mtools (FAT12 con MBR, offset part 32256). Backup master previo: `IOSv_startup_config.img.bak_v8.5041705`. Nuevo config-md5 `65319e7291b5076649a2f2a26e78e3ef`, imagen-md5 `ba842bcce419ac76439bf6ca3e94bc8b`; actualizado `.md5sum` (master) y `hdb_disk_image_md5sum` en `Proyecto_1.gns3` (.gns3 backup `.bak_pre_4170_acl`). **Boot-test** en QEMU aislado (overlay qcow2 sobre master nuevo, puerto 5026): `%CVAC-7-CONFIG_FOUND flash2:/ios_config.txt` + `%CVAC-4-CONFIG_DONE ... applied and saved to NVRAM`, verify config vía `show ip ssh` = "SSH Disabled - version 2.0" (sin RSA aún) y running-config con ACL/line vty correctos. **Rearranque real del nodo** (`reload` por consola 5030): login SSH desde admin-sede con 4170 → `Router-salida#`, `SSH Enabled - version 2.0`, ACL `SSH-ADMIN`/`permit 172.16.20.4`/`access-class in`/`login local`/`transport input ssh` presentes → **config v8.6 vigente tras reinicio, sin cambios de red**.
* 2026-09-08 (~21:00-21:10 UTC-6): **acceso a consola del `Servidor-web` restablecido (aprobado).** Reset offline del password de `tc`/`root` del Tiny Core (`Servidor-web`, node `aa0d2138`) a **`tc`/`tc`** (hash MD5-crypt `$1$tcsalt$gf1q...` en `/etc/shadow` dentro de `/tce/mydata.tgz`). Método: parcheo del overlay `hda_disk.qcow2` (qpraw `dd bs=512 skip=63` → `debugfs` rm/write mydata.tgz → rearmar overlay qcow2 con backing `linux-tinycore-11.1.qcow2`). **Corregido el ownership del repack a `0:50`** (tar `--owner=0 --group=50`; un primer repack con 1000:1000 causaba `can't change directory to '/home/tc'`). Backups: `hda_disk.qcow2.bak_antes_reset`/`.bak_antes_reset2`/`.bak_antes_diag`. **Validado en consola VGA (QEMU monitor `sendkey`+`screendump`): login `tc`/`tc` OK → prompt `tc@box:~$` (who → tc/tty1).** Web server sigue escuchando en puerto 80 tras reboot; script de diagnóstico `home/tc/d` inyectado vía mydata (puede borrarse después).
* 2026-09-08 (~21:10 UTC-6): **verificación saliente B2 desde el propio `Servidor-web`** (comandos reales vía shell, script `sh d`): ruta default `172.16.30.1` (FW interno) OK, red local `172.16.30.0/29`. **`10.0.0.2:5001` NO alcanzable**: ping `10.0.0.2` 100% pérdida, `nc 10.0.0.2 5001` rc=1, `wget http://10.0.0.2:5001/health` timeout. Confirma con evidencia desde adentro el pendiente ya documentado (depende del FORWARD del FW interno hacia el anillo / NAT del Router-salida). PENDIENTE DE CONFIRMACIÓN POR BANCO 1 y BANCO 2 (estado del servicio `10.20.1.34:5001`).

## Pendientes
* ~~Validación de acceso desde admin-sucursal (172.16.50.3)~~ **CERRADO 2026-09-09**: login SSH real OK hacia sucursal (`.50.10`/`.50.1`) y denegaciones a sede (`.30.5`/`.20.10`) verificadas con shell del OS (ver matriz filas 10/12/13).
* Endpoint `/interbancaria` implementado y probado localmente; **pendiente** validación coordinada real desde B2/B3/B5 (sin transferencia interbancaria real por instrucción) y definir conciliación contable si el emisor envía `cuenta_origen` no local (solo eco por ahora).
* Drill de failover autorizado (corte de 30 s por lado) — ahora el failover es E2E (tracks 10/20) y el anclaje de sondas es PBR (v8.4). **Re-drill pendiente** con el corte B5-B4 para confirmar que el tráfico real a `10.0.0.13` YA conmuta al oeste (en v8.3 quedaba secuestrado por la `/32`); el primer salto esperado ahora es `10.0.0.2`.
* B5 confirmado respondiendo en la última validación (ICMP `.17`/`.13` 100%, tracks 6/7/20 Up post-boot v8.3) y su doc reporta E2E Hop-2 activo — **cerrado el PENDIENTE previo** de "B5 mudo"; si reaparece la flake, condiciona el track 20 (E2E este).
* Confirmar con Banco 2 que migró su `.12/30` a E2E (debe dejar de depender del track 5 AND B1+B5-vía-B1, ver drill de B4) para que la flotante `10.0.0.12/30 via 10.0.0.2` de B1 sea segura sin rebote.
* B3 coordinaría la adopción E2E grupal y actualizar `ESTADO_ANILLO.md` (sondas vecino-del-vecino por banco, tabla maestra de la guía).

## Notas para otros bancos
* **B4 (coordinador E2E):** B1 **adoptó** el esquema de `docs/GUIA_SONDEO_END_TO_END.md` (v8.3, validada con rearranque) y luego **corrigió el anclaje de sondas a Local PBR (v8.4)** siguiendo `docs/GUIA_SONDEO_END_TO_END_BANCO5.md`: las rutas `/32` de la plantilla secuestran el tráfico real a la IP exacta del salto 2 (longest-prefix-match) y rompían el failover — comprobado en drill real. B1 recomienda al grupo **no usar `/32`** de ancla y adoptar `ip local policy` + ACLs de sonda (cf. técnica B3/B5). Adaptaciones vs la plantilla: (1) se reutilizaron los SLAs 2/5 existentes (`frequency 5` en vez de 3); (2) histéresis down 10/up 5 (en vez de 6/3) para tolerar la flake ICMP de B5; (3) **flotantes con track** (AD 20 trackeadas) para evitar flotantes ciegas. Portabilidad de la guía al grupo: **confirmada en B1**.
* **Evaluación Hop-3 (vecino del vecino del vecino) — conclusión B1:** en este anillo de 5 nodos **no aporta** monitorear el tercer salto (`.10`/`.9` desde B1): cada enlace ya queda cubierto por el par correspondiente (B2 valida `.10`; B5 valida `.9`; B3/B4 también) y Hop-2 duplica la cobertura de todo el anillo. Agregar sondas Hop-3 añadiría ruido, latencia de convergencia y dependencia de la salud de un banco extra sin información nueva. B1 mantiene Hop-2 (lo coordinado); desestimamos Hop-3 por redundancia estructural (documentado para el grupo).
* **B3 (coordinador):** re-ejecutar sus sondas SLA/PBR hacia B1 y hacia `.8/30`: el nodo responde ICMP, el arco oeste hasta `.10` (B4) está operativo y B1 ya no tiene dead-route hacia `.8/30`. `ESTADO_ANILLO.md` debe actualizarse (arco oeste OK, B5 flapeando, fix v8.1 + observación v8.2 + E2E v8.3 de B1). El requerimiento de su Paso 2 (`ip route 10.0.0.8 ... 10.0.0.17 20 track 2`) ya está satisfecho en B1 desde v7 (y en v8.3 permanece).
* **B2:** confirmar corrección del estado de sus tracks 4/6 (el tráfico B1→B4 vía `.8/30` YA transita por B2/B3; sus docs siguen listando Null0).
* **B5:** tras el rearranque v8.3 de B1 (2026-09-08 ~23:00) su nodo **responde ICMP de forma sostenida**: ping a `10.0.0.17` y `10.0.0.13` **100%**, tracks 6/7/20 **Up** (sla5→`.13` 529 OK/32 fail). Coincide con su doc (`_coord_temp/BANCO5.md`), que adoptó E2E Hop-2 (SLAs 10/20 + Local PBR, `delay down 10 up 5`) el 2026-09-07 23:07 UTC-6, y con `ESTADO_ANILLO.md` (tracks 10/20 UP). La flake histórica del arco este queda documentada en secciones anteriores; no observada en la última validación.
* **B4:** por `.13` (interfaz hacia B5) inalcanzable desde el arco este; el `.10` (hacia B3) es alcanzable vía oeste. Confirmar sostenibilidad de su failover Track B2 (según su doc, DOWN) — el oeste ya devuelve tráfico.
* **B2 (drill B4):** re-chequear su SLA3 a `10.0.0.17` (B5 responde a B1 intermitente: RTT 6-11 ms cuando lo hace). Para que el failover B4→este complete, B2 necesita ruta a `10.0.0.12/30` para el retorno; su track 5 (AND B1+B5-vía-B1) queda rehén de la flake ICMP de B5. Proponemos condicionar `.12/30 via 10.0.0.1` a **track 1 (B1 directo)** — y en el esquema E2E del grupo migrar `.12/30` a su arco oeste (vía B3) cuando no por B1. B1 confirma su `.12/30 via 10.0.0.17 track 20` (E2E a `.13`) listo.
* **B5:** la raíz del tapón del drill de B4 es la inestabilidad de su respuesta ICMP: sus ramas hacia B1 (`10.0.0.17`) y B4 (`10.0.0.13`) flapean (EEM de B1 registra up/down repetidos, p.ej. 02:25-03:12; sla4→`.17` responde intermitente y sla5→`.13` igual). Estabilizar ICMP desbloquea el retorno `10.0.0.12/30` en B2.
* **B4 (drill):** una vez B2/B5 estables, re-ejecutar y confirmar; hops esperados del traceroute a `10.0.0.5`: `.14` (B5) → `.18` (B1) → `.2` (B2) → `.5` (destino).
* **B2:** acceso interbancario publicado en `10.0.0.1:80` → `172.16.30.5:80` (portal + endpoint `/interbancaria` implementado, ver sección Endpoint) y `10.0.0.1:8080` → `172.16.30.6:8080`.