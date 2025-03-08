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

# Check if Erlang is already installed
echo "🔄 Checking Erlang installation..."
if command -v erl >/dev/null 2>&1; then
    CURRENT_ERLANG_VERSION=$(erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell)
    echo "✅ Erlang $CURRENT_ERLANG_VERSION is already installed"
else
    echo "🔄 Erlang $ERLANG_VERSION kuruluyor..."

    # Remove Erlang Solutions repository if exists
    echo "🔄 Cleaning up package sources..."
    sudo rm -f /etc/apt/sources.list.d/erlang*
    sudo rm -f /etc/apt/sources.list.d/rabbitmq*
    sudo apt-get update

    # Install build dependencies
    echo "🔄 Installing build dependencies..."
    sudo apt-get install -y \
        build-essential \
        autoconf \
        m4 \
        libncurses5-dev \
        libssh-dev \
        unixodbc-dev \
        libgmp3-dev \
        libssl-dev \
        libsctp-dev \
        lksctp-tools \
        ed \
        flex \
        libxml2-utils \
        wget \
        || {
            echo "❌ Failed to install build dependencies"
            exit 1
        }

    # Download and extract Erlang source
    echo "🔄 Downloading Erlang source..."
    ERLANG_DOWNLOAD_URL="https://github.com/erlang/otp/archive/OTP-${ERLANG_VERSION}.tar.gz"
    wget -q "$ERLANG_DOWNLOAD_URL" || {
        echo "❌ Failed to download Erlang source"
        echo "URL: $ERLANG_DOWNLOAD_URL"
        exit 1
    }

    tar xzf OTP-${ERLANG_VERSION}.tar.gz || {
        echo "❌ Failed to extract Erlang source"
        exit 1
    }

    cd otp-OTP-${ERLANG_VERSION} || {
        echo "❌ Failed to change to Erlang directory"
        exit 1
    }

    # Prepare for build
    echo "🔄 Preparing Erlang build..."
    ./otp_build autoconf || {
        echo "❌ Failed to run autoconf"
        exit 1
    }

    # Configure with minimal components needed for RabbitMQ
    ./configure --prefix=/usr/local \
        --without-wx \
        --without-debugger \
        --without-observer \
        --without-javac \
        --without-et \
        --without-megaco \
        --without-diameter \
        --without-edoc \
        --enable-threads \
        --enable-smp-support \
        --enable-kernel-poll \
        --disable-hipe \
        --disable-sctp \
        --disable-dynamic-ssl-lib \
        || {
            echo "❌ Configure failed"
            exit 1
        }

    # Build and install
    echo "🔄 Building Erlang (this may take a while)..."
    make -j$(nproc) || {
        echo "❌ Make failed"
        exit 1
    }

    echo "🔄 Installing Erlang..."
    sudo make install || {
        echo "❌ Make install failed"
        exit 1
    }

    # Cleanup
    cd ..
    rm -rf otp-OTP-${ERLANG_VERSION}*

    # Verify installation
    echo "🔄 Verifying Erlang installation..."
    erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell || {
        echo "❌ Erlang installation verification failed"
        exit 1
    }
fi

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

# Set the hostname to match the node name
SHORTNAME=$(echo $NODE_NAME | cut -d@ -f2)
sudo hostnamectl set-hostname $SHORTNAME

# Update hosts file for the current machine
echo "127.0.0.1 $SHORTNAME" | sudo tee -a /etc/hosts
echo "$NODE_IP $SHORTNAME" | sudo tee -a /etc/hosts

# Create RabbitMQ user if not exists
sudo useradd -r -d /var/lib/rabbitmq -s /bin/false rabbitmq || true

# Set up directories and permissions
sudo mkdir -p /var/lib/rabbitmq/mnesia
sudo mkdir -p /var/log/rabbitmq
sudo mkdir -p /etc/rabbitmq

# Set the Erlang cookie before anything else
echo "🔄 RabbitMQ Cluster Cookie Ayarlanıyor..."
echo "$RABBITMQ_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
echo "$RABBITMQ_COOKIE" | sudo tee /root/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /root/.erlang.cookie

# Set proper permissions
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq
sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq

# Configure RabbitMQ environment
cat << EOF | sudo tee /etc/rabbitmq/rabbitmq-env.conf
NODENAME=$NODE_NAME
NODE_IP_ADDRESS=$NODE_IP
NODE_PORT=$RABBITMQ_PORT
RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
EOF

# Stop any existing RabbitMQ process
sudo pkill -f rabbitmq || true
sleep 5

# Start RabbitMQ service with proper environment
echo "🚀 RabbitMQ servisi başlatılıyor..."
sudo -u rabbitmq RABBITMQ_HOME=/opt/rabbitmq \
    RABBITMQ_NODENAME=$NODE_NAME \
    RABBITMQ_NODE_IP_ADDRESS=$NODE_IP \
    RABBITMQ_NODE_PORT=$RABBITMQ_PORT \
    rabbitmq-server -detached

# Wait for service to start
echo "🔄 Waiting for RabbitMQ to start..."
for i in {1..30}; do
    if sudo rabbitmqctl status --node $NODE_NAME >/dev/null 2>&1; then
        echo "✅ RabbitMQ service started successfully"
        break
    fi
    echo "⏳ Still waiting... ($i/30)"
    sleep 2
done

# Verify the service is running
echo "🔄 Verifying RabbitMQ service..."
if ! sudo rabbitmqctl status --node $NODE_NAME; then
    echo "❌ RabbitMQ service failed to start"
    echo "🔍 Checking logs..."
    sudo tail -n 50 /var/log/rabbitmq/rabbit@${SHORTNAME}.log
    exit 1
fi

# Enable management plugin
echo "🔄 RabbitMQ Management Plugin Etkinleştiriliyor..."
sudo rabbitmqctl -n $NODE_NAME stop_app
sudo rabbitmqctl -n $NODE_NAME reset
sudo rabbitmqctl -n $NODE_NAME start_app
sudo rabbitmq-plugins -n $NODE_NAME enable rabbitmq_management

# Restart service to apply changes
echo "🔄 Restarting RabbitMQ service..."
sudo rabbitmqctl -n $NODE_NAME stop
sleep 5
sudo -u rabbitmq RABBITMQ_HOME=/opt/rabbitmq RABBITMQ_NODENAME=$NODE_NAME rabbitmq-server -detached
sleep 10

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

# Add after setting the cookie
echo "🔄 Verifying cookie files..."
if [ "$(sudo cat /var/lib/rabbitmq/.erlang.cookie)" != "$RABBITMQ_COOKIE" ]; then
    echo "❌ Cookie mismatch in /var/lib/rabbitmq/.erlang.cookie"
    exit 1
fi
if [ "$(sudo cat /root/.erlang.cookie)" != "$RABBITMQ_COOKIE" ]; then
    echo "❌ Cookie mismatch in /root/.erlang.cookie"
    exit 1
fi
