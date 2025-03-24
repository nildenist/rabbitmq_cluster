# RabbitMQ Cluster Installation

This project provides scripts and configurations for setting up a RabbitMQ cluster with one master node and multiple worker nodes.

## Overview

The `install_rabbit.sh` script automates the installation and configuration of a RabbitMQ cluster. It handles:

- Erlang installation from source
- RabbitMQ server installation
- Cluster configuration
- Security settings
- Plugin management
- Node synchronization

## Prerequisites

- Ubuntu/Debian-based Linux system
- Sudo privileges
- Network connectivity between nodes
- Open ports:
  - 4369 (EPMD)
  - 5672 (AMQP)
  - 15672 (Management UI)
  - 25672 (inter-node communication)

## Configuration

### Environment Variables
Create or modify `rabbit.env` with your cluster configuration:

```env
# Core Versions
ERLANG_VERSION=26.2
RABBITMQ_VERSION=4.0.1

# Cluster Configuration
MASTER_NODE_NAME=rabbit@master-node
MASTER_IP=10.128.0.46
WORKER_1_NODE_NAME=rabbit@worker1
WORKER_1_IP=10.128.0.47
WORKER_2_NODE_NAME=rabbit@worker2
WORKER_2_IP=10.128.0.48

# Security
RABBITMQ_COOKIE="RABBITMQ_CLUSTER_COOKIE_SECRET_KEY_STRING_1234567890"
RABBITMQ_ADMIN_USER=admin
RABBITMQ_ADMIN_PASSWORD=secretsecret
```

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd rabbitmq_cluster
```

2. Make the script executable:
```bash
chmod +x install_rabbit.sh
```

3. **Important**: Create RabbitMQ System User First:
```bash
# Create rabbitmq group
sudo groupadd -f rabbitmq

# Create rabbitmq user
sudo useradd -r -g rabbitmq -d /var/lib/rabbitmq -s /bin/false rabbitmq || true
```

4. Install the master node:
```bash
./install_rabbit.sh master
```

5. Install worker nodes:
```bash
./install_rabbit.sh worker1
./install_rabbit.sh worker2
```

## Common Issues and Solutions

1. **"chown: invalid user: 'rabbitmq:rabbitmq'"**
   - This error occurs when the rabbitmq user doesn't exist
   - Solution: Run the user creation commands from step 3 before running the installation script
   - The script will now check for user existence and create if missing

## Important Considerations

1. **Network Configuration**:
   - Ensure all nodes can reach each other
   - Configure firewalls to allow required ports
   - DNS resolution or `/etc/hosts` entries must be properly configured

2. **Security**:
   - Change default admin credentials
   - Use a strong Erlang cookie
   - Consider enabling SSL/TLS for production
   - Implement proper network security measures

3. **System Requirements**:
   - Sufficient disk space (recommended: 10GB+)
   - Adequate RAM (recommended: 4GB+ per node)
   - CPU: 2+ cores recommended

4. **Maintenance**:
   - Regular backups of definitions and data
   - Monitor disk space and system resources
   - Keep track of log files
   - Regular updates and security patches

5. **Troubleshooting**:
   - Check logs at `/var/log/rabbitmq/`
   - Use `rabbitmqctl cluster_status` for cluster health
   - Monitor management UI at `http://<master-ip>:15672`
   - Verify Erlang cookie consistency across nodes

## Script Workflow

1. **Pre-installation**:
   - Validates input parameters
   - Checks system requirements
   - Creates necessary users and directories

2. **Erlang Installation**:
   - Installs from source with required modules
   - Configures for RabbitMQ compatibility
   - Verifies installation and crypto support

3. **RabbitMQ Installation**:
   - Downloads and installs specified version
   - Creates systemd service
   - Configures environment variables
   - Sets up logging and data directories

4. **Cluster Configuration**:
   - Sets up node-specific configurations
   - Configures hostname and network settings
   - Manages Erlang cookies
   - Handles cluster joining for worker nodes

5. **Post-installation**:
   - Enables required plugins
   - Creates admin user
   - Verifies cluster status
   - Sets up monitoring and management UI

## Additional Features

- Automatic retry mechanism for cluster joining
- Comprehensive logging and error handling
- Plugin management
- User management
- Cluster status verification

## Monitoring

Access the RabbitMQ Management UI:

URL: http://<master-ip>:15672
Username: <configured-admin-user>
Password: <configured-admin-password>