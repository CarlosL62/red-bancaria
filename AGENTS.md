# Reglas Obligatorias para Agentes de IA — Banco 3 (Fintech)

Este documento define los lineamientos y restricciones estrictas que todo agente de inteligencia artificial debe acatar al operar, diagnosticar, diseñar o modificar la infraestructura del proyecto **Banco 3 (Banca Digital / Fintech)**.

---

## 1. Fuentes de Consulta Obligatorias
Antes de formular diagnósticos o proponer modificaciones en la topología, configuraciones o código, el agente **DEBE** consultar obligatoriamente:
1. `PROYECTO_REDES2_BANCO3.pdf` — Enunciado oficial de la cátedra.
2. `ENUNCIADO.md` — Transcripción textual y estructurada del enunciado.
3. `PROJECT.md` — Documento técnico vivo con la arquitectura, estados y avance real de Banco 3.

---

## 2. Reglas Fundamentales de Arquitectura
* **No inventar requisitos:** Apegarse estrictamente a lo establecido en el enunciado oficial y las solicitudes explícitas del usuario.
* **Routing estrictamente estático:** Prohibido implementar protocolos de enrutamiento dinámico (RIP, OSPF, EIGRP, BGP). El enunciado prohíbe el routing dinámico bajo penalización académica.
* **HSRP únicamente ante gateways redundantes:** No configurar HSRP en Banco 3 a menos que exista un segundo router físico/virtual como gateway redundante real de la LAN.
* **Aislamiento de redes internas:** Las redes internas de Banco 3 (`172.16.1.0/24`, `172.16.2.0/29`, `172.16.3.0/29`) **NO** deben exponerse directamente ni anunciarse a otros bancos.
* **Uso exclusivo de redes de tránsito para interbanco:** Las comunicaciones interbancarias deben realizarse utilizando las IPs de tránsito de R1 (`10.0.0.6` hacia B2 y `10.0.0.9` hacia B4).
* **Diferenciación de NAT:** Separar claramente la lógica de NAT/PAT hacia Internet (`FastEthernet0/1`) de la lógica de NAT de publicación e interconexión interbancaria (`FastEthernet1/0` y `FastEthernet2/0`).
* **Principio de mínimo privilegio:** En firewall (FW1) y routers, abrir únicamente los puertos, protocolos e IPs expresamente requeridos.
* **No intervenir otros bancos:** El alcance de Banco 3 se limita a sus propios nodos (R1, FW1, SW1, WEB01, DB01, PCs locales). No modificar configuraciones en bancos externos.

---

## 3. Acciones que Requieren Aprobación Previa del Usuario
Antes de ejecutar cualquiera de los siguientes cambios, el agente debe explicar la propuesta técnica y esperar confirmación expresa:
* Asignación o modificación de direcciones IP, máscaras o gateways.
* Creación, modificación o eliminación de rutas estáticas.
* Reglas de NAT / PAT (Internet o interbancarias).
* Reglas de firewall (`nftables` / `iptables` en FW1).
* Creación o reasignación de VLANs e interfaces troncales.
* Cambios en cableado, topología o enlaces en GNS3.
* Modificaciones en servicios del sistema o arranque (OpenRC).
* Modificaciones en bases de datos (esquemas, tablas o datos no solicitados).
* Instalación de nuevos paquetes en los sistemas operativos.
* Eliminación de archivos en el sistema.

---

## 4. Metodología de Trabajo y Buenas Prácticas
* **Un cambio pequeño a la vez:** Evitar modificaciones acumuladas o monolíticas que dificulten el aislamiento de fallos.
* **Verificación mínima y precisa:** Tras cada cambio, ejecutar únicamente la prueba mínima necesaria para confirmar el efecto buscado. Evitar baterías excesivas de pruebas o escaneos ruidosos.
* **Estructura clara de comunicación:**
  * Explicar qué se cambia.
  * Por qué se cambia.
  * Qué componentes puede afectar.
* **Diferenciar roles de respuesta:** Separar de forma explícita:
  1. *Diagnóstico* (solo lectura, análisis de causa raíz).
  2. *Propuesta técnica* (estrategia y comandos exactos a ejecutar).
  3. *Ejecución de cambios autorizados*.
* **No realizar correcciones espontáneas no solicitadas:** Si se detecta un problema secundario, documentarlo y reportarlo antes de modificarlo.

---

## 5. Persistencia de Configuraciones
* Todo cambio aprobado y validado debe quedar configurado de forma permanente:
  * **Cisco IOS (R1, SW1):** Ejecutar `write memory` o `copy running-config startup-config`.
  * **Alpine Linux (FW1, WEB01, DB01):** Guardar en archivos de configuración persistentes (`/etc/nftables.nft`, `/etc/network/interfaces`, scripts `/opt/`, etc.).
  * No dejar soluciones temporales dependientes de comandos volátiles en memoria sin persistir.

---

## 6. Seguridad y Manejo de Secretos
* **Prohibido registrar credenciales reales:** No escribir contraseñas reales, hashes o tokens en `PROJECT.md`, `AGENTS.md`, `ENUNCIADO.md`, commits de Git ni en los informes de entrega.
* **Ocultar secretos en salida:** Anonimizar contraseñas o tokens en los logs y salidas presentadas al usuario.
* **No modificar credenciales del sistema** a menos que sea una instrucción expresa de seguridad.

---

## 7. Gestión de Control de Versiones (Git)
* Documentar los cambios significativos con mensajes descriptivos.
* Antes de cada commit, inspeccionar el `git status` y `git diff` para evitar incluir:
  * Archivos temporales o de prueba (`scratch/`).
  * Archivos `.bak` o copias redundantes.
  * Logs extensos de ejecución o capturas de red innecesarias.
  * Secretos o credenciales sensibles.

---

## 8. Parámetros Técnicos Críticos de Banco 3
* **WEB01:** `172.16.2.2` (Frontend Nginx 80, Backend Flask 5001).
* **DB01:** `172.16.3.2` (PostgreSQL 5432, base de datos `banca_digital`).
* **R1 hacia Banco 2:** `10.0.0.6/30` (FastEthernet1/0).
* **R1 hacia Banco 4:** `10.0.0.9/30` (FastEthernet2/0).
* **Resolución de integración:** No solicitar a otros bancos rutas hacia redes internas de Banco 3 si la arquitectura de NAT en R1 puede resolver el flujo de forma transparente y segura.

---

## 9. Coordinación Interbancaria Temporal (Fase de Integración)
Durante la fase de integración grupal en el repositorio compartido, el agente debe acatar permanentemente:
* **Sincronización:** Antes de diagnosticar o evaluar cualquier problema interbancario, ejecutar `git pull --ff-only`.
* **Lectura previa obligatoria:** Consultar `_coord_temp/ESTADO_ANILLO.md` y `_coord_temp/BANCO3.md`.
* **Validación de vecinos:** Consultar el archivo `_coord_temp/BANCOX.md` del banco respectivo antes de hacer afirmaciones sobre su estado o formular diagnósticos externos.
* **Actualización viva:** Actualizar `_coord_temp/BANCO3.md` inmediatamente después de cualquier cambio relevante en interfaces, routing, rutas flotantes, IP SLA, tracks, PBR, NAT o servicios.
* **Rol de Coordinador:** Banco 3 actúa como coordinador del estado global y es el responsable de mantener y consolidar `_coord_temp/ESTADO_ANILLO.md`.
* **Exclusividad:** Modificar únicamente `BANCO3.md` (y `ESTADO_ANILLO.md` como coordinador). Prohibido editar `BANCO1.md`, `BANCO2.md`, `BANCO4.md` o `BANCO5.md`.
* **Seguridad y secretos:** Prohibido registrar credenciales reales, contraseñas, hashes, claves privadas o tokens en cualquiera de los archivos de coordinación.
* **Aprobación de cambios de red:** Los cambios en la infraestructura real (IPs, rutas, NAT, firewall, etc.) siguen requiriendo aprobación expresa del usuario antes de ejecutarse.
