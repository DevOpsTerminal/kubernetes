#!/bin/bash
set -e

if [ ! -f .env ]; then
    echo "Brak pliku .env"
    exit 1
fi

source .env

ssh -t root@$SERVER_IP "
    # Monitoring stack z hasłem
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set grafana.adminUser=${GRAFANA_ADMIN_USER} \
        --set grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD} \
        --set prometheus.server.basicAuth.enabled=true \
        --set prometheus.server.basicAuth.username=${PROMETHEUS_ADMIN_USER} \
        --set prometheus.server.basicAuth.password=${PROMETHEUS_ADMIN_PASSWORD} \
        --wait

    # Elasticsearch z hasłem
    helm upgrade --install elasticsearch elastic/elasticsearch \
        --namespace logging \
        --set replicas=1 \
        --set resources.requests.cpu=100m \
        --set resources.requests.memory=512M \
        --set elasticsearch.password=${ELASTIC_PASSWORD} \
        --wait

    # Kibana z hasłem
    helm upgrade --install kibana elastic/kibana \
        --namespace logging \
        --set kibanaPassword=${KIBANA_ADMIN_PASSWORD} \
        --set elasticsearch.password=${ELASTIC_PASSWORD} \
        --wait
"