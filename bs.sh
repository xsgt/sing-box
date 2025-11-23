#!/bin/bash

CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
IP=$(hostname -I | awk '{print $1}')

#===================================================#
#               安装 sing-box                     #
#===================================================#
install_singbox() {
    echo ">>> 安装依赖..."
    if [ -f /etc/debian_version ]; then
        apt update -y
        apt install wget unzip jq curl -y
    else
        yum install wget unzip jq curl -y
    fi

    echo ">>> 下载 sing-box 最新版..."
    curl -L https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip -o sing-box.zip
    unzip -o sing-box.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -f sing-box.zip

    mkdir -p $CONFIG_DIR

cat > $CONFIG_FILE <<EOF
{
  "inbounds": [],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "routing": []
}
EOF

    echo ">>> 创建 systemd 服务..."
cat > $SERVICE_FILE <<EOF
[Unit]
Description=sing-box Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box

    echo "✔ 安装完成，sing-box 已启动并开机自启！"
}

#===================================================#
#              添加节点并生成URL                  #
#===================================================#
add_node() {
    read -p "节点 tag: " tag
    read -p "监听端口: " port
    read -p "密码: " pass
    read -p "SNI (如 cloudflare.com): " sni
    read -p "混淆类型(srtp/utp/wireguard/none): " obfs

jq ".inbounds += [{
  \"type\": \"hysteria\",
  \"tag\": \"$tag\",
  \"listen\": \"0.0.0.0\",
  \"listen_port\": $port,
  \"sniff\": true,
  \"obfs\": {\"type\": \"$obfs\"},
  \"tls\": {\"enabled\": true, \"server_name\": \"$sni\"},
  \"users\": [
      {\"name\": \"$tag\", \"password\": \"$pass\"}
  ]
}]" $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE

echo ""
echo "✔ 节点添加成功！URL 如下："
echo "hysteria://$pass@$IP:$port?obfs=$obfs&sni=$sni"
echo ""
}

#===================================================#
#               显示所有 URL                        #
#===================================================#
show_url() {
    echo ""
    echo "=========== 所有节点 URL ==========="
    jq -c '.inbounds[]' $CONFIG_FILE | while read node; do
        tag=$(echo $node | jq -r '.tag')
        port=$(echo $node | jq -r '.listen_port')
        pass=$(echo $node | jq -r '.users[0].password')
        obfs=$(echo $node | jq -r '.obfs.type')
        sni=$(echo $node | jq -r '.tls.server_name')

        echo ""
        echo "[$tag]"
        echo "hysteria://$pass@$IP:$port?obfs=$obfs&sni=$sni"
    done
    echo ""
}

#===================================================#
#                  修改端口                        #
#===================================================#
modify_port() {
    read -p "输入节点 TAG: " tag
    read -p "新端口: " port

    jq "( .inbounds[] | select(.tag==\"$tag\") | .listen_port ) |= $port" \
    $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE

    echo "✔ 节点 $tag 的端口已修改为 $port"
}

#===================================================#
#                  删除节点                        #
#===================================================#
delete_node() {
    read -p "节点 TAG: " tag

    jq " .inbounds |= map(select(.tag != \"$tag\")) " \
    $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE

    echo "✔ 节点 $tag 已删除"
}

#===================================================#
#                 重启服务                         #
#===================================================#
restart_singbox() {
    systemctl restart sing-box
    echo "✔ sing-box 服务已重启"
}

#===================================================#
#                 卸载程序                         #
#===================================================#
uninstall_singbox() {
    systemctl stop sing-box
    systemctl disable sing-box
    rm -f /usr/local/bin/sing-box
    rm -rf /etc/sing-box
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload

    echo "✔ sing-box 已成功卸载"
}

#===================================================#
#                    主菜单                         #
#===================================================#
while true; do
echo "
=========== Sing-Box 精简 UI 控制界面 ===========
0. 退出控制界面
1. 安装 Hysteria2
2. 查看 URL + 添加节点
3. 修改端口
4. 重启 sing-box 服务
5. 删除节点
6. 卸载 sing-box

请输入选项 (0-6):
"
read -p "> " choice

case $choice in
    0) exit 0 ;;
    1) install_singbox ;;
    2) add_node; show_url ;;
    3) modify_port ;;
    4) restart_singbox ;;
    5) delete_node ;;
    6) uninstall_singbox ;;
    *) echo "无效输入，请重新选择！" ;;
esac
done
