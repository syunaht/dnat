#!/bin/bash

check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
    bit=`uname -m`
}
check_sys

# stop service
if [ -s /etc/systemd/system/dnat.service ] ; then
    systemctl stop dnat
    rm -f /etc/systemd/system/dnat.service
fi

# clean up
rm -rf /etc/init.d/dnat
rm -rf /usr/local/bin/dnat.sh
rm -rf /usr/local/bin/nat

echo "安装依赖...."
apk add bash iptables &> /dev/null
apk add iptables bind-tools &> /dev/null
yum install -y bind-utils &> /dev/null
apt install -y dnsutils &> /dev/null
cp -f nat /usr/local/bin/nat && chmod +x /usr/local/bin/nat
cp -f dnat.sh /usr/local/bin/dnat.sh && chmod +x /usr/local/bin/dnat.sh
echo "安装依赖结束"

echo "开启端口转发"
sed -n '/^net.ipv4.ip_forward=1/'p /etc/sysctl.conf | grep -q "net.ipv4.ip_forward=1"
if [ $? -ne 0 ]; then
    echo -e "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p
fi

echo "开放FORWARD链"
arr1=(`iptables -L FORWARD -n  --line-number |grep "REJECT"|grep "0.0.0.0/0"|sort -r|awk '{print $1,$2,$5}'|tr " " ":"|tr "\n" " "`)  #16:REJECT:0.0.0.0/0 15:REJECT:0.0.0.0/0
for cell in ${arr1[@]}
do
    arr2=(`echo $cell|tr ":" " "`)  #arr2=16 REJECT 0.0.0.0/0
    index=${arr2[0]}
    echo 删除禁止FOWARD的规则——$index
    iptables -D FORWARD $index
done
iptables --policy FORWARD ACCEPT

echo "注册系统服务"
cat > /etc/systemd/system/dnat.service <<\EOF
[Unit]
Description=DNAT Manager

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnat.sh
Restart=always
RestartSec=30
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/dsave.service <<\EOF
[Unit]
Description=Iptables Rules-Save Manager
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
ExecStart=/usr/local/bin/iptables-restore
ExecStartPost=/bin/rm /etc/.iptables-rules
ExecStop=/usr/local/bin/iptables-save
Restart=no
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/iptables-restore <<\EOF
#!/bin/bash
sleep 2 &&
/sbin/iptables-restore < /etc/.iptables-rules
EOF
chmod +x /usr/local/bin/iptables-restore

cat > /usr/local/bin/iptables-save <<\EOF
#!/bin/bash
/sbin/iptables-save > /etc/.iptables-rules.bak
/usr/bin/awk ' !x[$0]++' /etc/.iptables-rules.bak > /etc/.iptables-rules
echo "COMMIT" >> /etc/.iptables-rules
/bin/rm /etc/.iptables-rules.bak
EOF
chmod +x /usr/local/bin/iptables-save

echo "启动系统服务"
chmod 754 /etc/systemd/system/dnat.service
chmod 754 /etc/systemd/system/dsave.service
systemctl daemon-reload
systemctl enable dnat > /dev/null 2>&1
systemctl enable dsave > /dev/null 2>&1
systemctl start dnat > /dev/null 2>&1
systemctl start dsave > /dev/null 2>&1
systemctl status dnat && echo
systemctl status dsave && echo
echo "安装完毕，请输入指令运行 nat 运行"
