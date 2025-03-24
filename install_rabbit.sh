#!/bin/bash

set -e  # Hata yakalama
source rabbit.env  # rabbitmq.env dosyasını yükle

# Kullanım kontrolü
if [ -z "$1" ]; then
    echo "❌ Kullanım: ./install_rabbitmq.sh [master|worker1|worker2]"
    exit 1
fi

NODE_TYPE=$1  # Kullanıcıdan alınan node tipi

# Node tipine göre ismi ve IP adresini belirle
if [ "$NODE_TYPE" == "master" ]; then
    NODE_NAME=$MASTER_NODE_NAME
    NODE_IP=$MASTER_IP
elif [ "$NODE_TYPE" == "worker1" ]; then
    NODE_NAME=$WORKER_1_NODE_NAME
    NODE_IP=$WORKER_1_IP
elif [ "$NODE_TYPE" == "worker2" ]; then
    NODE_NAME=$WORKER_2_NODE_NAME
    NODE_IP=$WORKER_2_IP
else
    echo "❌ Geçersiz node tipi! Kullanım: ./install_rabbitmq.sh [master|worker1|worker2]"
    exit 1
fi

echo "🚀 RabbitMQ Kurulumu Başlıyor..."
echo "📌 Node Type: $NODE_TYPE"
echo "📌 Node Name: $NODE_NAME"
echo "📌 Node IP: $NODE_IP"

# Tüm RabbitMQ süreçlerini durdur ve temizle
echo "🔄 Mevcut kurulumu temizleme..."
sudo systemctl stop rabbitmq-server || true
sudo pkill -f rabbitmq || true
sudo pkill -f beam || true
sudo pkill -f epmd || true

# Temizlik
sudo rm -rf /var/lib/rabbitmq/*
sudo rm -rf /var/log/rabbitmq/*
sudo rm -rf /etc/rabbitmq/*
sudo rm -rf /opt/rabbitmq/var/lib/rabbitmq/mnesia/*

# Hostname ayarla
echo "🔄 Hostname ayarlanıyor..."
SHORTNAME=$(echo $NODE_NAME | cut -d@ -f2)
sudo hostnamectl set-hostname $SHORTNAME

# Hosts dosyasını düzenle
echo "🔄 Hosts dosyası güncelleniyor..."
sudo bash -c 'cat > /etc/hosts' << EOF
127.0.0.1 localhost
127.0.0.1 $SHORTNAME
$NODE_IP $SHORTNAME
$MASTER_IP master-node
$WORKER_1_IP worker1
$WORKER_2_IP worker2
EOF

# Gerekli dizinleri oluştur
echo "🔄 Dizinler oluşturuluyor..."
sudo mkdir -p /var/lib/rabbitmq
sudo mkdir -p /var/log/rabbitmq
sudo mkdir -p /etc/rabbitmq
sudo mkdir -p /opt/rabbitmq/var/lib/rabbitmq/mnesia
sudo mkdir -p /home/rabbitmq

# RabbitMQ yapılandırma dosyalarını oluştur
echo "🔄 RabbitMQ yapılandırması oluşturuluyor..."
sudo tee /etc/rabbitmq/rabbitmq-env.conf << EOF
NODENAME=$NODE_NAME
NODE_IP_ADDRESS=$NODE_IP
NODE_PORT=$RABBITMQ_PORT
EOF

# Node tipine göre yapılandırma
if [ "$NODE_TYPE" == "master" ]; then
    sudo tee /etc/rabbitmq/rabbitmq.conf << EOF
listeners.tcp.default = $RABBITMQ_PORT
management.listener.port = $RABBITMQ_MANAGEMENT_PORT
management.listener.ip = 0.0.0.0
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = $NODE_NAME
EOF
else
    sudo tee /etc/rabbitmq/rabbitmq.conf << EOF
listeners.tcp.default = $RABBITMQ_PORT
management.listener.port = $RABBITMQ_MANAGEMENT_PORT
management.listener.ip = 0.0.0.0
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = $MASTER_NODE_NAME
EOF
fi

# Erlang cookie'leri ayarla
echo "🔄 Erlang cookie'leri ayarlanıyor..."
sudo bash -c "echo '$RABBITMQ_COOKIE' > /var/lib/rabbitmq/.erlang.cookie"
sudo bash -c "echo '$RABBITMQ_COOKIE' > /root/.erlang.cookie"
sudo bash -c "echo '$RABBITMQ_COOKIE' > /home/rabbitmq/.erlang.cookie"

# Cookie izinlerini ayarla
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /root/.erlang.cookie
sudo chmod 400 /home/rabbitmq/.erlang.cookie

# Dizin izinlerini ayarla
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq
sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq
sudo chown -R rabbitmq:rabbitmq /home/rabbitmq

# RabbitMQ'yu başlat
echo "🔄 RabbitMQ başlatılıyor..."
sudo systemctl daemon-reload
sudo systemctl enable rabbitmq-server
sudo systemctl restart rabbitmq-server

# Servisin başlaması için bekle
sleep 15

# Plugin'leri etkinleştir
echo "🔄 Plugin'ler etkinleştiriliyor..."
sudo rabbitmq-plugins enable rabbitmq_management
sudo rabbitmq-plugins enable rabbitmq_management_agent
sudo systemctl restart rabbitmq-server
sleep 5

# Admin kullanıcısını oluştur
echo "🔄 Admin kullanıcısı oluşturuluyor..."
sudo rabbitmqctl add_user "$RABBITMQ_ADMIN_USER" "$RABBITMQ_ADMIN_PASSWORD" || true
sudo rabbitmqctl set_user_tags "$RABBITMQ_ADMIN_USER" administrator
sudo rabbitmqctl set_permissions -p "/" "$RABBITMQ_ADMIN_USER" ".*" ".*" ".*"

# Worker node ise cluster'a katıl
if [ "$NODE_TYPE" != "master" ]; then
    echo "🔄 Cluster'a katılınıyor..."
    
    # Bağlantıyı kontrol et
    if ! ping -c 3 master-node &>/dev/null; then
        echo "❌ Master node'a ulaşılamıyor!"
        exit 1
    fi
    
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    sudo rabbitmqctl join_cluster rabbit@master-node
    sudo rabbitmqctl start_app
fi

# Son durum kontrolü
echo "🔄 Cluster durumu kontrol ediliyor..."
sudo rabbitmqctl cluster_status

echo "✅ RabbitMQ kurulumu tamamlandı!"
echo "📝 Yönetim arayüzü: http://$NODE_IP:15672"
echo "📝 Kullanıcı adı: $RABBITMQ_ADMIN_USER"
echo "📝 Şifre: $RABBITMQ_ADMIN_PASSWORD"
