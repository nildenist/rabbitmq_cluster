#!/bin/bash

set -e  # Enable error handling
source rabbit.env  # Load rabbitmq.env file

# Usage check
if [ -z "$1" ]; then
    echo "❌ Usage: ./install_rabbitmq.sh [master|worker1|worker2]"
    exit 1
fi

NODE_TYPE=$1  # Node type from user input

# Determine node name and IP based on node type
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
    echo "❌ Invalid node type! Usage: ./install_rabbitmq.sh [master|worker1|worker2]"
    exit 1
fi

echo "🚀 Starting RabbitMQ Installation..."
echo "📌 Node Type: $NODE_TYPE"
echo "📌 Node Name: $NODE_NAME"
echo "📌 Node IP: $NODE_IP"

# Stop and clean all RabbitMQ processes
echo "🔄 Cleaning existing installation..."
sudo systemctl stop rabbitmq-server || true
sudo pkill -f rabbitmq || true
sudo pkill -f beam || true
sudo pkill -f epmd || true

# Clean old installation
echo "🔄 Removing old installation..."
sudo apt-get remove --purge -y rabbitmq-server erlang* || true
sudo apt-get autoremove -y
sudo rm -rf /var/lib/rabbitmq
sudo rm -rf /var/log/rabbitmq
sudo rm -rf /etc/rabbitmq
sudo rm -rf /opt/rabbitmq

# Add RabbitMQ repository and GPG key
echo "🔄 Adding RabbitMQ repository..."
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.deb.sh | sudo bash

# Add Erlang repository
echo "🔄 Adding Erlang repository..."
curl -s https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | sudo apt-key add -
echo "deb https://packages.erlang-solutions.com/ubuntu focal contrib" | sudo tee /etc/apt/sources.list.d/erlang.list

# Update packages and install required dependencies
echo "🔄 Updating packages and installing dependencies..."
sudo apt-get update
sudo apt-get install -y erlang-base \
    erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
    erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
    erlang-runtime-tools erlang-snmp erlang-ssl \
    erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl

# Install RabbitMQ
echo "🔄 Installing RabbitMQ..."
sudo apt-get install -y rabbitmq-server

# Create RabbitMQ user
echo "🔄 Creating RabbitMQ user..."
sudo groupadd -f rabbitmq
id -u rabbitmq &>/dev/null || sudo useradd -r -g rabbitmq -d /var/lib/rabbitmq -s /bin/false rabbitmq

# Cleanup
sudo rm -rf /var/lib/rabbitmq/*
sudo rm -rf /var/log/rabbitmq/*
sudo rm -rf /etc/rabbitmq/*
sudo rm -rf /opt/rabbitmq/var/lib/rabbitmq/mnesia/*

# Set hostname
echo "🔄 Setting hostname..."
SHORTNAME=$(echo $NODE_NAME | cut -d@ -f2)
sudo hostnamectl set-hostname $SHORTNAME

# Update hosts file
echo "🔄 Updating hosts file..."
sudo bash -c 'cat > /etc/hosts' << EOF
127.0.0.1 localhost
127.0.0.1 $SHORTNAME
$NODE_IP $SHORTNAME
$MASTER_IP master-node
$WORKER_1_IP worker1
$WORKER_2_IP worker2
EOF

# Create required directories
echo "🔄 Creating directories..."
sudo mkdir -p /var/lib/rabbitmq
sudo mkdir -p /var/log/rabbitmq
sudo mkdir -p /etc/rabbitmq
sudo mkdir -p /opt/rabbitmq/var/lib/rabbitmq/mnesia
sudo mkdir -p /home/rabbitmq

# Create RabbitMQ configuration files
echo "🔄 Creating RabbitMQ configuration..."
sudo tee /etc/rabbitmq/rabbitmq-env.conf << EOF
NODENAME=$NODE_NAME
NODE_IP_ADDRESS=$NODE_IP
NODE_PORT=$RABBITMQ_PORT
EOF

# Configure based on node type
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

# Set Erlang cookies
echo "🔄 Setting Erlang cookies..."
sudo bash -c "echo '$RABBITMQ_COOKIE' > /var/lib/rabbitmq/.erlang.cookie"
sudo bash -c "echo '$RABBITMQ_COOKIE' > /root/.erlang.cookie"
sudo bash -c "echo '$RABBITMQ_COOKIE' > /home/rabbitmq/.erlang.cookie"

# Set cookie permissions
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /root/.erlang.cookie
sudo chmod 400 /home/rabbitmq/.erlang.cookie

# Set directory permissions
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq
sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq
sudo chown -R rabbitmq:rabbitmq /home/rabbitmq

# Start RabbitMQ
echo "🔄 Starting RabbitMQ..."
sudo systemctl daemon-reload
sudo systemctl enable rabbitmq-server
sudo systemctl restart rabbitmq-server

# Wait for service to start
sleep 15

# Enable plugins
echo "🔄 Enabling plugins..."
sudo rabbitmq-plugins enable rabbitmq_management
sudo rabbitmq-plugins enable rabbitmq_management_agent
sudo systemctl restart rabbitmq-server
sleep 5

# Create admin user
echo "🔄 Creating admin user..."
sudo rabbitmqctl add_user "$RABBITMQ_ADMIN_USER" "$RABBITMQ_ADMIN_PASSWORD" || true
sudo rabbitmqctl set_user_tags "$RABBITMQ_ADMIN_USER" administrator
sudo rabbitmqctl set_permissions -p "/" "$RABBITMQ_ADMIN_USER" ".*" ".*" ".*"

# Join cluster if worker node
if [ "$NODE_TYPE" != "master" ]; then
    echo "🔄 Joining cluster..."
    
    # Check connectivity
    if ! ping -c 3 master-node &>/dev/null; then
        echo "❌ Cannot reach master node!"
        exit 1
    fi
    
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    sudo rabbitmqctl join_cluster rabbit@master-node
    sudo rabbitmqctl start_app
fi

# Check final status
echo "🔄 Checking cluster status..."
sudo rabbitmqctl cluster_status

echo "✅ RabbitMQ installation completed!"
echo "📝 Management UI: http://$NODE_IP:15672"
echo "📝 Username: $RABBITMQ_ADMIN_USER"
echo "📝 Password: $RABBITMQ_ADMIN_PASSWORD"
