#!/usr/bin/env bash
set -euo pipefail

BIN="/usr/local/bin/gost"
CFG_DIR="/etc/piggytun"
SVC_DIR="/etc/systemd/system"
TMP_DIR="/tmp/gost-install"

mkdir -p "$CFG_DIR"
mkdir -p "$TMP_DIR"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

################################
# Detect architecture
################################

detect_arch() {

case "$(uname -m)" in
x86_64) echo "amd64" ;;
aarch64|arm64) echo "arm64" ;;
armv7l) echo "armv7" ;;
*)
echo "Unsupported architecture"
exit 1
;;
esac

}

################################
# Install gost from official GitHub releases
################################

install_gost() {

if command -v gost >/dev/null 2>&1; then
echo "GOST already installed"
return
fi

echo "Installing GOST..."

ARCH=$(detect_arch)

LATEST=$(curl -s https://api.github.com/repos/go-gost/gost/releases/latest | grep tag_name | cut -d '"' -f4)

FILE="gost_${LATEST#v}_linux_${ARCH}.tar.gz"

URL="https://github.com/go-gost/gost/releases/download/${LATEST}/${FILE}"

echo "Downloading $URL"

if ! curl -L "$URL" -o "$TMP_DIR/gost.tar.gz"; then
echo "Download failed"
exit 1
fi

cd "$TMP_DIR"

tar -xzf gost.tar.gz

cp gost "$BIN"

chmod +x "$BIN"

rm -rf "$TMP_DIR"

echo "GOST installed successfully"

}

################################
# Ask input
################################

ask() {
read -rp "$1: " v
echo "$v"
}

################################
# Restart service
################################

enable_service() {

systemctl daemon-reload
systemctl enable "$1"
systemctl restart "$1"

}

################################
# Add KHAREJ aggregation server
################################

add_tunnel_kharej() {

install_gost

range_start=$(ask "Port range start")
count=$(ask "Port count")
dest_port=$(ask "Destination local port")

id="KHAREJ_${range_start}_${count}_${dest_port}"

for ((i=0;i<count;i++)); do

port=$((range_start+i))

svc="piggytun-kharej-$port.service"

cat > "$SVC_DIR/$svc" <<EOF
[Unit]
Description=PIGGYTUN KHAREJ PORT $port
After=network.target

[Service]
Type=simple
ExecStart=$BIN -L=tcp://:$port/127.0.0.1:$dest_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

enable_service "$svc"

done

echo "$id" > "$CFG_DIR/$id"

echo "KHAREJ aggregation tunnel created"

}

################################
# Add IRAN aggregation client
################################

add_tunnel_iran() {

install_gost

main_port=$(ask "Main listen port")
range_start=$(ask "Port range start")
count=$(ask "Port count")
kharej_ip=$(ask "Kharej IP")

id="IRAN_${main_port}_${range_start}_${count}"

FORWARD=""

for ((i=0;i<count;i++)); do

port=$((range_start+i))

FORWARD="$FORWARD -F=tcp://$kharej_ip:$port"

done

svc="piggytun-iran-$main_port.service"

cat > "$SVC_DIR/$svc" <<EOF
[Unit]
Description=PIGGYTUN IRAN Aggregator $main_port
After=network.target

[Service]
Type=simple
ExecStart=$BIN -L=tcp://:$main_port $FORWARD
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

enable_service "$svc"

echo "$id" > "$CFG_DIR/$id"

echo "IRAN aggregation tunnel created"

}

################################
# List tunnels
################################

list_tunnels() {

echo
echo "Installed tunnels:"
ls "$CFG_DIR" | nl || true

}

################################
# Remove tunnel
################################

remove_tunnel() {

list_tunnels

num=$(ask "Enter number")

id=$(ls "$CFG_DIR" | sed -n "${num}p")

if [[ -z "$id" ]]; then
echo "Invalid selection"
exit 1
fi

if [[ "$id" == IRAN* ]]; then

port=$(echo "$id" | cut -d_ -f2)

svc="piggytun-iran-$port.service"

systemctl stop "$svc"
systemctl disable "$svc"

rm -f "$SVC_DIR/$svc"

fi

if [[ "$id" == KHAREJ* ]]; then

start=$(echo "$id" | cut -d_ -f2)
count=$(echo "$id" | cut -d_ -f3)

for ((i=0;i<count;i++)); do

port=$((start+i))

svc="piggytun-kharej-$port.service"

systemctl stop "$svc"
systemctl disable "$svc"

rm -f "$SVC_DIR/$svc"

done

fi

rm -f "$CFG_DIR/$id"

systemctl daemon-reload

echo "Tunnel removed"

}

################################
# Remove all
################################

remove_all() {

systemctl stop piggytun-* 2>/dev/null || true

rm -f $SVC_DIR/piggytun-* 2>/dev/null || true

rm -rf "$CFG_DIR"

echo "All tunnels removed"

}

################################
# Menus
################################

iran_menu() {

while true; do

echo
echo "IRAN MENU"
echo "1) Install GOST"
echo "2) Add Aggregation Tunnel"
echo "3) List Tunnels"
echo "4) Remove Tunnel"
echo "5) Back"

c=$(ask "Choice")

case $c in
1) install_gost ;;
2) add_tunnel_iran ;;
3) list_tunnels ;;
4) remove_tunnel ;;
5) break ;;
esac

done

}

kharej_menu() {

while true; do

echo
echo "KHAREJ MENU"
echo "1) Install GOST"
echo "2) Add Aggregation Tunnel"
echo "3) List Tunnels"
echo "4) Remove Tunnel"
echo "5) Back"

c=$(ask "Choice")

case $c in
1) install_gost ;;
2) add_tunnel_kharej ;;
3) list_tunnels ;;
4) remove_tunnel ;;
5) break ;;
esac

done

}

################################
# Main menu
################################

echo
echo "PIGGYTUN GOST BANDWIDTH AGGREGATION"
echo "1) IRAN SERVER"
echo "2) KHAREJ SERVER"
echo "3) REMOVE ALL"

main=$(ask "Select")

case $main in
1) iran_menu ;;
2) kharej_menu ;;
3) remove_all ;;
*)
echo "Invalid"
;;
esac
