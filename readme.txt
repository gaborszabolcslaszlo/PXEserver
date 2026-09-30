# iVentoy PXE Server Dockerben

Ez a projekt egy Dockerben futó **iVentoy PXE szervert** tartalmaz Ubuntu Linux hoston.

A cél:

* PXE boot fizikai gépekről
* ISO fájlok kiszolgálása iVentoy segítségével
* ISO-k host könyvtárból történő mountolása
* a meglévő router használata DHCP szerverként
* iVentoy automatikus indítása Docker induláskor
* opcionálisan külön LAN IP-cím használata az iVentoy számára

---

# 1. Hálózati környezet

Jelenlegi hálózat:

```text
Router:
192.168.0.1

Linux host Wi-Fi:
wlp2s0
192.168.0.112/24

iVentoy:
192.168.0.112
```

A működő jelenlegi konfiguráció `network_mode: host` módban fut.

Az iVentoy Web UI:

```text
http://192.168.0.112:26000
```

Az iVentoy HTTP szolgáltatása:

```text
http://192.168.0.112:16000
```

---

# 2. Könyvtárszerkezet

Példa:

```text
PEXserver/
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── .env
├── isos/
│   └── ubuntu-26.04.1-desktop-amd64.iso
└── README.md
```

A jelenlegi ISO:

```text
/home/laca/Documents/Programok/PEXserver/isos/ubuntu-26.04.1-desktop-amd64.iso
```

---

# 3. .env

Példa:

```env
IVENTOY_VERSION=1.0.42

ISO_DIR=/home/laca/Documents/Programok/PEXserver/isos

PARENT_INTERFACE=wlp2s0

LAN_SUBNET=192.168.0.0/24
LAN_GATEWAY=192.168.0.1

PXE_IP=192.168.0.50
```

Az `ISO_DIR` azt a host könyvtárat jelenti, amelyben az ISO-k találhatók.

Például:

```text
ISO_DIR=/home/laca/Documents/Programok/PEXserver/isos
```

---

# 4. ISO fájlok

Az ISO-kat az `ISO_DIR` könyvtárba kell másolni.

Példa:

```text
/home/laca/Documents/Programok/PEXserver/isos/ubuntu-26.04.1-desktop-amd64.iso
```

Ellenőrzés:

```bash
ls -lh "$ISO_DIR"
```

A konténerben:

```bash
docker exec pxe-server ls -lh /iventoy/iso
```

Az ISO-nak itt is látszania kell:

```text
/iventoy/iso/ubuntu-26.04.1-desktop-amd64.iso
```

---

# 5. ISO jogosultságok

Az iVentoynak az ISO-t olvasnia kell.

Normális jogosultság például:

```text
-rw-rw-r-- 1 ubuntu ubuntu 6.1G ubuntu-26.04.1-desktop-amd64.iso
```

Ellenőrzés:

```bash
docker exec pxe-server test -r /iventoy/iso/ubuntu-26.04.1-desktop-amd64.iso \
  && echo "ISO OLVASHATO" \
  || echo "ISO NEM OLVASHATO"
```

Nem szükséges:

```bash
chmod 777
```

---

# 6. Docker indítás

A projekt könyvtárából:

```bash
docker compose up -d --build
```

Állapot:

```bash
docker compose ps
```

Log:

```bash
docker logs pxe-server
```

---

# 7. iVentoy indítása

Az entrypoint automatikusan indítsa el az iVentoyt:

```bash
/iventoy/iventoy.sh start
```

Ellenőrzés:

```bash
docker exec pxe-server /iventoy/iventoy.sh status
```

Például:

```text
iventoy is running, PID=15
```

Normál esetben nem kell kézzel futtatni:

```bash
docker exec pxe-server /iventoy/iventoy.sh start
```

---

# 8. iVentoy Web UI

Host network módban:

```text
http://192.168.0.112:26000
```

A Web UI segítségével ellenőrizhető az ISO lista és az iVentoy állapota.

---

# 9. Fontos: DHCP

A helyi router:

```text
192.168.0.1
```

DHCP szerverként működik.

Nem szabad két normál DHCP szervert véletlenszerűen párhuzamosan használni ugyanazon a LAN-on.

Korábban az iVentoy logban ez jelent meg:

```text
DHCP Internal mode port:67
```

majd:

```text
Client 192.168.0.109 is responsed by another server 192.168.0.1
```

Ez azt jelentette, hogy:

```text
Router DHCP
      +
iVentoy DHCP
```

egyszerre válaszolt.

Ez DHCP-konfliktust okozhat.

Az iVentoy DHCP-beállítását ezért a használt hálózati konfigurációhoz kell igazítani.

---

# 10. PXE boot ellenőrzése

A fizikai kliens gépen:

1. LAN kábellel csatlakozzon a hálózathoz.
2. PXE / Network Boot legyen engedélyezve a BIOS/UEFI-ben.
3. Boot menüből válaszd a hálózati bootot.
4. A kliens kapjon IP-címet.
5. Meg kell jelennie az iVentoy PXE menünek.
6. Válaszd ki az ISO-t.

Például:

```text
ubuntu-26.04.1-desktop-amd64.iso
```

---

# 11. Hasznos ellenőrzések

## iVentoy fut-e?

```bash
docker exec pxe-server /iventoy/iventoy.sh status
```

## ISO megvan-e?

```bash
docker exec pxe-server ls -lh /iventoy/iso
```

## ISO olvasható-e?

```bash
docker exec pxe-server test -r \
  /iventoy/iso/ubuntu-26.04.1-desktop-amd64.iso \
  && echo "ISO OLVASHATO"
```

## iVentoy portok

```bash
docker exec pxe-server ss -lntup
```

Fontos portok:

```text
26000/tcp   Web UI
16000/tcp   iVentoy HTTP
69/udp      TFTP
67/udp      DHCP, ha az iVentoy DHCP módja használva van
4011/udp    PXE
10809/tcp   iSCSI
3260/tcp    iSCSI
```

## iVentoy log

```bash
docker exec pxe-server tail -f /iventoy/log/log.txt
```

PXE boot közben ez különösen hasznos.

---

# 12. Külön IP-című iVentoy – ipvlan

Ha azt szeretnénk, hogy:

```text
Linux host:
192.168.0.112

iVentoy:
192.168.0.50
```

akkor az iVentoy konténert `ipvlan` hálózatra lehet tenni.

Ez előnyös, mert az iVentoy külön gépként jelenik meg a LAN-on.

Például:

```text
Router       192.168.0.1
Host         192.168.0.112
iVentoy      192.168.0.50
PXE kliens   192.168.0.x
```

---

# 13. ipvlan hálózat létrehozása

A fizikai Wi-Fi interfész jelen esetben:

```text
wlp2s0
```

Hozd létre:

```bash
docker network create -d ipvlan \
  --subnet=192.168.0.0/24 \
  --gateway=192.168.0.1 \
  -o parent=wlp2s0 \
  -o ipvlan_mode=l2 \
  pxe_ipvlan
```

Ellenőrzés:

```bash
docker network inspect pxe_ipvlan
```

---

# 14. Docker Compose külön IP-vel

A service-ben ne használjuk:

```yaml
network_mode: host
```

helyette:

```yaml
services:
  pxe:
    build:
      context: .
      args:
        IVENTOY_VERSION: ${IVENTOY_VERSION:-1.0.42}

    container_name: pxe-server
    hostname: pxe-server

    restart: unless-stopped
    privileged: true

    networks:
      pxe_lan:
        ipv4_address: ${PXE_IP}

    volumes:
      - ${ISO_DIR}:/iventoy/iso

networks:
  pxe_lan:
    driver: ipvlan

    driver_opts:
      parent: ${PARENT_INTERFACE}
      ipvlan_mode: l2

    ipam:
      config:
        - subnet: ${LAN_SUBNET}
          gateway: ${LAN_GATEWAY}
```

A `.env`:

```env
PARENT_INTERFACE=wlp2s0

LAN_SUBNET=192.168.0.0/24
LAN_GATEWAY=192.168.0.1

PXE_IP=192.168.0.50
```

---

# 15. ipvlan indítás

```bash
docker compose down
docker compose up -d --build
```

Ellenőrzés:

```bash
docker inspect pxe-server \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

Elvárt:

```text
192.168.0.50
```

A Web UI:

```text
http://192.168.0.50:26000
```

---

# 16. Fontos ipvlan sajátosság

Az `ipvlan` konténer és a host közötti közvetlen kommunikáció alapból problémás lehet.

Ez azt jelenti, hogy:

```text
Host 192.168.0.112
       |
       X
       |
iVentoy 192.168.0.50
```

a hostról nem feltétlenül érhető el közvetlenül.

Viszont a LAN többi gépe:

```text
Telefon
   |
   +------> 192.168.0.50
   |
PXE kliens
   |
   +------> 192.168.0.50
```

elérheti.

Ezért az ipvlan működését mindig egy **másik LAN gépről** is érdemes tesztelni.

Például:

```bash
curl http://192.168.0.50:26000
```

---

# 17. Host → ipvlan elérés

Ha a hostról is szeretnénk elérni a `192.168.0.50` címet, létrehozható host-oldali ipvlan interfész.

Példa:

```bash
sudo ip link add ipvlan-host \
  link wlp2s0 \
  type ipvlan mode l2
```

IP:

```bash
sudo ip addr add 192.168.0.49/24 dev ipvlan-host
```

Interfész bekapcsolása:

```bash
sudo ip link set ipvlan-host up
```

Teszt:

```bash
ping -c 3 192.168.0.50
```

és:

```bash
curl http://192.168.0.50:26000
```

---

# 18. VMware és azonos subnet problémája

Ha VMware is telepítve van, különösen figyelni kell arra, hogy ne legyen két hálózati interfész ugyanabban a subnetben.

Rossz példa:

```text
wlp2s0   192.168.0.112/24
vmnet8   192.168.0.37/24
```

Ilyenkor például:

```bash
ip route get 192.168.0.50
```

eredménye lehet:

```text
192.168.0.50 dev vmnet8 src 192.168.0.37
```

Ez hibás útvonalválasztást okozhat.

A VMware NAT hálózatát célszerű más subnetre tenni, például:

```text
192.168.100.0/24
```

miközben a fizikai LAN:

```text
192.168.0.0/24
```

marad.

---

# 19. Host network mód vs külön IP

## Host network

```yaml
network_mode: host
```

iVentoy:

```text
192.168.0.112
```

Előny:

* egyszerű
* nincs Docker hálózati izoláció
* hostról könnyen elérhető
* PXE szolgáltatások közvetlenül a host hálózatán működnek

Hátrány:

* nincs külön iVentoy IP
* az iVentoy portjai közvetlenül a hoston jelennek meg
* portütközés lehet

---

## ipvlan külön IP

iVentoy:

```text
192.168.0.50
```

Előny:

* külön hálózati IP
* a LAN számára önálló PXE szervernek látszik
* nem a host IP-jét használja

Hátrány:

* host → container kommunikáció külön kezelendő
* Wi-Fi interfészen az AP/driver támogatása fontos
* portok és DHCP/PXE működését külön kell tesztelni

---

# 20. TFTP port ütközés

Ha ezt látod:

```text
TFTP port is already in use
```

ellenőrzés:

```bash
sudo ss -lunp | grep :69
```

Ha például:

```text
users:(("in.tftpd",pid=2408,...))
```

látható, akkor egy külön TFTP szerver foglalja a portot.

Megnézhető:

```bash
systemctl status tftpd-hpa
```

Leállítás:

```bash
sudo systemctl stop tftpd-hpa
```

Automatikus indulás tiltása:

```bash
sudo systemctl disable tftpd-hpa
```

Ezután:

```bash
sudo ss -lunp | grep :69
```

majd az iVentoy indítása.

---

# 21. PXE hibakeresés

Ha a kliens ezt írja:

```text
No such file or directory
```

ne kezdjük az ISO jogosultságainak módosításával.

Először:

```bash
docker exec pxe-server ls -lh /iventoy/iso
```

majd:

```bash
docker exec pxe-server test -r \
  /iventoy/iso/ubuntu-26.04.1-desktop-amd64.iso \
  && echo "ISO OLVASHATO"
```

Ezután figyeljük a logot:

```bash
docker exec pxe-server tail -f /iventoy/log/log.txt
```

Ezután indítsuk a PXE bootot.

A logból kiderülhet:

* kapott-e DHCP kérést
* melyik kliensről van szó
* UEFI vagy BIOS boot
* milyen boot URL-t kapott
* milyen HTTP/TFTP kérés érkezik
* történt-e DHCP konfliktus

---

# 22. Példa működő PXE folyamatra

```text
PXE kliens
    |
    | DHCP
    v
Router / DHCP
192.168.0.1
    |
    | PXE információ
    v
iVentoy
192.168.0.112
vagy
192.168.0.50
    |
    | TFTP
    v
iPXE / iVentoy boot
    |
    | HTTP
    v
Ubuntu ISO
```

---

# 23. Docker újraépítése

Ha módosítottuk a Dockerfile-t:

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

Egyszerű Compose módosítás után:

```bash
docker compose down
docker compose up -d
```

ISO hozzáadása esetén általában nem kell újra buildelni:

```bash
docker compose restart
```

vagy szükség esetén:

```bash
docker exec pxe-server /iventoy/iventoy.sh stop
docker exec pxe-server /iventoy/iventoy.sh start
```

---

# 24. Gyors ellenőrző lista

Ha PXE nem működik:

```text
[ ] Docker konténer fut
[ ] iVentoy fut
[ ] ISO létezik /iventoy/iso alatt
[ ] ISO olvasható
[ ] Web UI elérhető
[ ] TFTP 69/UDP elérhető
[ ] HTTP 16000/TCP elérhető
[ ] DHCP konfiguráció helyes
[ ] nincs második DHCP szerver
[ ] nincs másik TFTP szerver
[ ] VMware nem használja ugyanazt a subnetet
[ ] PXE kliens Etherneten csatlakozik
[ ] iVentoy log ellenőrizve
```

---

# 25. Hasznos parancsok összefoglalva

### Konténer

```bash
docker compose ps
docker logs pxe-server
docker exec pxe-server /iventoy/iventoy.sh status
```

### ISO

```bash
docker exec pxe-server ls -lh /iventoy/iso
```

### Portok

```bash
docker exec pxe-server ss -lntup
sudo ss -lunp | grep :69
```

### Log

```bash
docker exec pxe-server tail -f /iventoy/log/log.txt
```

### Hálózat

```bash
ip addr
ip route
ip route get 192.168.0.50
```

### Docker hálózat

```bash
docker network ls
docker network inspect pxe_ipvlan
```

### Külön IP ellenőrzése

```bash
docker inspect pxe-server \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

---

# 26. Jelenlegi működő konfiguráció

A jelenlegi működő állapot:

```text
Linux host
192.168.0.112
    |
    +--- Docker iVentoy
         |
         +--- network_mode: host
         |
         +--- Web UI :26000
         +--- HTTP   :16000
         +--- TFTP   :69
         +--- PXE    :4011
```

ISO:

```text
/home/laca/Documents/Programok/PEXserver/isos/
└── ubuntu-26.04.1-desktop-amd64.iso
```

Konténerben:

```text
/iventoy/iso/
└── ubuntu-26.04.1-desktop-amd64.iso
```

Web UI:

```text
http://192.168.0.112:26000
```

A külön IP-s változatban az iVentoy címe:

```text
192.168.0.50
```

és a Web UI:

```text
http://192.168.0.50:26000
```
