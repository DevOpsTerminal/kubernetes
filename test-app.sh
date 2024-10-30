#!/bin/bash
set -e
LOG_FILE="app_testing.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

if [ "$#" -ne 1 ]; then
    echo "Użycie: $0 <IP_SERWERA>"
    exit 1
fi

SERVER_IP=$1

ssh root@$SERVER_IP "
    export KUBECONFIG=/root/.kube/config

    log() {
        echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] \$1\"
    }

    # Sprawdź stan klastra
    log 'Stan klastra:'
    kubectl get nodes
    kubectl describe nodes

    # Sprawdź stan podów
    log 'Stan podów:'
    kubectl get pods -l app=example -o wide
    kubectl describe pods -l app=example

    # Sprawdź eventy klastra
    log 'Eventy klastra:'
    kubectl get events --sort-by='.lastTimestamp'

    # Sprawdź stan komponentów systemowych
    log 'Stan komponentów systemowych:'
    kubectl get pods -n kube-system

    # Sprawdź status CNI (Flannel)
    log 'Status Flannel:'
    kubectl get pods -n kube-flannel

    # Sprawdź serwisy
    log 'Status serwisów:'
    kubectl get svc example-service
    kubectl describe svc example-service

    # Sprawdź Ingress
    log 'Status Ingress:'
    kubectl get ingress example-ingress
    kubectl describe ingress example-ingress

    # Jeśli pody są running, sprawdź logi
    if kubectl get pods -l app=example | grep Running; then
        log 'Logi aplikacji:'
        for pod in \$(kubectl get pods -l app=example -o jsonpath='{.items[*].metadata.name}'); do
            echo \"Logi dla poda \$pod:\"
            kubectl logs \$pod
        done
    fi
" 2>&1 | tee -a $LOG_FILE

log "Testy diagnostyczne na $SERVER_IP zakończone"