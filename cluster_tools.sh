#!/bin/bash
set -e
LOG_FILE="cluster_tools.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

if [ "$#" -ne 2 ]; then
    echo "Użycie: $0 <IP_SERWERA> <DOMENA_BAZOWA>"
    exit 1
fi

if [ ! -f .env ]; then
    echo "Brak pliku .env. Tworzę domyślny..."
    cat > .env << EOF
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=Strong@Grafana123
KIBANA_ADMIN_USER=elastic
KIBANA_ADMIN_PASSWORD=Strong@Kibana123
PROMETHEUS_ADMIN_USER=admin
PROMETHEUS_ADMIN_PASSWORD=Strong@Prom123
ELASTIC_PASSWORD=Strong@Elastic123
CLUSTER_DOMAIN=${2}
EOF
fi

source .env
SERVER_IP=$1
BASE_DOMAIN=$2

# Kopiuj .env na serwer
scp .env root@$SERVER_IP:/root/

ssh -t root@$SERVER_IP "
    set -x
    export KUBECONFIG=/root/.kube/config
    source /root/.env

    # Instalacja Nginx Ingress
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.publishService.enabled=true \
        --wait

    # Cert-manager
    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml

    sleep 10

    # Monitoring z auth
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set grafana.adminUser=\${GRAFANA_ADMIN_USER} \
        --set grafana.adminPassword=\${GRAFANA_ADMIN_PASSWORD} \
        --set prometheus.server.basicAuth.enabled=true \
        --set prometheus.server.basicAuth.username=\${PROMETHEUS_ADMIN_USER} \
        --set prometheus.server.basicAuth.password=\${PROMETHEUS_ADMIN_PASSWORD} \
        --wait

    # Elasticsearch z auth
    helm upgrade --install elasticsearch elastic/elasticsearch \
        --namespace logging \
        --set replicas=1 \
        --set resources.requests.cpu=100m \
        --set resources.requests.memory=512M \
        --set elasticsearch.password=\${ELASTIC_PASSWORD} \
        --wait

    # Kibana z auth
    helm upgrade --install kibana elastic/kibana \
        --namespace logging \
        --set kibanaPassword=\${KIBANA_ADMIN_PASSWORD} \
        --set elasticsearch.password=\${ELASTIC_PASSWORD} \
        --wait

    sleep 10

    # Ingress
    cat << EOF | kubectl apply -f -
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: logging
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: 'true'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - kibana.${BASE_DOMAIN}
    secretName: kibana-tls
  rules:
  - host: kibana.${BASE_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana-kibana
            port:
              number: 5601
EOF

    sleep 10

    # Ingress dla monitoringu
    cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring-ingress
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: 'true'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grafana.${BASE_DOMAIN}
    - prometheus.${BASE_DOMAIN}
    secretName: monitoring-tls
  rules:
  - host: grafana.${BASE_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: monitoring-grafana
            port:
              number: 80
  - host: prometheus.${BASE_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: monitoring-kube-prometheus-prometheus
            port:
              number: 9090
EOF

    # Metrics Server
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    echo \"Dostęp do usług:\"
    echo \"- Grafana: https://grafana.${BASE_DOMAIN}\"
    echo \"  Login: \${GRAFANA_ADMIN_USER}\"
    echo \"  Hasło: \${GRAFANA_ADMIN_PASSWORD}\"
    echo \"- Prometheus: https://prometheus.${BASE_DOMAIN}\"
    echo \"  Login: \${PROMETHEUS_ADMIN_USER}\"
    echo \"  Hasło: \${PROMETHEUS_ADMIN_PASSWORD}\"
    echo \"- Kibana: https://kibana.${BASE_DOMAIN}\"
    echo \"  Login: \${KIBANA_ADMIN_USER}\"
    echo \"  Hasło: \${KIBANA_ADMIN_PASSWORD}\"
"

log "Konfiguracja narzędzi zakończona dla domeny ${BASE_DOMAIN}"