#!/usr/bin/env bash
set -Eeuo pipefail

# PXE boot server telepítő Debian/Ubuntu alapú Linuxhoz.
# A WafaiCloud útmutató DHCP + TFTP + PXELINUX felépítését követi,
# néhány biztonságosabb/automatizáltabb kiegészítéssel.
#
# FONTOS:
# - A script dnsmasq-ot DHCP szerverként konfigurálja.
# - Csak azon a hálózati interfészen hallgat, amit megadsz/felderít.
# - Ha a hálózaton már van DHCP szerver, NE futtasd DHCP módban.
# - A PXE klienseknek ugyanabban a Layer-2 hálózatban kell lenniük,
#   vagy DHCP relay/IP helper szükséges.
#
# Használat:
#   sudo bash install-pxe.sh
#   sudo bash install-pxe.sh --interface enp1s0 --server-ip 192.168.1.10 \
#       --dhcp-start 192.168.1.50 --dhcp-end 192.168.1.150
#
# Alapértelmezés: a szerver interfészének meglévő IPv4 hálózatából próbál
# értelmes DHCP tartományt képezni.

SCRIPT_NAME="$(basename "$0")"
TFTP_ROOT="/var/lib/tftpboot"
PXE_CONF="/etc/dnsmasq.d/pxe.conf"
BACKUP_DIR="/root/pxe-backup-$(date +%Y%m%d-%H%M%S)"

INTERFACE=""
SERVER_IP=""
NETMASK=""
DHCP_START=""
DHCP_END=""
GATEWAY=""
DNS_SERVER=""
DHCP_MODE="server"

die() {
    echo "HIBA: $*" >&2
    exit 1
}

log() {
    echo
    echo "==> $*"
}

usage() {
    cat <<EOF
Használat:
  sudo $SCRIPT_NAME [opciók]

Opciók:
  --interface IFACE       Hálózati interfész, pl. enp1s0
  --server-ip IP          A PXE szerver IPv4 címe
  --netmask MASK          Hálózati maszk, pl. 255.255.255.0
  --dhcp-start IP         DHCP pool kezdete
  --dhcp-end IP           DHCP pool vége
  --gateway IP            Default gateway (opcionális)
  --dns IP                DNS szerver (alapértelmezés: gateway, majd 1.1.1.1)
  --proxy-dhcp             Meglévő DHCP mellé proxy-DHCP mód (nem oszt IP-t)
  -h, --help              Súgó

Példa:
  sudo $SCRIPT_NAME \\
    --interface enp1s0 \\
    --server-ip 192.168.1.10 \\
    --netmask 255.255.255.0 \\
    --dhcp-start 192.168.1.50 \\
    --dhcp-end 192.168.1.150 \\
    --gateway 192.168.1.1

FONTOS:
  DHCP server módban a script saját DHCP szervert indít.
  Ha a routered/szervered már DHCP-t oszt, használd a --proxy-dhcp opciót,
  vagy konfiguráld a meglévő DHCP szervert PXE-re.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --interface) INTERFACE="${2:?Hiányzó érték: --interface}"; shift 2 ;;
        --server-ip) SERVER_IP="${2:?Hiányzó érték: --server-ip}"; shift 2 ;;
        --netmask) NETMASK="${2:?Hiányzó érték: --netmask}"; shift 2 ;;
        --dhcp-start) DHCP_START="${2:?Hiányzó érték: --dhcp-start}"; shift 2 ;;
        --dhcp-end) DHCP_END="${2:?Hiányzó érték: --dhcp-end}"; shift 2 ;;
        --gateway) GATEWAY="${2:?Hiányzó érték: --gateway}"; shift 2 ;;
        --dns) DNS_SERVER="${2:?Hiányzó érték: --dns}"; shift 2 ;;
        --proxy-dhcp) DHCP_MODE="proxy"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Ismeretlen opció: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Rootként kell futtatni: sudo bash $SCRIPT_NAME"

command -v ip >/dev/null || die "Az ip parancs nem található."

if [[ -z "$INTERFACE" ]]; then
    INTERFACE="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')"
fi
[[ -n "$INTERFACE" ]] || die "Nem sikerült automatikusan megtalálni a hálózati interfészt."

if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    die "Nem létező interfész: $INTERFACE"
fi

if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="$(ip -4 -o addr show dev "$INTERFACE" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')"
fi
[[ -n "$SERVER_IP" ]] || die "Nem található IPv4 cím az interfészen: $INTERFACE"

CIDR="$(ip -4 -o addr show dev "$INTERFACE" scope global | awk 'NR==1 {print $4}')"
[[ -n "$CIDR" ]] || die "Az interfésznek nincs globális IPv4 címe: $INTERFACE"

PREFIX="${CIDR#*/}"

# Egyszerű prefix -> netmask konverzió.
prefix_to_mask() {
    local p="$1" full oct rem
    full=$((p / 8))
    rem=$((p % 8))
    local out=()
    for ((i=0;i<4;i++)); do
        if (( i < full )); then
            out+=(255)
        elif (( i == full && rem > 0 )); then
            out+=($((256 - 2**(8-rem))))
        else
            out+=(0)
        fi
    done
    echo "${out[0]}.${out[1]}.${out[2]}.${out[3]}"
}

[[ -n "$NETMASK" ]] || NETMASK="$(prefix_to_mask "$PREFIX")"

if [[ -z "$GATEWAY" ]]; then
    GATEWAY="$(ip route show default dev "$INTERFACE" 2>/dev/null | awk 'NR==1 {print $3}')"
fi

if [[ -z "$DNS_SERVER" ]]; then
    DNS_SERVER="${GATEWAY:-1.1.1.1}"
fi

# Alapértelmezett DHCP pool: a tipikus /24 hálózat .50-.150.
if [[ -z "$DHCP_START" || -z "$DHCP_END" ]]; then
    IFS=. read -r a b c d <<< "$SERVER_IP"
    if [[ "$PREFIX" == "24" ]]; then
        DHCP_START="${DHCP_START:-$a.$b.$c.50}"
        DHCP_END="${DHCP_END:-$a.$b.$c.150}"
    else
        die "Nem /24 hálózat és nincs megadva DHCP pool. Add meg a --dhcp-start és --dhcp-end opciókat."
    fi
fi

# Csomagkezelő és disztribúció felismerése.
if [[ -f /etc/debian_version ]] && command -v apt-get >/dev/null; then
    PKG="apt"
elif command -v dnf >/dev/null; then
    PKG="dnf"
elif command -v yum >/dev/null; then
    PKG="yum"
else
    die "Nem támogatott Linux. Debian/Ubuntu vagy RHEL/Fedora alapú rendszer szükséges."
fi

install_packages() {
    log "Szükséges csomagok telepítése"

    if [[ "$PKG" == "apt" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        # dnsmasq saját TFTP-je elegendő; pxelinux/syslinux adja a BIOS PXE fájlokat.
        apt-get install -y dnsmasq pxelinux syslinux-common curl ca-certificates
    else
        "$PKG" install -y dnsmasq syslinux-tftpboot curl ca-certificates
    fi
}

find_pxelinux() {
    local f=""
    for f in \
        /usr/lib/PXELINUX/pxelinux.0 \
        /usr/share/syslinux/pxelinux.0 \
        /usr/lib/syslinux/pxelinux.0
    do
        [[ -f "$f" ]] && { echo "$f"; return 0; }
    done

    f="$(find /usr -type f -name pxelinux.0 2>/dev/null | head -n1 || true)"
    [[ -n "$f" ]] && { echo "$f"; return 0; }

    return 1
}

find_syslinux_files() {
    local f
    for f in \
        /usr/lib/syslinux/modules/bios/ldlinux.c32 \
        /usr/share/syslinux/ldlinux.c32 \
        /usr/lib/syslinux/modules/bios/libcom32.c32 \
        /usr/share/syslinux/libcom32.c32 \
        /usr/lib/syslinux/modules/bios/libutil.c32 \
        /usr/share/syslinux/libutil.c32 \
        /usr/lib/syslinux/modules/bios/vesamenu.c32 \
        /usr/share/syslinux/vesamenu.c32
    do
        if [[ -f "$f" ]]; then
            echo "$f"
        fi
    done
}

backup_existing() {
    log "Meglévő konfiguráció mentése: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    [[ -f /etc/dnsmasq.conf ]] && cp -a /etc/dnsmasq.conf "$BACKUP_DIR/dnsmasq.conf"

    if [[ -d /etc/dnsmasq.d ]]; then
        tar -C /etc -czf "$BACKUP_DIR/dnsmasq.d.tar.gz" dnsmasq.d 2>/dev/null || true
    fi
}

configure_tftp() {
    log "TFTP/PXE könyvtár létrehozása"
    mkdir -p "$TFTP_ROOT/pxelinux.cfg"
    chmod 0755 "$TFTP_ROOT"

    local pxelinux
    pxelinux="$(find_pxelinux)" || die "Nem találom a pxelinux.0 fájlt a telepített csomagokban."
    cp -f "$pxelinux" "$TFTP_ROOT/pxelinux.0"

    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        cp -f "$f" "$TFTP_ROOT/"
    done < <(find_syslinux_files)

    # Az article vmlinuz/initrd fájlokat feltételez.
    # A script készít egy minimális PXE menüt, de a kernel/initrd párost
    # neked kell a választott disztribúcióhoz bemásolni.
    cat > "$TFTP_ROOT/pxelinux.cfg/default" <<'EOF'
DEFAULT menu.c32
PROMPT 0
TIMEOUT 50
ONTIMEOUT linux

MENU TITLE PXE Boot Server

LABEL linux
    MENU LABEL Linux installer
    KERNEL vmlinuz
    APPEND initrd=initrd.img

LABEL local
    MENU LABEL Boot from local disk
    LOCALBOOT 0
EOF

    # Ha nincs menu.c32, a konfigurációt egyszerű default módra cseréljük.
    if [[ ! -f "$TFTP_ROOT/menu.c32" ]]; then
        cat > "$TFTP_ROOT/pxelinux.cfg/default" <<'EOF'
DEFAULT linux
PROMPT 0
TIMEOUT 50

LABEL linux
    KERNEL vmlinuz
    APPEND initrd=initrd.img
EOF
    fi

    # Placeholder fájlok létrehozása helyett inkább egyértelműen jelezzük,
    # hogy valódi kernel/initrd szükséges.
    touch "$TFTP_ROOT/.PUT_VMLINUZ_AND_INITRD_HERE"
}

configure_dnsmasq() {
    log "dnsmasq konfigurálása"

    mkdir -p /etc/dnsmasq.d

    cat > "$PXE_CONF" <<EOF
# Automatikusan létrehozta: $SCRIPT_NAME
# Létrehozás: $(date -Is)

# Csak a PXE interfészen működjön.
interface=$INTERFACE
bind-interfaces

# DNS funkció kikapcsolva: ez a gép PXE/DHCP szerver.
port=0

# DHCP
EOF

    if [[ "$DHCP_MODE" == "proxy" ]]; then
        cat >> "$PXE_CONF" <<EOF
# Proxy-DHCP: a meglévő DHCP szerver oszt IP-címet.
dhcp-range=tag:proxy,$SERVER_IP,proxy
pxe-service=x86PC, "PXE boot", pxelinux
EOF
    else
        cat >> "$PXE_CONF" <<EOF
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,12h
dhcp-boot=pxelinux.0
dhcp-option=6,$DNS_SERVER
EOF
        if [[ -n "$GATEWAY" ]]; then
            echo "dhcp-option=3,$GATEWAY" >> "$PXE_CONF"
        fi
    fi

    cat >> "$PXE_CONF" <<EOF

# TFTP
enable-tftp
tftp-root=$TFTP_ROOT

# Naplózás
log-dhcp
EOF

    dnsmasq --test
}

configure_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        log "UFW szabályok hozzáadása"
        # DHCP: UDP 67, TFTP: UDP 69.
        ufw allow in on "$INTERFACE" to any port 67 proto udp || true
        ufw allow in on "$INTERFACE" to any port 69 proto udp || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
        log "firewalld szabályok hozzáadása"
        firewall-cmd --permanent --add-service=dhcp || true
        firewall-cmd --permanent --add-service=tftp || true
        firewall-cmd --reload || true
    else
        echo "FIGYELEM: UFW/firewalld nem található; a DHCP (UDP/67) és TFTP (UDP/69) forgalmat"
        echo "a hálózati tűzfalon engedélyezni kell."
    fi
}

start_services() {
    log "dnsmasq engedélyezése és indítása"

    # tftpd-hpa nem szükséges, mert a dnsmasq beépített TFTP-je fut.
    # Ha korábban tftpd-hpa futott, leállítjuk, hogy ne legyen portütközés.
    if systemctl list-unit-files 2>/dev/null | grep -q '^tftpd-hpa.service'; then
        systemctl disable --now tftpd-hpa 2>/dev/null || true
    fi

    systemctl enable dnsmasq
    systemctl restart dnsmasq
}

show_summary() {
    echo
    echo "============================================================"
    echo " PXE szerver telepítés kész"
    echo "============================================================"
    echo "Interfész : $INTERFACE"
    echo "Szerver IP: $SERVER_IP"
    echo "Netmask   : $NETMASK"
    echo "Gateway   : ${GATEWAY:-nincs}"
    echo "DNS       : $DNS_SERVER"
    echo "DHCP mód  : $DHCP_MODE"
    if [[ "$DHCP_MODE" == "server" ]]; then
        echo "DHCP pool : $DHCP_START - $DHCP_END"
    fi
    echo "TFTP root : $TFTP_ROOT"
    echo "dnsmasq   : $PXE_CONF"
    echo "Backup    : $BACKUP_DIR"
    echo
    echo "KÖVETKEZŐ LÉPÉS:"
    echo "1. Tegyél egy választott Linux installer vmlinuz + initrd fájlt ide:"
    echo "   $TFTP_ROOT/vmlinuz"
    echo "   $TFTP_ROOT/initrd.img"
    echo
    echo "2. PXE boot engedélyezése a kliensen (UEFI/BIOS Network Boot)."
    echo
    echo "3. Ellenőrzés:"
    echo "   systemctl status dnsmasq --no-pager"
    echo "   journalctl -u dnsmasq -n 50 --no-pager"
    echo "   ls -lah $TFTP_ROOT"
    echo
    echo "FONTOS: ha van másik DHCP szerver a hálózaton, ne használd"
    echo "a DHCP server módot. Használd inkább: --proxy-dhcp"
    echo "============================================================"
}

main() {
    log "PXE szerver telepítése"
    echo "Interfész: $INTERFACE"
    echo "Szerver IP: $SERVER_IP"
    echo "DHCP mód : $DHCP_MODE"

    install_packages
    backup_existing
    configure_tftp
    configure_dnsmasq
    configure_firewall
    start_services

    show_summary
}

main "$@"
