# Guía de Implementación: Sondeo IP SLA de Extremo a Extremo (End-to-End) en el Anillo Interbancario

Esta guía técnica detalla la arquitectura, el principio de funcionamiento y la configuración exacta paso a paso para replicar en **routers Cisco IOS (L3)** el mecanismo de **monitoreo y conmutación IP SLA de Extremo a Extremo (End-to-End)** implementado con éxito en Banco 4.

---

## 1. El Problema del Sondeo Solo al Vecino Directo (Next-Hop / Line-Protocol)

En una topología en anillo de 5 nodos (B1 ↔ B2 ↔ B3 ↔ B4 ↔ B5), la mayoría de los bancos inicialmente configuraron sus tracks de dos formas:
1. **Monitoreo de protocolo de línea (`line-protocol`):** Solo detecta si el cable físico local está conectado.
2. **IP SLA al vecino directo (1 salto):** Solo verifica si el router adyacente contesta ping.

### ¿Por qué fallan estos dos métodos?
* **Punto ciego de tránsito:** Si tu router monitorea solo a su vecino directo (ej. B4 monitoreando a B3), el enlace puede estar `UP` y el vecino responder `echo reply`, pero ese vecino puede tener **caída su conexión hacia el resto del anillo**, tener rutas a `Null0`, o sufrir un fallo de enrutamiento interno.
* **Agujeros negros (Blackholes) y Bucles (Loops):** Tu router seguirá enviando tráfico confiadamente a través de ese vecino porque su track está `UP`, generando descarte silencioso de paquetes o rebotes infinitos (como el bucle B4↔B5 que experimentamos hacia `10.0.0.4/30`).

---

## 2. La Solución: Monitoreo de Extremo a Extremo (Hop 2 - Vecino del Vecino)

El principio de **Extremo a Extremo (End-to-End)** consiste en monitorear la salud del **camino completo** en cada sentido del anillo, auditando no solo al vecino directo (Salto 1), sino al **vecino de tu vecino (Salto 2)**.

```text
               [Banco 1]
             /           \
   10.0.0.0/30           10.0.0.16/30
         /                   \
   [Banco 2]               [Banco 5]
         \                   /
   10.0.0.4/30           10.0.0.12/30
             \           /
               [Banco 3]
                   |
              10.0.0.8/30
                   |
               [Banco 4] (Nosotros)
```

En un anillo de 5 nodos:
* **2 saltos hacia la derecha** cubren la mitad derecha del anillo.
* **2 saltos hacia la izquierda** cubren la mitad izquierda del anillo.
* Ambas mitades se encuentran en el nodo opuesto, garantizando **visibilidad total del 100% de la topología**.

### Beneficios Inmediatos:
1. **Detección temprana de cortes distantes:** Si el cable B3-B2 se corta, el router B4 lo detecta de inmediato porque la sonda al Hop 2 (B2) cae, conmutando el tráfico por B5 **antes de que los paquetes se pierdan**.
2. **Extinción automática de loops:** Ningún router activa rutas primarias hacia un camino sordo o bloqueado.
3. **Failover simétrico y determinista.**

---

## 3. Matriz de Direccionamiento y Objetivos de Sonda por Banco

Para implementar este mecanismo, cada banco necesita conocer:
1. **Sus interfaces de tránsito locales.**
2. **La IP de su Vecino Directo (Salto 1)** en cada cara.
3. **La IP del Vecino de su Vecino (Salto 2 - End-to-End)** en cada cara.

### Topología de Enlaces /30:
* **B1 ↔ B2:** `10.0.0.0/30` | B1 = `10.0.0.1`, B2 = `10.0.0.2`
* **B2 ↔ B3:** `10.0.0.4/30` | B2 = `10.0.0.5`, B3 = `10.0.0.6`
* **B3 ↔ B4:** `10.0.0.8/30` | B3 = `10.0.0.9`, B4 = `10.0.0.10`
* **B4 ↔ B5:** `10.0.0.12/30` | B4 = `10.0.0.13`, B5 = `10.0.0.14`
* **B5 ↔ B1:** `10.0.0.16/30` | B5 = `10.0.0.17`, B1 = `10.0.0.18`

---

### Tabla Maestra de Objetivos para cada Banco:

| Banco | Cara / Sentido | Vecino Directo (Hop 1) | Objetivo End-to-End (Hop 2 - Vecino del Vecino) | Redes Primarias que Controla |
|---|---|---|---|---|
| **Banco 1** | Sentido Horario (Oeste) | `10.0.0.2` (B2) | **`10.0.0.6` (B3)** | `10.0.0.4/30`, `10.0.0.8/30` |
| **Banco 1** | Sentido Anti-Horario (Este) | `10.0.0.17` (B5) | **`10.0.0.13` (B4)** | `10.0.0.12/30` |
| **Banco 2** | Sentido Horario (Sur) | `10.0.0.6` (B3) | **`10.0.0.10` (B4)** | `10.0.0.8/30`, `10.0.0.12/30` |
| **Banco 2** | Sentido Anti-Horario (Norte) | `10.0.0.1` (B1) | **`10.0.0.17` (B5)** | `10.0.0.16/30` |
| **Banco 3** | Sentido Horario (Sur) | `10.0.0.10` (B4) | **`10.0.0.14` (B5)** | `10.0.0.12/30`, `10.0.0.16/30` |
| **Banco 3** | Sentido Anti-Horario (Norte) | `10.0.0.5` (B2) | **`10.0.0.1` (B1)** | `10.0.0.0/30` |
| **Banco 4** | Sentido Horario (Oeste) | `10.0.0.14` (B5) | **`10.0.0.18` (B1)** | `10.0.0.16/30`, LAN B5 |
| **Banco 4** | Sentido Anti-Horario (Este) | `10.0.0.9` (B3) | **`10.0.0.5` (B2)** | `10.0.0.4/30`, `10.0.0.0/30` |
| **Banco 5** | Sentido Horario (Norte) | `10.0.0.18` (B1) | **`10.0.0.2` (B2)** | `10.0.0.0/30`, `10.0.0.4/30` |
| **Banco 5** | Sentido Anti-Horario (Sur) | `10.0.0.13` (B4) | **`10.0.0.9` (B3)** | `10.0.0.8/30` |

---

## 4. Desafío Crítico en Cisco IOS: Evitar la Dependencia Circular / Flapping

> [!WARNING]
> **El Comportamiento Trampa de Cisco IOS:**
> En Cisco IOS, cuando configuras `ip sla 1` con `icmp-echo <target> source-interface <interfaz>`, la opción `source-interface` **únicamente define la IP origen del paquete**, pero **NO fuerza la interfaz de salida**. El router Cisco sigue consultando su tabla de enrutamiento (FIB).
>
> Si la ruta primaria falla y el track conmuta a la ruta flotante (que da la vuelta por el otro lado del anillo), la siguiente sonda ICMP **empezará a salir por la interfaz contraria**. Si alcanza el destino dando la vuelta al anillo, el track se levantará (`UP`), reactivará la ruta rota, volverá a caer... provocando un bucle de flapping infinito.

### La Solución Definitiva en Cisco: Host Routes `/32` Fijas para las Sondas

Para aislar por completo las sondas SLA y evitar que jamás salgan por el camino opuesto, se debe agregar una **ruta estática `/32` fija** para cada IP monitoreada amarrada estrictamente a su vecino directo:

```cisco
! Fijar la sonda para que SOLO pueda salir por la interfaz y next-hop previstos:
ip route <IP_DESTINO_SONDA> 255.255.255.255 <NEXT_HOP_DIRECTO>
```

Como una ruta `/32` tiene la máxima longitud de prefijo (Longest Prefix Match), Cisco enviará los paquetes de prueba **exclusivamente a través de esa interfaz**, sin importar qué ocurra con las rutas `/30` o las rutas por defecto.

---

## 5. Plantillas de Configuración Listas para Aplicar en Cisco IOS

A continuación se presentan las configuraciones exactas para cada banco con routers Cisco.

---

### Configuración para BANCO 1 (Cisco IOS)

* Interfaz hacia B2: `GigabitEthernet0/1` (`10.0.0.1/30`)
* Interfaz hacia B5: `GigabitEthernet0/2` (`10.0.0.18/30`)

```cisco
configure terminal

! 1. Host routes fijas para amarrar las sondas y evitar dependencias circulares:
ip route 10.0.0.6 255.255.255.255 10.0.0.2
ip route 10.0.0.13 255.255.255.255 10.0.0.17

! 2. Sondas IP SLA (cada 3 segundos, timeout 1s):
ip sla 10
 icmp-echo 10.0.0.6 source-interface GigabitEthernet0/1
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 10 life forever start-time now

ip sla 20
 icmp-echo 10.0.0.13 source-interface GigabitEthernet0/2
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 20 life forever start-time now

! 3. Object Tracking con histéresis (delay):
track 10 ip sla 10 reachability
 delay down 6 up 3

track 20 ip sla 20 reachability
 delay down 6 up 3

! 4. Rutas Estáticas Primarias (asociadas al Track E2E):
ip route 10.0.0.4 255.255.255.252 10.0.0.2 track 10
ip route 10.0.0.8 255.255.255.252 10.0.0.2 track 10
ip route 10.0.0.12 255.255.255.252 10.0.0.17 track 20

! 5. Rutas Flotantes de Respaldo (AD 20):
ip route 10.0.0.4 255.255.255.252 10.0.0.17 20
ip route 10.0.0.8 255.255.255.252 10.0.0.17 20
ip route 10.0.0.12 255.255.255.252 10.0.0.2 20

end
write memory
```

---

### Configuración para BANCO 2 (Cisco IOS)

* Interfaz hacia B1: `FastEthernet2/0` (`10.0.0.2/30`)
* Interfaz hacia B3: `FastEthernet3/0` (`10.0.0.5/30`)

```cisco
configure terminal

! 1. Host routes fijas para amarrar las sondas:
ip route 10.0.0.10 255.255.255.255 10.0.0.6
ip route 10.0.0.17 255.255.255.255 10.0.0.1

! 2. Sondas IP SLA:
ip sla 10
 icmp-echo 10.0.0.10 source-interface FastEthernet3/0
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 10 life forever start-time now

ip sla 20
 icmp-echo 10.0.0.17 source-interface FastEthernet2/0
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 20 life forever start-time now

! 3. Object Tracking:
track 10 ip sla 10 reachability
 delay down 6 up 3

track 20 ip sla 20 reachability
 delay down 6 up 3

! 4. Rutas Estáticas Primarias:
ip route 10.0.0.8 255.255.255.252 10.0.0.6 track 10
ip route 10.0.0.12 255.255.255.252 10.0.0.6 track 10
ip route 10.0.0.16 255.255.255.252 10.0.0.1 track 20

! 5. Rutas Flotantes de Respaldo (AD 100):
ip route 10.0.0.8 255.255.255.252 10.0.0.1 100
ip route 10.0.0.12 255.255.255.252 10.0.0.1 100
ip route 10.0.0.16 255.255.255.252 10.0.0.6 100

end
write memory
```

---

### Configuración para BANCO 3 (Cisco IOS)

* Interfaz hacia B2: `FastEthernet1/0` (`10.0.0.6/30`)
* Interfaz hacia B4: `FastEthernet2/0` (`10.0.0.9/30`)

```cisco
configure terminal

! 1. Host routes fijas para amarrar las sondas:
ip route 10.0.0.1 255.255.255.255 10.0.0.5
ip route 10.0.0.14 255.255.255.255 10.0.0.10

! 2. Sondas IP SLA:
ip sla 10
 icmp-echo 10.0.0.1 source-interface FastEthernet1/0
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 10 life forever start-time now

ip sla 20
 icmp-echo 10.0.0.14 source-interface FastEthernet2/0
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 20 life forever start-time now

! 3. Object Tracking:
track 10 ip sla 10 reachability
 delay down 6 up 3

track 20 ip sla 20 reachability
 delay down 6 up 3

! 4. Rutas Estáticas Primarias:
ip route 10.0.0.0 255.255.255.252 10.0.0.5 track 10
ip route 10.0.0.12 255.255.255.252 10.0.0.10 track 20
ip route 10.0.0.16 255.255.255.252 10.0.0.10 track 20

! 5. Rutas Flotantes de Respaldo:
ip route 10.0.0.0 255.255.255.252 10.0.0.10 50
ip route 10.0.0.12 255.255.255.252 10.0.0.5 50
ip route 10.0.0.16 255.255.255.252 10.0.0.5 50

end
write memory
```

---

### Configuración para BANCO 5 (Cisco IOS)

* Interfaz hacia B4: `Ethernet1/0` (`10.0.0.14/30`)
* Interfaz hacia B1: `Ethernet1/1` (`10.0.0.17/30`)

```cisco
configure terminal

! 1. Host routes fijas para amarrar las sondas:
ip route 10.0.0.9 255.255.255.255 10.0.0.13
ip route 10.0.0.2 255.255.255.255 10.0.0.18

! 2. Sondas IP SLA:
ip sla 10
 icmp-echo 10.0.0.9 source-interface Ethernet1/0
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 10 life forever start-time now

ip sla 20
 icmp-echo 10.0.0.2 source-interface Ethernet1/1
 threshold 1000
 timeout 1000
 frequency 3
ip sla schedule 20 life forever start-time now

! 3. Object Tracking:
track 10 ip sla 10 reachability
 delay down 6 up 3

track 20 ip sla 20 reachability
 delay down 6 up 3

! 4. Rutas Estáticas Primarias:
ip route 10.0.0.8 255.255.255.252 10.0.0.13 track 10
ip route 10.0.0.4 255.255.255.252 10.0.0.13 track 10
ip route 10.0.0.0 255.255.255.252 10.0.0.18 track 20

! 5. Rutas Flotantes de Respaldo (AD 200):
ip route 10.0.0.8 255.255.255.252 10.0.0.18 200
ip route 10.0.0.4 255.255.255.252 10.0.0.18 200
ip route 10.0.0.0 255.255.255.252 10.0.0.13 200

end
write memory
```

---

## 6. Comandos de Verificación y Diagnóstico en Cisco

Una vez aplicada la configuración, el estado de la supervisión de extremo a extremo se valida con:

1. **Estado general de los tracks:**
   ```cisco
   show track brief
   ```
   *Debe mostrar los tracks en estado `UP`.*

2. **Estadísticas operativas de IP SLA:**
   ```cisco
   show ip sla statistics
   ```
   *Debe reflejar `Number of successes` incrementándose cada 3 segundos y 0 fallos.*

3. **Verificación de rutas en FIB:**
   ```cisco
   show ip route static
   ```
   *Las rutas primarias deben estar activas. Si se apaga o desconecta una interfaz de un vecino, el track correspondiente pasa a `DOWN` en ~6 segundos y la ruta flotante asume el tráfico de inmediato.*

---

## 7. Conclusión y Resumen Operativo

El monitoreo de Extremo a Extremo (Hop 2):
* Convierte el anillo en una topología autorreparable y predictiva.
* Elimina completamente los bucles generados por dependencias locales o colisión de flotantes ciegas.
* Permite que las transferencias bancarias y las llamadas REST interbancarias (`/interbancaria`, `/blacklist`, `/deposito`) continúen operando transparentemente incluso ante el corte de cualquier enlace del anillo.
