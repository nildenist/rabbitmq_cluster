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

echo "🚀 RabbitMQ ve Erlang Kurulum Başlıyor..."
echo "📌 Erlang Version: $ERLANG_VERSION"
echo "📌 RabbitMQ Version: $RABBITMQ_VERSION"
echo "📌 Node Type: $NODE_TYPE"
echo "📌 Node Name: $NODE_NAME"
echo "📌 Node IP: $NODE_IP"

# Gerekli bağımlılıkları yükleyelim
sudo apt update && sudo apt install -y curl gnupg apt-transport-https

# Erlang Kurulumu
echo "🔄 Erlang $ERLANG_VERSION kuruluyor..."

# First try the official download URL
echo "🔄 Downloading Erlang from official source..."
ERLANG_DOWNLOAD_URL="https://github.com/erlang/otp/archive/OTP-${ERLANG_VERSION}.tar.gz"

if ! wget -q "$ERLANG_DOWNLOAD_URL" -O otp_src_$ERLANG_VERSION.tar.gz; then
    echo "⚠️ Failed to download from GitHub, trying alternative source..."
    # Try alternative download URL
    ERLANG_DOWNLOAD_URL="https://erlang.org/download/otp_src_${ERLANG_VERSION}.tar.gz"
    if ! wget -q "$ERLANG_DOWNLOAD_URL" -O otp_src_$ERLANG_VERSION.tar.gz; then
        echo "❌ Failed to download Erlang source from both sources"
        echo "Attempted URLs:"
        echo "1. https://github.com/erlang/otp/archive/OTP-${ERLANG_VERSION}.tar.gz"
        echo "2. https://erlang.org/download/otp_src_${ERLANG_VERSION}.tar.gz"
        exit 1
    fi
fi

echo "✅ Successfully downloaded Erlang source"

# Extract and get the actual directory name
tar -xzf otp_src_$ERLANG_VERSION.tar.gz || {
    echo "❌ Failed to extract Erlang source"
    exit 1
}

# Find the extracted directory name
ERLANG_SRC_DIR=$(find . -maxdepth 1 -type d -name "otp-OTP-${ERLANG_VERSION}*" -o -name "otp_src_${ERLANG_VERSION}*" | head -n 1)
if [ -z "$ERLANG_SRC_DIR" ]; then
    echo "❌ Could not find extracted Erlang directory"
    exit 1
fi

echo "🔄 Building Erlang in directory: $ERLANG_SRC_DIR"
cd "$ERLANG_SRC_DIR" || {
    echo "❌ Failed to change to Erlang source directory"
    exit 1
}

# Configure without wxWidgets and JavaC
./configure --prefix=/usr/local --without-wx --without-javac || {
    echo "❌ Erlang configure failed"
    exit 1
}

echo "🔄 Compiling Erlang (this may take a while)..."
make -j$(nproc) || {
    echo "❌ Erlang compilation failed"
    exit 1
}

echo "🔄 Installing Erlang..."
sudo make install || {
    echo "❌ Erlang installation failed"
    exit 1
}

cd ..
rm -rf "$ERLANG_SRC_DIR"
rm -f otp_src_$ERLANG_VERSION.tar.gz

# Verify Erlang installation
erl -eval 'erlang:display(erlang:system_info(version)), halt().' -noshell || {
    echo "❌ Erlang installation verification failed"
    exit 1
}

# RabbitMQ Kurulumu
echo "🔄 RabbitMQ $RABBITMQ_VERSION kuruluyor..."
wget -q https://github.com/rabbitmq/rabbitmq-server/releases/download/v$RABBITMQ_VERSION/rabbitmq-server-generic-unix-$RABBITMQ_VERSION.tar.xz
tar -xf rabbitmq-server-generic-unix-$RABBITMQ_VERSION.tar.xz

# Remove old installation if exists
sudo rm -rf /opt/rabbitmq
sudo rm -f /usr/local/bin/rabbitmqctl
sudo rm -f /usr/local/bin/rabbitmq-server
sudo rm -f /usr/local/bin/rabbitmq-env

# Install RabbitMQ
sudo mv rabbitmq_server-$RABBITMQ_VERSION /opt/rabbitmq

# Create all necessary symbolic links
sudo ln -sf /opt/rabbitmq/sbin/rabbitmqctl /usr/local/bin/rabbitmqctl
sudo ln -sf /opt/rabbitmq/sbin/rabbitmq-server /usr/local/bin/rabbitmq-server
sudo ln -sf /opt/rabbitmq/sbin/rabbitmq-env /usr/local/bin/rabbitmq-env
sudo ln -sf /opt/rabbitmq/sbin/rabbitmq-plugins /usr/local/bin/rabbitmq-plugins

# Clean up downloaded files
rm -f rabbitmq-server-generic-unix-$RABBITMQ_VERSION.tar.xz

# Set environment variables
echo "🔄 Setting up RabbitMQ environment..."
sudo mkdir -p /etc/rabbitmq
cat << EOF | sudo tee /etc/rabbitmq/rabbitmq-env.conf
NODENAME=$NODE_NAME
NODE_IP_ADDRESS=$NODE_IP
NODE_PORT=$RABBITMQ_PORT
RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
EOF

# Ensure proper permissions
sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq
sudo chmod -R 755 /opt/rabbitmq

# RabbitMQ Kullanıcısını Ayarla
sudo useradd --system --no-create-home --shell /bin/false rabbitmq || true
sudo mkdir -p /var/lib/rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq /var/log/rabbitmq

# RabbitMQ Node İsmini Ayarla
echo "🔄 RabbitMQ Node İsmi Ayarlanıyor: $NODE_NAME"
sudo mkdir -p /etc/rabbitmq
echo "NODENAME=$NODE_NAME" | sudo tee /etc/rabbitmq/rabbitmq-env.conf

# Set RabbitMQ environment for the rabbitmq user
sudo mkdir -p /var/lib/rabbitmq/mnesia
sudo mkdir -p /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq

# Start RabbitMQ service with proper environment
echo "🚀 RabbitMQ servisi başlatılıyor..."
sudo -u rabbitmq RABBITMQ_HOME=/opt/rabbitmq rabbitmq-server -detached
sleep 10  # Give more time for the service to start properly

# RabbitMQ Management Plugin Aç
echo "🔄 RabbitMQ Management Plugin Etkinleştiriliyor..."
sudo rabbitmq-plugins enable rabbitmq_management

# Cluster İçin Cookie Ayarı
echo "🔄 RabbitMQ Cluster Cookie Ayarlanıyor..."
echo "$RABBITMQ_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Restart RabbitMQ to apply cookie changes
echo "🔄 Restarting RabbitMQ service..."
sudo rabbitmqctl stop
sleep 5
sudo -u rabbitmq rabbitmq-server -detached
sleep 5

# Check connectivity to master
echo "🔄 Checking connectivity to master node..."
if ! ping -c 1 $MASTER_IP &> /dev/null; then
    echo "❌ Cannot reach master node at $MASTER_IP"
    exit 1
fi

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
elif [ "$NODE_TYPE" == "worker1" ] || [ "$NODE_TYPE" == "worker2" ]; then
    echo "🔄 $NODE_NAME, Master Node'a bağlanıyor: $MASTER_NODE_NAME ($MASTER_IP)"
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    sudo rabbitmqctl join_cluster $MASTER_NODE_NAME
    sudo rabbitmqctl start_app

    echo "✅ Worker Node Master'a Bağlandı: $MASTER_NODE_NAME"

else
    echo "❌ Geçersiz node tipi!"
    exit 1
fi

# Log ve Data Yollarını Belirleme
echo "🔄 RabbitMQ Log & Mnesia Yolları Ayarlanıyor..."
sudo mkdir -p $RABBITMQ_LOG_DIR $RABBITMQ_MNESIA_DIR
sudo chown -R rabbitmq:rabbitmq $RABBITMQ_LOG_DIR $RABBITMQ_MNESIA_DIR

echo "✅ RabbitMQ ve Erlang Kurulumu Tamamlandı!"
echo "📌 RabbitMQ Yönetim Paneli: http://$MASTER_IP:15672"
echo "📌 Kullanıcı Adı: $RABBITMQ_ADMIN_USER"
echo "📌 Şifre: $RABBITMQ_ADMIN_PASSWORD"

echo "🔄 Checking host resolution..."
# Add hosts entries if they don't exist
if ! grep -q "$MASTER_IP.*master-node" /etc/hosts; then
    echo "$MASTER_IP master-node" | sudo tee -a /etc/hosts
fi
if ! grep -q "$WORKER_1_IP.*worker1" /etc/hosts; then
    echo "$WORKER_1_IP worker1" | sudo tee -a /etc/hosts
fi
if ! grep -q "$WORKER_2_IP.*worker2" /etc/hosts; then
    echo "$WORKER_2_IP worker2" | sudo tee -a /etc/hosts
fi
