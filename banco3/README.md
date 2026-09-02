# Banco 3

Índice técnico de la banca digital / Fintech:

- R1: router de borde, enrutamiento y NAT
- SW1: VLAN, trunk y Port Security
- FW1: firewall nftables y enrutamiento inter-VLAN
- WEB01: nginx
- DB01: PostgreSQL
- PC-USR: cliente VLAN 10

Direccionamiento:

- FW1-R1: 172.16.0.0/30
- VLAN 10 Usuarios: 172.16.1.0/24
- VLAN 20 Web: 172.16.2.0/29
- VLAN 30 Database: 172.16.3.0/29
