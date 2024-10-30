#!/bin/bash
set -e
LOG_FILE="password_reset.log"

if [ "$#" -ne 1 ]; then
    echo "Użycie: $0 <IP_SERWERA>"
    exit 1
fi

if [ ! -f .env ]; then
    echo "Brak pliku .env"
    exit 1
fi

SERVER_IP=$1

# Kopiuj .env na serwer
scp .env root@$SERVER_IP:/root/

ssh -t root@$SERVER_IP "
    set -x
    export KUBECONFIG=/root/.kube/config
    source /root/.env

    # Instalacja Helm jeśli nie istnieje
    if ! command -v helm &> /dev/null; then
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        sleep 10
    fi

    # Sprawdź czy namespace istnieją, jeśli nie - uruchom cluster_tools.sh
    if ! kubectl get namespace monitoring &> /dev/null; then
        echo 'Namespace monitoring nie istnieje. Proszę najpierw uruchomić cluster_tools.sh'
        exit 1
    fi

    # Update Grafana
    kubectl -n monitoring create secret generic monitoring-grafana \
        --from-literal=admin-user=\${GRAFANA_ADMIN_USER} \
        --from-literal=admin-password=\${GRAFANA_ADMIN_PASSWORD} \
        --dry-run=client -o yaml | kubectl apply -f -

    # Update Prometheus
    kubectl -n monitoring create secret generic monitoring-kube-prometheus-prometheus-basic-auth \
        --from-literal=auth=\$(echo -n \${PROMETHEUS_ADMIN_USER}:\${PROMETHEUS_ADMIN_PASSWORD} | base64) \
        --dry-run=client -o yaml | kubectl apply -f -

    # Update Elasticsearch i Kibana
    helm repo add elastic https://helm.elastic.co
    helm repo update

    helm upgrade --install elasticsearch elastic/elasticsearch \
        --namespace logging \
        --set replicas=1 \
        --set resources.requests.cpu=100m \
        --set resources.requests.memory=512M \
        --set elasticsearch.password=\${ELASTIC_PASSWORD} \
        --wait

    helm upgrade --install kibana elastic/kibana \
        --namespace logging \
        --set kibanaPassword=\${KIBANA_ADMIN_PASSWORD} \
        --set elasticsearch.password=\${ELASTIC_PASSWORD} \
        --wait

    # Restart podów
    echo 'Restartuję pody...'
    kubectl -n monitoring rollout restart deployment monitoring-grafana
    kubectl -n logging rollout restart statefulset elasticsearch-master
    kubectl -n logging rollout restart deployment kibana-kibana

    echo 'Czekam na gotowość podów...'
    kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=180s
    kubectl wait --for=condition=ready pod -l app=elasticsearch-master -n logging --timeout=180s
    kubectl wait --for=condition=ready pod -l app=kibana -n logging --timeout=180s

    echo 'Status podów:'
    kubectl get pods -A | grep -E 'monitoring|logging'

    echo 'Hasła zostały zaktualizowane dla:'
    echo '- Grafana'
    echo '- Prometheus'
    echo '- Elasticsearch'
    echo '- Kibana'
"