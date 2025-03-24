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

# Add this section after the NODE_TYPE check and before starting the installation

# Prompt for RabbitMQ admin credentials if not already set
if [ -z "$RABBITMQ_ADMIN_USER" ] || [ -z "$RABBITMQ_ADMIN_PASSWORD" ]; then
    echo "🔄 Please enter RabbitMQ admin credentials:"
    
    # Keep asking until we get a valid username
    while true; do
        read -p "Admin Username (minimum 4 characters): " RABBITMQ_ADMIN_USER
        if [ ${#RABBITMQ_ADMIN_USER} -ge 4 ]; then
            break
        else
            echo "❌ Username must be at least 4 characters long"
        fi
    done
    
    # Keep asking until we get a valid password
    while true; do
        read -s -p "Admin Password (minimum 8 characters): " RABBITMQ_ADMIN_PASSWORD
        echo
        if [ ${#RABBITMQ_ADMIN_PASSWORD} -ge 8 ]; then
            read -s -p "Confirm Password: " RABBITMQ_ADMIN_PASSWORD_CONFIRM
            echo
            if [ "$RABBITMQ_ADMIN_PASSWORD" = "$RABBITMQ_ADMIN_PASSWORD_CONFIRM" ]; then
                break
            else
                echo "❌ Passwords do not match"
            fi
        else
            echo "❌ Password must be at least 8 characters long"
        fi
    done
    
    # Export the variables so they're available throughout the script
    export RABBITMQ_ADMIN_USER
    export RABBITMQ_ADMIN_PASSWORD
    
    # Save to rabbit.env file if user confirms
    read -p "Would you like to save these credentials to rabbit.env? (y/N): " SAVE_CREDS
    if [[ "$SAVE_CREDS" =~ ^[Yy]$ ]]; then
        # Remove old credentials if they exist
        sed -i '/RABBITMQ_ADMIN_USER=/d' rabbit.env
        sed -i '/RABBITMQ_ADMIN_PASSWORD=/d' rabbit.env
        
        # Add new credentials
        echo "RABBITMQ_ADMIN_USER=$RABBITMQ_ADMIN_USER" >> rabbit.env
        echo "RABBITMQ_ADMIN_PASSWORD=$RABBITMQ_ADMIN_PASSWORD" >> rabbit.env
        echo "✅ Credentials saved to rabbit.env"
    fi
fi

echo "🚀 RabbitMQ ve Erlang Kurulum Başlıyor..."
echo "📌 Erlang Version: $ERLANG_VERSION"
echo "📌 RabbitMQ Version: $RABBITMQ_VERSION"
echo "📌 Node Type: $NODE_TYPE"
echo "📌 Node Name: $NODE_NAME"
echo "📌 Node IP: $NODE_IP"

# Gerekli bağımlılıkları yükleyelim
sudo apt update && sudo apt install -y curl wget build-essential

# Check if Erlang is already installed with correct version
echo "🔄 Checking Erlang installation..."
if command -v erl >/dev/null 2>&1; then
    CURRENT_ERLANG_VERSION=$(erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell)
    if [ "$CURRENT_ERLANG_VERSION" = "$ERLANG_VERSION" ]; then
        echo "✅ Erlang $CURRENT_ERLANG_VERSION is already installed"
    else
        echo "⚠️ Found Erlang $CURRENT_ERLANG_VERSION but need $ERLANG_VERSION"
        echo "🔄 Removing existing Erlang installation..."
        sudo rm -f /etc/apt/sources.list.d/erlang*  # Remove Erlang repo
        sudo apt-get remove -y erlang* || true
        sudo apt-get autoremove -y
        sudo rm -rf /usr/lib/erlang
        sudo rm -f /usr/bin/erl
        sudo rm -f /usr/bin/erlc
        INSTALL_ERLANG=true
    fi
else
    INSTALL_ERLANG=true
fi

# Remove any remaining repository files
sudo rm -f /etc/apt/sources.list.d/erlang*
sudo rm -f /etc/apt/sources.list.d/rabbitmq*

# Update package list after removing repos
sudo apt-get update

if [ "$INSTALL_ERLANG" = true ]; then
    echo "🔄 Installing Erlang $ERLANG_VERSION from source..."
    
    # Install build dependencies
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

    # Download and extract Erlang source from GitHub
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

    # Configure and build
    ./otp_build autoconf || {
        echo "❌ Failed to run autoconf"
        exit 1
    }

    ./configure --prefix=/usr/local \
        --enable-threads \
        --enable-smp-support \
        --enable-kernel-poll \
        --enable-ssl \
        --with-ssl \
        --enable-crypto \
        || {
            echo "❌ Configure failed"
            exit 1
        }

    make -j$(nproc) || {
        echo "❌ Make failed"
        exit 1
    }

    sudo make install || {
        echo "❌ Make install failed"
        exit 1
    }

    cd ..
    rm -rf otp-OTP-${ERLANG_VERSION}*
fi

# Verify Erlang installation
echo "🔄 Verifying Erlang installation..."
erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell || {
    echo "❌ Erlang installation verification failed"
    exit 1
}

# After verifying Erlang version
echo "🔄 Checking Erlang modules..."
if ! erl -noshell -eval 'case code:ensure_loaded(crypto) of {module,crypto} -> halt(0); _ -> halt(1) end.'; then
    echo "⚠️ Crypto module not found, reinstalling Erlang from source..."
    
    # Remove existing Erlang installation
    sudo rm -f /etc/apt/sources.list.d/erlang*  # Remove Erlang repo
    sudo apt-get remove -y erlang* || true
    sudo apt-get autoremove -y
    sudo rm -rf /usr/lib/erlang
    sudo rm -f /usr/bin/erl
    sudo rm -f /usr/bin/erlc
    
    # Install build dependencies
    sudo apt-get update
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

    # Configure and build
    ./configure --prefix=/usr/local \
        --enable-threads \
        --enable-smp-support \
        --enable-kernel-poll \
        --enable-ssl \
        --with-ssl \
        --enable-crypto \
        || {
            echo "❌ Configure failed"
            exit 1
        }

    make -j$(nproc) || {
        echo "❌ Make failed"
        exit 1
    }

    sudo make install || {
        echo "❌ Make install failed"
        exit 1
    }

    cd ..
    rm -rf otp-OTP-${ERLANG_VERSION}*
fi

# Verify crypto module again
echo "🔄 Verifying crypto module..."
if ! erl -noshell -eval '
    case application:ensure_all_started(crypto) of
        {ok, _} -> 
            io:format("Crypto module working~n"),
            halt(0);
        Error -> 
            io:format("Error: ~p~n", [Error]),
            halt(1)
    end.'; then
    echo "❌ Crypto module verification failed"
    echo "🔍 Checking Erlang installation:"
    dpkg -l | grep erlang
    echo "🔍 Checking crypto module location:"
    find /usr/lib/erlang -name crypto.beam
    exit 1
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

# Update hosts file with all cluster nodes
echo "🔄 Configuring hosts file for cluster communication..."
# First remove any existing entries for our nodes
sudo sed -i "/$SHORTNAME/d" /etc/hosts
sudo sed -i "/master-node/d" /etc/hosts
sudo sed -i "/worker1/d" /etc/hosts
sudo sed -i "/worker2/d" /etc/hosts

# Add localhost entry for current node
echo "127.0.0.1 $SHORTNAME" | sudo tee -a /etc/hosts
echo "$NODE_IP $SHORTNAME" | sudo tee -a /etc/hosts

# Add all cluster nodes to hosts file
if [ "$NODE_TYPE" == "master" ]; then
    # Master needs to know about all workers
    echo "$WORKER_1_IP worker1" | sudo tee -a /etc/hosts
    echo "$WORKER_2_IP worker2" | sudo tee -a /etc/hosts
    echo "✅ Added worker nodes to hosts file"
else
    # Workers need to know about master
    echo "$MASTER_IP master-node" | sudo tee -a /etc/hosts
    echo "✅ Added master node to hosts file"
fi

# Verify hosts file
echo "🔄 Verifying hosts file configuration:"
cat /etc/hosts

# Create RabbitMQ user first
echo "🔄 Creating RabbitMQ system user..."
sudo groupadd -f rabbitmq
sudo useradd -r -g rabbitmq -d /var/lib/rabbitmq -s /bin/false rabbitmq || true

# Create necessary directories first
echo "🔄 Creating required directories..."
sudo mkdir -p /var/lib/rabbitmq
sudo mkdir -p /var/log/rabbitmq
sudo mkdir -p /etc/rabbitmq
sudo mkdir -p /opt/rabbitmq/var/lib/rabbitmq/mnesia
sudo mkdir -p /home/rabbitmq

# Set proper ownership
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq
sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq
sudo chown -R rabbitmq:rabbitmq /home/rabbitmq

# Set hostname first
echo "🔄 Setting hostname..."
SHORTNAME=$(echo $NODE_NAME | cut -d@ -f2)
sudo hostnamectl set-hostname $SHORTNAME

# Update hosts file before any other operations
echo "🔄 Updating hosts file..."
sudo bash -c 'cat > /etc/hosts' << EOF
127.0.0.1 localhost
127.0.0.1 $SHORTNAME
$NODE_IP $SHORTNAME
$MASTER_IP master-node
$WORKER_1_IP worker1
$WORKER_2_IP worker2
EOF

# Verify hosts file
echo "🔄 Verifying hosts file configuration:"
cat /etc/hosts

# Remove any existing service files
echo "🔄 Cleaning up any existing service files..."
sudo rm -f /etc/systemd/system/rabbitmq-server.service
sudo rm -f /lib/systemd/system/rabbitmq-server.service
sudo systemctl daemon-reload

# Modify the cleanup section
echo "🔄 Performing cleanup..."
if systemctl is-active rabbitmq-server &>/dev/null; then
    sudo systemctl stop rabbitmq-server || true
fi
sudo pkill -f rabbitmq || true
sudo pkill -f beam || true
sudo pkill -f epmd || true

# Clean up directories
sudo rm -rf /var/lib/rabbitmq/*
sudo rm -rf /var/log/rabbitmq/*
sudo rm -rf /etc/rabbitmq/*
sudo rm -rf /opt/rabbitmq/var/lib/rabbitmq/mnesia/*

# Erlang cookie'lerini temizle ve yeniden ayarla
echo "🔄 Setting up Erlang cookies..."
for COOKIE_PATH in /var/lib/rabbitmq/.erlang.cookie /root/.erlang.cookie /home/rabbitmq/.erlang.cookie; do
    echo "$RABBITMQ_COOKIE" | sudo tee "$COOKIE_PATH" > /dev/null
    sudo chmod 400 "$COOKIE_PATH"
    if [[ "$COOKIE_PATH" == "/var/lib/rabbitmq/.erlang.cookie" ]] || [[ "$COOKIE_PATH" == "/home/rabbitmq/.erlang.cookie" ]]; then
        sudo chown rabbitmq:rabbitmq "$COOKIE_PATH"
    fi
done

# Hostname ve hosts dosyasını ayarla
echo "🔄 Setting up hostname and hosts..."
sudo hostnamectl set-hostname $SHORTNAME

# Hosts dosyasını temizle ve yeniden ayarla
sudo sed -i "/$SHORTNAME/d" /etc/hosts
sudo sed -i "/master-node/d" /etc/hosts
sudo sed -i "/worker1/d" /etc/hosts
sudo sed -i "/worker2/d" /etc/hosts

# Yeni host girişlerini ekle
echo "127.0.0.1 localhost" | sudo tee /etc/hosts
echo "127.0.0.1 $SHORTNAME" | sudo tee -a /etc/hosts
echo "$NODE_IP $SHORTNAME" | sudo tee -a /etc/hosts
echo "$MASTER_IP master-node" | sudo tee -a /etc/hosts
echo "$WORKER_1_IP worker1" | sudo tee -a /etc/hosts
echo "$WORKER_2_IP worker2" | sudo tee -a /etc/hosts

# RabbitMQ servisini başlat
sudo systemctl daemon-reload
sudo systemctl restart rabbitmq-server

# Servisin başlaması için bekle
sleep 15

# Plugin'leri etkinleştir
echo "🔄 Enabling plugins..."
sudo rabbitmq-plugins enable rabbitmq_management
sudo rabbitmq-plugins enable rabbitmq_management_agent
sudo rabbitmq-plugins enable rabbitmq_prometheus

# Admin kullanıcısını oluştur
echo "🔄 Creating admin user..."
sudo rabbitmqctl add_user "$RABBITMQ_ADMIN_USER" "$RABBITMQ_ADMIN_PASSWORD" || true
sudo rabbitmqctl set_user_tags "$RABBITMQ_ADMIN_USER" administrator
sudo rabbitmqctl set_permissions -p "/" "$RABBITMQ_ADMIN_USER" ".*" ".*" ".*"

# Worker node ise cluster'a katıl
if [ "$NODE_TYPE" != "master" ]; then
    echo "🔄 Joining cluster as $NODE_TYPE..."
    
    # Önce bağlantıyı kontrol et
    if ! ping -c 3 master-node &>/dev/null; then
        echo "❌ Cannot reach master node. Check network connectivity."
        exit 1
    fi

    # RabbitMQ uygulamasını durdur
    sudo rabbitmqctl stop_app
    
    # Node'u sıfırla
    sudo rabbitmqctl reset
    
    # Cluster'a katılmayı dene
    MAX_RETRIES=5
    RETRY_COUNT=0
    JOINED=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$JOINED" = false ]; do
        echo "🔄 Attempting to join cluster (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
        if sudo rabbitmqctl join_cluster rabbit@master-node; then
            JOINED=true
            echo "✅ Successfully joined the cluster"
        else
            RETRY_COUNT=$((RETRY_COUNT+1))
            echo "⚠️ Join attempt failed, waiting before retry..."
            sleep 10
        fi
    done
    
    if [ "$JOINED" = false ]; then
        echo "❌ Failed to join cluster after $MAX_RETRIES attempts"
        exit 1
    fi
    
    # Uygulamayı başlat
    sudo rabbitmqctl start_app
fi

# Son durum kontrolü
echo "🔄 Final status check..."
sudo rabbitmqctl cluster_status
sudo rabbitmq-plugins list

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

# After creating the systemd service and before starting it, add:

echo "🔄 Creating RabbitMQ configuration files..."

# Create rabbitmq-env.conf with proper environment settings
sudo tee /etc/rabbitmq/rabbitmq-env.conf << EOF
NODENAME=${NODE_NAME}
HOME=/home/rabbitmq
NODE_IP_ADDRESS=${NODE_IP}
NODE_PORT=${RABBITMQ_PORT}
RABBITMQ_BASE=/var/lib/rabbitmq
RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
RABBITMQ_LOG_BASE=/var/log/rabbitmq
EOF

# Create rabbitmq.conf with proper configuration based on node type
if [ "$NODE_TYPE" == "master" ]; then
    # Master node configuration
    sudo tee /etc/rabbitmq/rabbitmq.conf << EOF
# Networking
listeners.tcp.default = ${RABBITMQ_PORT}
management.listener.port = ${RABBITMQ_MANAGEMENT_PORT}
management.listener.ip = 0.0.0.0

# Basic logging
log.file = true
log.file.level = info
log.dir = /var/log/rabbitmq

# Cluster settings
cluster_partition_handling = ignore
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = ${NODE_NAME}

# Memory and disk limits
vm_memory_high_watermark.relative = 0.7
disk_free_limit.absolute = 2GB

# Security
loopback_users = none
EOF
else
    # Worker node configuration
    sudo tee /etc/rabbitmq/rabbitmq.conf << EOF
# Networking
listeners.tcp.default = 5672
management.listener.port = 15672
management.listener.ip = 0.0.0.0

# Basic logging
log.file = true
log.file.level = debug  # Temporarily increase log level
log.dir = /var/log/rabbitmq

# Cluster settings
cluster_partition_handling = ignore
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@master-node

# Memory and disk limits
vm_memory_high_watermark.relative = 0.7
disk_free_limit.absolute = 2GB

# Security
loopback_users = none
EOF
fi

# Set proper permissions
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq
sudo chmod 644 /etc/rabbitmq/rabbitmq.conf
sudo chmod 644 /etc/rabbitmq/rabbitmq-env.conf

# Clean any existing state before starting
sudo systemctl stop rabbitmq-server || true
sudo rm -rf /var/lib/rabbitmq/mnesia/*
sudo rm -f /var/log/rabbitmq/*.log
sudo rm -f erl_crash.dump

# Verify directory permissions
echo "🔄 Verifying directory permissions..."
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /home/rabbitmq
sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq

# Verify cookie files
echo "🔄 Verifying cookie files..."
for COOKIE_PATH in /var/lib/rabbitmq/.erlang.cookie /home/rabbitmq/.erlang.cookie /root/.erlang.cookie; do
    if [ -f "$COOKIE_PATH" ]; then
        CURRENT_COOKIE=$(sudo cat "$COOKIE_PATH")
        if [ "$CURRENT_COOKIE" != "$RABBITMQ_COOKIE" ]; then
            echo "⚠️ Fixing cookie mismatch in $COOKIE_PATH"
            echo "$RABBITMQ_COOKIE" | sudo tee "$COOKIE_PATH" > /dev/null
            sudo chmod 400 "$COOKIE_PATH"
            sudo chown rabbitmq:rabbitmq "$COOKIE_PATH"
        fi
    fi
done

# Reload systemd
sudo systemctl daemon-reload

echo "✅ RabbitMQ configuration completed"

# Add after creating directories and before starting the service
echo "🔄 Setting up PID directory..."
sudo mkdir -p /opt/rabbitmq/var/lib/rabbitmq/mnesia
sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq/var/lib/rabbitmq
sudo chmod 755 /opt/rabbitmq/var/lib/rabbitmq
sudo chmod 755 /opt/rabbitmq/var/lib/rabbitmq/mnesia

# Also update the systemd service to use the correct PID directory
cat << EOF | sudo tee /etc/systemd/system/rabbitmq-server.service
[Unit]
Description=RabbitMQ Server
After=network.target epmd@0.0.0.0.socket
Wants=network.target epmd@0.0.0.0.socket

[Service]
Type=notify
User=rabbitmq
Group=rabbitmq
Environment=HOME=/home/rabbitmq
Environment=RABBITMQ_HOME=/opt/rabbitmq
Environment=RABBITMQ_NODENAME=${NODE_NAME}
Environment=RABBITMQ_NODE_IP_ADDRESS=${NODE_IP}
Environment=RABBITMQ_NODE_PORT=${RABBITMQ_PORT}
Environment=RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
Environment=RABBITMQ_LOG_BASE=/var/log/rabbitmq
Environment=RABBITMQ_MNESIA_BASE=/opt/rabbitmq/var/lib/rabbitmq/mnesia
Environment=RABBITMQ_PID_FILE=/opt/rabbitmq/var/lib/rabbitmq/mnesia/\${RABBITMQ_NODENAME}.pid
Environment=RABBITMQ_ENABLED_PLUGINS_FILE=/etc/rabbitmq/enabled_plugins
Environment=PATH=/opt/rabbitmq/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=LANG=en_US.UTF-8
Environment=LC_ALL=en_US.UTF-8

ExecStart=/opt/rabbitmq/sbin/rabbitmq-server
ExecStop=/opt/rabbitmq/sbin/rabbitmqctl stop
Restart=always
RestartSec=10
WorkingDirectory=/var/lib/rabbitmq
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Check cookie files on both master and worker2
sudo cat /var/lib/rabbitmq/.erlang.cookie  # On both nodes
sudo cat /home/rabbitmq/.erlang.cookie     # On both nodes
sudo cat /root/.erlang.cookie              # On both nodes

# Restart RabbitMQ with the new configuration
sudo systemctl restart rabbitmq-server

# Add this section after line 748 (after "Clean any existing state before starting")
# Complete cleanup and restart sequence
echo "🔄 Performing complete cleanup and restart sequence..."
sudo systemctl stop rabbitmq-server
sudo rm -rf /var/lib/rabbitmq/mnesia/*
sudo rm -f /var/log/rabbitmq/*.log
sudo rm -f /opt/rabbitmq/var/lib/rabbitmq/mnesia/*

# Verify and fix cookie files with proper permissions
echo "🔄 Fixing cookie files with proper permissions..."
sudo bash -c 'echo "RABBITMQ_CLUSTER_COOKIE_SECRET_KEY_STRING_1234567890" > /var/lib/rabbitmq/.erlang.cookie'
sudo bash -c 'echo "RABBITMQ_CLUSTER_COOKIE_SECRET_KEY_STRING_1234567890" > /root/.erlang.cookie'
sudo bash -c 'echo "RABBITMQ_CLUSTER_COOKIE_SECRET_KEY_STRING_1234567890" > /home/rabbitmq/.erlang.cookie'

# Set proper permissions for cookie files
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /root/.erlang.cookie
sudo chmod 400 /home/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /home/rabbitmq/.erlang.cookie

# Verify hostname
echo "🔄 Setting hostname..."
sudo hostnamectl set-hostname $SHORTNAME

# Update /etc/hosts with clean entries
echo "🔄 Updating hosts file..."
sudo sed -i "/$SHORTNAME/d" /etc/hosts
sudo sed -i "/master-node/d" /etc/hosts
sudo sed -i "/worker1/d" /etc/hosts
sudo sed -i "/worker2/d" /etc/hosts

# Add fresh host entries
echo "127.0.0.1 $SHORTNAME" | sudo tee -a /etc/hosts
echo "$NODE_IP $SHORTNAME" | sudo tee -a /etc/hosts
echo "$MASTER_IP master-node" | sudo tee -a /etc/hosts
echo "$WORKER_1_IP worker1" | sudo tee -a /etc/hosts
echo "$WORKER_2_IP worker2" | sudo tee -a /etc/hosts

# Continue with the existing script...

# Add after the RabbitMQ service start
if [ "$NODE_TYPE" != "master" ]; then
    echo "🔄 Joining cluster as $NODE_TYPE..."
    
    # Stop the RabbitMQ application (but not the Erlang node)
    sudo rabbitmqctl stop_app
    
    # Reset the node
    sudo rabbitmqctl reset
    
    # Verify connectivity to master node before joining
    echo "🔄 Verifying connectivity to master node..."
    if ! ping -c 3 master-node &>/dev/null; then
        echo "❌ Cannot reach master node. Check network connectivity."
        exit 1
    fi

    # Check if master node is reachable via RabbitMQ
    if ! sudo rabbitmqctl -n rabbit@master-node status &>/dev/null; then
        echo "❌ Cannot reach RabbitMQ on master node. Check if RabbitMQ is running on master."
        exit 1
    fi
    
    # Join the cluster with retry logic
    MAX_RETRIES=5
    RETRY_COUNT=0
    JOINED=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$JOINED" = false ]; do
        echo "🔄 Attempting to join cluster (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
        if sudo rabbitmqctl join_cluster rabbit@master-node; then
            JOINED=true
            echo "✅ Successfully joined the cluster"
        else
            RETRY_COUNT=$((RETRY_COUNT+1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "⚠️ Join attempt failed, waiting before retry..."
                sleep 10
            fi
        fi
    done
    
    if [ "$JOINED" = false ]; then
        echo "❌ Failed to join cluster after $MAX_RETRIES attempts"
        exit 1
    fi
    
    # Start the application
    sudo rabbitmqctl start_app
    
    # Verify cluster status
    echo "🔄 Verifying cluster status..."
    sudo rabbitmqctl cluster_status
fi

# Enable management plugin and other necessary plugins
echo "🔄 Enabling RabbitMQ plugins..."
sudo rabbitmq-plugins enable rabbitmq_management
sudo rabbitmq-plugins enable rabbitmq_management_agent
sudo rabbitmq-plugins enable rabbitmq_prometheus

# Create admin user and set permissions
echo "🔄 Setting up admin user..."
sudo rabbitmqctl add_user "$RABBITMQ_ADMIN_USER" "$RABBITMQ_ADMIN_PASSWORD" || true
sudo rabbitmqctl set_user_tags "$RABBITMQ_ADMIN_USER" administrator
sudo rabbitmqctl set_permissions -p "/" "$RABBITMQ_ADMIN_USER" ".*" ".*" ".*"

# Restart RabbitMQ to apply plugin changes
sudo systemctl restart rabbitmq-server

# Wait for service to fully start
sleep 15  # Bekleme süresini artıralım

# If this is a worker node, join the cluster
if [ "$NODE_TYPE" != "master" ]; then
    echo "🔄 Joining cluster as $NODE_TYPE..."
    
    # Stop the RabbitMQ application (but not the Erlang node)
    sudo rabbitmqctl stop_app
    
    # Reset the node
    sudo rabbitmqctl reset
    
    # Verify connectivity to master node before joining
    echo "🔄 Verifying connectivity to master node..."
    if ! ping -c 3 master-node &>/dev/null; then
        echo "❌ Cannot reach master node. Check network connectivity."
        exit 1
    fi

    # Check if master node is reachable via RabbitMQ
    if ! sudo rabbitmqctl -n rabbit@master-node status &>/dev/null; then
        echo "❌ Cannot reach RabbitMQ on master node. Check if RabbitMQ is running on master."
        exit 1
    fi
    
    # Join the cluster with retry logic
    MAX_RETRIES=5
    RETRY_COUNT=0
    JOINED=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$JOINED" = false ]; do
        echo "🔄 Attempting to join cluster (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
        if sudo rabbitmqctl join_cluster rabbit@master-node; then
            JOINED=true
            echo "✅ Successfully joined the cluster"
        else
            RETRY_COUNT=$((RETRY_COUNT+1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "⚠️ Join attempt failed, waiting before retry..."
                sleep 10
            fi
        fi
    done
    
    if [ "$JOINED" = false ]; then
        echo "❌ Failed to join cluster after $MAX_RETRIES attempts"
        exit 1
    fi
    
    # Start the application
    sudo rabbitmqctl start_app
    
    # Verify cluster status
    echo "🔄 Verifying cluster status..."
    sudo rabbitmqctl cluster_status
fi

# Final verification of plugins
echo "🔄 Verifying plugin status..."
sudo rabbitmq-plugins list

# Final cluster status check
echo "🔄 Final cluster status check..."
sudo rabbitmqctl cluster_status
