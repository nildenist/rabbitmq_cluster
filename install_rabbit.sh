#!/bin/bash

set -e  # Hata yakalama
source rabbitmq.env  # rabbitmq.env dosyasını yükle

# Kullanım kontrolü
if [ -z "$1" ]; then
    echo "❌ Kullanım: ./install_rabbitmq.sh [master|worker]"
    exit 1
fi

NODE_TYPE=$1  # Kullanıcıdan alınan node tipi
FULL_NODE_NAME="rabbit@$NODE_NAME"

echo "🚀 RabbitMQ ve Erlang Kurulum Başlıyor..."
echo "📌 Erlang Version: $ERLANG_VERSION"
echo "📌 RabbitMQ Version: $RABBITMQ_VERSION"
echo "📌 Node Type: $NODE_TYPE"
echo "📌 Node Name: $FULL_NODE_NAME"

# Gerekli bağımlılıkları yükleyelim
sudo apt update && sudo apt install -y curl gnupg apt-transport-https

# Erlang Kurulumu
echo "🔄 Erlang $ERLANG_VERSION kuruluyor..."
wget -q https://erlang.org/download/otp_src_$ERLANG_VERSION.tar.gz
tar -xzf otp_src_$ERLANG_VERSION.tar.gz
cd otp_src_$ERLANG_VERSION
./configure
make -j$(nproc)
sudo make install
cd ..
rm -rf otp_src_$ERLANG_VERSION*

# RabbitMQ Kurulumu
echo "🔄 RabbitMQ $RABBITMQ_VERSION kuruluyor..."
wget -q https://github.com/rabbitmq/rabbitmq-server/releases/download/v$RABBITMQ_VERSION/rabbitmq-server-generic-unix-$RABBITMQ_VERSION.tar.xz
tar -xf rabbitmq-server-generic-unix-$RABBITMQ_VERSION.tar.xz
sudo mv rabbitmq_server-$RABBITMQ_VERSION /opt/rabbitmq
sudo ln -s /opt/rabbitmq/sbin/rabbitmqctl /usr/local/bin/rabbitmqctl
sudo ln -s /opt/rabbitmq/sbin/rabbitmq-server /usr/local/bin/rabbitmq-server
rm -f rabbitmq-server-generic-unix-$RABBITMQ_VERSION.tar.xz

# RabbitMQ Kullanıcısını Ayarla
sudo useradd --system --no-create-home --shell /bin/false rabbitmq || true
sudo mkdir -p /var/lib/rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq /var/log/rabbitmq

# RabbitMQ Node İsmini Ayarla
echo "🔄 RabbitMQ Node İsmi Ayarlanıyor: $FULL_NODE_NAME"
sudo mkdir -p /etc/rabbitmq
echo "NODENAME=$FULL_NODE_NAME" | sudo tee /etc/rabbitmq/rabbitmq-env.conf

# RabbitMQ Servisini Başlat
echo "🚀 RabbitMQ servisi başlatılıyor..."
sudo -u rabbitmq rabbitmq-server -detached
sleep 5  # Servisin başlamasını bekleyelim

# RabbitMQ Management Plugin Aç
echo "🔄 RabbitMQ Management Plugin Etkinleştiriliyor..."
sudo rabbitmq-plugins enable rabbitmq_management

# Cluster İçin Cookie Ayarı
echo "🔄 RabbitMQ Cluster Cookie Ayarlanıyor..."
echo "$RABBITMQ_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Master Node Ayarları
if [ "$NODE_TYPE" == "master" ]; then
    echo "🔄 Master node yapılandırılıyor..."
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    sudo rabbitmqctl start_app

    echo "🔄 Yönetici Kullanıcı Ayarları Yapılıyor..."
    sudo rabbitmqctl add_user $RABBITMQ_ADMIN_USER $RABBITMQ_ADMIN_PASSWORD
    sudo rabbitmqctl set_user_tags $RABBITMQ_ADMIN_USER administrator
    sudo rabbitmqctl set_permissions -p / $RABBITMQ_ADMIN_USER ".*" ".*" ".*"

    echo "✅ Master Node Kurulumu Tamamlandı!"

# Worker Node Ayarları
elif [ "$NODE_TYPE" == "worker" ]; then
    echo "🔄 Worker node yapılandırılıyor..."
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    sudo rabbitmqctl join_cluster $RABBITMQ_NODENAME
    sudo rabbitmqctl start_app

    echo "✅ Worker Node Master'a Bağlandı: $RABBITMQ_NODENAME"

else
    echo "❌ Geçersiz node tipi! Kullanım: ./install_rabbitmq.sh [master|worker]"
    exit 1
fi

# Log ve Data Yollarını Belirleme
echo "🔄 RabbitMQ Log & Mnesia Yolları Ayarlanıyor..."
sudo mkdir -p $RABBITMQ_LOG_DIR $RABBITMQ_MNESIA_DIR
sudo chown -R rabbitmq:rabbitmq $RABBITMQ_LOG_DIR $RABBITMQ_MNESIA_DIR

echo "✅ RabbitMQ ve Erlang Kurulumu Tamamlandı!"
echo "📌 RabbitMQ Yönetim Paneli: http://$(hostname -I | awk '{print $1}'):15672"
echo "📌 Kullanıcı Adı: $RABBITMQ_ADMIN_USER"
echo "📌 Şifre: $RABBITMQ_ADMIN_PASSWORD"
