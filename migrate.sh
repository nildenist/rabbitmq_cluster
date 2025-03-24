#!/bin/bash

set -e

# Load environment variables
if [ ! -f migrate.env ]; then
    echo "❌ migrate.env dosyası bulunamadı. Lütfen oluşturun."
    exit 1
fi

source migrate.env

echo "🔄 Kaynaktan hedefe geçiş başlatılıyor..."
echo "📌 Kaynak: $OLD_RABBITMQ_HOST"
echo "📌 Hedef: $NEW_RABBITMQ_HOST"

# Gerekli komutlar kontrolü
for CMD in curl jq; do
    if ! command -v $CMD &> /dev/null; then
        echo "❌ $CMD yüklü değil. Lütfen kurun: sudo apt install $CMD -y"
        exit 1
    fi
done

# Gerekli Pluginleri Aktifleştir
echo "🔧 Plugin kontrolü ve etkinleştirme"
for HOST in $OLD_RABBITMQ_HOST $NEW_RABBITMQ_HOST; do
    for PLUGIN in rabbitmq_management rabbitmq_shovel rabbitmq_shovel_management; do
        echo "🔍 $HOST üzerinde $PLUGIN etkin mi kontrol ediliyor..."
        sudo rabbitmq-plugins enable $PLUGIN || true
    done
done

# Kaynak tanımlarını dışa aktar
echo "📤 Kaynak tanımlar dışa aktarılıyor..."
curl -s -u $OLD_RABBITMQ_USER:$OLD_RABBITMQ_PASSWORD -o $TMP_FILE http://$OLD_RABBITMQ_HOST:15672/api/definitions

if [ ! -f "$TMP_FILE" ]; then
    echo "❌ $TMP_FILE dosyası oluşturulamadı"
    exit 1
fi

echo "✅ Tanımlar $TMP_FILE dosyasına alındı"

# Kuyrukları oku ve shovel konfigürasyonu oluştur
echo "🔨 Shovel konfigürasyonu hazırlanıyor..."

SHOVEL_CONFIGS=$(jq -r --arg OLD "$OLD_RABBITMQ_HOST" --arg NEW "$NEW_RABBITMQ_HOST" --arg USER "$OLD_RABBITMQ_USER" --arg PASS "$OLD_RABBITMQ_PASSWORD" '
    .queues[] | select(.vhost == "/") | 
    {
        name: "shovel_" + .name,
        value: {
            "src-uri": "amqp://"+$USER+":"+$PASS+"@"+$OLD,
            "src-queue": .name,
            "dest-uri": "amqp://"+$USER+":"+$PASS+"@"+$NEW,
            "dest-queue": .name,
            "ack-mode": "on-confirm",
            "delete-after": "never"
        }
    }' $TMP_FILE)

echo "$SHOVEL_CONFIGS" > shovel_config.json

# Hedefe shovel policy gönder
echo "🚀 Shovel konfigürasyonları hedefe gönderiliyor..."

POLICIES_JSON=$(jq -n --argjson shovel "$(cat shovel_config.json | jq -s .)" '
    {
        "policies": [
            ($shovel[] | {
                "vhost": "/",
                "name": .name,
                "pattern": "^" + .value."src-queue" + "$",
                "definition": {
                    "shovel": .value
                },
                "priority": 0,
                "apply-to": "queues"
            })
        ]
    }
')

curl -u $NEW_RABBITMQ_USER:$NEW_RABBITMQ_PASSWORD -H "content-type: application/json" -X POST     -d "$POLICIES_JSON"     http://$NEW_RABBITMQ_HOST:15672/api/parameters/shovel/%2f

echo "✅ Shovel konfigürasyonları başarıyla uygulandı."
