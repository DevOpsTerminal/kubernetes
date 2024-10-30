#!/bin/bash
set -e
LOG_FILE="app_deployment.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

if [ "$#" -ne 1 ]; then
    echo "Użycie: $0 <IP_SERWERA>"
    exit 1
fi

SERVER_IP=$1

# Sprawdź czy to master node
ssh root@$SERVER_IP "
    if [ ! -f /root/.kube/config ]; then
        echo 'To nie jest master node!'
        exit 1
    fi
"

# Generowanie i kopiowanie certyfikatu
log "Generowanie certyfikatu SSL lokalnie"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt \
    -subj "/CN=example.com"

log "Kopiowanie certyfikatów na serwer"
scp tls.key tls.crt root@$SERVER_IP:/root/

# Wdrożenie na serwerze
ssh root@$SERVER_IP "
    export KUBECONFIG=/root/.kube/config

    # Usuń stare zasoby jeśli istnieją
    kubectl delete secret example-tls --ignore-not-found
    kubectl delete deployment example-app --ignore-not-found
    kubectl delete service example-service --ignore-not-found
    kubectl delete ingress example-ingress --ignore-not-found

    # Utwórz nowe zasoby
    kubectl create secret tls example-tls --key /root/tls.key --cert /root/tls.crt

    cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: example-service
spec:
  selector:
    app: example
  ports:
  - port: 443
    targetPort: 80
  type: LoadBalancer
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: \"true\"
spec:
  tls:
  - hosts:
    - example.com
    secretName: example-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 443
EOF

    # Sprawdź status deploymentu
    kubectl wait --for=condition=ready pod -l app=example --timeout=300s
    kubectl get pods,svc,ingress
"

log "Aplikacja została wdrożona na $SERVER_IP"

# Sprzątanie
rm -f tls.key tls.crt