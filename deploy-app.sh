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
TIMEOUT=180 # 3 minuty

# Generowanie certyfikatu
log "Generowanie certyfikatu SSL"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt \
    -subj "/CN=example.com"

scp tls.key tls.crt root@$SERVER_IP:/root/

ssh -t root@$SERVER_IP "
    set -x
    export KUBECONFIG=/root/.kube/config

    echo '[1/5] Sprawdzanie stanu klastra...'
    kubectl get nodes
    kubectl get pods -A

    echo '[2/5] Usuwanie starych zasobów...'
    kubectl delete all,secrets,ingress --all -n default --force --grace-period=0 || true

    echo '[3/5] Czekanie na usunięcie zasobów...'
    while kubectl get pods -n default 2>/dev/null | grep -v 'No resources found'; do
        echo 'Czekam na usunięcie podów...'
        kubectl get pods -n default
        sleep 5
    done

    echo '[4/5] Wdrażanie nowej aplikacji...'
    kubectl create secret tls example-tls --key /root/tls.key --cert /root/tls.crt

    cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
  labels:
    app: example
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
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoSchedule
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: '64Mi'
            cpu: '250m'
          limits:
            memory: '128Mi'
            cpu: '500m'
---
apiVersion: v1
kind: Service
metadata:
  name: example-service
  labels:
    app: example
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
  labels:
    app: example
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

    echo '[5/5] Monitoring wdrożenia...'
    for i in \$(seq 1 $TIMEOUT); do
        echo \"Sprawdzanie stanu (\$i/${TIMEOUT}s)\"
        kubectl get pods,svc,ingress -l app=example
        kubectl describe pods -l app=example | grep -A 5 Events:
        if kubectl get deployment example-app -o jsonpath='{.status.availableReplicas}' | grep -q 2; then
            echo 'Wdrożenie zakończone sukcesem'
            break
        fi
        sleep 3
    done
"

log "Aplikacja została wdrożona na $SERVER_IP"
rm -f tls.key tls.crt