# Documentación Técnica y Requisitos Interbancarios - Banco 5

> Banco 5: Banco con Segmentación Interna Avanzada. Fuente: configuración activa verificada en GNS3 (`CLAUDE.md` del proyecto, `_coord_temp/BANCO5.md`, `_coord_temp/ESTADO_ANILLO.md`). Última actualización: 2026-09-11.

---

## 1. Routing Interbancario (Estático y Failover)

### Tabla de Rutas Estáticas Interbancarias

| Ruta Principal / Alternativa | Destino (Red/IP) | Próximo Salto (Next-Hop) | Interfaz de Salida | Métrica / Prioridad |
| :--- | :--- | :--- | :--- | :--- |
| Conectada (sin ruta estática) | 10.0.0.12/30 (enlace B4↔B5) | — | Ethernet1/0 | Directa, AD 0 |
| Conectada (sin ruta estática) | 10.0.0.16/30 (enlace B5↔B1) | — | Ethernet1/1 | Directa, AD 0 |
| Principal | 10.0.0.4/30 (B2↔B3) | 10.0.0.13 (Banco4) | Ethernet1/0 | AD 1, gobernada por `track 10` |
| Alternativa (flotante) | 10.0.0.4/30 (B2↔B3) | 10.0.0.18 (Banco1) | Ethernet1/1 | AD 200 |
| Principal | 10.0.0.8/30 (B3↔B4) | 10.0.0.13 (Banco4) | Ethernet1/0 | AD 1, gobernada por `track 10` |
| Alternativa (flotante) | 10.0.0.8/30 (B3↔B4) | 10.0.0.18 (Banco1) | Ethernet1/1 | AD 200 |
| Principal | 10.0.0.0/30 (B1↔B2) | 10.0.0.18 (Banco1) | Ethernet1/1 | AD 1, gobernada por `track 20` |
| Alternativa (flotante) | 10.0.0.0/30 (B1↔B2) | 10.0.0.13 (Banco4) | Ethernet1/0 | AD 200 |

Los dos tramos directamente conectados (B4↔B5 y B5↔B1) no requieren ruta estática. Los otros tres tramos del anillo, ajenos a Banco 5, tienen ruta primaria por el camino corto y una flotante de respaldo dando la vuelta completa por el otro lado, con distancia administrativa (AD) 200 para que solo se instale si la primaria desaparece del RIB.

### Mecanismo de Recuperación (Failover)

- **Detección:** IP SLA + Object Tracking sobre ICMP echo (`frequency 5`, `delay down 10 up 5`) hacia los next-hops directos (`10.0.0.13` y `10.0.0.18`) y, en la revisión de extremo a extremo (Hop-2), hacia `10.0.0.9` (Banco3) y `10.0.0.2` (Banco2).
- **Anclaje sin afectar tráfico real (Local PBR):** las sondas Hop-2 se anclan con `ip local policy route-map RM-LOCAL-SLA`, que solo redirige paquetes originados por el propio router (las sondas), nunca el tráfico de tránsito/aplicación real — evita el problema de que una ruta `/32` fija habría anclado también las transferencias reales hacia `10.0.0.9` (misma IP que el endpoint interbancario de Banco3).
- **Comportamiento ante pérdida de un enlace físico:** al caer el track correspondiente, la ruta primaria (AD 1) se retira automáticamente del RIB y la flotante de respaldo (AD 200) se instala sola, sin intervención manual. Al restaurarse el enlace, el track vuelve a Up y el router regresa automáticamente a la ruta primaria.
- **Limitación de diseño conocida y documentada:** el mecanismo detecta "¿el vecino directo está vivo?" y, desde la migración a Hop-2, también "¿el vecino puede llegar más allá de sí mismo?" — pero sigue sin ser una solución de routing dinámico (BGP/OSPF); es floating static route + tracking activo.

### Pruebas de Fallo Controlado

Prueba realizada desconectando físicamente el enlace Banco5↔Banco4 (`enp7s0` puesto en `NO-CARRIER`), documentada en `CLAUDE.md` sección 3:

- **Tiempo de recuperación:** los tracks correspondientes pasan a Down en aproximadamente 10–90 s, según el temporizador `delay down 10` combinado con el momento exacto del corte dentro del ciclo de sondeo de 5 s.
- **Ruta antes del fallo:** `10.0.0.4/30` y `10.0.0.8/30` vía `10.0.0.13` (Banco4, Ethernet1/0) — primaria, AD 1.
- **Ruta después del fallo:** conmutación automática a `[200/0] via 10.0.0.18` (Banco1, Ethernet1/1).
- **Cambios en tablas de routing:** retiro automático de la primaria del RIB al caer el track; instalación automática de la flotante de respaldo; regreso automático a la primaria al reconectar el enlace, sin intervención manual en ningún sentido.
- **Pérdida de paquetes:** `ping 10.0.0.9` (Banco3) tras el failover — **100 % de éxito (5/5), 0 % de pérdida**, RTT ~52–64 ms. `traceroute 10.0.0.9` confirmó el camino largo real por el anillo: `10.0.0.18 (Banco1) → 10.0.0.2 (Banco2) → 10.0.0.6 (Banco3)`, 3 saltos limpios sin rebotes.

---

## 2. Seguridad Interbancaria y Políticas de Comunicación

### Matriz de Comunicación (con los otros 4 bancos)

| Banco Destino | Servicios Permitidos | Servicios Bloqueados | Puertos Autorizados | Tráfico Restringido / Observaciones |
| :--- | :--- | :--- | :--- | :--- |
| **Banco 4** | Consulta de API desde Servidor1 (172.20.5.130) hacia `http://10.0.0.13:8080` (`GET /health`, `GET /blacklist`) | Cualquier otro destino/puerto en Banco4; acceso directo de Cajas/RRHH/Sistemas/Admin a `eth0` (no existe, todo pasa por Servidor1) | TCP 8080 (saliente) | Excepción puntual en firewall: `FORWARD -i eth1.50 -o eth0 -d 10.0.0.13 -p tcp --dport 8080 -j ACCEPT`. NAT oculta la subred interna real (172.20.5.0/24); Banco4 solo ve `10.0.0.14`. |
| **Banco 3** (tránsito vía Banco4, o vía Banco1 en respaldo) | Transferencias interbancarias salientes desde Servidor1: `POST http://10.0.0.9:80/interbancaria` (endpoint definitivo confirmado el 7 de septiembre) | Cualquier otro destino/puerto; tráfico entrante desde Banco3 hacia VLANs internas de Banco5 | TCP 80 (saliente) | Excepción puntual en firewall hacia `10.0.0.9` (y `10.0.0.6`, mantenida temporalmente durante la discrepancia inicial de endpoint con Banco3, ya resuelta). Protocolo de negocio: débito local antes de llamar a la API; commit si `200 OK`, rollback si falla/timeout. Banco3 nunca toca cuentas de Banco5 directamente. |
| **Banco 1** | Solo conectividad L3 de tránsito (enlace directo `10.0.0.16/30`, usado como ruta de respaldo del anillo) | Todo tráfico de aplicación entrante desde `10.0.0.18` hacia las VLAN internas (no existe regla de excepción en `FORWARD`) | Ninguno a nivel de aplicación | No hay servicio de Banco1 consumido por Banco5 todavía, ni viceversa. `PENDIENTE DE CONFIRMACIÓN POR BANCO 1` sobre cualquier servicio a integrar entre ambos. |
| **Banco 2** | Ninguno — Banco2 no es vecino directo de Banco5 en el anillo | Todo (sin regla, no hay adyacencia física) | Ninguno | Cualquier tráfico entre Banco5 y Banco2 transita lógicamente por Banco1 o por Banco3/Banco4. Sin integración de servicios definida. `PENDIENTE DE CONFIRMACIÓN POR BANCO 2`. |

### Evidencias de Políticas Aplicadas

- **Modelo de filtrado:** política por defecto `DROP` en `INPUT` y `FORWARD` del firewall (`/etc/firewall-banco5.sh`), con `ACCEPT` explícito únicamente para `ESTABLISHED,RELATED` y las reglas puntuales de mínimo privilegio descritas en la matriz anterior. El router del borde (`Banco5-Router`) solo hace NAT/routing, no filtra tráfico entre VLAN.
- **NAT interbancario (route-map, no ACL simple):** 3 reglas independientes de `ip nat inside source route-map ... overload`, una por interfaz de salida real (Internet, Banco4, Banco1), para evitar que IOS traduzca con la interfaz incorrecta cuando varias reglas comparten el mismo rango de origen. Confirmado en producción: `172.20.5.130 → 10.0.0.14` visible en `show ip nat translations` hacia Banco4.
- **Capturas Wireshark/tcpdump de respaldo (`capturas/` del proyecto):**
  - `03_tcp_http.pcap`: handshake TCP completo + HTTP GET `/blacklist` exitoso hacia Banco4 (tráfico permitido).
  - `05_bloqueado.pcap`: 5 ICMP echo-request entrando por `eth0` hacia `172.20.5.130` sin ninguna respuesta — evidencia directa de la política DROP por defecto ante tráfico no autorizado desde el anillo.
  - `06_nat_antes.pcap` / `06_nat_despues_cli.txt`: par antes/después de la traducción NAT real hacia Banco4.

---

## 3. Alta Disponibilidad y Resiliencia

### Caminos Principales y Alternativos

- **Topología:** anillo físico de 5 nodos (B1↔B2↔B3↔B4↔B5↔B1). Banco5 es vecino directo únicamente de Banco4 (`10.0.0.12/30`) y Banco1 (`10.0.0.16/30`); a Banco2 y Banco3 se llega siempre por tránsito.
- **Camino principal hacia Banco3:** Banco5 → Banco4 (`10.0.0.13`) → Banco3, 2 saltos.
- **Camino alternativo hacia Banco3 (ante corte del enlace B4↔B5):** Banco5 → Banco1 (`10.0.0.18`) → Banco2 → Banco3, 3 saltos — verificado con tráfico real (100 % de éxito, ver sección 1).
- **Supervisión de extremo a extremo (Hop-2):** adoptada de una guía compartida por Banco4 en el repositorio de coordinación e implementada por los 5 bancos (con adaptaciones locales; Banco5 usa Local PBR para no afectar el tráfico real). Según la consolidación oficial del anillo (`_coord_temp/ESTADO_ANILLO.md`, mantenida por Banco3 como coordinador), al momento de esta documentación los 5 bancos reportan sus tracks Hop-2 en estado **Up**, con 0 bucles activos y convergencia completa del anillo.
- **Mitigación de bucles:** el diseño de rutas primarias/flotantes de todo el anillo evita, por construcción, que un banco reenvíe tráfico de vuelta hacia el mismo segmento del que vino; los bucles detectados durante la integración grupal (documentados en `ESTADO_ANILLO.md` secciones 5.1–5.5) se originaron en la interacción entre configuraciones de otros bancos y ya fueron resueltos.

### Justificación de mecanismos no implementados

- **HSRP:** No aplica en el diseño de Banco5. No existen gateways L3 redundantes hacia las VLAN internas — el Firewall es el único gateway (subinterfaces 802.1Q), y la resiliencia del proyecto se concentra deliberadamente en el borde interbancario (routing estático + IP SLA/tracking), no en redundancia de gateway L2 dentro de la red interna.
- **DMZ:** No aplica en el perfil individual de Banco5. No se expone ningún servicio propio hacia Internet público; el único NAT hacia el exterior es de salida (overload). Los servicios interbancarios (API de transferencias) se exponen únicamente hacia el anillo privado del proyecto (`10.0.0.0/30` por segmento), nunca hacia Internet.
