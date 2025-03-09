#!/bin/bash

# Load environment variables from .env file
source .env

# Set RabbitMQ API endpoint for the new cluster
RABBITMQ_API="http://${NEW_RABBITMQ_USER}:${NEW_RABBITMQ_PASSWORD}@${NEW_RABBITMQ_HOST}:15672/api"

echo "🔹 Enabling RabbitMQ Federation Plugin on New Cluster..."
rabbitmq-plugins enable rabbitmq_federation
rabbitmq-plugins enable rabbitmq_federation_management

# Create Federation Upstream
echo "🔹 Configuring Federation Upstream..."
UPSTREAM_PAYLOAD=$(cat <<EOF
{
  "uri": "amqp://${OLD_RABBITMQ_USER}:${OLD_RABBITMQ_PASSWORD}@${OLD_RABBITMQ_HOST}",
  "expires": 3600000
}
EOF
)
curl -i -u "${NEW_RABBITMQ_USER}:${NEW_RABBITMQ_PASSWORD}" \
     -H "Content-Type: application/json" \
     -X PUT \
     -d "$UPSTREAM_PAYLOAD" \
     "${RABBITMQ_API}/parameters/federation-upstream/my_old_cluster"

# Configure Federation for Queues
IFS=',' read -r -a QUEUE_ARRAY <<< "$FEDERATED_QUEUES"
for QUEUE in "${QUEUE_ARRAY[@]}"; do
    echo "🔹 Setting Federation Policy for Queue: $QUEUE"
    curl -i -u "${NEW_RABBITMQ_USER}:${NEW_RABBITMQ_PASSWORD}" \
         -H "Content-Type: application/json" \
         -X PUT \
         -d '{"pattern": "'$QUEUE'", "definition": {"federation-upstream-set": "all"}}' \
         "${RABBITMQ_API}/policies/%2F/federate-queue-$QUEUE"
done

# Configure Federation for Exchanges
IFS=',' read -r -a EXCHANGE_ARRAY <<< "$FEDERATED_EXCHANGES"
for EXCHANGE in "${EXCHANGE_ARRAY[@]}"; do
    echo "🔹 Setting Federation Policy for Exchange: $EXCHANGE"
    curl -i -u "${NEW_RABBITMQ_USER}:${NEW_RABBITMQ_PASSWORD}" \
         -H "Content-Type: application/json" \
         -X PUT \
         -d '{"pattern": "'$EXCHANGE'", "definition": {"federation-upstream-set": "all"}}' \
         "${RABBITMQ_API}/policies/%2F/federate-exchange-$EXCHANGE"
done

echo "✅ Federation Setup Completed Successfully!"
