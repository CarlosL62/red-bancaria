# Documentación Técnica y Requisitos Interbancarios - Banco 2 (Banca de Inversión)

> Fuente de los datos: análisis directo de la topología GNS3 (`R-WAN`, `R-LAN`, `FW-BANCO2`) y de `_coord_temp/BANCO2.md` / `_coord_temp/ESTADO_ANILLO.md` (última consolidación grupal: 2026-09-08; ajustes de Banco 2 posteriores: 2026-09-10). Los puntos que no pudieron verificarse directamente quedan marcados como `PENDIENTE DE CONFIRMACIÓN`, siguiendo el protocolo del repositorio (`_coord_temp/README.md`).

---

## 1. Routing Interbancario (Estático y Failover)

### Vecinos directos de R-WAN (Banco 2)
| Vecino | Red de tránsito | IP propia | IP vecino | Interfaz |
| :--- | :--- | :--- | :--- | :--- |
| Banco 1 | `10.0.0.0/30` | `10.0.0.2` | `10.0.0.1` | FastEthernet2/0 (NAT outside) |
| Banco 3 | `10.0.0.4/30` | `10.0.0.5` | `10.0.0.6` | FastEthernet3/0 (NAT outside) |

### Tabla de Rutas Estáticas Interbancarias
| Ruta Principal / Alternativa | Destino (Red/IP) | Próximo Salto (Next-Hop) | Interfaz de Salida | Métrica / Prioridad |
| :--- | :--- | :--- | :--- | :--- |
| Principal (E2E, trackeada) | `10.0.0.8/30` (Banco 4, vía Banco 3) | `10.0.0.6` | Fa3/0 | AD 1, `track 10` |
| Principal (E2E, trackeada) | `10.0.0.12/30` (Banco 5, vía Banco 3) | `10.0.0.6` | Fa3/0 | AD 1, `track 10` |
| Principal (E2E, trackeada) | `10.0.0.16/30` (Banco 5–Banco 1, vía Banco 1) | `10.0.0.1` | Fa2/0 | AD 1, `track 20` |
| Alternativa (flotante) | `10.0.0.8/30` | `10.0.0.1` | Fa2/0 | AD 100, sin track |
| Alternativa (flotante) | `10.0.0.12/30` | `10.0.0.1` | Fa2/0 | AD 100, sin track |
| Alternativa (flotante) | `10.0.0.16/30` | `10.0.0.6` | Fa3/0 | AD 100, sin track |
| Protección final (anti-loop) | `10.0.0.0/27` | `Null0` | — | AD 250 |
| Ruta por defecto | `0.0.0.0/0` | `192.168.100.1` | Fa0/0 | AD 1 |
| Ruta hacia LAN interna | `10.20.0.0/16` | `10.20.0.2` | Fa1/0 | AD 1 |

> Las redes `10.0.0.0/30` y `10.0.0.4/30` son directamente conectadas (no requieren ruta estática).

### Mecanismo de Recuperación (Failover)

El routing es **100% estático**; la conmutación automática se logra combinando cuatro mecanismos, sin usar ningún protocolo de routing dinámico:

1. **IP SLA "End-to-End" (salto 2):** en vez de monitorear solo al vecino directo, las sondas ICMP echo (`ip sla monitor 10` / `20`) apuntan al **vecino del vecino** (`10.0.0.10` = Banco 4 vía Banco 3; `10.0.0.17` = Banco 5 vía Banco 1). Esto detecta cortes más allá del enlace inmediato.
2. **Object Tracking (`track 10` / `track 20`):** vincula el resultado de cada SLA a un objeto de tracking con histéresis (actualmente `delay down 6 up 3`, en proceso de alinearse a `delay down 10 up 5` según la guía de Banco 5) para evitar *flapping* por la pérdida aislada de un ping.
3. **PBR local para las sondas (`ip local policy route-map RM-LOCAL-SLA`):** ancla cada sonda a su interfaz de salida (norte/sur) **sin usar rutas `/32`**. Se descartó deliberadamente el uso de `/32` porque esas rutas también anclaban el tráfico real hacia el destino de la sonda, rompiendo el failover del tráfico de aplicación (bug detectado y corregido el 2026-09-08).
4. **Rutas primarias trackeadas (AD 1) + flotantes sin track (AD 100):** cuando el `track` asociado a la primaria cae, esa ruta se retira de la RIB y la flotante —que ya estaba pre-configurada— la reemplaza de inmediato. El `Null0 /27` actúa como última barrera para no filtrar tráfico interbancario hacia el ISP si ninguna ruta más específica está disponible.

### Pruebas de Fallo Controlado

**Escenario documentado y verificado (corte lógico del enlace Banco 1 ↔ Banco 2, 2026-09-10/11):**

| Métrica | Valor |
| :--- | :--- |
| **Tiempo de recuperación** | No cronometrado formalmente en un drill dedicado. Cota teórica según histéresis: **~6 s** para declarar la primaria caída (`delay down`) y reinstalar la flotante; **~3–5 s** para volver a la primaria al restaurarse el enlace (`delay up`). *(Pendiente: medición empírica con cronómetro/`debug`).* |
| **Ruta antes del fallo** | `10.0.0.16/30` vía `10.0.0.1` (Fa2/0, primaria, `track 20` UP). |
| **Ruta después del fallo** | `10.0.0.16/30` vía `10.0.0.6` (Fa3/0, flotante AD 100), confirmado con `show ip route 10.0.0.16 255.255.255.252` → `distance 100`. |
| **Cambios en tabla de routing** | `track 20`: `Up -> Down` (`%TRACKING-5-STATE`); ruta primaria retirada de la RIB; flotante instalada automáticamente sin intervención manual. |
| **Pérdida de paquetes / evidencia de servicio** | `curl http://10.0.0.10:8080/blacklist` y `curl http://10.0.0.18:8080/api/blacklist` responden **HTTP 200** tras la conmutación; traducción NAT confirmada como `10.20.1.34 -> 10.0.0.5` (cara sur) en `show ip nat translations`. No se midió porcentaje de pérdida de paquetes en tránsito (solo éxito/fallo de conexión TCP de aplicación). |

> Nota técnica adicional (hallazgo del 2026-09-11): la conmutación de **ruta** funcionaba correctamente desde el diseño original, pero el **NAT** tenía un bug independiente — dos reglas `ip nat inside source list <ACL> interface <intf> overload` con ACLs de origen solapadas, donde la primera declarada (Fa2/0) ganaba siempre sin importar la interfaz de salida real. Se corrigió reemplazando las ACLs planas por **NAT basado en route-map** (`NAT-NORTE` / `NAT-SUR`, cada uno con una ACL de destino mutuamente excluyente), de forma que la traducción sigue exactamente a la interfaz de egreso decidida por el routing. Ver detalle en `_coord_temp/BANCO2.md`.

---

## 2. Seguridad Interbancaria y Políticas de Comunicación

### Matriz de Comunicación (con los otros 4 bancos)
| Banco Destino | Servicios Permitidos | Servicios Bloqueados | Puertos Autorizados | Tráfico Restringido / Observaciones |
| :--- | :--- | :--- | :--- | :--- |
| **Banco 1** (vecino directo, `10.0.0.1`) | Banco 2 consulta blacklist de Banco 1 (`GET /api/blacklist`, con respaldo cruzando el anillo si el primario falla); Banco 2 publica su API interbancaria (`10.0.0.2:5001`) para que Banco 1 la use | Acceso directo de Banco 1 a la LAN interna (`10.20.0.0/16`) más allá del endpoint publicado | TCP 8080 (saliente, consulta), TCP 5001 (entrante, publicación) | Solo el servicio de blacklist y el endpoint interbancario están expuestos; el resto de la LAN de Banco 2 no es alcanzable desde Banco 1 |
| **Banco 3** (vecino directo, `10.0.0.6`) | Tránsito de tráfico hacia Banco 4/Banco 5 (Banco 3 es el salto intermedio del arco sur) | Consumo del servicio `POST /interbancaria` de Banco 3 (`10.0.0.6:80`) — **actualmente sin respuesta desde Banco 2** | — | `PENDIENTE DE CONFIRMACIÓN POR BANCO 3`: se sospecha que el firewall de Banco 3 no autoriza el origen `10.0.0.5` (Banco 2). No se ha podido confirmar si es bloqueo intencional o falla de config |
| **Banco 4** (2 saltos, vía Banco 3) | Banco 2 consulta blacklist de Banco 4 (`GET /blacklist`, primario `10.0.0.10` vía Banco 3, respaldo `10.0.0.13` dando la vuelta al anillo); Banco 2 publica su API (`10.0.0.5:5001` por la cara sur) | — | TCP 8080 (saliente), TCP 5001 (entrante) | El acceso es siempre en tránsito (no hay enlace físico directo); depende de la salud de Banco 3 como intermediario |
| **Banco 5** (2 saltos, vía Banco 1) | Ninguno funcional consumido todavía; solo se usa `10.0.0.17` como objetivo de sonda IP SLA (salud del camino, no un servicio de negocio) | Cualquier servicio de aplicación de Banco 5 (no probado, Banco 5 no publica servicios propios según `ESTADO_ANILLO.md`) | — | `PENDIENTE`: no hay contrato de comunicación de negocio definido con Banco 5 |

### Evidencias de Políticas Aplicadas
- **A nivel de routing:** el acceso interbancario solo es posible a través de las redes de tránsito `10.0.0.0/30` y `10.0.0.4/30`; no existe ninguna ruta que exponga `10.20.0.0/16` (LAN interna completa) a los demás bancos — solo el host `10.20.1.34:5001` (API) queda alcanzable, y únicamente por NAT estático puntual.
- **A nivel de NAT:** la publicación hacia afuera es explícita y mínima — dos entradas `ip nat inside source static tcp 10.20.1.34 5001 <IP-cara> 5001 extendable` (una por cada cara del router). No hay NAT genérico que exponga otros puertos/servicios internos.
- **A nivel de firewall (`FW-BANCO2`, Debian):** existe un firewall de 3 patas (WAN / LAN / DMZ) en la ruta de todo el tráfico interbancario entrante hacia `API-custom-1`, pero **las reglas `iptables`/`nftables` vigentes no se documentaron en este archivo** — requieren revisión directa en la consola de `FW-BANCO2`. `PENDIENTE DE CONFIRMACIÓN POR BANCO 2 (este banco)`.
- **Evidencia de tráfico permitido:** `curl http://10.0.0.1:8080/api/blacklist` y `curl http://10.0.0.10:8080/blacklist` devuelven 200 desde `API-custom-1` (`10.20.1.34`).
- **Evidencia de tráfico restringido:** intento de `API-custom-1` hacia `10.0.0.6:80` (`/interbancaria` de Banco 3) sin respuesta — pendiente de determinar si es política de Banco 3 o falla técnica.

---

## 3. Alta Disponibilidad y Resiliencia

### Topología del anillo (contexto grupal)
```text
[BANCO 1] <--- 10.0.0.0/30 ---> [BANCO 2] <--- 10.0.0.4/30 ---> [BANCO 3]
    ^                                                                 |
    |                                                            10.0.0.8/30
10.0.0.16/30                                                          |
    |                                                                 v
[BANCO 5] <------------------ 10.0.0.12/30 ------------------> [BANCO 4]
```
Banco 2 tiene exactamente **dos caras físicas** hacia el anillo (norte = Banco 1, sur = Banco 3) y depende de ambas para alcanzar, por tránsito, a Banco 4 y Banco 5.

### Caminos Principales y Alternativos por destino
| Destino remoto | Camino principal | Camino alternativo | Disparador de conmutación |
| :--- | :--- | :--- | :--- |
| Banco 1 (`10.0.0.0/30`) | Directo, Fa2/0 | Ninguno (enlace directo, sin respaldo lógico en R-WAN) | Caída física/L2 del enlace |
| Banco 3 (`10.0.0.4/30`) | Directo, Fa3/0 | Ninguno (enlace directo) | Caída física/L2 del enlace |
| Banco 4 (`10.0.0.8/30`, `10.0.0.12/30`) | Sur, vía Banco 3 (`10.0.0.6`) | Norte, vía Banco 1 (`10.0.0.1`) | `track 10` (sonda E2E a `10.0.0.10`) pasa a Down |
| Banco 5 (`10.0.0.16/30`) | Norte, vía Banco 1 (`10.0.0.1`) | Sur, vía Banco 3 (`10.0.0.6`) | `track 20` (sonda E2E a `10.0.0.17`) pasa a Down |

### Comportamiento ante fallos críticos (anillo/malla)
- **Falla de un enlace directo (B1–B2 o B2–B3):** el tráfico hacia las redes que dependían de esa cara conmuta a la flotante de la cara contraria (ver tabla arriba); el enlace directo caído en sí no tiene respaldo propio porque es la única conexión física de Banco 2 hacia ese vecino — la redundancia la da el **anillo completo**, no un segundo enlace físico hacia el mismo banco.
- **Falla de un enlace no adyacente (p. ej. Banco 3–Banco 4):** Banco 2 la detecta indirectamente porque su sonda E2E (`track 10`, objetivo `10.0.0.10`) deja de responder; conmuta su tráfico hacia `10.0.0.8/30`/`10.0.0.12/30` a la flotante norte, aunque su propio enlace físico con Banco 3 siga arriba.
- **Doble contingencia (dos enlaces caídos simultáneamente):** documentado como riesgo latente en `ESTADO_ANILLO.md` (§5.2) — si Banco 1 pierde su cara este (hacia Banco 5) y Banco 2 pierde su cara oeste (hacia Banco 4) al mismo tiempo, ambas flotantes cruzadas podrían activarse hacia `10.0.0.0/30`. Mitigado por el `Null0 /27` como descarte final, pero **sin garantía de convergencia limpia** — señalado como pendiente de análisis conjunto con el coordinador (Banco 3).
- **Protección anti-loop:** ruta de descarte `ip route 10.0.0.0 255.255.255.224 Null0 250` — si ninguna ruta primaria ni flotante es válida para una red del anillo, el tráfico se descarta localmente en vez de reenviarse indefinidamente o escaparse hacia el ISP.

### Resultados de pruebas (estado más reciente confirmado)
| Sonda | Objetivo (salto 2) | Resultado | Track |
| :--- | :--- | :--- | :--- |
| SLA 10 | `10.0.0.10` (Banco 4 vía Banco 3), fuente Fa3/0 | 18 éxitos / 1 fallo | `track 10` UP |
| SLA 20 | `10.0.0.17` (Banco 5 vía Banco 1), fuente Fa2/0 | 19 éxitos / 0 fallos (estado normal); **Down confirmado** durante corte B1–B2 del 2026-09-10/11 | `track 20` |

### Riesgos conocidos / pendientes
- Dependencia de que Banco 5 responda ICMP de forma sostenida para que `track 20` (y por transitividad la conmutación hacia `10.0.0.16/30`) sea confiable — reportado históricamente como inestable (`PENDIENTE DE CONFIRMACIÓN POR BANCO 5`).
- Falta ejecutar un **drill cronometrado** formal (corte físico controlado + medición de tiempo de recuperación y pérdida de paquetes con herramienta tipo `ping -c` continuo), tal como exige la parte grupal del proyecto.
- Reglas de firewall de `FW-BANCO2` no documentadas en este archivo (pendiente de revisión directa en consola).

---

*Documento generado a partir del análisis de la infraestructura GNS3 de Banco 2 y de la coordinación registrada en `_coord_temp/BANCO2.md` y `_coord_temp/ESTADO_ANILLO.md` del repositorio `red-bancaria`. Los puntos marcados `PENDIENTE` requieren confirmación adicional antes de considerarse definitivos para la entrega grupal.*
