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
        libcrypto++-dev \
        erlang-dev \
        erlang-crypto \
        || {
            echo "❌ Failed to install build dependencies"
            exit 1
        }

    # Download and extract Erlang source
    echo "🔄 Downloading Erlang source..."
    ERLANG_DOWNLOAD_URL="https://github.com/erlang/otp/releases/download/OTP-${ERLANG_VERSION}/otp_src_${ERLANG_VERSION}.tar.gz"
    wget -q "$ERLANG_DOWNLOAD_URL" || {
        echo "❌ Failed to download Erlang source"
        echo "URL: $ERLANG_DOWNLOAD_URL"
        exit 1
    }

    tar xzf otp_src_${ERLANG_VERSION}.tar.gz || {
        echo "❌ Failed to extract Erlang source"
        exit 1
    }

    cd otp_src_${ERLANG_VERSION} || {
        echo "❌ Failed to change to Erlang directory"
        exit 1
    }

    # Prepare for build
    echo "🔄 Preparing Erlang build..."
    ./otp_build autoconf || {
        echo "❌ Failed to run autoconf"
        exit 1
    }

    # Configure with crypto support
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
        --enable-ssl \
        --with-ssl=/usr/lib/ssl \
        --enable-crypto \
        --with-crypto \
        --with-ssl-rpath=yes \
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

    # After make install, verify crypto module
    echo "🔄 Verifying Erlang crypto module..."
    erl -noshell -eval 'case code:ensure_loaded(crypto) of {module,crypto} -> halt(0); _ -> halt(1) end.' || {
        echo "❌ Erlang crypto module verification failed"
        exit 1
    }

    # Cleanup
    cd ..
    rm -rf otp_src_${ERLANG_VERSION}*

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

# Create RabbitMQ user if not exists
sudo useradd -r -d /var/lib/rabbitmq -s /bin/false rabbitmq || true

# Set up directories and permissions
sudo mkdir -p /var/lib/rabbitmq/mnesia
sudo mkdir -p /var/log/rabbitmq
sudo mkdir -p /etc/rabbitmq

# Stop any existing RabbitMQ process and clean up
sudo pkill -f rabbitmq || true
sudo rm -rf /var/lib/rabbitmq/mnesia/*
sleep 5

# Set the Erlang cookie for all potential locations
echo "🔄 Setting up Erlang cookies..."
# First, determine the current user's home directory correctly
CURRENT_USER=$(whoami)
CURRENT_USER_HOME=$(eval echo ~$CURRENT_USER)

# Set cookies in required locations
for COOKIE_PATH in /var/lib/rabbitmq/.erlang.cookie /root/.erlang.cookie "$CURRENT_USER_HOME/.erlang.cookie"; do
    # Create directory if it doesn't exist
    sudo mkdir -p "$(dirname $COOKIE_PATH)"
    
    # Set the cookie
    echo "$RABBITMQ_COOKIE" | sudo tee "$COOKIE_PATH" > /dev/null
    sudo chmod 400 "$COOKIE_PATH"
    
    # Set ownership based on location
    if [[ "$COOKIE_PATH" == "/var/lib/rabbitmq/.erlang.cookie" ]]; then
        sudo chown rabbitmq:rabbitmq "$COOKIE_PATH"
    elif [[ "$COOKIE_PATH" == "$CURRENT_USER_HOME/.erlang.cookie" ]]; then
        sudo chown $CURRENT_USER:$CURRENT_USER "$COOKIE_PATH"
    fi
done

# Fix ownership of RabbitMQ directories
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

# Create more detailed RabbitMQ config
cat << EOF | sudo tee /etc/rabbitmq/rabbitmq.conf
listeners.tcp.default = $RABBITMQ_PORT
management.tcp.port = $RABBITMQ_MANAGEMENT_PORT
management.tcp.ip = 0.0.0.0
loopback_users = none

# Logging configuration
log.file = true
log.file.level = debug
log.file.rotation.date = \$D0
log.file.rotation.size = 10485760
log.file.rotation.count = 10

# Networking
listeners.tcp.local = 127.0.0.1:$RABBITMQ_PORT
listeners.tcp.external = $NODE_IP:$RABBITMQ_PORT

# Clustering
cluster_formation.peer_discovery_backend = rabbit_peer_discovery_classic_config
cluster_formation.classic_config.nodes.$NODE_TYPE = rabbit@$SHORTNAME

# Distribution
distribution.port_range.min = 25672
distribution.port_range.max = 25672
EOF

# Add this before starting RabbitMQ
echo "🔄 Verifying RabbitMQ installation..."
ls -l /opt/rabbitmq/sbin/rabbitmq-server
ls -l /usr/local/bin/rabbitmq-server
file /opt/rabbitmq/sbin/rabbitmq-server
echo "🔄 Verifying RabbitMQ directories:"
ls -ld /var/lib/rabbitmq
ls -ld /var/log/rabbitmq
ls -ld /etc/rabbitmq

# Test rabbitmq-env script
echo "🔄 Testing RabbitMQ environment..."
/opt/rabbitmq/sbin/rabbitmq-env || {
    echo "❌ RabbitMQ environment test failed"
    exit 1
}

# Verify RabbitMQ version
echo "🔄 Checking RabbitMQ version..."
rabbitmqctl version || {
    echo "❌ Failed to get RabbitMQ version"
    exit 1
}

# Add after setting cookies
echo "🔄 Verifying cookie setup..."
for COOKIE_PATH in /var/lib/rabbitmq/.erlang.cookie /root/.erlang.cookie "$CURRENT_USER_HOME/.erlang.cookie"; do
    if [ -f "$COOKIE_PATH" ]; then
        echo "✅ Cookie exists at $COOKIE_PATH"
        echo "   Owner: $(stat -c '%U:%G' "$COOKIE_PATH")"
        echo "   Permissions: $(stat -c '%a' "$COOKIE_PATH")"
    else
        echo "❌ Cookie file missing at $COOKIE_PATH"
    fi
done

# Before starting RabbitMQ
echo "🔄 Verifying Erlang cookie consistency..."
COOKIE_HASH=$(echo "$RABBITMQ_COOKIE" | sha1sum | cut -d' ' -f1)
for COOKIE_FILE in /var/lib/rabbitmq/.erlang.cookie /root/.erlang.cookie "$CURRENT_USER_HOME/.erlang.cookie"; do
    if [ -f "$COOKIE_FILE" ]; then
        CURRENT_HASH=$(sudo cat "$COOKIE_FILE" | sha1sum | cut -d' ' -f1)
        if [ "$COOKIE_HASH" != "$CURRENT_HASH" ]; then
            echo "❌ Cookie mismatch in $COOKIE_FILE"
            echo "Expected: $COOKIE_HASH"
            echo "Got: $CURRENT_HASH"
            exit 1
        fi
    fi
done

# Before starting RabbitMQ
echo "🔄 Verifying Erlang crypto module..."
if ! erl -noshell -eval 'case application:ensure_all_started(crypto) of {ok,_} -> halt(0); _ -> halt(1) end.'; then
    echo "❌ Failed to start Erlang crypto application"
    echo "🔄 Installing crypto module..."
    sudo apt-get install -y erlang-crypto
    if ! erl -noshell -eval 'case application:ensure_all_started(crypto) of {ok,_} -> halt(0); _ -> halt(1) end.'; then
        echo "❌ Still unable to start crypto application"
        exit 1
    fi
fi

# Before starting RabbitMQ service
echo "🔄 Preparing RabbitMQ environment..."

# Ensure log directory exists with proper permissions
sudo mkdir -p /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chmod 755 /var/log/rabbitmq

# Create empty log file with proper permissions
sudo touch /var/log/rabbitmq/rabbit@${SHORTNAME}.log
sudo chown rabbitmq:rabbitmq /var/log/rabbitmq/rabbit@${SHORTNAME}.log
sudo chmod 644 /var/log/rabbitmq/rabbit@${SHORTNAME}.log

# Debug information
echo "🔄 Directory permissions:"
ls -la /var/log/rabbitmq/
ls -la /var/lib/rabbitmq/
ls -la /etc/rabbitmq/
ls -la /opt/rabbitmq/

echo "🔄 Environment variables:"
echo "RABBITMQ_NODENAME=$NODE_NAME"
echo "RABBITMQ_HOME=/opt/rabbitmq"
echo "RABBITMQ_LOG_BASE=/var/log/rabbitmq"
echo "Current user: $(whoami)"
echo "RabbitMQ user home: $(eval echo ~rabbitmq)"

# Start RabbitMQ with more verbose output
echo "🚀 Starting RabbitMQ service..."

# Create a temporary environment file with explicit exports
TEMP_ENV_FILE=$(mktemp)
cat << EOF > $TEMP_ENV_FILE
export HOME=/var/lib/rabbitmq
export RABBITMQ_HOME=/opt/rabbitmq
export RABBITMQ_NODENAME="${NODE_NAME}"
export RABBITMQ_NODE_IP_ADDRESS="${NODE_IP}"
export RABBITMQ_NODE_PORT="${RABBITMQ_PORT}"
export RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
export RABBITMQ_LOG_BASE=/var/log/rabbitmq
export RABBITMQ_CONSOLE_LOG=new
export RABBITMQ_LOGS=/var/log/rabbitmq/rabbit@${SHORTNAME}.log
export RABBITMQ_DIST_PORT=25672
export RABBITMQ_PID_FILE=/var/lib/rabbitmq/mnesia/rabbit@${SHORTNAME}.pid
export RABBITMQ_ENABLED_PLUGINS_FILE=/etc/rabbitmq/enabled_plugins
export PATH=/opt/rabbitmq/sbin:\$PATH
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF

# Set proper permissions
sudo chown rabbitmq:rabbitmq $TEMP_ENV_FILE
sudo chmod 644 $TEMP_ENV_FILE

# Start RabbitMQ with explicit environment
sudo -u rabbitmq bash -c "
    set -x  # Enable debug output
    set -a  # Automatically export all variables
    source $TEMP_ENV_FILE
    set +a
    
    echo 'Starting server with environment:'
    env | grep RABBIT
    
    cd /var/lib/rabbitmq
    
    # Start server directly (not detached) to see output
    echo 'Starting RabbitMQ server...'
    exec /opt/rabbitmq/sbin/rabbitmq-server > /var/log/rabbitmq/startup.log 2>&1
" &

# Clean up temp file after starting
rm -f $TEMP_ENV_FILE

# Wait for server to start
echo "🔄 Waiting for RabbitMQ to start..."
for i in $(seq 1 30); do
    if sudo rabbitmqctl status >/dev/null 2>&1; then
        echo "✅ RabbitMQ is running"
        break
    fi
    echo "⏳ Waiting for RabbitMQ to start ($i/30)"
    echo "🔍 Current logs:"
    tail -n 5 /var/log/rabbitmq/startup.log
    tail -n 5 /var/log/rabbitmq/rabbit@${SHORTNAME}.log
    sleep 2
done

# Check final status
if ! sudo rabbitmqctl status >/dev/null 2>&1; then
    echo "❌ RabbitMQ failed to start"
    echo "🔍 Startup log:"
    cat /var/log/rabbitmq/startup.log
    echo "🔍 Main log:"
    cat /var/log/rabbitmq/rabbit@${SHORTNAME}.log
    echo "🔍 Process status:"
    ps aux | grep -E "[r]abbit|[b]eam"
    echo "🔍 EPMD status:"
    epmd -names
    exit 1
fi

# Check process
echo "🔍 Checking RabbitMQ processes:"
ps aux | grep -E "[r]abbit|[b]eam"

# Check EPMD
echo "🔍 Checking EPMD status:"
epmd -names

# Check if server is responding
echo "🔍 Checking server status:"
sudo rabbitmqctl status || {
    echo "❌ RabbitMQ failed to start"
    echo "🔍 Last 50 lines of logs:"
    tail -n 50 /var/log/rabbitmq/rabbit@${SHORTNAME}.log
    exit 1
}

# Verify node is running
echo "🔄 Verifying RabbitMQ node status..."
sudo rabbitmqctl status || {
    echo "❌ RabbitMQ node is not running"
    exit 1
}

# Enable management plugin
echo "🔄 RabbitMQ Management Plugin Etkinleştiriliyor..."
sudo rabbitmqctl -n $NODE_NAME wait --timeout 60 || {
    echo "❌ Failed to wait for RabbitMQ node"
    exit 1
}

sudo rabbitmqctl -n $NODE_NAME stop_app || {
    echo "❌ Failed to stop RabbitMQ app"
    exit 1
}

sudo rabbitmqctl -n $NODE_NAME reset || {
    echo "❌ Failed to reset RabbitMQ"
    exit 1
}

sudo rabbitmqctl -n $NODE_NAME start_app || {
    echo "❌ Failed to start RabbitMQ app"
    exit 1
}

sudo rabbitmq-plugins -n $NODE_NAME enable rabbitmq_management || {
    echo "❌ Failed to enable management plugin"
    exit 1
}

# Verify the plugin is enabled
echo "🔄 Verifying management plugin..."
sudo rabbitmq-plugins list | grep rabbitmq_management

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
