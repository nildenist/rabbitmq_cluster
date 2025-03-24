#!/bin/bash

set -e

# migrate.env dosyasını içe aktar
if [ ! -f migrate.env ]; then
  echo "❌ migrate.env dosyası bulunamadı!"
  exit 1
fi

source migrate.env

# Gereksinimleri kontrol et
echo "🔍 jq kontrol ediliyor..."
if ! command -v jq &> /dev/null; then
    echo "📦 jq yükleniyor..."
    sudo apt update && sudo apt install jq -y
fi

# Shovel için management API URL'leri
OLD_API="http://${OLD_RABBITMQ_HOST}:15672/api"
NEW_API="http://${NEW_RABBITMQ_HOST}:15672/api"

# Management plugin yüklü mü kontrol et (yeni cluster)
echo "🔍 Management Plugin kontrol ediliyor (yeni cluster)..."
if ! rabbitmq-plugins list -e | grep rabbitmq_management &> /dev/null; then
    echo "⚙️ Management Plugin yükleniyor..."
    sudo rabbitmq-plugins enable rabbitmq_management
    sudo systemctl restart rabbitmq-server
    sleep 5
fi

# Shovel plugin yüklü mü kontrol et
echo "🔍 Shovel Plugin kontrol ediliyor (yeni cluster)..."
if ! rabbitmq-plugins list -e | grep rabbitmq_shovel &> /dev/null; then
    echo "⚙️ Shovel Plugin yükleniyor..."
    sudo rabbitmq-plugins enable rabbitmq_shovel rabbitmq_shovel_management
    sudo systemctl restart rabbitmq-server
    sleep 5
fi

# Eski cluster'dan definitions.json al
echo "⬇️ Eski cluster'dan definitions.json alınıyor..."
curl -u "$OLD_RABBITMQ_USER:$OLD_RABBITMQ_PASSWORD" \
     -o "$TMP_FILE" \
     "$OLD_API/definitions"

if [ ! -f "$TMP_FILE" ]; then
    echo "❌ Definitions dosyası alınamadı."
    exit 1
fi

# Virtual host'ları al
vhosts=$(jq -r '.vhosts[].name' "$TMP_FILE")

for vhost in $vhosts; do
    echo "🔁 VHost işleniyor: $vhost"

    # Shovel policy ayarlarını oku
    policies=$(jq -c --arg vhost "$vhost" '.policies[] | select(.vhost == $vhost and .definition."shovels")' "$TMP_FILE")

    if [ -z "$policies" ]; then
        echo "⚠️  $vhost için Shovel policy bulunamadı. Atlanıyor."
        continue
    fi

    while IFS= read -r policy; do
        name=$(echo "$policy" | jq -r '.name')
        definition=$(echo "$policy" | jq -c '.definition')

        echo "🚀 Shovel policy uygulanıyor: $name"

        curl -u "$NEW_RABBITMQ_USER:$NEW_RABBITMQ_PASSWORD" \
             -H "Content-Type: application/json" \
             -X PUT "$NEW_API/policies/$vhost/$name" \
             -d "{
                   \"pattern\": \"\",
                   \"definition\": $definition,
                   \"priority\": 0,
                   \"apply-to\": \"all\"
                 }"

    done <<< "$policies"

done

echo "✅ Migration ve CDC (Shovel) yapılandırması tamamlandı!"
