#!/bin/bash

# поиск интерфейса, на который будем перенаправлять пакеты, и присвоение его имени переменной {eth} - применяется в iptables
eth=$(ip route | grep default | head -n1 | awk '{print $5}')

# узнаем ip адрес сервера и записываем в переменную ip_serv
ip_serv=$(curl ident.me)

# диалог с пользователем - запрос параметров установки
echo "Input LOGIN user VPN:"
read USER
echo "Input PASS user VPN:"
read PASS
echo "Input secret key (PSK):"
read PSK

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
    echo ""
    echo "iptables -F" >> /etc/iptables.rules
    echo "iptables -X" >> /etc/iptables.rules
    echo ""
    echo "iptables -A INPUT -i $eth -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -m conntrack --ctstate INVALID -j DROP" >> /etc/iptables.rules
    echo "iptables -A INPUT -i $eth -p tcp --dport 22 -j ACCEPT" >> /etc/iptables.rules
    echo ""
    echo "iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o $eth -j MASQUERADE" >> /etc/iptables.rules
    echo ""
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
    echo ""
    echo "[Service]" >> /etc/systemd/system/ipt.service
    echo "Type=notify" >> /etc/systemd/system/ipt.service
    echo "ExecStart=/etc/iptables.rules" >> /etc/systemd/system/ipt.service
    echo "ExecReload=/bin/kill -HUP $MAINPID" >> /etc/systemd/system/ipt.service
    echo "KillMode=process" >> /etc/systemd/system/ipt.service
    echo "Restart=on-failure" >> /etc/systemd/system/ipt.service
    echo ""
    echo "[Install]" >> /etc/systemd/system/ipt.service
    echo "WantedBy=multi-user.target" >> /etc/systemd/system/ipt.service
    # автозагрузка службы ipt
    systemctl enable ipt
 }

ipsec_install () {
    apt install strongswan -y
    cp /etc/ipsec.conf /etc/ipsec.conf.old
    echo "config setup" > /etc/ipsec.conf
    echo "        charondebug=\"ike 2, knl 3, cfg 0, ike 1\""  >> /etc/ipsec.conf
    echo "        uniqueids=no"  >> /etc/ipsec.conf
    echo "conn l2tp-vpn" >> /etc/ipsec.conf
    echo "        type=transport"  >> /etc/ipsec.conf
    echo "        authby=secret"  >> /etc/ipsec.conf
    echo "        pfs=no"  >> /etc/ipsec.conf
    echo "        rekey=no"  >> /etc/ipsec.conf
    echo "        keyingtries=2"  >> /etc/ipsec.conf
    echo "        left=%any"  >> /etc/ipsec.conf
    echo "        leftid=$ip_serv"  >> /etc/ipsec.conf
    echo "        right=%any"  >> /etc/ipsec.conf
    echo "        auto=add"  >> /etc/ipsec.conf
    cp /etc/ipsec.secrets /etc/ipsec.secrets.old
    echo "%any : PSK \"$PSK\"" > /etc/ipsec.secrets
    systemctl restart strongswan-starter
    systemctl enable strongswan-starter
}

l2tp_install () {
    apt install xl2tpd -y
    cp /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.old
    echo "[global]" > /etc/xl2tpd/xl2tpd.conf
    echo "port = 1701" >> /etc/xl2tpd/xl2tpd.conf
    echo "auth file = /etc/ppp/chap-secrets" >> /etc/xl2tpd/xl2tpd.conf
    echo "access control = no" >> /etc/xl2tpd/xl2tpd.conf
    echo ""
    echo "[lns default]" >> /etc/xl2tpd/xl2tpd.conf
    echo "exclusive = no" >> /etc/xl2tpd/xl2tpd.conf
    echo "ip range = 10.10.0.10-10.10.0.20" >> /etc/xl2tpd/xl2tpd.conf
    echo "hidden bit = no" >> /etc/xl2tpd/xl2tpd.conf
    echo "local ip = $ip_serv" >> /etc/xl2tpd/xl2tpd.conf
    echo "length bit = yes" >> /etc/xl2tpd/xl2tpd.conf
    echo "require chap = yes" >> /etc/xl2tpd/xl2tpd.conf
    echo "refuse pap = yes" >> /etc/xl2tpd/xl2tpd.conf
    echo "require authentication = yes" >> /etc/xl2tpd/xl2tpd.conf
    echo "name = srvl2tp" >> /etc/xl2tpd/xl2tpd.conf
    echo "pppoptfile = /etc/ppp/options.xl2tpd" >> /etc/xl2tpd/xl2tpd.conf
    echo "flow bit = yes" >> /etc/xl2tpd/xl2tpd.conf
    systemctl restart xl2tpd
    systemctl enable xl2tpd
}

ppp_install () {
    echo "noccp" > /etc/ppp/options.xl2tpd
    echo "auth" >> /etc/ppp/options.xl2tpd
    echo "mtu 1410" >> /etc/ppp/options.xl2tpd
    echo "mru 1410" >> /etc/ppp/options.xl2tpd
    echo "nodefaultroute" >> /etc/ppp/options.xl2tpd
    echo "noproxyarp" >> /etc/ppp/options.xl2tpd
    echo "silent" >> /etc/ppp/options.xl2tpd
    echo "asyncmap 0" >> /etc/ppp/options.xl2tpd
    echo "hide-password" >> /etc/ppp/options.xl2tpd
    echo "require-mschap-v2" >> /etc/ppp/options.xl2tpd
    echo "ms-dns 8.8.8.8" >> /etc/ppp/options.xl2tpd
    echo "ms-dns 8.8.4.4" >> /etc/ppp/options.xl2tpd
    mkdir /var/log/xl2tpd
    echo "logfile /var/log/xl2tpd/xl2tpd.log" >> /etc/ppp/options.xl2tpd
    echo "debug" >> /etc/ppp/options.xl2tpd
}

add_user () {
    cp /etc/ppp/chap-secrets /etc/ppp/chap-secrets.old
    echo "\"$USER\" srvl2tp \"$PASS\" *" > /etc/ppp/chap-secrets
}

ipforwarding
iptables
ipsec_install
l2tp_install
ppp_install
add_user

echo "INSTALL VPN COMPLETE!"