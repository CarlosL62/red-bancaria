# Banco 3 (Banca Digital / Fintech)

Índice técnico y configuraciones de referencia de Banco 3:

## Componentes de Infraestructura
- **R1 (Router de borde):** Enrutamiento estático, IP SLA, tracks, NAT/PAT y Local PBR.
  - Configuración verificada: [`r1/running-config.txt`](r1/running-config.txt)
- **FW1 (Firewall perimetral e inter-VLAN):** Políticas de filtrado de estado con `nftables` y ruteo interno.
  - Ruleset verificado: [`fw1/nftables.nft`](fw1/nftables.nft)
  - Resumen de red y políticas: [`fw1/network-summary.md`](fw1/network-summary.md)
- **SW1 (Switch de acceso y distribución):** Segmentación VLAN 802.1Q, enlaces troncales y Port Security sticky.
  - Configuración verificada: [`sw1/running-config.txt`](sw1/running-config.txt)
- **WEB01 (Servidor Web y Backend):** Proxy reverso Nginx y microservicio Flask interbancario.
  - Configuración Nginx: [`web01/default.conf`](web01/default.conf)
  - Backend Flask (sanitizado): [`web01/interbanco_sanitized.py`](web01/interbanco_sanitized.py)
  - Resumen de servicios: [`web01/service-summary.md`](web01/service-summary.md)
- **DB01 (Base de Datos):** PostgreSQL relacional (`banca_digital`) con autenticación SCRAM-SHA-256.
  - Configuración pg_hba (sanitizada): [`db01/pg_hba-sanitized.conf`](db01/pg_hba-sanitized.conf)
  - Resumen del servicio de datos: [`db01/postgresql-summary.md`](db01/postgresql-summary.md)
- **PC-USR:** Cliente en VLAN 10 para pruebas del portal.

## Documentación y Evidencia
- **Documentación técnica integral:** [`../_coord_temp/BANCO3.md`](../_coord_temp/BANCO3.md)
- **Evidencia de verificación y pruebas en vivo:** [`../docs/BANCO3_VERIFICACION.md`](../docs/BANCO3_VERIFICACION.md)

## Direccionamiento Interno
- **FW1 - R1:** `172.16.0.0/30`
- **VLAN 10 (Usuarios):** `172.16.1.0/24` (GW: `172.16.1.1`)
- **VLAN 20 (Web DMZ):** `172.16.2.0/29` (GW: `172.16.2.1`)
- **VLAN 30 (Database):** `172.16.3.0/29` (GW: `172.16.3.1`)

## Enlaces de Tránsito Interbancarios
- **R1 - Banco 2:** `10.0.0.4/30` (IP R1: `10.0.0.6`, Vecino B2: `10.0.0.5`)
- **R1 - Banco 4:** `10.0.0.8/30` (IP R1: `10.0.0.9`, Vecino B4: `10.0.0.10`)
