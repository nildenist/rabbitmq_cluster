#!/bin/bash

set -e

# ENV dosyasını yükle
if [ ! -f "migrate.env" ]; then
  echo "❌ migrate.env dosyası bulunamadı."
  exit 1
fi

source migrate.env

# jq kontrolü ve kurulum
if ! command -v jq >/dev/null 2>&1; then
  echo "🔧 jq yükleniyor..."
  sudo apt update && sudo apt install -y jq
fi

MODE=$1

if [ "$MODE" != "source" ] && [ "$MODE" != "target" ]; then
  echo "❌ Kullanım: ./migrate.sh [source|target]"
  exit 1
fi

# Plugin kontrol fonksiyonu
enable_plugins() {
  local HOST=$1
  local USER=$2
  local PASSWORD=$3

  echo "🔍 $HOST sunucusunda eklentiler kontrol ediliyor..."
  curl -s -u "$USER:$PASSWORD" http://$HOST:15672/api/overview >/dev/null || {
    echo "❌ $HOST erişilemedi veya kullanıcı bilgileri hatalı"
    exit 1
  }

  echo "✅ $HOST erişimi başarılı, eklentiler etkinleştiriliyor..."
  sudo rabbitmq-plugins enable rabbitmq_shovel rabbitmq_shovel_management rabbitmq_management || true
  sudo systemctl restart rabbitmq-server
  sleep 5
}

if [ "$MODE" == "source" ]; then
  echo "🚀 Kaynak sunucu işlemleri başlatılıyor..."
  enable_plugins "$OLD_RABBITMQ_HOST" "$OLD_RABBITMQ_USER" "$OLD_RABBITMQ_PASSWORD"
  echo "✅ Kaynak sunucuda Shovel ve Management plugin etkinleştirildi."
  exit 0
fi

if [ "$MODE" == "target" ]; then
  echo "🚀 Hedef sunucu işlemleri başlatılıyor..."
  enable_plugins "$NEW_RABBITMQ_HOST" "$NEW_RABBITMQ_USER" "$NEW_RABBITMQ_PASSWORD"

  echo "📥 Kaynak tanımlar alınıyor: $TMP_FILE"
  curl -u "$OLD_RABBITMQ_USER:$OLD_RABBITMQ_PASSWORD" -o "$TMP_FILE"     "http://$OLD_RABBITMQ_HOST:15672/api/definitions" || {
    echo "❌ Tanımlar alınamadı!"
    exit 1
  }

  echo "🔧 Shovel tanımı oluşturuluyor..."
  SHOVEL_JSON=$(printf '{
    "component": "shovel",
    "name": "shovel_migration",
    "value": {
      "src-uri": "amqp://%s:%s@%s",
      "src-queue": "my_queue",
      "dest-uri": "amqp://%s:%s@%s",
      "dest-queue": "my_queue",
      "ack-mode": "on-confirm",
      "delete-after": "never"
    },
    "vhost": "/"
  }' "$OLD_RABBITMQ_USER" "$OLD_RABBITMQ_PASSWORD" "$OLD_RABBITMQ_HOST"      "$NEW_RABBITMQ_USER" "$NEW_RABBITMQ_PASSWORD" "$NEW_RABBITMQ_HOST")

  echo "$SHOVEL_JSON" | jq '.' > shovel_definition.json

  echo "🚀 Shovel tanımı hedef sunucuya uygulanıyor..."
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEW_RABBITMQ_USER:$NEW_RABBITMQ_PASSWORD"     -H "content-type: application/json"     -X PUT -d @"shovel_definition.json"     http://$NEW_RABBITMQ_HOST:15672/api/parameters/shovel/%2F/shovel_migration)

  if [ "$RESPONSE" == "204" ]; then
    echo "✅ Shovel kurulumu tamamlandı. CDC başlatıldı."
  else
    echo "❌ Shovel kurulumu başarısız oldu! HTTP kodu: $RESPONSE"
    echo "🔍 Gönderilen veri:"
    cat shovel_definition.json
    exit 1
  fi

  echo "🔍 Shovel durumu kontrol ediliyor..."
  curl -s -u "$NEW_RABBITMQ_USER:$NEW_RABBITMQ_PASSWORD"     "http://$NEW_RABBITMQ_HOST:15672/api/shovels" | jq
fi


if [ "$MODE" == "target" ]; then
  echo "📥 Kaynak tanımlar alınıyor: $TMP_FILE"
  curl -u "$OLD_RABBITMQ_USER:$OLD_RABBITMQ_PASSWORD" -o "$TMP_FILE" \
    "http://$OLD_RABBITMQ_HOST:15672/api/definitions" || {
    echo "❌ Tanımlar alınamadı!"
    exit 1
  }

  echo "🔍 Tanımlardan tüm kuyruklar alınıyor..."
  QUEUE_NAMES=$(jq -r '.queues[] | select(.vhost == "/") | .name' "$TMP_FILE")

  if [ -z "$QUEUE_NAMES" ]; then
    echo "❌ Hiç kuyruk bulunamadı!"
    exit 1
  fi

  for queue in $QUEUE_NAMES; do
    echo "🔧 Shovel oluşturuluyor: shovel_migrate_$queue"
    cat <<EOF > shovel_$queue.json
{
  "component": "shovel",
  "name": "shovel_migrate_$queue",
  "vhost": "/",
  "value": {
    "src-uri": "amqp://$OLD_RABBITMQ_USER:$OLD_RABBITMQ_PASSWORD@$OLD_RABBITMQ_HOST",
    "src-queue": "$queue",
    "dest-uri": "amqp://$NEW_RABBITMQ_USER:$NEW_RABBITMQ_PASSWORD@$NEW_RABBITMQ_HOST",
    "dest-queue": "$queue",
    "ack-mode": "on-confirm",
    "delete-after": "never"
  }
}
EOF

    curl -u "$NEW_RABBITMQ_USER:$NEW_RABBITMQ_PASSWORD" -H "content-type:application/json" \
      -X PUT -d @shovel_$queue.json \
      http://$NEW_RABBITMQ_HOST:15672/api/parameters/shovel/%2F/shovel_migrate_$queue

    echo "✅ Shovel oluşturuldu: shovel_migrate_$queue"
  done

  echo "🚀 Tüm kuyruğun shovel ile aktarımı başlatıldı."
fi
