# Banco 3 (Banca Digital / Fintech) — Guía Operativa de Integración y Coordinación Interbancaria

Documento técnico vivo y oficial de coordinación interbancaria de **Banco 3**. Proporciona a los agentes de los demás bancos del anillo la información operativa precisa para integración transaccional, enrutamiento, resiliencia y políticas de seguridad perimetral.

---

## 1. Ficha Técnica y Direccionamiento de Tránsito

### Nodos de la Infraestructura de Banco 3
* **R1 (Cisco 3745):** Router de borde y gateway interbancario. Administra la salida a Internet (`Fa0/1`), conectividad hacia B2 (`Fa1/0`) y B4 (`Fa2/0`), enrutamiento estático con alta disponibilidad (IP SLA + Object Tracking + Local PBR) y NAT/PAT.
* **FW1 (Alpine Linux v3.20):** Firewall perimetral interno de estado (`nftables`). Gateway de todas las VLANs internas con política por defecto `DROP` en FORWARD e INPUT.
* **SW1 (Cisco IOSvL2):** Switch de acceso y distribución con VLANs 802.1Q (10, 20, 30) y troncal dot1q hacia FW1. Port-security restrictivo en puertos de acceso.
* **WEB01 (Alpine Linux v3.20, `172.16.2.2`):** Servidor frontend/backend en DMZ (VLAN 20). Nginx como reverse proxy (puertos 80, 8080, 8081) y Flask en background (`0.0.0.0:5001`).
* **DB01 (Alpine Linux v3.20, `172.16.3.2`):** Servidor de base de datos en VLAN 30. PostgreSQL 5432 escuchando exclusivamente para conexiones autorizadas de `172.16.2.2/32`.
* **PC-USR / FIREFOX-USR (VLAN 10):** Clientes de usuario para banca web. `PC-USR`: `172.16.1.2/24`, `FIREFOX-USR`: `172.16.1.3/24`, Gateway: `172.16.1.1` (FW1 `eth1.10`).

### Direccionamiento Interbancario (Enlaces de Tránsito)
| Enlace | Interfaz R1 | IP Banco 3 | IP Vecino | Subred | Estado Operativo |
|---|---|---|---|---|---|
| **B3 ↔ Banco 2 (Oeste)** | `FastEthernet1/0` | `10.0.0.6` | `10.0.0.5` (B2) | `10.0.0.4/30` | **UP / UP** |
| **B3 ↔ Banco 4 (Este)** | `FastEthernet2/0` | `10.0.0.9` | `10.0.0.10` (B4) | `10.0.0.8/30` | **UP / UP** |

### Redes Internas (Estrictamente Aisladas)
| Zona / Propósito | Subred | Máscara | Gateway (FW1) | Hosts Notables |
|---|---|---|---|---|
| **Tránsito R1 - FW1** | `172.16.0.0/30` | `255.255.255.252` | `172.16.0.1` (`eth0`) | `172.16.0.2` (R1 `Fa0/0`) |
| **VLAN 10: Usuarios** | `172.16.1.0/24` | `255.255.255.0` | `172.16.1.1` (`eth1.10`) | `172.16.1.2` (PC-USR), `172.16.1.3` (FIREFOX-USR) |
| **VLAN 20: DMZ Web** | `172.16.2.0/29` | `255.255.255.248` | `172.16.2.1` (`eth1.20`) | `172.16.2.2` (WEB01) |
| **VLAN 30: Base de Datos** | `172.16.3.0/29` | `255.255.255.248` | `172.16.3.1` (`eth1.30`) | `172.16.3.2` (DB01) |

> **Aislamiento Total:** Ninguna subred `172.16.0.0/16` se anuncia, enruta ni expone al anillo interbancario.

---

## 2. Cómo Deben Consumir a Banco 3 (Tráfico Inbound Interbancario)

Banco 3 expone su servicio transaccional mediante NAT estático en R1 y filtrado estricto por IP origen en el firewall FW1 (`nftables`).

### Puntos de Acceso Publicados
* **Cara Oeste (lado Banco 2 / vía B1-B2):**
  * **IP Destino:** `10.0.0.6`
  * **Puerto Externo:** `80` (TCP)
  * **DNAT en R1:** Traduce `10.0.0.6:80` → `172.16.2.2:8080` (WEB01 Nginx)
  * **IP Origen Permitida en FW1:** **Únicamente `10.0.0.17`** (Banco 5 vía oeste)
* **Cara Este (lado Banco 4 / vía B4-B5):**
  * **IP Destino:** `10.0.0.9`
  * **Puerto Externo:** `80` (TCP)
  * **DNAT en R1:** Traduce `10.0.0.9:80` → `172.16.2.2:8081` (WEB01 Nginx)
  * **IP Origen Permitida en FW1:** **Únicamente `10.0.0.14`** (Banco 5 vía este)

### Endpoint Transaccional
* **Método y Ruta:** `POST /interbancaria`
* **Encabezado Requerido:** `Content-Type: application/json`

### Formato del Payload Esperado (JSON)
```json
{
  "cuenta_origen": 1001,
  "cuenta_destino": 2001,
  "monto": 50.00,
  "banco_origen": "Banco5"
}
```
* `cuenta_destino` (obligatorio, entero): Número de cuenta existente en Banco 3 (ej. 2001, 2002).
* `monto` (obligatorio, número flotante > 0): Valor a acreditar.
* `cuenta_origen` (opcional/descriptivo): Referencia de la cuenta origen en el banco emisor.
* `banco_origen` (opcional, string): Identificador del banco emisor.

### Respuestas del Servicio
* **Transacción Exitosa (HTTP 200 OK):**
  ```json
  {
    "ok": true,
    "mensaje": "Deposito interbancario recibido con exito",
    "saldo": 1050.0
  }
  ```
* **Error de Validación de Datos (HTTP 400 Bad Request):**
  ```json
  {
    "ok": false,
    "error": "El monto debe ser mayor a 0"
  }
  ```
* **Cuenta Destino No Encontrada (HTTP 404 Not Found):**
  ```json
  {
    "ok": false,
    "error": "Cuenta destino no encontrada"
  }
  ```

### Comportamiento ante Errores y Bloqueos de Seguridad
1. **Envío desde una IP NO autorizada:**
   * Ejemplo: Banco 4 intentando consumir directamente desde `10.0.0.10`, o Banco 1 desde `10.0.0.1`.
   * **Resultado:** R1 efectúa el DNAT en el borde, pero el firewall perimetral FW1 aplica la política por defecto `chain forward policy drop`. El paquete es **descartado silenciosamente (DROP)**. No se emite RST ni ICMP Unreachable; la conexión del cliente finaliza por `Connection timed out`.
2. **Envío al puerto o ruta equivocada:**
   * Intentos hacia puertos internos (ej. `5001` Flask o `5432` PostgreSQL): R1 no tiene reglas de DNAT para esos puertos; el tráfico no entra a la DMZ y es descartado.
   * Intentos en puerto 80 público hacia rutas distintas de `/interbancaria`: Nginx devuelve `404 Not Found`.

---

## 3. Cómo Consume Banco 3 a Banco 1 (Tráfico Outbound Interbancario)

### Endpoint Utilizado
Banco 3 consume a Banco 1 a través del endpoint oficial:
* **Endpoint Primario:** `http://10.0.0.18:80/interbancaria`
* **Endpoint de Contingencia:** `http://10.0.0.1:80/interbancaria` (fallback exclusivo ante fallos de conexión a nivel de socket previo al envío).

### Por qué Banco 3 NO debe cambiar ese Endpoint
* **Resiliencia de Capa 3 Garantizada:** La tabla de enrutamiento de R1 cuenta con convergencia hacia la subred `10.0.0.16/30` (donde reside `10.0.0.18`) en ambos sentidos del anillo:
  * Arco Este (Primaria): `10.0.0.16/30 via 10.0.0.10 track 2` (AD 1).
  * Arco Oeste (Respaldo): `10.0.0.16/30 via 10.0.0.5 10 track 1` (AD 10).
* Por lo tanto, el endpoint `10.0.0.18` es completamente tolerante a fallos y no requiere ser modificado por contingencias en los enlaces.

### Por qué Banco 3 NO usa 10.0.0.1 como Endpoint de Aplicación
* La dirección `10.0.0.1` es la IP de tránsito del enlace físico B1-B2, utilizada para la supervisión de vecindad de Capa 3 (IP SLA 1). El servicio transaccional de Banco 1 está publicado y operativo en su interfaz interbancaria `10.0.0.18`.

### Manejo de Transaccionalidad y Timeouts
La aplicación `/opt/interbanco.py` de WEB01 implementa un esquema transaccional atómico y defensivo:
1. **Reserva y Validación Local:** Bloquea la cuenta local con `SELECT ... FOR UPDATE` en PostgreSQL, verifica saldo y ejecuta el débito provisional.
2. **Llamada HTTP:** Ejecuta POST con un timeout de conexión de 5 segundos.
3. **Rechazo por Banco 1 (`urllib.error.HTTPError`):** Si Banco 1 devuelve un código de error HTTP (4xx o 5xx), Banco 3 ejecuta un `ROLLBACK` inmediato en la base de datos, revierte el saldo local y responde `502 Bad Gateway` adjuntando el detalle retornado por Banco 1. **No se reintenta en ningún otro endpoint**, respetando la respuesta del banco emisor.
4. **Fallo de Transporte Previo al Envío:** Si se produce un fallo neto de capa de transporte previo a la transmisión de datos (`Connection refused`, `Network is unreachable`, `No route to host`), se conmuta al endpoint secundario.
5. **Supresión de Reintento ante Timeout Ambiguo:** Si la conexión fue iniciada pero se agota el temporizador (`socket.timeout` o `TimeoutError`), Banco 3 **suprime cualquier reintento automático** para reducir el riesgo de acreditación duplicada en Banco 1. Se ejecuta `ROLLBACK` local de los fondos debitados y se devuelve `504 Gateway Timeout`. *(Nota: este mecanismo corresponde a supresión de reintentos ante ambigüedad, no a idempotencia de protocolo).*

---

## 4. Arquitectura de Routing, Tracking y Failover de Banco 3

R1 implementa enrutamiento estático puro con alta disponibilidad basada en supervisión de 2 saltos (Hop-2), Local PBR y descarte de anillo.

### Sondas IP SLA y Object Tracking en R1
```text
! SLA 1: Monitorea Banco 1 (Hop-2) vía Banco 2 (Arco Oeste)
ip sla monitor 1
 type echo protocol ipIcmpEcho 10.0.0.1 source-interface FastEthernet1/0
 timeout 2000
 threshold 2000
 frequency 5
ip sla monitor schedule 1 life forever start-time now
track 1 rtr 1 reachability
 delay down 6 up 3

! SLA 2: Monitorea Banco 5 cara B1 (Hop-2) vía Banco 4 (Arco Este)
ip sla monitor 2
 type echo protocol ipIcmpEcho 10.0.0.17 source-interface FastEthernet2/0
 timeout 2000
 threshold 2000
 frequency 5
ip sla monitor schedule 2 life forever start-time now
track 2 rtr 2 reachability
 delay down 6 up 3

! SLA 3: Monitorea Banco 5 cara B4 (Hop-2) vía Banco 4 (Arco Este)
ip sla monitor 3
 type echo protocol ipIcmpEcho 10.0.0.14 source-interface FastEthernet2/0
 timeout 2000
 threshold 2000
 frequency 5
ip sla monitor schedule 3 life forever start-time now
track 3 rtr 3 reachability
 delay down 6 up 3
```

### Funciones de cada Track
* **Track 1 (UP):** Vigila la salud del arco oeste hasta B1 (`10.0.0.1`). Gobierna la primaria hacia `10.0.0.0/30` y habilita las flotantes hacia B2 (`10.0.0.16/30` y `10.0.0.8/30`).
* **Track 2 (UP):** Vigila la salud del segmento B5-B1 (`10.0.0.17`) por el arco este. Gobierna la primaria hacia `10.0.0.16/30`. Resuelve el punto ciego si B5-B1 cae mientras B4-B5 sigue UP.
* **Track 3 (UP):** Vigila la salud del segmento B4-B5 (`10.0.0.14`) por el arco este. Gobierna la primaria hacia `10.0.0.12/30` y habilita las flotantes hacia B4 (`10.0.0.0/30` y `10.0.0.4/30`).

### Mecanismo Local PBR (`RM-LOCAL-SLA`)
Para asegurar que las sondas ICMP salgan estrictamente por su cara asignada sin recurrir a rutas `/32`:
```text
ip access-list extended ACL-SLA-B4-B5-EAST
 permit icmp host 10.0.0.9 host 10.0.0.17
ip access-list extended ACL-SLA-B4-B5
 permit icmp host 10.0.0.9 host 10.0.0.14
ip access-list extended ACL-SLA-B2-B1
 permit icmp host 10.0.0.6 host 10.0.0.1

route-map RM-LOCAL-SLA permit 12
 match ip address ACL-SLA-B4-B5-EAST
 set ip next-hop 10.0.0.10
route-map RM-LOCAL-SLA permit 15
 match ip address ACL-SLA-B4-B5
 set ip next-hop 10.0.0.10
route-map RM-LOCAL-SLA permit 20
 match ip address ACL-SLA-B2-B1
 set ip next-hop 10.0.0.5

ip local policy route-map RM-LOCAL-SLA
```
* **Por qué Local PBR y NO rutas `/32` fijas:** Las rutas host `/32` fijas contaminan la tabla de enrutamiento (FIB) y secuestran el tráfico real por regla de prefijo más largo (*longest prefix match*), impidiendo la conmutación efectiva en escenarios de contingencia. Local PBR actúa **única y exclusivamente sobre paquetes ICMP originados localmente por el propio R1**, dejando el tráfico de datos y de tránsito interbancario 100% libre para seguir la FIB.

### Tabla de Rutas Estáticas, Flotantes y Descarte Null0
```text
! --- Rutas Primarias (AD 1, condicionadas a Object Tracking) ---
ip route 10.0.0.0 255.255.255.252 10.0.0.5 track 1
ip route 10.0.0.12 255.255.255.252 10.0.0.10 track 3
ip route 10.0.0.16 255.255.255.252 10.0.0.10 track 2

! --- Rutas Flotantes Validadas (AD 10, condicionadas a Track del camino alterno) ---
ip route 10.0.0.16 255.255.255.252 10.0.0.5 10 track 1
ip route 10.0.0.8 255.255.255.252 10.0.0.5 10 track 1
ip route 10.0.0.0 255.255.255.252 10.0.0.10 10 track 3
ip route 10.0.0.4 255.255.255.252 10.0.0.10 10 track 3

! --- Descarte de Anillo (Protección contra Bucles y Rebotes) ---
ip route 10.0.0.0 255.255.255.224 Null0 250
```

* **Distancia Administrativa REAL de Null0:** La ruta de descarte tiene una métrica/AD explícita de **250** (`ip route 10.0.0.0 255.255.255.224 Null0 250`).
* **Función de Null0:** Si tanto la ruta primaria como la flotante hacia una subred `/30` caen a DOWN, cualquier tráfico dirigido a esa subred es descartado inmediatamente a nivel local en R1, impidiendo bucles de rebote y evitando fugas hacia la ruta por defecto a Internet.

### Por qué NO hay Rebote entre B3 y B2
* Durante una caída del enlace B4-B5 (`10.0.0.12/30`), Banco 3 **no tiene configurada ninguna ruta flotante hacia Banco 2** para esa red. El tráfico hacia `10.0.0.14` cae de inmediato en `Null0 250` en R1. Al no reenviarse hacia B2, B2 jamás puede devolverlo hacia B3, eliminando por completo el rebote `B3 ↔ B2`.

### Por qué NO hay Bucle con B4
* Gracias al desacoplamiento de SLA 2 hacia `10.0.0.17`, si ocurre un corte exclusivo en el enlace B5-B1 (`10.0.0.16/30`), Track 2 pasa inmediatamente a DOWN y retira la ruta primaria hacia B4, activando la flotante por el oeste vía B2 (`track 1`). B3 no retiene una ruta falsa hacia B4 cuando el enlace posterior está caído.

---

## 5. Reglas de Interacción para Otros Bancos (Lo que NO deben hacer)

1. **No asumir que Banco 3 acepta tráfico desde cualquier IP:** FW1 opera bajo el principio de mínimo privilegio (`drop` por defecto). Únicamente se admiten las IPs autorizadas de Banco 5 (`10.0.0.14` por el este en 8081 y `10.0.0.17` por el oeste en 8080).
2. **No solicitar rutas hacia redes internas `172.16.x.x`:** Banco 3 mantiene total aislamiento perimetral. Todas las comunicaciones deben dirigirse a las IPs de tránsito de R1 (`10.0.0.6` o `10.0.0.9`).
3. **No enviar tráfico directamente a puertos internos:** Puertos como `5001` (Flask) o `5432` (PostgreSQL) no están expuestos ni mapeados externamente en R1. Cualquier intento a esos puertos será descartado por el router o por FW1.
4. **No asumir que el endpoint de Banco 1 debe cambiarse a `10.0.0.1` para B3:** Banco 3 ya tiene convergencia probada y soporte de failover hacia `http://10.0.0.18:80/interbancaria`.

---

## 6. Configuraciones Descartadas y Prohibición de Restaurar

Para evitar regresiones técnicas en el anillo, se documentan las configuraciones que fueron probadas y descartadas definitivamente:

1. **NO usar IP SLA 2 hacia `10.0.0.18`:**
   * *Motivo:* Generó más de 900 eventos de aleteo continuo (flapping) debido a asimetrías de enrutamiento y retornos en el anillo. La supervisión Hop-2 se realiza de manera limpia hacia `10.0.0.17` con 0 flaps.
2. **NO usar rutas host `/32` fijas para anclar sondas:**
   * *Motivo:* Secuestran el tráfico real debido a la regla de prefijo más específico (Longest Prefix Match) y anulan la conmutación de las rutas flotantes. El anclaje se realiza exclusivamente con Local PBR (`RM-LOCAL-SLA`).
3. **NO reactivar la ruta flotante `10.0.0.12/30 via 10.0.0.5 10`:**
   * *Motivo:* Al cortarse el segmento B4-B5, el segmento deja de existir físicamente. Desviarlo hacia Banco 2 obligaba a B2 a reenviarlo de vuelta a B3, creando un bucle de rebote `B3 ↔ B2`. El descarte en `Null0 250` extingue el tráfico de forma local y limpia.

---

## 7. Políticas de NAT y Tránsito Interbancario

* **Traducción Inbound:** DNAT en `10.0.0.6:80` → `172.16.2.2:8080` (oeste) y `10.0.0.9:80` → `172.16.2.2:8081` (este).
* **Traducción Outbound:** PAT con overload sobre `Fa1/0` y `Fa2/0` exclusivamente para tráfico generado por `172.16.2.2` hacia otros bancos.
* **Tránsito Interbancario:** Banco 3 **NO realiza NAT al tráfico de tránsito interbancario**. Los paquetes que fluyen entre Banco 2 y Banco 4 se enrutan de forma pura a nivel de Capa 3 sin modificar cabeceras IP.
