# RabbitMQ Log Retention Management Guide

## Overview
This document describes the automated log retention system implemented for your RabbitMQ cluster to prevent disk space issues.

## Configuration
The log retention settings are configured in `rabbit.env`:

```bash
# Log Retention Management Configuration
LOG_RETENTION_DAYS=10               # Keep logs for 10 days (as requested)
LOG_CLEANUP_HOUR=2                  # Run cleanup at 2 AM daily
LOG_MAX_SIZE="100MB"                # Max individual log file size
LOG_ROTATE_COUNT=5                  # Number of rotated log files to keep
LOG_COMPRESS_AFTER_DAYS=1           # Compress logs older than 1 day
LOG_CLEANUP_SCRIPT_PATH="/opt/rabbitmq/bin/cleanup_logs.sh"

# Disk Space Monitoring
DISK_USAGE_THRESHOLD=80             # Alert when disk usage > 80%
DISK_CLEANUP_THRESHOLD=85           # Force cleanup when disk usage > 85%
```

## Features Implemented

### 1. **Automatic Log Rotation**
- RabbitMQ logs rotate when they reach 100MB
- Keeps 5 rotated files before deletion
- Daily rotation based on date

### 2. **Automated Cleanup**
- **Daily Schedule**: Runs at 2 AM every day
- **Retention**: Keeps logs for 10 days (configurable)
- **Compression**: Compresses logs older than 1 day
- **Emergency Mode**: Aggressive cleanup when disk > 85% full

### 3. **Disk Monitoring**
- **Warning Level**: 80% disk usage
- **Critical Level**: 85% disk usage  
- **Emergency Actions**: Automatic cleanup when critical

### 4. **Multiple Safety Layers**
- RabbitMQ built-in rotation
- Custom cleanup script
- System logrotate integration
- Cron job automation

## Usage Commands

### Manual Operations
```bash
# Manual log cleanup
sudo rabbitmq-log-cleanup

# View log monitoring report
sudo rabbitmq-log-monitor

# Check current log status
sudo systemctl status rabbitmq-server
```

### Monitoring
```bash
# Check disk usage
df -h /var/log/rabbitmq

# View cleanup logs
tail -f /var/log/rabbitmq/cleanup.log

# List all log files
ls -la /var/log/rabbitmq/
```

### Configuration Changes
```bash
# Edit retention settings
nano rabbit.env

# Restart RabbitMQ to apply config changes
sudo systemctl restart rabbitmq-server

# View current cron jobs
crontab -l
```

## Log Types Managed

### 1. **Main Logs**
- `rabbit.log` - Current main log
- `rabbit.log.1`, `rabbit.log.2`, etc. - Rotated logs

### 2. **Compressed Archives**
- `rabbit.log.1.gz`, `rabbit.log.2.gz` - Compressed old logs

### 3. **Management Logs**
- Management plugin logs
- Connection logs
- Queue logs

## Cleanup Logic

### Normal Cleanup (Daily at 2 AM)
1. **Compress** logs older than 1 day
2. **Delete** compressed logs older than 10 days
3. **Remove** rotated logs older than 10 days
4. **Monitor** disk usage and alert if needed

### Emergency Cleanup (When Disk > 85%)
1. **Aggressive deletion** - 5-day retention instead of 10
2. **Truncate** very large current logs (>500MB)
3. **Immediate compression** of all old logs
4. **System alerts** via syslog

## Installation Details

### Files Created/Modified
- `/opt/rabbitmq/bin/cleanup_logs.sh` - Main cleanup script
- `/opt/rabbitmq/bin/monitor_logs.sh` - Monitoring script
- `/etc/logrotate.d/rabbitmq` - System logrotate config
- `/etc/rabbitmq/rabbitmq.conf` - Updated with rotation settings
- `rabbit.env` - Added retention configuration

### Symlinks for Easy Access
- `/usr/local/bin/rabbitmq-log-cleanup` → cleanup script
- `/usr/local/bin/rabbitmq-log-monitor` → monitoring script

### Cron Job
```bash
# Daily cleanup at 2:00 AM
0 2 * * * /bin/bash /opt/rabbitmq/bin/cleanup_logs.sh >> /var/log/rabbitmq/cleanup.log 2>&1
```

## Troubleshooting

### High Disk Usage Alert
```bash
# Check current usage
df -h /var/log/rabbitmq

# Run emergency cleanup
sudo rabbitmq-log-cleanup

# Check what's consuming space
sudo rabbitmq-log-monitor
```

### Cleanup Not Working
```bash
# Check cron job status
sudo systemctl status cron

# Test cleanup script manually
sudo -u rabbitmq /opt/rabbitmq/bin/cleanup_logs.sh

# Check cleanup logs
tail -20 /var/log/rabbitmq/cleanup.log
```

### Modify Retention Period
```bash
# Edit configuration
nano rabbit.env

# Change LOG_RETENTION_DAYS=10 to desired value
# Save and the next cleanup will use new value
```

## Benefits

✅ **Prevents Disk Full Issues**: Proactive cleanup before disk fills  
✅ **Automated Management**: No manual intervention needed  
✅ **Configurable**: Easy to adjust retention periods  
✅ **Multi-layered**: Multiple cleanup mechanisms  
✅ **Monitoring**: Alerts and reports for visibility  
✅ **Emergency Handling**: Automatic response to critical situations  
✅ **Compression**: Saves space while keeping old logs accessible  

## Alerts & Monitoring

### Syslog Integration
- Log cleanup completion messages
- Disk usage warnings and critical alerts
- Emergency cleanup notifications

### Manual Monitoring
- Use `rabbitmq-log-monitor` for detailed reports
- Check `/var/log/rabbitmq/cleanup.log` for cleanup history
- Monitor disk usage with `df -h /var/log/rabbitmq`

This system will effectively manage your RabbitMQ log retention and prevent the disk space issues you were experiencing!