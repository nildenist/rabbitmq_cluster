#!/bin/bash

# RabbitMQ Log Retention Patch Script
# Author: Ozgur SALGINCI
# Description: Apply log retention management to existing RabbitMQ installations
# Usage: ./patch_rabbit.sh

set -e  # Exit on error

echo "🔄 RabbitMQ Log Retention Management Patch Script"
echo "=================================================="
echo "This script will apply log retention settings to your existing RabbitMQ server."
echo ""

# Load configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/rabbit.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo "✅ Configuration loaded from $CONFIG_FILE"
else
    echo "❌ Configuration file $CONFIG_FILE not found!"
    echo "Please ensure rabbit.env exists in the same directory as this script."
    exit 1
fi

# Check if running as root or with sudo
if [ "$EUID" -eq 0 ]; then
    echo "❌ Please do not run this script as root. Use your regular user account."
    echo "The script will use sudo when needed."
    exit 1
fi

# Verify RabbitMQ is running
check_rabbitmq_status() {
    echo "🔄 Checking RabbitMQ status..."
    
    if ! sudo systemctl is-active --quiet rabbitmq-server; then
        echo "❌ RabbitMQ server is not running!"
        echo "Please start RabbitMQ first: sudo systemctl start rabbitmq-server"
        exit 1
    fi
    
    if ! sudo rabbitmqctl status >/dev/null 2>&1; then
        echo "❌ RabbitMQ is running but not responding to commands!"
        echo "Please check RabbitMQ health before running this patch."
        exit 1
    fi
    
    echo "✅ RabbitMQ server is running and responsive"
}

# Backup existing configuration
backup_existing_config() {
    echo "🔄 Creating backup of existing configuration..."
    
    local backup_dir="/tmp/rabbitmq_backup_$(date +%Y%m%d_%H%M%S)"
    sudo mkdir -p "$backup_dir"
    
    # Backup configuration files
    if [ -f "/etc/rabbitmq/rabbitmq.conf" ]; then
        sudo cp "/etc/rabbitmq/rabbitmq.conf" "$backup_dir/"
        echo "✅ Backed up rabbitmq.conf"
    fi
    
    if [ -f "/etc/rabbitmq/rabbitmq-env.conf" ]; then
        sudo cp "/etc/rabbitmq/rabbitmq-env.conf" "$backup_dir/"
        echo "✅ Backed up rabbitmq-env.conf"
    fi
    
    if [ -f "/etc/logrotate.d/rabbitmq" ]; then
        sudo cp "/etc/logrotate.d/rabbitmq" "$backup_dir/"
        echo "✅ Backed up existing logrotate config"
    fi
    
    # Save current cron jobs
    crontab -l > "$backup_dir/current_crontab.txt" 2>/dev/null || true
    
    echo "✅ Backup created at: $backup_dir"
    export BACKUP_DIR="$backup_dir"
}

# Detect current RabbitMQ installation paths
detect_rabbitmq_paths() {
    echo "🔄 Detecting RabbitMQ installation paths..."
    
    # Try to detect RabbitMQ installation directory
    if [ -d "/opt/rabbitmq" ]; then
        DETECTED_RABBITMQ_HOME="/opt/rabbitmq"
    elif [ -d "/usr/lib/rabbitmq" ]; then
        DETECTED_RABBITMQ_HOME="/usr/lib/rabbitmq"
    elif command -v rabbitmq-server >/dev/null; then
        RABBITMQ_SERVER_PATH=$(which rabbitmq-server)
        DETECTED_RABBITMQ_HOME=$(dirname $(dirname "$RABBITMQ_SERVER_PATH"))
    else
        echo "❌ Could not detect RabbitMQ installation directory!"
        echo "Please specify manually:"
        read -p "RabbitMQ installation directory [/opt/rabbitmq]: " DETECTED_RABBITMQ_HOME
        DETECTED_RABBITMQ_HOME=${DETECTED_RABBITMQ_HOME:-/opt/rabbitmq}
    fi
    
    # Detect log directory
    if [ -d "$RABBITMQ_LOG_DIR" ]; then
        DETECTED_LOG_DIR="$RABBITMQ_LOG_DIR"
    elif [ -d "/var/log/rabbitmq" ]; then
        DETECTED_LOG_DIR="/var/log/rabbitmq"
    else
        echo "❌ Could not detect RabbitMQ log directory!"
        read -p "RabbitMQ log directory [/var/log/rabbitmq]: " DETECTED_LOG_DIR
        DETECTED_LOG_DIR=${DETECTED_LOG_DIR:-/var/log/rabbitmq}
    fi
    
    echo "✅ Detected RabbitMQ home: $DETECTED_RABBITMQ_HOME"
    echo "✅ Detected log directory: $DETECTED_LOG_DIR"
    
    # Update variables for the rest of the script
    export RABBITMQ_HOME="$DETECTED_RABBITMQ_HOME"
    export RABBITMQ_LOG_DIR="$DETECTED_LOG_DIR"
    export LOG_CLEANUP_SCRIPT_PATH="$RABBITMQ_HOME/bin/cleanup_logs.sh"
}

# Show current configuration and get user confirmation
show_current_config() {
    echo ""
    echo "📊 Current Configuration to be Applied:"
    echo "======================================"
    echo "🗓️ Log Retention Days: $LOG_RETENTION_DAYS"
    echo "🕐 Daily Cleanup Time: ${LOG_CLEANUP_HOUR}:00 AM"
    echo "📁 Max Log File Size: $LOG_MAX_SIZE"
    echo "🔄 Rotated Files to Keep: $LOG_ROTATE_COUNT"
    echo "📦 Compress After Days: $LOG_COMPRESS_AFTER_DAYS"
    echo "⚠️ Disk Warning Threshold: $DISK_USAGE_THRESHOLD%"
    echo "🚨 Disk Cleanup Threshold: $DISK_CLEANUP_THRESHOLD%"
    echo ""
    echo "📁 Paths:"
    echo "   RabbitMQ Home: $RABBITMQ_HOME"
    echo "   Log Directory: $RABBITMQ_LOG_DIR"
    echo "   Cleanup Script: $LOG_CLEANUP_SCRIPT_PATH"
    echo ""
    
    read -p "❓ Do you want to proceed with these settings? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        echo "❌ Operation cancelled by user."
        exit 0
    fi
}

# Update RabbitMQ configuration with log rotation settings
update_rabbitmq_config() {
    echo "🔄 Updating RabbitMQ configuration for log rotation..."
    
    local config_file="/etc/rabbitmq/rabbitmq.conf"
    local temp_config="/tmp/rabbitmq_temp_config.conf"
    
    if [ -f "$config_file" ]; then
        # Read existing config
        sudo cp "$config_file" "$temp_config"
        
        # Remove existing log-related lines to avoid duplicates
        sudo sed -i '/^log\./d' "$temp_config"
        
        # Add new log configuration
        sudo tee -a "$temp_config" << EOF

# Log Configuration with Rotation (Added by patch script)
log.file.level = info
log.dir = $RABBITMQ_LOG_DIR
log.file = rabbit.log
log.file.rotation.date = \$daily
log.file.rotation.size = $LOG_MAX_SIZE
log.file.rotation.count = $LOG_ROTATE_COUNT
log.file.formatter = plaintext

# Connection and Channel Logging (reduced verbosity)
log.connection.level = info
log.channel.level = info
log.queue.level = info
EOF
        
        # Replace the original config
        sudo mv "$temp_config" "$config_file"
        echo "✅ Updated $config_file with log rotation settings"
    else
        # Create new config file with log settings
        sudo tee "$config_file" << EOF
# RabbitMQ Configuration with Log Rotation
log.file.level = info
log.dir = $RABBITMQ_LOG_DIR
log.file = rabbit.log
log.file.rotation.date = \$daily
log.file.rotation.size = $LOG_MAX_SIZE
log.file.rotation.count = $LOG_ROTATE_COUNT
log.file.formatter = plaintext

# Connection and Channel Logging (reduced verbosity)
log.connection.level = info
log.channel.level = info
log.queue.level = info
EOF
        echo "✅ Created new $config_file with log rotation settings"
    fi
}

# Install log cleanup scripts
install_cleanup_scripts() {
    echo "🔄 Installing log cleanup and monitoring scripts..."
    
    # Create bin directory if it doesn't exist
    sudo mkdir -p "$RABBITMQ_HOME/bin"
    
    # Copy the main cleanup script
    if [ -f "$SCRIPT_DIR/cleanup_rabbitmq_logs.sh" ]; then
        sudo cp "$SCRIPT_DIR/cleanup_rabbitmq_logs.sh" "$LOG_CLEANUP_SCRIPT_PATH"
    else
        echo "❌ cleanup_rabbitmq_logs.sh not found in $SCRIPT_DIR"
        echo "Please ensure the cleanup script is in the same directory as this patch script."
        return 1
    fi
    
    sudo chmod +x "$LOG_CLEANUP_SCRIPT_PATH"
    sudo chown rabbitmq:rabbitmq "$LOG_CLEANUP_SCRIPT_PATH" 2>/dev/null || true
    
    # Create symlink for easy access
    sudo ln -sf "$LOG_CLEANUP_SCRIPT_PATH" /usr/local/bin/rabbitmq-log-cleanup
    echo "✅ Cleanup script installed at $LOG_CLEANUP_SCRIPT_PATH"
    
    # Create monitoring script
    local monitor_script="$RABBITMQ_HOME/bin/monitor_logs.sh"
    sudo tee "$monitor_script" << 'EOF'
#!/bin/bash
# RabbitMQ Log Monitoring Script

# Try to source config file
for config in /home/*/rabbitmq_cluster/rabbit.env ./rabbit.env; do
    if [ -f "$config" ]; then
        source "$config"
        break
    fi
done

# Default values if config not found
RABBITMQ_LOG_DIR=${RABBITMQ_LOG_DIR:-/var/log/rabbitmq}
DISK_USAGE_THRESHOLD=${DISK_USAGE_THRESHOLD:-80}

echo "=== RabbitMQ Log Monitoring Report ==="
echo "Generated: $(date)"
echo ""

# Disk usage
DISK_USAGE=$(df "$RABBITMQ_LOG_DIR" | awk 'NR==2 {sub(/%$/, "", $5); print $5}')
echo "💽 Disk Usage: $DISK_USAGE%"
if [ "$DISK_USAGE" -gt "$DISK_USAGE_THRESHOLD" ]; then
    echo "  ⚠️ WARNING: Above threshold ($DISK_USAGE_THRESHOLD%)"
fi

# Log directory size
LOG_SIZE=$(du -sh "$RABBITMQ_LOG_DIR" 2>/dev/null | awk '{print $1}')
echo "📁 Log Directory Size: $LOG_SIZE"

# Log file count and details
echo ""
echo "📄 Log Files:"
find "$RABBITMQ_LOG_DIR" -type f \( -name "*.log" -o -name "*.log.*" \) -printf "%T@ %Tc %s %p\n" 2>/dev/null | sort -n | while read timestamp date size file; do
    human_size=$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B")
    echo "  $(basename "$file"): $human_size ($(echo "$date" | cut -d' ' -f1-3))"
done

# Largest files
echo ""
echo "🔝 Largest Log Files:"
find "$RABBITMQ_LOG_DIR" -type f -exec ls -la {} + 2>/dev/null | sort -k5 -n -r | head -5 | while read line; do
    size=$(echo "$line" | awk '{print $5}')
    human_size=$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B")
    filename=$(echo "$line" | awk '{print $9}')
    echo "  $(basename "$filename"): $human_size"
done

echo ""
echo "🕒 Last Cleanup: $(find "$RABBITMQ_LOG_DIR" -name "cleanup.log" -exec tail -1 {} \; 2>/dev/null | head -1 | cut -d']' -f1 | cut -d'[' -f2 || echo "Never")"
EOF
    
    sudo chmod +x "$monitor_script"
    sudo ln -sf "$monitor_script" /usr/local/bin/rabbitmq-log-monitor
    echo "✅ Monitoring script installed at $monitor_script"
}

# Setup logrotate configuration
setup_logrotate() {
    echo "🔄 Setting up system logrotate configuration..."
    
    sudo tee /etc/logrotate.d/rabbitmq << EOF
$RABBITMQ_LOG_DIR/*.log {
    daily
    missingok
    rotate $LOG_ROTATE_COUNT
    compress
    delaycompress
    notifempty
    copytruncate
    create 640 rabbitmq rabbitmq
}
EOF
    
    echo "✅ Logrotate configuration created"
}

# Setup cron job for automated cleanup
setup_cron_job() {
    echo "🔄 Setting up automated cleanup cron job..."
    
    # Create the cron job entry
    local cron_job="0 $LOG_CLEANUP_HOUR * * * /bin/bash $LOG_CLEANUP_SCRIPT_PATH >> $RABBITMQ_LOG_DIR/cleanup.log 2>&1"
    
    # Check if a similar cron job already exists
    if crontab -l 2>/dev/null | grep -q "cleanup.*rabbitmq\|rabbitmq.*cleanup"; then
        echo "⚠️ Existing RabbitMQ cleanup cron job found"
        read -p "❓ Replace existing cron job? (y/N): " REPLACE_CRON
        
        if [[ "$REPLACE_CRON" =~ ^[yY]$ ]]; then
            # Remove existing rabbitmq cleanup jobs
            crontab -l 2>/dev/null | grep -v "cleanup.*rabbitmq\|rabbitmq.*cleanup" | crontab -
            echo "✅ Removed existing RabbitMQ cleanup cron jobs"
        else
            echo "⚠️ Keeping existing cron job. Manual cleanup available with: sudo rabbitmq-log-cleanup"
            return 0
        fi
    fi
    
    # Add the new cron job
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    echo "✅ Cron job added: Daily cleanup at ${LOG_CLEANUP_HOUR}:00 AM"
}

# Test the setup
test_setup() {
    echo "🔄 Testing log retention setup..."
    
    # Test cleanup script
    echo "Testing cleanup script execution..."
    if sudo -u rabbitmq bash "$LOG_CLEANUP_SCRIPT_PATH" --dry-run 2>/dev/null; then
        echo "✅ Cleanup script test passed"
    else
        echo "⚠️ Cleanup script test had issues, but this may be normal for a dry run"
    fi
    
    # Test monitoring script
    echo "Testing monitoring script..."
    if bash /usr/local/bin/rabbitmq-log-monitor >/dev/null 2>&1; then
        echo "✅ Monitoring script test passed"
    else
        echo "⚠️ Monitoring script test had issues"
    fi
    
    # Check current log files
    echo "Current log directory contents:"
    ls -la "$RABBITMQ_LOG_DIR" 2>/dev/null | head -10 || echo "Could not list log directory"
}

# Restart RabbitMQ to apply configuration changes
restart_rabbitmq() {
    echo ""
    read -p "❓ RabbitMQ needs to be restarted to apply log rotation settings. Proceed? (y/N): " RESTART_CONFIRM
    
    if [[ "$RESTART_CONFIRM" =~ ^[yY]$ ]]; then
        echo "🔄 Restarting RabbitMQ server..."
        
        # Get current cluster status for verification
        echo "Saving current cluster status..."
        sudo rabbitmqctl cluster_status > /tmp/cluster_status_before.txt 2>/dev/null || true
        
        # Restart RabbitMQ
        sudo systemctl restart rabbitmq-server
        
        # Wait for RabbitMQ to start
        echo "⏳ Waiting for RabbitMQ to restart..."
        sleep 10
        
        # Verify RabbitMQ is back up
        local retries=0
        local max_retries=30
        
        while ! sudo rabbitmqctl status >/dev/null 2>&1; do
            sleep 2
            ((retries++))
            if [ $retries -ge $max_retries ]; then
                echo "❌ RabbitMQ failed to start within expected time!"
                echo "Please check: sudo systemctl status rabbitmq-server"
                echo "Log files: sudo tail -50 $RABBITMQ_LOG_DIR/rabbit.log"
                exit 1
            fi
            echo -n "."
        done
        
        echo ""
        echo "✅ RabbitMQ restarted successfully"
        
        # Verify cluster status if it was clustered before
        if grep -q "running_nodes" /tmp/cluster_status_before.txt 2>/dev/null; then
            echo "🔄 Verifying cluster status..."
            sudo rabbitmqctl cluster_status
        fi
        
    else
        echo "⚠️ RabbitMQ restart skipped."
        echo "⚠️ Log rotation settings will take effect after the next restart."
        echo "   You can restart manually with: sudo systemctl restart rabbitmq-server"
    fi
}

# Show final summary
show_summary() {
    echo ""
    echo "🎉 RabbitMQ Log Retention Management Patch Completed!"
    echo "===================================================="
    echo ""
    echo "📊 Applied Configuration:"
    echo "  🗓️ Log Retention: $LOG_RETENTION_DAYS days"
    echo "  🕐 Daily Cleanup: ${LOG_CLEANUP_HOUR}:00 AM"
    echo "  📁 Max Log Size: $LOG_MAX_SIZE per file"
    echo "  🔄 Rotated Files: $LOG_ROTATE_COUNT files kept"
    echo "  📦 Compression: After $LOG_COMPRESS_AFTER_DAYS day(s)"
    echo ""
    echo "🛠️ Available Commands:"
    echo "  📋 Manual cleanup: sudo rabbitmq-log-cleanup"
    echo "  📊 Log monitoring: sudo rabbitmq-log-monitor"
    echo "  📁 Check disk usage: df -h $RABBITMQ_LOG_DIR"
    echo "  📜 View cleanup log: tail -f $RABBITMQ_LOG_DIR/cleanup.log"
    echo ""
    echo "📁 Installed Files:"
    echo "  🗂️ Cleanup script: $LOG_CLEANUP_SCRIPT_PATH"
    echo "  📊 Monitor script: $RABBITMQ_HOME/bin/monitor_logs.sh"
    echo "  ⚙️ Logrotate config: /etc/logrotate.d/rabbitmq"
    echo "  🔄 Updated config: /etc/rabbitmq/rabbitmq.conf"
    echo ""
    echo "💾 Backup Location: $BACKUP_DIR"
    echo ""
    echo "✅ Your existing RabbitMQ server now has automated log retention!"
    echo "🔄 The system will automatically clean up logs older than $LOG_RETENTION_DAYS days."
    echo "⚠️ Disk usage will be monitored and emergency cleanup will trigger at $DISK_CLEANUP_THRESHOLD%."
}

# Main execution
main() {
    echo "Starting RabbitMQ Log Retention Patch Process..."
    echo ""
    
    # Pre-flight checks
    check_rabbitmq_status
    detect_rabbitmq_paths
    show_current_config
    
    # Create backup
    backup_existing_config
    
    # Apply patches
    update_rabbitmq_config
    install_cleanup_scripts
    setup_logrotate
    setup_cron_job
    
    # Test and restart
    test_setup
    restart_rabbitmq
    
    # Final summary
    show_summary
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi