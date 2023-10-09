#!/bin/bash

# поиск интерфейса, на который будем перенаправлять пакеты, и присвоение его имени переменной {eth} - применяется в iptables
eth=$(ip route | grep default | head -n1 | awk '{print $5}')

# узнаем ip адрес сервера и записываем в переменную ip_serv
ip_serv=$(curl ident.me)

ipforwarding () {
    # сохраняем резервную копию /etc/sysctl.conf в /etc/sysctl.conf.old
    cp /etc/sysctl.conf /etc/sysctl.conf.old
    # включаем маршрутизации пакетов через VPN сервер
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf
    # применяем настройки
    sysctl -p
}

iptables () {
    # правила iptables
    echo "#!/bin/bash" > /etc/iptables.rules
    echo "iptables -F" >> /etc/iptables.rules
    echo "iptables -X" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -m conntrack --ctstate INVALID -j DROP" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -p tcp --dport 22 -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o $eth -j MASQUERADE" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -p udp --dport 500 -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -p udp --dport 4500 -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -p 50 -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -p 51 -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -p udp -m policy --dir in --pol ipsec -m udp --dport 1701 -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -j DROP" >> /etc/iptables.rules
    chmod +x /etc/iptables.rules
    # создание службы iptables для автоматического запсука
    echo "[Unit]" > /etc/systemd/system/ipt.service
    echo "Description=Iptables service" >> /etc/systemd/system/ipt.service
    echo "After=network.target" >> /etc/systemd/system/ipt.service
    echo "[Service]" >> /etc/systemd/system/ipt.service
    echo "Type=notify" >> /etc/systemd/system/ipt.service
    echo "ExecStart=/etc/iptables.rules" >> /etc/systemd/system/ipt.service
    echo "ExecReload=/bin/kill -HUP $MAINPID" >> /etc/systemd/system/ipt.service
    echo "KillMode=process" >> /etc/systemd/system/ipt.service
    echo "Restart=on-failure" >> /etc/systemd/system/ipt.service
    echo "[Install]" >> /etc/systemd/system/ipt.service
    echo "WantedBy=multi-user.target" >> /etc/systemd/system/ipt.service
    # автозагрузка службы ipt
    systemctl enable ipt
 }

ipsec_install () {
    apt install strongswan -y
}

#ipforwarding
#iptables
#ipsec_install
