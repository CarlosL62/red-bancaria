# Protocolo de Coordinación Interbancaria Temporal

Este directorio (`_coord_temp/`) contiene la infraestructura de sincronización y estado vivo para los agentes de IA de los 5 bancos durante la fase de integración grupal.

> **IMPORTANTE:** Esta carpeta es temporal y será removida completamente antes de la entrega final del proyecto mediante un commit de limpieza. No agregarla a `.gitignore`.

---

## Reglas Obligatorias para Todos los Agentes

1. **Sincronización obligatoria antes de cualquier acción:**
   Antes de diagnosticar problemas interbancarios o proponer cambios de red, ejecutar siempre:
   ```bash
   git pull --ff-only
   ```

2. **Lectura obligatoria de contexto compartido:**
   Consultar siempre:
   * `_coord_temp/ESTADO_ANILLO.md` (visión global del anillo).
   * `_coord_temp/BANCOX.md` (archivo del propio banco y de bancos vecinos involucrados).

3. **Principio de exclusividad de edición:**
   Cada agente modifica **ÚNICAMENTE** su propio archivo (`BANCO1.md`, `BANCO2.md`, `BANCO3.md`, `BANCO4.md` o `BANCO5.md`).

4. **Coordinación global:**
   Banco 3 actúa como coordinador del estado global y mantiene `_coord_temp/ESTADO_ANILLO.md`.

5. **No intervenir configuraciones de otros bancos:**
   Ningún agente tiene autorización para conectarse a consolas, modificar configuraciones ni editar archivos de otros bancos.

6. **Actualización tras cambios relevantes:**
   Después de cualquier cambio aprobado en:
   * Interfaces de tránsito
   * Routing estático (primarias y flotantes)
   * IP SLA, sondas y Object Tracking
   * PBR / Route-maps
   * NAT interbancario y PAT saliente
   * Servicios publicados (`/interbancaria`, puertos HTTP)
   * Pruebas de failover
   El agente **DEBE** actualizar inmediatamente su respectivo `BANCOX.md`.

7. **Seguridad estricta y secretos:**
   **PROHIBIDO** almacenar o commitear contraseñas reales, tokens, claves privadas SSH, credenciales de bases de datos o secretos en estos archivos.

8. **Consulta previa antes de diagnosticar a otro banco:**
   Antes de diagnosticar a un banco vecino o asumir una falla externa, consultar primero su `BANCOX.md`.

9. **Manejo de información no confirmada:**
   Cualquier dato o estado no confirmado explícitamente por el agente del banco respectivo debe marcarse como:
   `PENDIENTE DE CONFIRMACIÓN POR BANCO X`.

10. **Sin suposiciones de vigencia:**
    No asumir que una configuración anterior sigue vigente sin verificar el commit más reciente de su archivo.

11. **Autorización previa intacta:**
    Las reglas de `AGENTS.md` locales siguen aplicando con máxima prioridad: ningún cambio en la red real puede ejecutarse sin aprobación expresa del usuario.

12. **Commits pequeños y aislados:**
    Hacer commits pequeños y descriptivos afectando exclusivamente su propio archivo `BANCOX.md`.
