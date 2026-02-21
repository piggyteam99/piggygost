#!/bin/bash

# ==========================================
# Gost Bandwidth Aggregation (Relay+MWS)
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}لطفا با دسترسی Root اجرا کنید.${NC}"
  exit
fi

install_prerequisites() {
    clear
    echo -e "${CYAN}در حال نصب پیش‌نیازها...${NC}"
    apt-get update
    apt-get install -y wget curl tar ufw

    if [ ! -f "/usr/local/bin/gost" ]; then
        wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz -O gost.gz
        gzip -d gost.gz
        mv gost /usr/local/bin/gost
        chmod +x /usr/local/bin/gost
    fi
    echo -e "${GREEN}نصب با موفقیت انجام شد.${NC}"
    sleep 2
}

setup_iran_tunnel() {
    clear
    read -p "پورت داخلی (ایران): " LOCAL_PORT
    read -p "آی‌پی سرور خارج: " FOREIGN_IP
    read -p "پورت خارجی (پورت کانفیگ V2ray در خارج): " TARGET_PORT
    read -p "شروع رنج پورت: " RANGE_START
    read -p "پایان رنج پورت: " RANGE_END
    
    # ساخت رشته لودبالانس
    F_STR=""
    for (( p=$RANGE_START; p<=$RANGE_END; p++ )); do
        if [ -z "$F_STR" ]; then
            F_STR="relay+mws://${FOREIGN_IP}:${p}?strategy=round"
        else
            F_STR="${F_STR},relay+mws://${FOREIGN_IP}:${p}"
        fi
    done

    SERVICE_NAME="gost-ir-${LOCAL_PORT}.service"
    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Iran Tunnel
After=network.target

[Service]
Type=simple
# دریافت ترافیک از کاربر و ارسال به صورت پخش‌شده (Round-Robin) به رنج پورت‌ها در خارج برای رسیدن به پورت هدف
ExecStart=/usr/local/bin/gost -L tcp://0.0.0.0:${LOCAL_PORT}/127.0.0.1:${TARGET_PORT} -F "${F_STR}"
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    ufw allow $LOCAL_PORT/tcp >/dev/null 2>&1

    # بررسی وضعیت اجرا
    sleep 1
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}تانل ایران با موفقیت فعال شد!${NC}"
    else
        echo -e "${RED}خطا در استارت سرویس! لطفا مقادیر را چک کنید.${NC}"
    fi
    sleep 4
}

setup_kharej_tunnel() {
    clear
    read -p "شروع رنج پورت: " RANGE_START
    read -p "پایان رنج پورت: " RANGE_END

    L_STR=""
    for (( p=$RANGE_START; p<=$RANGE_END; p++ )); do
        L_STR="${L_STR} -L relay+mws://0.0.0.0:${p}"
        ufw allow $p/tcp >/dev/null 2>&1
    done

    SERVICE_NAME="gost-kh-range.service"
    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Kharej Tunnel Range
After=network.target

[Service]
Type=simple
# لیسن کردن روی تمام رنج پورت‌ها برای دریافت ترافیک و هدایت اتوماتیک به پورت هدف
ExecStart=/usr/local/bin/gost ${L_STR}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME

    sleep 1
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}تانل خارج فعال شد و در حال گوش دادن به پورت‌هاست!${NC}"
    else
        echo -e "${RED}خطا در استارت سرویس! ممکن است تعداد پورت‌ها بیش از حد زیاد باشد.${NC}"
    fi
    sleep 4
}

manage_tunnels() {
    clear
    files=(/etc/systemd/system/gost-*.service)
    if [ ! -e "${files[0]}" ]; then
        echo -e "${RED}هیچ تانلی یافت نشد!${NC}"
        sleep 2
        return
    fi
    count=1
    for f in "${files[@]}"; do
        filename=$(basename -- "$f")
        status=$(systemctl is-active "$filename")
        color=$([[ "$status" == "active" ]] && echo "$GREEN" || echo "$RED")
        echo -e "${count}) ${filename} - [${color}${status}${NC}]"
        ((count++))
    done
    echo "1) حذف یک تانل | 0) بازگشت"
    read -p "انتخاب: " choice
    if [ "$choice" == "1" ]; then
        read -p "شماره: " del_num
        idx=$((del_num-1))
        target=$(basename -- "${files[$idx]}")
        systemctl stop "$target"; systemctl disable "$target"; rm "${files[$idx]}"; systemctl daemon-reload
        echo -e "${GREEN}حذف شد.${NC}"; sleep 2
    fi
}

uninstall_all() {
    read -p "آیا مطمئن هستید؟ (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for f in /etc/systemd/system/gost-*.service; do
            if [ -e "$f" ]; then
                name=$(basename -- "$f")
                systemctl stop "$name"; systemctl disable "$name"; rm "$f"
            fi
        done
        systemctl daemon-reload; rm -f /usr/local/bin/gost
        echo -e "${GREEN}پاکسازی کامل انجام شد.${NC}"; exit
    fi
}

menu() {
    while true; do
        clear
        echo -e "${YELLOW}=== Gost Aggregation Tunnel ===${NC}"
        echo "1) نصب پیش‌نیازها"
        echo "2) ساخت تانل سرور ایران"
        echo "3) ساخت تانل سرور خارج"
        echo "4) مدیریت تانل‌ها"
        echo "5) حذف کامل همه چیز"
        echo "0) خروج"
        read -p "انتخاب: " choice
        case $choice in
            1) install_prerequisites ;;
            2) setup_iran_tunnel ;;
            3) setup_kharej_tunnel ;;
            4) manage_tunnels ;;
            5) uninstall_all ;;
            0) exit 0 ;;
        esac
    done
}
menu
