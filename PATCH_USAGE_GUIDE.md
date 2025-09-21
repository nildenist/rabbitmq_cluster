# RabbitMQ Patch Script Usage Guide

## Overview
The `patch_rabbit.sh` script applies log retention management to existing, running RabbitMQ installations without disrupting operations.

## Prerequisites
- RabbitMQ must be already installed and running
- `rabbit.env` configuration file must exist in the same directory
- `cleanup_rabbitmq_logs.sh` must exist in the same directory
- User must have sudo privileges

## Usage

### 1. Basic Usage
```bash
# Make sure the script is executable (you already did this)
chmod +x patch_rabbit.sh

# Run the patch script
./patch_rabbit.sh
```

### 2. Pre-Patch Checklist
Before running the patch script, ensure:

```bash
# Check RabbitMQ is running
sudo systemctl status rabbitmq-server

# Check RabbitMQ is responsive
sudo rabbitmqctl status

# Verify you have the required files
ls -la rabbit.env cleanup_rabbitmq_logs.sh patch_rabbit.sh
```

## What the Patch Script Does

### 🔍 **Detection Phase**
1. **Verifies RabbitMQ Status**
   - Checks if RabbitMQ service is running
   - Verifies RabbitMQ responds to commands
   - Ensures system is healthy before patching

2. **Auto-detects Installation Paths**
   - Finds RabbitMQ installation directory (`/opt/rabbitmq`, `/usr/lib/rabbitmq`, etc.)
   - Locates log directory (`/var/log/rabbitmq`)
   - Detects configuration directory (`/etc/rabbitmq`)

### 💾 **Backup Phase**
Creates timestamped backup of:
- `/etc/rabbitmq/rabbitmq.conf`
- `/etc/rabbitmq/rabbitmq-env.conf` 
- `/etc/logrotate.d/rabbitmq`
- Current cron jobs

Backup location: `/tmp/rabbitmq_backup_YYYYMMDD_HHMMSS/`

### ⚙️ **Configuration Phase**
1. **Updates RabbitMQ Configuration**
   - Adds log rotation settings to `rabbitmq.conf`
   - Sets max log file size (100MB default)
   - Configures rotation count (5 files default)
   - Enables daily rotation

2. **Installs Cleanup Scripts**
   - Copies `cleanup_rabbitmq_logs.sh` to RabbitMQ bin directory
   - Creates monitoring script
   - Sets up symlinks for easy access (`rabbitmq-log-cleanup`, `rabbitmq-log-monitor`)

3. **Sets Up System Integration**
   - Creates logrotate configuration
   - Sets up daily cron job (2 AM default)
   - Configures proper permissions

### 🔄 **Restart Phase**
- Prompts user before restarting RabbitMQ
- Safely restarts service to apply configuration changes  
- Verifies RabbitMQ comes back online
- Checks cluster status if applicable

## Interactive Prompts

The script will ask for:

1. **Confirmation to Proceed**
   ```
   Do you want to proceed with these settings? (y/N):
   ```

2. **Existing Cron Job Replacement**
   ```
   Replace existing cron job? (y/N):
   ```

3. **RabbitMQ Restart Confirmation**
   ```
   RabbitMQ needs to be restarted to apply log rotation settings. Proceed? (y/N):
   ```

## Configuration Options

The script uses settings from `rabbit.env`:

```bash
LOG_RETENTION_DAYS=10               # Keep logs for 10 days
LOG_CLEANUP_HOUR=2                  # Run cleanup at 2 AM daily
LOG_MAX_SIZE="100MB"                # Max individual log file size
LOG_ROTATE_COUNT=5                  # Number of rotated log files to keep
LOG_COMPRESS_AFTER_DAYS=1           # Compress logs older than 1 day
DISK_USAGE_THRESHOLD=80             # Alert when disk usage > 80%
DISK_CLEANUP_THRESHOLD=85           # Force cleanup when disk usage > 85%
```

## Safety Features

### 🛡️ **Safety Checks**
- Verifies RabbitMQ is healthy before starting
- Creates automatic backups of all modified files
- Tests scripts before installing
- Graceful restart with health verification

### 🔒 **Non-Destructive Operation**
- Preserves existing RabbitMQ configuration
- Adds to configuration instead of replacing
- Maintains cluster status
- Keeps existing functionality intact

### ⚡ **Rollback Capability**
If something goes wrong, you can restore from backup:

```bash
# Find your backup directory
ls -la /tmp/rabbitmq_backup_*

# Restore configuration (example)
sudo cp /tmp/rabbitmq_backup_20250921_143052/rabbitmq.conf /etc/rabbitmq/
sudo systemctl restart rabbitmq-server
```

## After Patch Completion

### ✅ **Verification**
```bash
# Check log rotation is working
sudo rabbitmq-log-monitor

# View RabbitMQ configuration
sudo cat /etc/rabbitmq/rabbitmq.conf | grep log

# Check cron job was added
crontab -l | grep rabbitmq

# Test manual cleanup
sudo rabbitmq-log-cleanup
```

### 📊 **Monitoring**
```bash
# Daily monitoring
sudo rabbitmq-log-monitor

# Check disk usage
df -h /var/log/rabbitmq

# View cleanup history
tail -f /var/log/rabbitmq/cleanup.log
```

### 🔧 **Manual Controls**
```bash
# Force cleanup now
sudo rabbitmq-log-cleanup

# Check current log files
ls -la /var/log/rabbitmq/

# View log file sizes
du -h /var/log/rabbitmq/*
```

## Troubleshooting

### ❌ **Common Issues**

1. **Script fails with "RabbitMQ not running"**
   ```bash
   sudo systemctl start rabbitmq-server
   sudo systemctl status rabbitmq-server
   ```

2. **Permission errors**
   ```bash
   # Ensure proper ownership
   sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
   sudo chown -R rabbitmq:rabbitmq /opt/rabbitmq
   ```

3. **Cron job not working**
   ```bash
   # Check cron service
   sudo systemctl status cron
   
   # Test cleanup script manually
   sudo -u rabbitmq /opt/rabbitmq/bin/cleanup_logs.sh
   ```

4. **RabbitMQ won't restart**
   ```bash
   # Check logs
   sudo journalctl -u rabbitmq-server -n 50
   
   # Check configuration syntax
   sudo rabbitmq-server -t
   ```

### 🔙 **Quick Rollback**
```bash
# If you need to quickly rollback
BACKUP_DIR="/tmp/rabbitmq_backup_YYYYMMDD_HHMMSS"  # Use your actual backup dir

# Restore configuration
sudo cp "$BACKUP_DIR/rabbitmq.conf" /etc/rabbitmq/ 2>/dev/null || true
sudo cp "$BACKUP_DIR/rabbitmq-env.conf" /etc/rabbitmq/ 2>/dev/null || true

# Remove our additions
sudo rm -f /etc/logrotate.d/rabbitmq
crontab -l | grep -v "rabbitmq.*cleanup" | crontab -

# Restart RabbitMQ
sudo systemctl restart rabbitmq-server
```

## Expected Results

After successful patching:

✅ **Automatic log rotation** every day or when files exceed 100MB  
✅ **Daily cleanup** at 2 AM removing logs older than 10 days  
✅ **Log compression** after 1 day to save disk space  
✅ **Emergency cleanup** when disk usage exceeds 85%  
✅ **Monitoring tools** for visibility into log status  
✅ **System integration** with logrotate and cron  

Your existing RabbitMQ server will continue operating normally while gaining automated log management capabilities!