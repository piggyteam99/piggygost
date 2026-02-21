#!/bin/bash

# ==========================================
# Gost Bandwidth Aggregation Tunnel Script
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}لطفا اسکریپت را با دسترسی Root (sudo) اجرا کنید.${NC}"
  exit
fi

install_prerequisites() {
    clear
    echo -e "${CYAN}در حال نصب پیش‌نیازها و دانلود Gost...${NC}"
    apt-get update
    apt-get install -y wget curl jq tar ufw net-tools

    if [ -f "/usr/local/bin/gost" ]; then
        echo -e "${GREEN}Gost از قبل نصب شده است.${NC}"
    else
        echo -e "${YELLOW}در حال دانلود آخرین نسخه Gost V2...${NC}"
        wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz -O gost.gz
        gzip -d gost.gz
        mv gost /usr/local/bin/gost
        chmod +x /usr/local/bin/gost
        echo -e "${GREEN}نصب Gost با موفقیت انجام شد.${NC}"
    fi
    sleep 2
}

setup_iran_tunnel() {
    clear
    echo -e "${CYAN}--- تنظیم تانل در سرور ایران ---${NC}"
    read -p "پورت داخلی (پورتی که در ایران به آن وصل میشوید) را وارد کنید: " LOCAL_PORT
    read -p "آی‌پی (IP) سرور خارج را وارد کنید: " FOREIGN_IP
    read -p "شروع رنج پورت (مثلا 20000): " RANGE_START
    read -p "پایان رنج پورت (مثلا 20050): " RANGE_END

    echo -e "${YELLOW}در حال ساخت کانفیگ تجمیع پهنای باند...${NC}"
    
    F_STR=""
    for (( p=$RANGE_START; p<=$RANGE_END; p++ )); do
        if [ -z "$F_STR" ]; then
            F_STR="mws://${FOREIGN_IP}:${p}?strategy=round"
        else
            F_STR="${F_STR},mws://${FOREIGN_IP}:${p}"
        fi
    done

    SERVICE_NAME="gost-ir-${LOCAL_PORT}.service"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Gost Iran Tunnel Port ${LOCAL_PORT}
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L tcp://0.0.0.0:${LOCAL_PORT} -F "${F_STR}"
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME

    # Allow Firewall
    ufw allow $LOCAL_PORT/tcp >/dev/null 2>&1

    echo -e "${GREEN}تانل ایران با موفقیت ساخته و استارت شد!${NC}"
    echo -e "پورت ورودی شما: ${CYAN}${LOCAL_PORT}${NC}"
    echo -e "ارسال ترافیک به سرور خارج روی رنج پورت: ${CYAN}${RANGE_START} تا ${RANGE_END}${NC}"
    sleep 4
}

setup_kharej_tunnel() {
    clear
    echo -e "${CYAN}--- تنظیم تانل در سرور خارج ---${NC}"
    read -p "پورت خارجی (پورتی که کانفیگ V2ray/Xray شما روی آن است) را وارد کنید: " TARGET_PORT
    read -p "شروع رنج پورت (باید دقیقا با ایران یکی باشد - مثلا 20000): " RANGE_START
    read -p "پایان رنج پورت (باید دقیقا با ایران یکی باشد - مثلا 20050): " RANGE_END

    echo -e "${YELLOW}در حال ساخت کانفیگ دریافت رنج پورت...${NC}"

    L_STR=""
    for (( p=$RANGE_START; p<=$RANGE_END; p++ )); do
        L_STR="${L_STR} -L mws://0.0.0.0:${p}/127.0.0.1:${TARGET_PORT}"
        ufw allow $p/tcp >/dev/null 2>&1
    done

    SERVICE_NAME="gost-kh-${TARGET_PORT}.service"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Gost Kharej Tunnel Target Port ${TARGET_PORT}
After=network.target

[Service]
Type=simple
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

    echo -e "${GREEN}تانل خارج با موفقیت ساخته و استارت شد!${NC}"
    echo -e "دریافت از ایران روی رنج پورت: ${CYAN}${RANGE_START} تا ${RANGE_END}${NC}"
    echo -e "ارسال ترافیک تجمیع شده به پورت محلی: ${CYAN}${TARGET_PORT}${NC}"
    sleep 4
}

manage_tunnels() {
    clear
    echo -e "${CYAN}--- لیست تانل‌های فعال ---${NC}"
    
    files=(/etc/systemd/system/gost-*.service)
    
    if [ ! -e "${files[0]}" ]; then
        echo -e "${RED}هیچ تانلی یافت نشد!${NC}"
        sleep 2
        return
    fi

    echo "تانل های پیدا شده:"
    count=1
    for f in "${files[@]}"; do
        filename=$(basename -- "$f")
        status=$(systemctl is-active "$filename")
        if [ "$status" == "active" ]; then
            echo -e "${count}) ${filename} - [${GREEN}فعال${NC}]"
        else
            echo -e "${count}) ${filename} - [${RED}غیرفعال${NC}]"
        fi
        ((count++))
    done

    echo -e "\n${YELLOW}گزینه ها:${NC}"
    echo "1) حذف یک تانل"
    echo "0) بازگشت به منوی قبل"
    read -p "انتخاب شما: " choice

    if [ "$choice" == "1" ]; then
        read -p "شماره تانلی که میخواهید حذف کنید را وارد کنید: " del_num
        if [[ $del_num -gt 0 && $del_num -lt $count ]]; then
            idx=$((del_num-1))
            target_file="${files[$idx]}"
            target_name=$(basename -- "$target_file")
            
            systemctl stop "$target_name"
            systemctl disable "$target_name"
            rm "$target_file"
            systemctl daemon-reload
            echo -e "${GREEN}تانل $target_name با موفقیت حذف شد.${NC}"
            sleep 2
        else
            echo -e "${RED}شماره نامعتبر است.${NC}"
            sleep 2
        fi
    fi
}

uninstall_all() {
    clear
    echo -e "${RED}هشدار: این کار تمام تانل‌ها و خود نرم‌افزار Gost را پاک می‌کند.${NC}"
    read -p "آیا مطمئن هستید؟ (y/n): " confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        echo -e "${YELLOW}در حال متوقف کردن سرویس‌ها...${NC}"
        for f in /etc/systemd/system/gost-*.service; do
            if [ -e "$f" ]; then
                name=$(basename -- "$f")
                systemctl stop "$name"
                systemctl disable "$name"
                rm "$f"
            fi
        done
        systemctl daemon-reload
        rm -f /usr/local/bin/gost
        echo -e "${GREEN}حذف کامل با موفقیت انجام شد.${NC}"
        sleep 2
        exit
    fi
}

menu_iran() {
    while true; do
        clear
        echo -e "${GREEN}====== منوی سرور ایران ======${NC}"
        echo "1) نصب پیش‌نیازها و Gost"
        echo "2) ساخت تانل جدید (Bandwidth Aggregation)"
        echo "3) مشاهده و حذف تانل‌ها"
        echo "4) حذف کامل اسکریپت و تانل‌ها"
        echo "0) بازگشت به منوی اصلی"
        echo -e "${GREEN}=============================${NC}"
        read -p "لطفا یک گزینه را انتخاب کنید: " choice

        case $choice in
            1) install_prerequisites ;;
            2) setup_iran_tunnel ;;
            3) manage_tunnels ;;
            4) uninstall_all ;;
            0) break ;;
            *) echo -e "${RED}گزینه نامعتبر!${NC}"; sleep 1 ;;
        esac
    done
}

menu_kharej() {
    while true; do
        clear
        echo -e "${BLUE}====== منوی سرور خارج ======${NC}"
        echo "1) نصب پیش‌نیازها و Gost"
        echo "2) ساخت تانل جدید (دریافت رنج پورت)"
        echo "3) مشاهده و حذف تانل‌ها"
        echo "4) حذف کامل اسکریپت و تانل‌ها"
        echo "0) بازگشت به منوی اصلی"
        echo -e "${BLUE}============================${NC}"
        read -p "لطفا یک گزینه را انتخاب کنید: " choice

        case $choice in
            1) install_prerequisites ;;
            2) setup_kharej_tunnel ;;
            3) manage_tunnels ;;
            4) uninstall_all ;;
            0) break ;;
            *) echo -e "${RED}گزینه نامعتبر!${NC}"; sleep 1 ;;
        esac
    done
}

# Main Loop
while true; do
    clear
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "${CYAN} Gost Bandwidth Aggregation Tunnel Manager ${NC}"
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "این سرور در کجا قرار دارد؟"
    echo "1) سرور ایران (مبدا)"
    echo "2) سرور خارج (مقصد)"
    echo "0) خروج از اسکریپت"
    echo -e "${YELLOW}==================================================${NC}"
    read -p "انتخاب شما: " server_type

    case $server_type in
        1) menu_iran ;;
        2) menu_kharej ;;
        0) exit 0 ;;
        *) echo -e "${RED}گزینه نامعتبر!${NC}"; sleep 1 ;;
    esac
done
