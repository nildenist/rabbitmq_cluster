#!/bin/bash

# Node.js and npm installation script
NODE_VERSION="v20.15.1"
NODE_DISTRO="linux-x64"

echo "🔍 Detecting OS..."
OS=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')

# Install necessary dependencies
install_dependencies() {
    echo "📦 Installing dependencies..."
    case "$OS" in
        ubuntu|debian)
            sudo apt update -y
            sudo apt install -y curl wget xz-utils
            ;;
        centos|rocky|almalinux|amzn)
            sudo yum install -y curl wget xz
            ;;
        *)
            echo "❌ Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Install Node.js and npm
install_node() {
    echo "⬇️ Installing Node.js $NODE_VERSION..."
    cd /usr/local
    sudo rm -rf node-$NODE_VERSION-$NODE_DISTRO
    sudo curl -O https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-$NODE_DISTRO.tar.xz
    sudo tar -xf node-$NODE_VERSION-$NODE_DISTRO.tar.xz
    sudo mv node-$NODE_VERSION-$NODE_DISTRO nodejs
    sudo rm node-$NODE_VERSION-$NODE_DISTRO.tar.xz

    echo "✅ Node.js installation completed."
    echo "🔗 Creating symbolic links..."
    sudo ln -sf /usr/local/nodejs/bin/node /usr/bin/node
    sudo ln -sf /usr/local/nodejs/bin/npm /usr/bin/npm
    sudo ln -sf /usr/local/nodejs/bin/npx /usr/bin/npx
}

# Check if Node.js is already installed
check_node() {
    if command -v node &> /dev/null; then
        INSTALLED_VERSION=$(node -v)
        echo "✅ Node.js is already installed: $INSTALLED_VERSION"
        if [ "$INSTALLED_VERSION" != "$NODE_VERSION" ]; then
            echo "🔄 Updating Node.js..."
            install_node
        fi
    else
        install_node
    fi
}

# Execute installation steps
install_dependencies
check_node

# Update npm
echo "🚀 Updating npm..."
sudo npm install -g npm

echo "🎉 Node.js and npm installation completed successfully!"
echo "🆕 Node.js version: $(node -v)"
echo "🆕 npm version: $(npm -v)"
