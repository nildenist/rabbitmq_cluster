# RabbitMQ Log Rotation Configuration Guide

## RabbitMQ Log Rotation Format Options

RabbitMQ uses specific format strings for log rotation. Here are the available options:

### Date-based Rotation Formats

#### **Daily Rotation**
```
log.file.rotation.date = $D0
```
- Rotates every day at midnight

#### **Weekly Rotation** 
```
log.file.rotation.date = $W0    # Sunday
log.file.rotation.date = $W1    # Monday  
log.file.rotation.date = $W2    # Tuesday
log.file.rotation.date = $W3    # Wednesday
log.file.rotation.date = $W4    # Thursday
log.file.rotation.date = $W5    # Friday (Recommended for business logs)
log.file.rotation.date = $W6    # Saturday
```

#### **Monthly Rotation**
```
log.file.rotation.date = $M     # First day of month
```

#### **Specific Date/Time Formats**
```
log.file.rotation.date = $W5D16   # Friday at 4 PM (16:00)
log.file.rotation.date = $D23     # Daily at 11 PM (23:00)
log.file.rotation.date = $W0D2    # Sunday at 2 AM
```

### Size-based Rotation

RabbitMQ file sizes must be specified in **bytes**:

```bash
log.file.rotation.size = 104857600    # 100 MB (100 * 1024 * 1024)
log.file.rotation.size = 52428800     # 50 MB
log.file.rotation.size = 10485760     # 10 MB
log.file.rotation.size = 1048576      # 1 MB
```

### Combined Rotation

RabbitMQ will rotate logs when **either** condition is met:
- File reaches specified size
- Date/time condition is reached

## Current Configuration in rabbit.env

Based on your settings:
```bash
LOG_MAX_SIZE="100"                # Will be converted to 100000000 bytes (100MB)
```

And in RabbitMQ config:
```bash
log.file.rotation.date = $W5D16   # Friday at 4 PM
log.file.rotation.size = 100000000 # 100 MB in bytes
log.file.rotation.count = 5       # Keep 5 rotated files
```

## Recommended Settings for Different Use Cases

### **High Traffic Production (Current)**
```bash
log.file.rotation.date = $W5D16    # Weekly on Friday 4 PM
log.file.rotation.size = 100000000  # 100 MB
log.file.rotation.count = 5         # 5 weeks of history
```

### **Daily Business Hours**
```bash
log.file.rotation.date = $D0        # Daily at midnight
log.file.rotation.size = 50000000   # 50 MB  
log.file.rotation.count = 10        # 10 days of history
```

### **Low Traffic/Development**
```bash
log.file.rotation.date = $W0        # Weekly on Sunday
log.file.rotation.size = 10000000   # 10 MB
log.file.rotation.count = 4         # 4 weeks of history
```

### **High Frequency Rotation**
```bash
log.file.rotation.date = $D2        # Daily at 2 AM
log.file.rotation.size = 20000000   # 20 MB
log.file.rotation.count = 7         # 1 week of daily files
```

## File Size Calculator

Convert human-readable sizes to bytes for RabbitMQ:

| Human Size | Bytes | Configuration Value |
|------------|-------|-------------------|
| 1 MB | 1,048,576 | `1048576` |
| 5 MB | 5,242,880 | `5242880` |
| 10 MB | 10,485,760 | `10485760` |
| 20 MB | 20,971,520 | `20971520` |
| 50 MB | 52,428,800 | `52428800` |
| 100 MB | 104,857,600 | `104857600` |
| 200 MB | 209,715,200 | `209715200` |
| 500 MB | 524,288,000 | `524288000` |

## Quick Calculation
```bash
# For MB to bytes: MB * 1024 * 1024
# Example: 100 MB = 100 * 1024 * 1024 = 104,857,600 bytes

# Our script automatically converts: LOG_MAX_SIZE * 1,000,000
# So LOG_MAX_SIZE="100" becomes 100,000,000 bytes (~95.4 MB)
```

## Time Format Examples

| Format | Description | When it Rotates |
|--------|-------------|-----------------|
| `$D0` | Daily at midnight | Every day at 00:00 |
| `$D2` | Daily at 2 AM | Every day at 02:00 |
| `$W0` | Weekly on Sunday | Every Sunday at 00:00 |
| `$W5D16` | Weekly Friday 4 PM | Every Friday at 16:00 |
| `$W1D8` | Weekly Monday 8 AM | Every Monday at 08:00 |
| `$M` | Monthly | 1st day of each month |

## How to Modify Your Configuration

### **Option 1: Edit rabbit.env**
```bash
# Change rotation size (in "MB", will be converted to bytes)
LOG_MAX_SIZE="50"                # 50MB files

# The script will automatically convert this to 50000000 bytes
```

### **Option 2: Choose Different Rotation Schedule**
Modify the patch script to use different date format:

```bash
# For daily rotation at 2 AM:
log.file.rotation.date = $D2

# For weekly rotation on Sunday:
log.file.rotation.date = $W0

# For monthly rotation:
log.file.rotation.date = $M
```

Your current setup (`$W5D16` with 100MB) is excellent for production use:
- ✅ Rotates weekly on Friday afternoon (good for business review)
- ✅ 100MB size limit prevents huge files
- ✅ 5 file rotation gives 5+ weeks of history
- ✅ Combined with 10-day cleanup provides good balance