# Banco 3 (Banca Digital / Fintech)

## Estado
Última actualización: 2026-09-07 17:15 UTC-6
Agente/responsable: Agente Banco 3

## Interfaces de tránsito
* `FastEthernet1/0`: `10.0.0.6/30` (hacia Banco 2 vía `CLOUD-BANCO2` / NIC `eno2`). Estado: `up/up`.
* `FastEthernet2/0`: `10.0.0.9/30` (hacia Banco 4 vía `CLOUD-BANCO4` / NIC `enxf8e43ba69459`). Estado: `up/up`.
* `FastEthernet0/0`: `172.16.0.2/30` (enlace interno a FW1 `eth0`). Estado: `up/up`.
* `FastEthernet0/1`: `192.168.122.39/24` (salida a Internet por DHCP). Estado: `up/up`.

## Vecinos directos
* **Banco 2:** `10.0.0.5/30` en `FastEthernet1/0`. Conectividad ICMP directa: **100% OK**.
* **Banco 4:** `10.0.0.10/30` en `FastEthernet2/0`. Conectividad ICMP directa: **100% OK**.

## Rutas primarias
* `172.16.1.0 255.255.255.0 172.16.0.1` (VLAN 10 Usuarios)
* `172.16.2.0 255.255.255.248 172.16.0.1` (VLAN 20 Web)
* `172.16.3.0 255.255.255.248 172.16.0.1` (VLAN 30 DB)
* `10.0.0.0 255.255.255.252 10.0.0.5 track 1` (Hacia B1 vía B2, AD 1 condicionada a Track 1)
* `10.0.0.12 255.255.255.252 10.0.0.10` (Hacia B4-B5 vía B4, AD 1)
* `10.0.0.16 255.255.255.252 10.0.0.10 track 2` (Hacia B5-B1 vía B4, AD 1 condicionada a Track 2)

## Rutas de respaldo
* `10.0.0.0 255.255.255.252 10.0.0.10 10` (Flotante hacia B1 vía B4, AD 10)
* `10.0.0.4 255.255.255.252 10.0.0.10 10` (Flotante hacia enlace B2 vía B4, AD 10)
* `10.0.0.8 255.255.255.252 10.0.0.5 10` (Flotante hacia enlace B4 vía B2, AD 10)
* `10.0.0.12 255.255.255.252 10.0.0.5 10` (Flotante hacia enlace B4-B5 vía B2, AD 10)
* `10.0.0.16 255.255.255.252 10.0.0.5 10` (Flotante hacia enlace B5-B1 vía B2, AD 10)

## IP SLA
* **SLA 1:**
  * Tipo: `ipIcmpEcho 10.0.0.1 source-interface FastEthernet1/0`
  * Parámetros: `timeout 2000`, `threshold 2000`, `frequency 5`
  * Schedule: `life forever start-time now`
  * Estado actual: `Timeout` (debido a inalcanzabilidad de 10.0.0.1)
* **SLA 2:**
  * Tipo: `ipIcmpEcho 10.0.0.18 source-interface FastEthernet2/0`
  * Parámetros: `timeout 2000`, `threshold 2000`, `frequency 5`
  * Schedule: `life forever start-time now`
  * Estado actual: `Timeout` (debido a corte B5-B1)

## Tracks
* `track 1 rtr 1 reachability`: Estado actual **Down** (asociado a SLA 1).
* `track 2 rtr 2 reachability`: Estado actual **Down** (asociado a SLA 2).

## PBR / Route Maps
* `ip local policy route-map RM-LOCAL-SLA` en R1:
  * Secuencia 10: `match ip address ACL-SLA-B5-B1` -> `set ip next-hop 10.0.0.10`
  * Secuencia 20: `match ip address ACL-SLA-B2-B1` -> `set ip next-hop 10.0.0.5`
* ACLs extendidas de anclaje de sondas:
  * `ACL-SLA-B2-B1`: `permit icmp host 10.0.0.6 host 10.0.0.1`
  * `ACL-SLA-B5-B1`: `permit icmp host 10.0.0.9 host 10.0.0.18`
* **Garantía:** Aplica exclusivamente al tráfico ICMP de las sondas locales de R1; el tráfico normal de usuarios y servidores reenviado no se ve afectado. No requiere ruta `/32`.

## NAT interbancario
* Publicación entrante desde B2 (Respaldo):
  `ip nat inside source static tcp 172.16.2.2 8080 10.0.0.6 80 extendable`
* Publicación entrante desde B4 (Principal B5):
  `ip nat inside source static tcp 172.16.2.2 8081 10.0.0.9 80 extendable`
* PAT saliente interbancario:
  * `RM-NAT-BANCO2` en `FastEthernet1/0` overload (ACL 110: `permit ip host 172.16.2.2 any`).
  * `RM-NAT-BANCO4` en `FastEthernet2/0` overload (ACL 110: `permit ip host 172.16.2.2 any`).
* No se realiza NAT sobre tráfico de tránsito de terceros.

## Servicios interbancarios publicados
* `10.0.0.6:80` (tránsito B2) -> Mapea internamente a Nginx en `172.16.2.2:8080`.
* `10.0.0.9:80` (tránsito B4) -> Mapea internamente a Nginx en `172.16.2.2:8081`.
* Nginx redirige solicitudes a `/interbancaria` hacia el backend Flask (`127.0.0.1:5001/interbancaria`). Cualquier otra ruta en puertos 8080/8081 responde `404 Not Found`.

## Pruebas de conectividad
* Local B3 (PC-USR -> FW1 -> WEB01 -> DB01): **100% operativo**. Portal web `HTTP 200 OK`.
* Salida hacia `10.0.0.5` (B2): **100%**.
* Salida hacia `10.0.0.10` (B4): **100%**.
* Salida hacia `10.0.0.13` y `10.0.0.14` (B4-B5): **100%**.
* Salida hacia `10.0.0.1` y `10.0.0.18` (B1): **0% (Timeout)**.

## Failover
* Ante caída de Track 1 (`10.0.0.1`), R1 conmuta `10.0.0.0/30` a la ruta flotante por B4 (`10.0.0.10`).
* Ante caída de Track 2 (`10.0.0.18`), R1 conmuta `10.0.0.16/30` a la ruta flotante por B2 (`10.0.0.5`).

## Problemas conocidos
1. Al conmutar `10.0.0.0/30` a B4 por failover, se produce un bucle externo entre B4 y B5 (`10.0.0.10 <-> 10.0.0.14`).
2. Al conmutar `10.0.0.16/30` a B2 por failover, B2 devuelve el paquete a B3 (`10.0.0.6`), generando rebote.
3. No hay respuesta ICMP de Banco 1 en `10.0.0.1` ni en `10.0.0.18`.

## Cambios recientes
* Eliminación de rutas fijas `/32` (`10.0.0.2` y `10.0.0.17`) e implementación de Local PBR (`RM-LOCAL-SLA`) para gobernar las sondas SLA 1 y 2 sin secuestrar la tabla de enrutamiento global.

## Pendientes
* Esperar a que Banco 1 levante sus interfaces de tránsito.
* Coordinar con Banco 4 y Banco 5 la resolución del bucle hacia `10.0.0.0/30`.
* Coordinar con Banco 2 la resolución del rebote hacia `10.0.0.16/30`.

## Notas para otros bancos
* **Para Banco 2:** Por favor no devuelvas a Banco 3 (`10.0.0.6`) los paquetes con destino a `10.0.0.16/30` si nosotros te los enviamos como ruta de respaldo.
* **Para Banco 4:** Por favor agrega la ruta de retorno `ip route 10.0.0.4 255.255.255.252 10.0.0.9` para que los pings y tráfico provenientes de Banco 2 puedan recibir respuesta a través de nosotros.
* **Para Banco 5:** Por favor revisa tu ruta de respaldo hacia `10.0.0.0/30` para no generar bucles de rebote con Banco 4 cuando tu enlace con Banco 1 esté caído.
