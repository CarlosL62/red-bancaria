# Guía Técnica: Sondeo IP SLA de Extremo a Extremo (Salto 2) — Implementación de Banco 5

Este documento explica en detalle **cómo Banco 5 implementó el mecanismo de sondeo de extremo a extremo** propuesto originalmente por Banco 4 (`docs/GUIA_SONDEO_END_TO_END.md`), con una corrección técnica importante que **cualquier banco debería revisar antes de aplicar la plantilla original**, porque puede romper el failover de tráfico real de producción sin que se note de inmediato.

Todos los bancos del anillo usan **Cisco 7200** como router de borde interbancario, así que todo lo aquí descrito es replicable directamente con los mismos comandos IOS, cambiando solo IPs e interfaces.

---

## 1. Por qué esto importa (el problema real que resuelve)

Un router que solo monitorea a su **vecino directo** (salto 1) puede quedar "engañado": el vecino contesta ping perfectamente, pero ese vecino puede tener **su propio camino hacia el resto del anillo caído**. El router sigue enviando tráfico con confianza porque su sonda al vecino sigue en `Up`, y el tráfico se pierde silenciosamente un salto más adelante.

**Esto no es teórico — lo vivimos en carne propia en Banco 5, repetidas veces, durante el desarrollo:**

```
Banco5-Router#ping 10.0.0.13
Success rate is 100 percent (5/5)   ← Banco4 está vivo

Banco5-Router#traceroute 10.0.0.9
  1 10.0.0.13   ← responde real, Banco4 vivo
  2 10.0.0.13 !H ← pero Banco4 mismo dice "no puedo llegar a Banco3"
```

Con un track que solo mira al salto 1 (`10.0.0.13`), este escenario nunca se detecta: el track se queda en `Up` para siempre porque, técnicamente, Banco4 sí responde. El respaldo nunca se activa aunque el camino real esté roto.

---

## 2. El concepto: monitorear al vecino del vecino (salto 2)

En un anillo de 5 nodos, cada router tiene dos "caras" (una por cada dirección del anillo). Para cada cara:
- **Salto 1** = tu vecino directo.
- **Salto 2** = el vecino de tu vecino (el siguiente banco en esa dirección).

Con 5 nodos, 2 saltos en cada dirección cubren **el 100% de los otros 4 bancos** — no hace falta ir más lejos. Ejemplo desde Banco5:

```
Sentido "sur" (vía Banco4):  salto 1 = Banco4  →  salto 2 = Banco3
Sentido "norte" (vía Banco1): salto 1 = Banco1  →  salto 2 = Banco2
```

Monitoreando esos dos puntos (salto 2 en cada dirección), Banco5 tiene visibilidad de los 4 bancos vecinos, no solo de los 2 directamente conectados.

### ¿Necesitas saber quién es el "vecino de tu vecino"? Sí, obligatoriamente.

No es opcional ni se puede inferir localmente — necesitas la IP exacta del segundo salto en cada dirección, tomada de la tabla de direccionamiento oficial del anillo (`_coord_temp/ESTADO_ANILLO.md`) o confirmada directamente con tu vecino. Sin ese dato no puedes configurar la sonda de salto 2.

---

## 3. Qué información necesita reunir cada banco antes de empezar

Antes de tocar el router, reuní esta lista completa (usá la tabla del anillo, no supongas nada):

| Dato | Ejemplo (Banco5) | De dónde sale |
|---|---|---|
| Tus 2 interfaces de tránsito (nombre IOS + tu IP en cada una) | `Ethernet1/0` = `10.0.0.14`, `Ethernet1/1` = `10.0.0.17` | Tu propia configuración |
| Vecino directo en cada cara (salto 1) | `10.0.0.13` (Banco4), `10.0.0.18` (Banco1) | Tabla de direccionamiento del anillo |
| Vecino del vecino en cada cara (salto 2) | `10.0.0.9` (Banco3, detrás de Banco4), `10.0.0.2` (Banco2, detrás de Banco1) | Tabla de direccionamiento del anillo — pedísela al coordinador (Banco3) o a tu propio vecino si tenés dudas |
| Las redes `/30` que tu ruta primaria de cada cara debe controlar | Vía Banco4: `10.0.0.4/30` y `10.0.0.8/30`. Vía Banco1: `10.0.0.0/30` | Topología del anillo — todo lo que está "más allá" de tu vecino en esa dirección |
| **¿Tu objetivo de salto 2 coincide con una IP de servicio real que ya usás?** | Sí: `10.0.0.9` es la IP que usamos para las transferencias interbancarias reales con Banco3 | Revisar tu propia configuración de servicios/NAT — este dato decide qué método de anclaje usar (sección 5) |

Ese último punto es el más importante y el que casi todos van a pasar por alto — ver sección 5.

---

## 4. Tabla de objetivos de sonda (referencia del anillo completo)

Reproducida de la topología oficial, para que cada banco identifique su fila:

| Banco | Cara | Vecino directo (salto 1) | Objetivo salto 2 (extremo a extremo) | Redes que controla esa cara |
|---|---|---|---|---|
| Banco 1 | Oeste | `10.0.0.2` (B2) | `10.0.0.6` (B3) | `10.0.0.4/30`, `10.0.0.8/30` |
| Banco 1 | Este | `10.0.0.17` (B5) | `10.0.0.13` (B4) | `10.0.0.12/30` |
| Banco 2 | Sur | `10.0.0.6` (B3) | `10.0.0.10` (B4) | `10.0.0.8/30`, `10.0.0.12/30` |
| Banco 2 | Norte | `10.0.0.1` (B1) | `10.0.0.17` (B5) | `10.0.0.16/30` |
| Banco 3 | Sur | `10.0.0.10` (B4) | `10.0.0.14` (B5) | `10.0.0.12/30`, `10.0.0.16/30` |
| Banco 3 | Norte | `10.0.0.5` (B2) | `10.0.0.1` (B1) | `10.0.0.0/30` |
| Banco 4 | Oeste | `10.0.0.14` (B5) | `10.0.0.18` (B1) | `10.0.0.16/30` |
| Banco 4 | Este | `10.0.0.9` (B3) | `10.0.0.5` (B2) | `10.0.0.4/30`, `10.0.0.0/30` |
| **Banco 5** | **Sur** | **`10.0.0.13` (B4)** | **`10.0.0.9` (B3)** | **`10.0.0.4/30`, `10.0.0.8/30`** |
| **Banco 5** | **Norte** | **`10.0.0.18` (B1)** | **`10.0.0.2` (B2)** | **`10.0.0.0/30`** |

---

## 5. ⚠️ El error crítico que hay que evitar: anclar la sonda con una ruta `/32`

La forma más simple de evitar que la sonda "se contamine" con su propia ruta flotante (dependencia circular — ver sección 6) es fijarla con una ruta host `/32` sin track:

```cisco
ip route <IP_OBJETIVO_SALTO2> 255.255.255.255 <IP_VECINO_DIRECTO>
```

**Esto funciona para anclar la sonda, pero tiene un efecto secundario peligroso:** una ruta `/32` siempre gana por *longest prefix match* sobre cualquier ruta `/30`, **sin importar el AD**. Eso significa que esa ruta fija no solo dirige la sonda — **también dirige todo el tráfico real** que cualquier host de tu banco mande a esa IP exacta.

### Por qué esto nos afectó directamente en Banco 5

Nuestro objetivo de sonda hacia el sur es `10.0.0.9` — que es **exactamente la misma IP** que usamos para las transferencias interbancarias reales con Banco 3 (`POST http://10.0.0.9/interbancaria`). Si hubiéramos aplicado la ruta `/32` tal como la plantilla original sugiere, el día que Banco4 no pudiera reenviar hacia Banco3 (el escenario que justamente queremos detectar), **nuestras transferencias reales habrían seguido intentando salir por Banco4 para siempre** — la ruta fija nunca cede ante el respaldo, aunque el track sí detecte la falla y mueva las rutas `/30` generales. Habríamos ganado visibilidad de red a costa de romper el servicio que más nos importa.

**Antes de copiar la ruta `/32` de la plantilla, cada banco debe preguntarse:** *¿la IP de mi objetivo de salto 2 coincide con alguna IP de servicio real que yo llamo (API de transferencias, blacklist, etc.)?* Mirando la tabla de la sección 4: si tu objetivo de salto 2 es la IP de tránsito de un banco cuyo servicio consumís (por ejemplo, cualquiera que le hable a Banco3 en `10.0.0.6` o `10.0.0.9`, o a Banco4 en `10.0.0.10`/`10.0.0.13`), **es muy probable que tengas el mismo problema.**

### La solución que usamos: PBR local (`ip local policy route-map`)

En vez de una ruta que afecta *todo* el tráfico hacia esa IP, usamos una política de ruteo que **solo actúa sobre paquetes que el propio router genera** (como las sondas IP SLA) — el tráfico real que llega desde adentro de tu red y se reenvía (aunque después del NAT tenga la misma IP de origen que el router) sigue la tabla de rutas normal, con su track y su respaldo intactos, sin ninguna interferencia.

Esta es la misma técnica que **Banco 3 ya implementó de forma independiente** en su propio router (`RM-LOCAL-SLA`), lo cual confirma que es un patrón sólido y ya probado en más de un nodo del anillo.

---

## 6. Configuración completa paso a paso (genérica, aplicable a cualquier Cisco 7200 del anillo)

Reemplazá los placeholders (`<...>`) con los valores de tu fila en la tabla de la sección 4.

### Paso 1 — ACLs que identifican exclusivamente el tráfico de la sonda

El truco es que el ACL solo hace match si el **origen** es tu propia IP de tránsito (la que usa la sonda) **y** el **destino** es exactamente tu objetivo de salto 2. Ningún tráfico real de tus servidores tiene ese origen exacto (el origen de tráfico real es siempre un host interno, no la IP del router), así que el ACL nunca confunde una cosa con la otra.

```cisco
ip access-list extended ACL-SLA-<NOMBRE_CARA_1>
 permit icmp host <TU_IP_INTERFAZ_CARA_1> host <OBJETIVO_SALTO2_CARA_1>

ip access-list extended ACL-SLA-<NOMBRE_CARA_2>
 permit icmp host <TU_IP_INTERFAZ_CARA_2> host <OBJETIVO_SALTO2_CARA_2>
```

### Paso 2 — Route-map que fuerza el next-hop, solo para ese tráfico

```cisco
route-map RM-LOCAL-SLA permit 10
 match ip address ACL-SLA-<NOMBRE_CARA_1>
 set ip next-hop <IP_VECINO_DIRECTO_CARA_1>

route-map RM-LOCAL-SLA permit 20
 match ip address ACL-SLA-<NOMBRE_CARA_2>
 set ip next-hop <IP_VECINO_DIRECTO_CARA_2>
```

### Paso 3 — Activar la política local (afecta SOLO tráfico originado por el router)

```cisco
ip local policy route-map RM-LOCAL-SLA
```

Este único comando es la diferencia clave frente a la plantilla original: sin él, tendrías que usar rutas `/32` (riesgosas). Con él, el route-map de los pasos 1-2 solo aplica a paquetes que el propio router genera (como el IP SLA que sigue).

### Paso 4 — Sondas IP SLA de extremo a extremo

```cisco
ip sla 10
 icmp-echo <OBJETIVO_SALTO2_CARA_1> source-interface <INTERFAZ_CARA_1>
 frequency 5
ip sla schedule 10 life forever start-time now

ip sla 20
 icmp-echo <OBJETIVO_SALTO2_CARA_2> source-interface <INTERFAZ_CARA_2>
 frequency 5
ip sla schedule 20 life forever start-time now
```

**Nota sobre temporización:** la plantilla original de Banco4 usa `frequency 3` con `timeout 1000ms`. En Banco5 optamos por ser más conservadores (`frequency 5`, timeout por defecto de 5000ms) porque **medimos picos de RTT superiores a 1000ms** en el anillo durante las pruebas de esta semana (hasta 2432ms en un traceroute con múltiples saltos). Un timeout tan corto como 1000ms puede generar falsos positivos (flapping) en una topología con esta latencia variable. Recomendamos que cada banco revise su propia latencia observada antes de copiar los valores agresivos de la plantilla original.

### Paso 5 — Object Tracking con histéresis

```cisco
track 10 ip sla 10 reachability
 delay down 10 up 5

track 20 ip sla 20 reachability
 delay down 10 up 5
```

El `delay down 10 up 5` evita que un solo ping perdido dispare un failover en falso — el track necesita ver la falla sostenida por 10 segundos antes de declarar `Down`, y 5 segundos de éxito sostenido antes de volver a `Up`.

### Paso 6 — Rutas primarias condicionadas al track de salto 2

```cisco
ip route <RED_1_CARA_1> <MASCARA> <IP_VECINO_DIRECTO_CARA_1> track 10
ip route <RED_2_CARA_1> <MASCARA> <IP_VECINO_DIRECTO_CARA_1> track 10
ip route <RED_CARA_2>   <MASCARA> <IP_VECINO_DIRECTO_CARA_2> track 20
```

Si tu cara controla más de una red (como Banco5 con `10.0.0.4/30` y `10.0.0.8/30` hacia el sur), **ambas pueden compartir el mismo track** — si tu vecino directo no puede llegar al salto 2, es muy probable que tampoco pueda llegar a nada más allá, así que no hace falta un track por cada red.

### Paso 7 — Rutas flotantes de respaldo (sin cambios respecto al diseño de salto 1)

```cisco
ip route <RED_1_CARA_1> <MASCARA> <IP_VECINO_DIRECTO_CARA_2> 200
ip route <RED_2_CARA_1> <MASCARA> <IP_VECINO_DIRECTO_CARA_2> 200
ip route <RED_CARA_2>   <MASCARA> <IP_VECINO_DIRECTO_CARA_1> 200
```

El valor de distancia administrativa (200 en nuestro caso) es local a cada router — no necesita coincidir entre bancos, solo debe ser mayor que la distancia de la ruta primaria (por defecto 1).

### Paso 8 — Guardar

```cisco
end
write memory
```

---

## 7. Ejemplo completo real — configuración exacta aplicada en Banco 5

```cisco
! --- ACLs que identifican el trafico de las sondas ---
ip access-list extended ACL-SLA-B4-B3
 permit icmp host 10.0.0.14 host 10.0.0.9
ip access-list extended ACL-SLA-B1-B2
 permit icmp host 10.0.0.17 host 10.0.0.2

! --- Route-map + PBR local ---
route-map RM-LOCAL-SLA permit 10
 match ip address ACL-SLA-B4-B3
 set ip next-hop 10.0.0.13
route-map RM-LOCAL-SLA permit 20
 match ip address ACL-SLA-B1-B2
 set ip next-hop 10.0.0.18
ip local policy route-map RM-LOCAL-SLA

! --- Sondas IP SLA extremo a extremo ---
ip sla 10
 icmp-echo 10.0.0.9 source-interface Ethernet1/0
 frequency 5
ip sla schedule 10 life forever start-time now

ip sla 20
 icmp-echo 10.0.0.2 source-interface Ethernet1/1
 frequency 5
ip sla schedule 20 life forever start-time now

! --- Object Tracking ---
track 10 ip sla 10 reachability
 delay down 10 up 5
track 20 ip sla 20 reachability
 delay down 10 up 5

! --- Rutas primarias (condicionadas al track de salto 2) ---
ip route 10.0.0.4 255.255.255.252 10.0.0.13 track 10
ip route 10.0.0.8 255.255.255.252 10.0.0.13 track 10
ip route 10.0.0.0 255.255.255.252 10.0.0.18 track 20

! --- Rutas flotantes de respaldo ---
ip route 10.0.0.0 255.255.255.252 10.0.0.13 200
ip route 10.0.0.4 255.255.255.252 10.0.0.18 200
ip route 10.0.0.8 255.255.255.252 10.0.0.18 200

end
write memory
```

---

## 8. Comandos de verificación

```cisco
show track brief                     ! estado Up/Down de cada track
show ip sla configuration <N>        ! confirma destino y source-interface de cada sonda
show ip sla statistics <N>           ! RTT y numero de exitos/fallos
show route-map RM-LOCAL-SLA          ! contador de "Policy routing matches" — si sube, el PBR esta funcionando
show ip route static                 ! ruta activa (AD 1 = primaria, AD mayor = respaldo)
show ip route <IP_OBJETIVO_SALTO2>   ! DEBE mostrar la ruta /30 normal, NO una ruta /32 — confirma que el trafico real no esta secuestrado
```

El último comando es la prueba definitiva de que el PBR local está aislado correctamente: si en vez de la ruta `/30` normal ves una ruta `/32`, algo quedó mal configurado y el tráfico real corre riesgo.

---

## 9. Evidencia real de funcionamiento (Banco 5, producción)

Implementamos un vigía de solo lectura que registra cada cambio de estado sin intervenir en nada. Captura real de un evento de failover ocurrido en producción, el mismo día de la implementación:

```
[07-Sep 23:37:22] Vigia iniciado. Estado inicial:
[07-Sep 23:37:22]   track_10: Up
[07-Sep 23:37:22]   track_20: Up
[07-Sep 23:37:22]   10.0.0.4/30 (B2-B3): via 10.0.0.13 (Banco4), primaria
[07-Sep 23:37:22]   10.0.0.8/30 (B3-B4): via 10.0.0.13 (Banco4), primaria

[07-Sep 23:38:07] track 10: Up -> Down
[07-Sep 23:38:07] 10.0.0.4/30 (B2-B3): via 10.0.0.18 (Banco1), respaldo (AD 200)   (antes: via 10.0.0.13, primaria)
[07-Sep 23:38:07] 10.0.0.8/30 (B3-B4): via 10.0.0.18 (Banco1), respaldo (AD 200)   (antes: via 10.0.0.13, primaria)
```

El track de salto 2 detectó una falla real (Banco4 dejó de poder llegar a Banco3) y ambas rutas primarias conmutaron automáticamente al respaldo, en el mismo segundo, sin intervención manual. Este es exactamente el escenario que el monitoreo de solo salto 1 nunca hubiera detectado.

---

## 10. Resumen para quien solo quiere la conclusión

1. **Sí, necesitás conocer al vecino de tu vecino** (salto 2) — no es opcional, sacalo de la tabla oficial del anillo.
2. **No copies la ruta `/32` de la plantilla original sin revisar primero** si esa IP coincide con un servicio real que consumís — si coincide, usá `ip local policy route-map` en vez de la ruta fija.
3. Un solo track por cara alcanza para cubrir varias redes, si todas dependen del mismo camino.
4. Usá temporización conservadora (`frequency 5`, timeout por defecto) salvo que hayas medido que tu anillo tolera algo más agresivo.
5. Verificá siempre con `show ip route <objetivo>` que el tráfico real sigue la ruta `/30` normal, no una `/32` secuestrada.
