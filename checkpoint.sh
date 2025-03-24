#!/bin/bash

# Create backup directory with timestamp
BACKUP_DIR="rabbitmq_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup install_rabbit.sh
cp install_rabbit.sh "$BACKUP_DIR/install_rabbit.sh"

# Backup rabbit.env
cp rabbit.env "$BACKUP_DIR/rabbit.env"

# Create a README with checkpoint information
cat > "$BACKUP_DIR/README.md" << EOF
# RabbitMQ Installation Checkpoint
Created: $(date)

## Files Backed Up
- install_rabbit.sh
- rabbit.env

## Current Working State
- RabbitMQ installation script with English messages
- Proper systemd service configuration
- Complete cleanup and restart sequence
- Proper cookie file handling
- Cluster join functionality with retry mechanism
- Plugin management
- Admin user creation

## To Restore
To restore this checkpoint:
1. Copy install_rabbit.sh back to your working directory:
   cp $BACKUP_DIR/install_rabbit.sh ./install_rabbit.sh

2. Copy rabbit.env back to your working directory:
   cp $BACKUP_DIR/rabbit.env ./rabbit.env

## Verification Steps
After restoration, verify:
1. File permissions are correct
2. Scripts are executable
3. Environment variables are properly set

## Notes
- This checkpoint represents a working state of the RabbitMQ cluster setup
- All messages have been converted to English
- The script includes proper error handling and retry mechanisms
EOF

# Set proper permissions
chmod 644 "$BACKUP_DIR/rabbit.env"
chmod 755 "$BACKUP_DIR/install_rabbit.sh"

echo "✅ Checkpoint created in directory: $BACKUP_DIR"
echo "📝 To restore this checkpoint later, use:"
echo "   cp $BACKUP_DIR/install_rabbit.sh ./install_rabbit.sh"
echo "   cp $BACKUP_DIR/rabbit.env ./rabbit.env" 