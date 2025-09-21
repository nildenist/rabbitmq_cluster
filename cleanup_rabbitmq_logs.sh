#!/bin/bash

# RabbitMQ Log Cleanup Script
# Author: Ozgur SALGINCI
# Description: Automated log cleanup for RabbitMQ with disk space monitoring

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/rabbit.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Configuration file $CONFIG_FILE not found!"
    exit 1
fi

# Default values if not set in config
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-10}
DISK_USAGE_THRESHOLD=${DISK_USAGE_THRESHOLD:-80}
DISK_CLEANUP_THRESHOLD=${DISK_CLEANUP_THRESHOLD:-85}
RABBITMQ_LOG_DIR=${RABBITMQ_LOG_DIR:-/var/log/rabbitmq}
LOG_COMPRESS_AFTER_DAYS=${LOG_COMPRESS_AFTER_DAYS:-1}

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
}

# Get disk usage percentage for a directory
get_disk_usage() {
    local dir=$1
    df "$dir" | awk 'NR==2 {sub(/%$/, "", $5); print $5}'
}

# Get directory size in human readable format
get_directory_size() {
    local dir=$1
    du -sh "$dir" 2>/dev/null | awk '{print $1}' || echo "0B"
}

# Compress old log files
compress_old_logs() {
    local log_dir=$1
    local days_old=$2
    
    log_info "Compressing log files older than $days_old days in $log_dir"
    
    # Find and compress .log files older than specified days (not already compressed)
    find "$log_dir" -type f -name "*.log" -mtime +$days_old ! -name "*.gz" -print0 | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            log_info "Compressing: $file"
            gzip "$file" && log_info "✅ Compressed: $file.gz" || log_error "Failed to compress: $file"
        fi
    done
    
    # Also compress .log files with numeric extensions (rabbit.log.1, rabbit.log.2, etc.)
    find "$log_dir" -type f -name "*.log.[0-9]*" -mtime +$days_old ! -name "*.gz" -print0 | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            log_info "Compressing rotated log: $file"
            gzip "$file" && log_info "✅ Compressed: $file.gz" || log_error "Failed to compress: $file"
        fi
    done
}

# Clean up old log files
cleanup_old_logs() {
    local log_dir=$1
    local retention_days=$2
    
    log_info "Starting log cleanup in $log_dir (retention: $retention_days days)"
    
    if [ ! -d "$log_dir" ]; then
        log_warn "Log directory $log_dir does not exist"
        return 1
    fi
    
    # Count files before cleanup
    local files_before=$(find "$log_dir" -type f \( -name "*.log" -o -name "*.log.*" \) | wc -l)
    local size_before=$(get_directory_size "$log_dir")
    
    # Remove log files older than retention period
    local deleted_count=0
    
    # Remove old compressed logs
    find "$log_dir" -type f -name "*.log.*.gz" -mtime +$retention_days -print0 | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            log_info "Removing old compressed log: $file"
            rm -f "$file" && ((deleted_count++)) && log_info "✅ Deleted: $file" || log_error "Failed to delete: $file"
        fi
    done
    
    # Remove old uncompressed rotated logs
    find "$log_dir" -type f -name "*.log.[0-9]*" -mtime +$retention_days ! -name "*.gz" -print0 | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            log_info "Removing old rotated log: $file"
            rm -f "$file" && ((deleted_count++)) && log_info "✅ Deleted: $file" || log_error "Failed to delete: $file"
        fi
    done
    
    # Remove old main log files (but keep current ones)
    find "$log_dir" -type f -name "*.log" -mtime +$retention_days ! -name "rabbit.log" -print0 | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            log_info "Removing old log: $file"
            rm -f "$file" && ((deleted_count++)) && log_info "✅ Deleted: $file" || log_error "Failed to delete: $file"
        fi
    done
    
    # Count files after cleanup
    local files_after=$(find "$log_dir" -type f \( -name "*.log" -o -name "*.log.*" \) | wc -l)
    local size_after=$(get_directory_size "$log_dir")
    
    log_info "Cleanup summary:"
    log_info "  Files before: $files_before, after: $files_after"
    log_info "  Size before: $size_before, after: $size_after"
    log_info "  Files processed: $((files_before - files_after))"
}

# Emergency cleanup when disk is very full
emergency_cleanup() {
    local log_dir=$1
    
    log_warn "🚨 EMERGENCY CLEANUP: Disk usage is critically high!"
    
    # More aggressive cleanup - remove files older than half the retention period
    local emergency_retention=$((LOG_RETENTION_DAYS / 2))
    if [ $emergency_retention -lt 1 ]; then
        emergency_retention=1
    fi
    
    log_warn "Emergency retention period: $emergency_retention days"
    
    # Remove all files older than emergency retention period
    find "$log_dir" -type f \( -name "*.log" -o -name "*.log.*" \) -mtime +$emergency_retention -print0 | while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ "$(basename "$file")" != "rabbit.log" ]; then
            log_warn "Emergency removal: $file"
            rm -f "$file" && log_warn "✅ Emergency deleted: $file" || log_error "Failed to emergency delete: $file"
        fi
    done
    
    # Also truncate current log files if they're very large (> 500MB)
    find "$log_dir" -name "rabbit.log" -size +500M -print0 | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            log_warn "Truncating large current log file: $file"
            # Keep last 1000 lines
            tail -n 1000 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            log_warn "✅ Truncated: $file (kept last 1000 lines)"
        fi
    done
}

# Monitor disk usage and alert
monitor_disk_usage() {
    local log_dir=$1
    local current_usage=$(get_disk_usage "$log_dir")
    
    log_info "Current disk usage: $current_usage%"
    
    if [ "$current_usage" -gt "$DISK_CLEANUP_THRESHOLD" ]; then
        log_warn "⚠️ Disk usage ($current_usage%) exceeds cleanup threshold ($DISK_CLEANUP_THRESHOLD%)"
        emergency_cleanup "$log_dir"
        
        # Check again after emergency cleanup
        local new_usage=$(get_disk_usage "$log_dir")
        log_info "Disk usage after emergency cleanup: $new_usage%"
        
        if [ "$new_usage" -gt "$DISK_CLEANUP_THRESHOLD" ]; then
            log_error "🚨 CRITICAL: Disk usage still high after emergency cleanup!"
            # Send alert to syslog
            logger -p local0.crit "RabbitMQ: Critical disk usage $new_usage% after cleanup"
        fi
        
    elif [ "$current_usage" -gt "$DISK_USAGE_THRESHOLD" ]; then
        log_warn "⚠️ Disk usage ($current_usage%) exceeds warning threshold ($DISK_USAGE_THRESHOLD%)"
        # Send warning to syslog
        logger -p local0.warning "RabbitMQ: High disk usage $current_usage%"
    fi
}

# Main cleanup function
main() {
    log_info "=== RabbitMQ Log Cleanup Started ==="
    log_info "Configuration:"
    log_info "  Log directory: $RABBITMQ_LOG_DIR"
    log_info "  Retention days: $LOG_RETENTION_DAYS"
    log_info "  Compress after: $LOG_COMPRESS_AFTER_DAYS days"
    log_info "  Disk warning threshold: $DISK_USAGE_THRESHOLD%"
    log_info "  Disk cleanup threshold: $DISK_CLEANUP_THRESHOLD%"
    
    # Check if RabbitMQ log directory exists
    if [ ! -d "$RABBITMQ_LOG_DIR" ]; then
        log_error "RabbitMQ log directory $RABBITMQ_LOG_DIR does not exist!"
        exit 1
    fi
    
    # Monitor disk usage first
    monitor_disk_usage "$RABBITMQ_LOG_DIR"
    
    # Compress old logs first to save space
    if [ "$LOG_COMPRESS_AFTER_DAYS" -gt 0 ]; then
        compress_old_logs "$RABBITMQ_LOG_DIR" "$LOG_COMPRESS_AFTER_DAYS"
    fi
    
    # Perform regular cleanup
    cleanup_old_logs "$RABBITMQ_LOG_DIR" "$LOG_RETENTION_DAYS"
    
    # Final disk usage check
    local final_usage=$(get_disk_usage "$RABBITMQ_LOG_DIR")
    local final_size=$(get_directory_size "$RABBITMQ_LOG_DIR")
    
    log_info "=== RabbitMQ Log Cleanup Completed ==="
    log_info "Final disk usage: $final_usage%"
    log_info "Final log directory size: $final_size"
    
    # Log to syslog for monitoring
    logger -p local0.info "RabbitMQ log cleanup completed. Disk usage: $final_usage%, Log size: $final_size"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi