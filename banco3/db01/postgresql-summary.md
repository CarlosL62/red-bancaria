# Resumen Técnico de DB01 (Servidor de Base de Datos Banco 3)

- **Nodo:** DB01 (Alpine Linux 3.18)
- **IP:** `172.16.3.2/29` (VLAN 30)
- **Gateway:** `172.16.3.1` (FW1 `eth1.30`)
- **Estado:** Verificado en vivo (2026-09-07)

---

## 1. Servicio y Configuración de PostgreSQL

- **Motor:** PostgreSQL (versión de Alpine Linux).
- **Directorio de datos:** `/data/postgresql/`.
- **Servicio OpenRC:** `postgresql` en nivel de ejecución por defecto (`rc-service postgresql status` = started).
- **Parámetro de escucha:** `listen_addresses = '*'` en `/data/postgresql/postgresql.conf`.
- **Puerto de escucha:** TCP `5432` en todas las interfaces (`0.0.0.0:5432` y `:::5432`).

---

## 2. Seguridad y Control de Acceso

La seguridad de la base de datos se implementa en profundidad a través de dos capas independientes:
1. **Perímetro de Red (Firewall FW1):** Solo se permite tráfico TCP hacia el puerto 5432 si el origen es la IP del servidor web (`172.16.2.2`). Cualquier otro origen (incluidos usuarios de VLAN 10 o bancos externos) es descartado silenciosamente por la política `drop` de FW1.
2. **Control de Acceso a Nivel Motor (`pg_hba.conf`):**
   - Conexiones locales (`127.0.0.1/32`, `::1/128`): método `trust`.
   - Conexiones de red externas: únicamente permitidas desde `172.16.2.2/32` (WEB01) exigiendo cifrado y autenticación fuerte `scram-sha-256`.

---

## 3. Base de Datos y Esquema

- **Base de datos:** `banca_digital`
- **Propietario / Usuario de aplicación:** `bancaweb`
- **Tabla principal:** `cuentas`
  - Campos: `id` (entero), `titular` (texto), `saldo` (numérico).
  - Consulta verificada desde WEB01: `SELECT id, titular, saldo FROM cuentas WHERE id = 1` devuelve saldo y titular correctamente.
