#!/usr/bin/env bash
set -euo pipefail

BIN="/usr/local/bin/gost"
CFG_DIR="/etc/piggytun"
SVC_DIR="/etc/systemd/system"

mkdir -p "$CFG_DIR"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (با دسترسی روت اجرا کنید)"
  exit 1
fi

################################
# CHECK GOST VALID INSTALL
################################
gost_valid() {

  if [[ ! -f "$BIN" ]]; then
    return 1
  fi

  if [[ ! -x "$BIN" ]]; then
    return 1
  fi

  if [[ ! -s "$BIN" ]]; then
    return 1
  fi

  if ! "$BIN" -V >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

################################
# INSTALL GOST
################################
install_gost() {

  if gost_valid; then
    echo "GOST already installed and valid"
    return
  fi

  echo "Installing GOST..."

  rm -f "$BIN"

  ARCH=$(uname -m)
  GOST_VERSION="2.11.5"

  case "$ARCH" in
    x86_64)
      URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-amd64-${GOST_VERSION}.gz"
      ;;
    aarch64)
      URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-armv8-${GOST_VERSION}.gz"
      ;;
    *)
      echo "Unsupported arch"
      exit 1
      ;;
  esac

  TMP="/tmp/gost.gz"

  echo "Downloading..."
  wget -q -O "$TMP" "$URL"

  if [[ ! -s "$TMP" ]]; then
    echo "Download failed"
    exit 1
  fi

  echo "Extracting..."
  gzip -f -d "$TMP"

  mv /tmp/gost "$BIN"
  chmod +x "$BIN"

  if gost_valid; then
    echo "GOST installed successfully"
  else
    echo "Install failed"
    exit 1
  fi
}

################################
ask() {
  read -rp "$1: " v
  echo "$v"
}

################################
restart_service() {

  systemctl daemon-reload
  systemctl enable "$1"
  systemctl restart "$1"

}

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
Description=PIGGYTUN KHAREJ $port
After=network.target

[Service]
Type=simple
ExecStart=$BIN -L=tcp://:$port/127.0.0.1:$dest_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    restart_service "$svc"

  done

  echo "$id" > "$CFG_DIR/$id"

  echo "KHAREJ tunnel created"
}

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
Description=PIGGYTUN IRAN Aggregator
After=network.target

[Service]
Type=simple
ExecStart=$BIN -L=tcp://:$main_port $FORWARD
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  restart_service "$svc"

  echo "$id" > "$CFG_DIR/$id"

  echo "IRAN tunnel created"
}

################################
list_tunnels() {

  echo
  echo "Installed tunnels:"

  if [[ -z "$(ls -A "$CFG_DIR")" ]]; then
    echo "None"
    return
  fi

  ls "$CFG_DIR" | nl

}

################################
remove_tunnel() {

  list_tunnels

  num=$(ask "Enter number")

  id=$(ls "$CFG_DIR" | sed -n "${num}p")

  if [[ -z "$id" ]]; then
    echo "Invalid"
    return
  fi

  if [[ "$id" == IRAN* ]]; then

    port=$(echo "$id" | cut -d_ -f2)
    svc="piggytun-iran-$port.service"

    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    rm -f "$SVC_DIR/$svc"

  fi

  if [[ "$id" == KHAREJ* ]]; then

    start=$(echo "$id" | cut -d_ -f2)
    count=$(echo "$id" | cut -d_ -f3)

    for ((i=0;i<count;i++)); do

      port=$((start+i))
      svc="piggytun-kharej-$port.service"

      systemctl stop "$svc" 2>/dev/null || true
      systemctl disable "$svc" 2>/dev/null || true
      rm -f "$SVC_DIR/$svc"

    done

  fi

  rm -f "$CFG_DIR/$id"

  systemctl daemon-reload

  echo "Removed"
}

################################
remove_all() {

  echo "Removing all piggytun services..."

  for svc in "$SVC_DIR"/piggytun-*.service; do

    [[ -e "$svc" ]] || continue

    name=$(basename "$svc")

    systemctl stop "$name" 2>/dev/null || true
    systemctl disable "$name" 2>/dev/null || true

    rm -f "$svc"

  done

  rm -rf "$CFG_DIR"
  mkdir -p "$CFG_DIR"

  systemctl daemon-reload

  echo "All removed successfully"

}

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

    case "$c" in

      1) install_gost ;;
      2) add_tunnel_iran ;;
      3) list_tunnels ;;
      4) remove_tunnel ;;
      5) break ;;
      *) echo "Invalid" ;;

    esac

  done

}

################################
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

    case "$c" in

      1) install_gost ;;
      2) add_tunnel_kharej ;;
      3) list_tunnels ;;
      4) remove_tunnel ;;
      5) break ;;
      *) echo "Invalid" ;;

    esac

  done

}

################################
echo
echo "PIGGYTUN GOST Aggregation"
echo "1) IRAN SERVER"
echo "2) KHAREJ SERVER"
echo "3) REMOVE ALL"

main=$(ask "Select")

case "$main" in

  1) iran_menu ;;
  2) kharej_menu ;;
  3) remove_all ;;
  *) echo "Invalid" ;;

esac
