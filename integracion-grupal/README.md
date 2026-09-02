# Integración grupal

Redes de tránsito propuestas:

- Banco 1 - Banco 2: 10.0.0.0/30
- Banco 2 - Banco 3: 10.0.0.4/30
- Banco 3 - Banco 4: 10.0.0.8/30
- Banco 4 - Banco 5: 10.0.0.12/30
- Banco 5 - Banco 1: 10.0.0.16/30

Para Banco 3:

- Enlace con Banco 2:
  - Banco 2 = 10.0.0.5
  - Banco 3 / R1 = 10.0.0.6
- Enlace con Banco 4:
  - Banco 3 / R1 = 10.0.0.9
  - Banco 4 = 10.0.0.10

Las rutas estáticas hacia las redes internas de los otros bancos, la configuración de GNS3 Cloud y la integración física grupal están pendientes. La integración física grupal se completará posteriormente. No deben inventarse prefijos internos de otros bancos.
