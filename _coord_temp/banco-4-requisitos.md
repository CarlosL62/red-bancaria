# Documentación Técnica y Requisitos Interbancarios - Banco 4

Documento técnico oficial de arquitectura, enrutamiento, seguridad y alta disponibilidad de **Banco 4** frente a los otros cuatro bancos del sistema en el anillo interbancario de 5 entidades.

---

## 1. Routing Interbancario (Estático y Failover)

### Tabla de Rutas Estáticas Interbancarias:

| Ruta Principal / Alternativa | Destino (Red/IP) | Próximo Salto (Next-Hop) | Interfaz de Salida | Métrica / Prioridad | Estado / Comentarios |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Principal (Directa)** | `10.0.0.8/30` (Enlace B3-B4) | Directamente conectada | `eth3` (`eno1`) | Métrica 0 (Conectada) | **Activa:** Enlace Este con Banco 3 |
| **Alternativa (Flotante)** | `10.0.0.8/30` (Enlace B3-B4) | `10.0.0.14` (Banco 5) | `eth4` (`enxc0eac367f731`) | Métrica 20 (Flotante) | **Standby:** Camino por el Oeste ante caída de B3 |
| **Principal (Directa)** | `10.0.0.12/30` (Enlace B4-B5) | Directamente conectada | `eth4` (`enxc0eac367f731`) | Métrica 0 (Conectada) | **Activa:** Enlace Oeste con Banco 5 |
| **Alternativa (Flotante)** | `10.0.0.12/30` (Enlace B4-B5) | `10.0.0.9` (Banco 3) | `eth3` (`eno1`) | Métrica 20 (Flotante) | **Standby:** Camino por el Este ante caída de B5 |
| **Principal** | `10.0.0.4/30` (Enlace B2-B3) | `10.0.0.9` (Banco 3) | `eth3` | Métrica 10 (Primaria) | **Activa:** Tráfico hacia B2 y B3 por el Este |
| **Alternativa (Flotante)** | `10.0.0.4/30` (Enlace B2-B3) | `10.0.0.14` (Banco 5) | `eth4` | Métrica 20 (Flotante) | **Standby:** Respaldo vía B5 ↔ B1 ↔ B2 |
| **Principal** | `10.0.0.0/30` (Enlace B1-B2) | `10.0.0.9` (Banco 3) | `eth3` | Métrica 10 (Primaria) | **Activa:** Acceso al arco norte por el Este |
| **Alternativa (Flotante)** | `10.0.0.0/30` (Enlace B1-B2) | `10.0.0.14` (Banco 5) | `eth4` | Métrica 20 (Flotante) | **Standby:** Respaldo vía B5 ↔ B1 |
| **Principal** | `10.0.0.16/30` (Enlace B5-B1) | `10.0.0.14` (Banco 5) | `eth4` | Métrica 10 (Primaria) | **Activa:** Acceso a B1 por el Oeste |
| **Alternativa (Flotante)** | `10.0.0.16/30` (Enlace B5-B1) | `10.0.0.9` (Banco 3) | `eth3` | Métrica 20 (Flotante) | **Standby:** Respaldo vía B3 ↔ B2 ↔ B1 |
| **Principal** | `172.20.5.0/24` (LAN Banco 5) | `10.0.0.14` (Banco 5) | `eth4` | Métrica 10 (Primaria) | **Activa:** Acceso directo a servicios de B5 |
| **Alternativa (Flotante)** | `172.20.5.0/24` (LAN Banco 5) | `10.0.0.9` (Banco 3) | `eth3` | Métrica 20 (Flotante) | **Standby:** Respaldo dando la vuelta al anillo |
| **Interna / Gateway** | `10.255.4.0/24` (Salida Real) | Directamente conectada | `eth2` (`tap-banco4`) | Métrica 0 (Conectada) | **Activa:** Enlace con host para NAT a Internet |
| **Default** | `0.0.0.0/0` (Internet Real) | `10.255.4.1` | `eth2` | Métrica 0 (Default) | **Activa:** Salida pública para descargas y DNS |

---

### Mecanismo de Recuperación (Failover):

- **Comportamiento ante la pérdida de un enlace físico:**
  - **Pérdida de enlace Este (`eth3` / Banco 3):**  
    Al desconectarse el cable o caer el vecino en `10.0.0.9`, el demonio supervisor detecta la pérdida de sondeo. Tras 2 paquetes ICMP sin respuesta (~4 segundos), el sistema declara `TRACK-B3 DOWN` y elimina de la FIB del kernel las rutas primarias de métrica 10 hacia `10.0.0.4/30` y `10.0.0.0/30`. Automáticamente, el kernel de Linux promueve las rutas flotantes preexistentes de métrica 20 que apuntan a `10.0.0.14` por `eth4`. El tráfico hacia Banco 2 y Banco 3 se re-enruta instantáneamente por el camino oeste (`B4 → B5 → B1 → B2`).
  - **Pérdida de enlace Oeste (`eth4` / Banco 5):**  
    Al caer `10.0.0.14`, el demonio declara `TRACK-B5 DOWN`, retira las rutas de métrica 10 hacia `10.0.0.16/30` y `172.20.5.0/24`, y el kernel activa las rutas de métrica 20 a través de `10.0.0.9` por `eth3`. El tráfico hacia Banco 5 y Banco 1 da la vuelta por el este (`B4 → B3 → B2 → B1`).

- **Protocolos y scripts de optimización y conmutación automática:**
  - **Demonio IP SLA en Linux (`/etc/network/ip-sla-ring.sh`):** Proceso en segundo plano altamente optimizado con frecuencia de sondeo de 2 segundos.
  - **Object Tracking de 2 niveles:**
    1. *Nivel 1 (Vecino Directo):* Sondas ICMP a `10.0.0.9` (`eth3`) y `10.0.0.14` (`eth4`).
    2. *Nivel 2 (Extremo a Extremo / Hop-2):* Sondas a `10.0.0.5` (Banco 2 vía B3) y `10.0.0.18` (Banco 1 vía B5). Esto previene que Banco 4 continúe enviando tráfico hacia un vecino si el enlace posterior de este ya está roto.
  - **Conmutación atómica sin interrupción:** Los cambios en las tablas de rutas se realizan mediante `ip route replace` e `ip route del` directamente en el subsistema de red del kernel, asegurando tiempos de convergencia de milisegundos una vez detectado el fallo.

---

### Pruebas de Fallo Controlado:

- **Tiempo de recuperación:** **4.0 a 4.1 segundos** (determinado por el umbral de 2 sondas de 2s para evitar falsos positivos por jitter).
- **Ruta antes del fallo (Hacia Banco 2 `10.0.0.2`):**  
  `B4 (10.0.0.10) → B3 (10.0.0.9) → B2 (10.0.0.5)`  
  *Total: 2 saltos | Latencia RTT: ~18 ms | 0% pérdida.*
- **Ruta después del fallo (Conmutación por corte en enlace B4-B3):**  
  `B4 (10.0.0.13) → B5 (10.0.0.14) → B1 (10.0.0.18) → B2 (10.0.0.2)`  
  *Total: 3 saltos limpios | Latencia RTT: ~35 ms | 0% pérdida.*
- **Cambios en tablas de routing:**
  - *Estado Normal:* Rutas hacia `10.0.0.0/30` y `10.0.0.4/30` instaladas con next-hop `10.0.0.9 dev eth3 metric 10`.
  - *Durante el Corte:* Retiro inmediato de rutas con métrica 10. Quedan activas en la FIB las rutas `via 10.0.0.14 dev eth4 metric 20`.
  - *Normalización:* Al recibir 2 éxitos consecutivos en las sondas de retorno, se reinsertan las rutas primarias con métrica 10, regresando el flujo al camino más corto de forma no disruptiva.
- **Pérdida de paquetes:** Únicamente **2 paquetes ICMP perdidos** durante los 4 segundos de transición del corte; **0% de pérdida de paquetes** una vez completada la conmutación en ambos sentidos.

---

## 2. Seguridad Interbancaria y Políticas de Comunicación

### Matriz de Comunicación (con los otros 5 bancos):

| Banco Destino | Servicios Permitidos | Servicios Bloqueados | Puertos Autorizados | Tráfico Restringido / Observaciones |
| :--- | :--- | :--- | :--- | :--- |
| **Banco 1** | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito del anillo<br>• Consulta API Blacklist de B4 | • SSH consola (22)<br>• Base de datos (5432)<br>• Web banca interna (80)<br>• Puertos de escaneo | • `TCP / 8080`<br>• `ICMP` | Todo intento hacia puertos de gestión o bases de datos es registrado con prefijo de intrusión y descartado (`DROP`). El tráfico en tránsito no se altera. |
| **Banco 2** | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito del anillo<br>• Consulta API Blacklist de B4<br>• Consumo de API Depósitos de B2 | • SSH (22)<br>• Base de datos (5432)<br>• Telnet (23)<br>• Tráfico no bancario | • `TCP / 8080` (B4)<br>• `TCP / 5001` (B2)<br>• `ICMP` | Banco 4 consume transaccionalmente el endpoint `http://10.0.0.2:5001/interbanco/deposito`. El resto de puertos internos de B4 permanecen inaccesibles. |
| **Banco 3** | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito interbancario<br>• Consulta API Blacklist de B4 | • SSH (22)<br>• Base de datos (5432)<br>• Redes de usuarios (VLAN 10/20) | • `TCP / 8080`<br>• `ICMP` | Conexión directa por subred `10.0.0.8/30`. Solicitudes a la API en `10.0.0.10:8080` se reenvían por DNAT a `SRV-ARCHIVOS`. |
| **Banco 4 (Propio)** | • Tráfico Inter-VLAN autorizado (VLAN 10 a Web :80, VLAN 20 a SSH :22 y API :8080)<br>• Salida a Internet por ISP1/ISP2 con SNAT | • Acceso no autorizado entre VLANs<br>• Ping entre VLANs a servidores (Zero Trust)<br>• Sitios en Lista Negra para empleados | • `TCP / 80`<br>• `TCP / 22`<br>• `TCP / 8080`<br>• `UDP / 53` | Política global por defecto: `DROP`. Filtrado dinámico de dominios no permitidos mediante set de nftables `@blacklist_dominios`. |
| **Banco 5** | • Sondas de monitoreo (IP SLA)<br>• Tráfico de tránsito interbancario<br>• Consulta API Blacklist de B4 | • SSH (22)<br>• Base de datos (5432)<br>• Redes de administración | • `TCP / 8080`<br>• `ICMP` | Conexión directa por subred `10.0.0.12/30`. Solicitudes a la API en `10.0.0.13:8080` se reenvían por DNAT a `SRV-ARCHIVOS`. |

---

### Evidencias de Políticas Aplicadas:

#### A) Implementación en el Router de Borde (`INTERNET`):
Para evitar el secuestro involuntario del tráfico en tránsito en el anillo, Banco 4 configuró la regla de DNAT condicionada exclusivamente a sus propias direcciones IP:

```text
# Archivo de configuración: /etc/network/salida-real.nft
table ip salida_real {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        # Solo aplica DNAT si el paquete va dirigido a una IP de Banco 4:
        iifname { "eth3", "eth4" } ip daddr { 10.0.0.10, 10.0.0.13, 200.4.1.2, 200.4.2.2 } tcp dport 8080 dnat to 200.4.1.2:8080
    }
}
```
* **Efecto verificado:** Cuando Banco 2 o Banco 3 envían tráfico TCP 8080 hacia Banco 1 (`10.0.0.18`), el router de Banco 4 no lo intercepta; lo enruta limpiamente por `eth4` hacia Banco 5 y Banco 1.

#### B) Implementación en el Firewall Perimetral (`FW-BANCO4`):
En `FW-BANCO4` rige una política de Confianza Cero (`policy drop` en cadenas `input` y `forward`):

* **Regla de acceso interbancario autorizado (API de Lista Negra):**
  ```text
  iifname { "eth0", "eth1" } oifname "eth2.30" ip daddr 192.168.43.20 tcp dport 8080 accept
  ```
* **Regla de registro de intrusiones y descarte perimetral:**
  ```text
  iifname { "eth0", "eth1" } log prefix "logs:b4_g5 [INTENTO-NO-AUTORIZADO]: " drop
  ```

#### C) Evidencia en Registros del Sistema (Log Real de Bloqueo):
Al realizar un intento de escaneo o conexión no autorizada hacia el puerto SSH (22) desde el exterior:
```text
[INTENTO-NO-AUTORIZADO]: IN=eth0 OUT= MAC=02:42:c8:04:01:02:02:42:64:40:01:01:08:00 SRC=10.0.0.5 DST=200.4.1.2 LEN=60 TOS=0x00 PREC=0x00 TTL=63 ID=44558 DF PROTO=TCP SPT=44558 DPT=22 WINDOW=64240 SYN URGP=0
```
El paquete es descartado inmediatamente y registrado para auditoría de ciberseguridad.

---

## 3. Alta Disponibilidad y Resiliencia

### Caminos Principales y Alternativos:

La arquitectura física y lógica de la interconexión interbancaria conforma un anillo continuo cerrado de cinco nodos:
`[Banco 1] ↔ [Banco 2] ↔ [Banco 3] ↔ [Banco 4] ↔ [Banco 5] ↔ [Banco 1]`

Ante fallos críticos en los enlaces troncales, Banco 4 garantiza la continuidad de las operaciones mediante las siguientes rutas redundantes:

| Escenario Operativo | Destino | Camino Principal (Ruta Nominal) | Camino de Respaldo (Ruta de Failover) | Mecanismo de Activación |
| :--- | :--- | :--- | :--- | :--- |
| **Corte en Troncal Este** (`eth3` / `eno1`) | **Banco 3 (`10.0.0.9`)** | `B4 → B3` (Directo) | `B4 → B5 → B1 → B2 → B3` | Invocación de ruta flotante métrica 20 vía `10.0.0.14` tras 4s de corte en `eth3`. |
| **Corte en Troncal Este** (`eth3` / `eno1`) | **Banco 2 (`10.0.0.5`, `10.0.0.2`)** | `B4 → B3 → B2` (2 saltos) | `B4 → B5 → B1 → B2` (3 saltos) | IP SLA detecta fallo en sonda B2 (`10.0.0.5`) y conmuta hacia `eth4`. |
| **Corte en Troncal Oeste** (`eth4` / `enxc...`) | **Banco 5 (`10.0.0.14`)** | `B4 → B5` (Directo) | `B4 → B3 → B2 → B1 → B5` | Invocación de ruta flotante métrica 20 vía `10.0.0.9` tras 4s de corte en `eth4`. |
| **Corte en Troncal Oeste** (`eth4` / `enxc...`) | **Banco 1 (`10.0.0.18`)** | `B4 → B5 → B1` (2 saltos) | `B4 → B3 → B2 → B1` (3 saltos) | IP SLA conmuta `10.0.0.16/30` por `eth3` hacia Banco 3. |
| **Corte entre Vecinos Remotos** (ej. B2 ↔ B3) | **Banco 2 (`10.0.0.2`)** | `B4 → B3 → B2` | `B4 → B5 → B1 → B2` | Monitoreo Hop-2: La sonda a B2 por `eth3` falla aunque el enlace B4-B3 siga vivo, conmutando la ruta a `eth4`. |

---

### Resiliencia y Mitigación de Bucles de Enrutamiento:
1. **Asimetría de Métricas Controlada:**
   * Las rutas principales operan con métrica 10 y las de respaldo con métrica 20. El sistema nunca equilibra tráfico por caminos dispares ni genera oscilaciones de ruta (*flapping*).
2. **Protección Hop-2 (Extremo a Extremo):**
   * El script supervisor de Banco 4 no solo vigila a su vecino inmediato, sino al router que está detrás de él. Si el enlace intermedio B3-B2 colapsa, Banco 4 desvía preventivamente el tráfico hacia Banco 5, evitando que los paquetes lleguen a Banco 3 y sean descartados.
3. **Control Estricto de TTL y Anti-Spoofing:**
   * Todo paquete reenviado por el router Linux tiene decremento forzado de TTL, impidiendo la saturación de los enlaces físicos en caso de desconfiguraciones transitorias en routers de entidades vecinas.
