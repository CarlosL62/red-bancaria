# Resumen Técnico de WEB01 (Servidor Web y Backend Banco 3)

- **Nodo:** WEB01 (Alpine Linux 3.18)
- **IP:** `172.16.2.2/29` (VLAN 20)
- **Gateway:** `172.16.2.1` (FW1 `eth1.20`)
- **Estado:** Verificado en vivo (2026-09-07)

---

## 1. Arquitectura de Servicios

WEB01 implementa una arquitectura en dos capas desacopladas:
1. **Frontend / Proxy Reverso:** Nginx (escuchando en puertos 80, 8080 y 8081).
2. **Backend API / Aplicación:** Flask en Python 3 (`/opt/interbanco.py`, servicio OpenRC `interbanco`, escuchando en puerto 5001).

---

## 2. Configuración de Nginx (`/etc/nginx/http.d/default.conf`)

### Server Block 1: Portal de Usuarios e Internet (`listen 80;`)
- **Raíz:** `/var/lib/nginx/html` (sirve portal web estático `index.html`).
- **Control de Acceso:** Bloqueo explícito devolviendo `404 Not Found` en:
  - `location = /interbancaria`
  - `location = /api/interbancaria`
  - `location = /api/interbancaria/`
- **Proxy API Local:** Redirige `/api/` a `http://127.0.0.1:5001/` para consumo legítimo de clientes locales.

### Server Block 2: Pasarela Interbancaria (`listen 8080; listen 8081;`)
- **Objetivo:** Recibir solicitudes de transacciones de bancos externos.
  - Puerto 8080: Asociado a DNAT de R1 desde Banco 2 (`10.0.0.6:80`).
  - Puerto 8081: Asociado a DNAT de R1 desde Banco 4 (`10.0.0.9:80`).
- **Endpoint:** `location = /interbancaria` con `proxy_pass http://127.0.0.1:5001/interbancaria;`.
- **Aislamiento:** Cualquier otra ruta (`location /`) devuelve `404 Not Found`.

---

## 3. Servicio Flask (`/opt/interbanco.py`)

- **Proceso:** Gestionado mediante OpenRC como `/etc/init.d/interbanco`.
- **Binding Real:** `0.0.0.0:5001` (confirmado mediante `ss -lntp`).
  *(Nota técnica: Aunque Nginx reenvía hacia `127.0.0.1:5001`, el socket de Python está enlazado a `0.0.0.0:5001`. El cortafuegos FW1 impide cualquier conexión externa directa al puerto 5001).*
- **Conexión a Base de Datos:**
  - Host: `172.16.3.2` (DB01)
  - Base de datos: `banca_digital`
  - Usuario: `bancaweb`
  - Autenticación: Contraseña gestionada de forma segura (sanitizada en repo).
- **Endpoints:**
  - `POST /interbancaria`: Procesa transacciones entrantes o salientes entre bancos.
  - `GET /cuenta/<id>`: Consulta saldo y titular desde la base de datos `banca_digital`.
