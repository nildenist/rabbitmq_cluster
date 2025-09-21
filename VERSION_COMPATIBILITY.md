# RabbitMQ Version Compatibility Guide

## Log Rotation Format Differences by Version

### **RabbitMQ 3.x (Your Current Version: 3.10.0)**

**Log Rotation Configuration:**
```bash
# RabbitMQ 3.x format
log.file.level = info
log.dir = /var/log/rabbitmq
log.file = rabbit.log
log.file.rotation.date = {}                # Size-based rotation only
log.file.rotation.size = 100000000         # 100MB in bytes
log.file.rotation.count = 5                # Keep 5 rotated files
```

**Key Characteristics:**
- ✅ **Size-based rotation** works reliably
- ❌ **Date-based rotation** syntax is limited/unreliable
- ✅ **File count rotation** supported
- ✅ **Basic log levels** supported

### **RabbitMQ 4.x+ (Newer Versions)**

**Log Rotation Configuration:**
```bash
# RabbitMQ 4.x+ format
log.file.level = info
log.dir = /var/log/rabbitmq
log.file = rabbit.log
log.file.rotation.date = $W5D16            # Friday at 4 PM
log.file.rotation.size = 100000000         # 100MB in bytes
log.file.rotation.count = 5                # Keep 5 rotated files
log.file.formatter = plaintext             # Additional formatter options
```

**Key Characteristics:**
- ✅ **Size-based rotation** enhanced
- ✅ **Date-based rotation** fully supported with $W5D16 syntax
- ✅ **Advanced formatters** (plaintext, json, etc.)
- ✅ **Enhanced logging controls**

## Current Setup for RabbitMQ 3.10.0

Your configuration has been optimized for **RabbitMQ 3.10.0**:

### **What Works Reliably:**
```bash
log.file.rotation.size = 100000000         # ✅ 100MB size limit
log.file.rotation.count = 5                # ✅ Keep 5 rotated files
log.file.level = info                      # ✅ Standard log level
```

### **What's Simplified:**
```bash
log.file.rotation.date = {}                # ✅ Size-only rotation (more reliable)
# No complex date formats like $W5D16      # Avoided for compatibility
```

### **Why Size-Only Rotation is Better for RabbitMQ 3.x:**

1. **More Reliable**: Size-based rotation is consistent across all RabbitMQ 3.x versions
2. **Predictable**: Files rotate when they reach exactly 100MB
3. **No Time Dependencies**: Doesn't depend on system time/timezone
4. **Simpler Debugging**: Easier to troubleshoot if issues arise

## Upgrade Path Considerations

### **If You Upgrade to RabbitMQ 4.x Later:**

The patch script now **automatically detects** your RabbitMQ version and applies the appropriate configuration:

```bash
# Version detection in patch script
if [[ "$rabbitmq_version_major" -ge 4 ]]; then
    # Use advanced date rotation: $W5D16
else
    # Use reliable size rotation: {}
fi
```

### **Current Behavior:**
- **RabbitMQ 3.10.0** → Uses size-only rotation (`{}`)
- **RabbitMQ 4.0.1+** → Uses date+size rotation (`$W5D16`)

## File Rotation Examples for RabbitMQ 3.10.0

### **How Your Current Setup Works:**

1. **rabbit.log** (current log, up to 100MB)
2. **rabbit.log.1** (previous rotation, up to 100MB)
3. **rabbit.log.2** (2 rotations ago, up to 100MB)
4. **rabbit.log.3** (3 rotations ago, up to 100MB)
5. **rabbit.log.4** (4 rotations ago, up to 100MB)
6. **rabbit.log.5** (oldest, will be deleted on next rotation)

### **Rotation Trigger:**
- When `rabbit.log` reaches 100MB → rotate to `rabbit.log.1`
- All other files shift: `.1` → `.2`, `.2` → `.3`, etc.
- Oldest file (`.5`) gets deleted

## Benefits of Current Configuration

### **For RabbitMQ 3.10.0:**
✅ **Reliable rotation** at 100MB per file  
✅ **Predictable file sizes** (max 500MB total for 5 files)  
✅ **No timezone issues** (pure size-based)  
✅ **Compatible** with your cluster setup  
✅ **Combined with cleanup script** for comprehensive log management  

### **Total Log Management Strategy:**
1. **RabbitMQ built-in rotation**: 100MB per file, 5 files max
2. **Daily cleanup script**: Removes logs older than 10 days
3. **Compression**: Compresses logs older than 1 day
4. **Emergency cleanup**: Triggers at 85% disk usage

This gives you both **immediate file size control** (via RabbitMQ) and **long-term retention management** (via cleanup scripts).

## Configuration Summary

Your cleaned `rabbit.env` now contains:
- ✅ **RabbitMQ 3.10.0** (proper version for your setup)
- ✅ **Erlang 24.3.4.7** (compatible with RabbitMQ 3.10.0)
- ✅ **Size-based rotation** (100MB, 5 files)
- ✅ **10-day cleanup** (automated)
- ✅ **Version-aware scripts** (automatically adapt to your version)

This configuration is **production-ready** and **optimized** for your RabbitMQ 3.10.0 cluster! 🚀