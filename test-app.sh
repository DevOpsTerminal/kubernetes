#!/bin/bash
# Skrypt do testowania aplikacji

set -e
LOG_FILE="app_testing.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Sprawdzenie statusu podów
log "Sprawdzanie statusu podów"
kubectl get pods -l app=example -o wide

# Sprawdzenie statusu serwisu
log "Sprawdzanie statusu serwisu"
kubectl get svc example-service

# Sprawdzenie statusu Ingress
log "Sprawdzanie statusu Ingress"
kubectl get ingress example-ingress

# Test połączenia HTTPS
log "Testowanie połączenia HTTPS"
SERVICE_IP=$(kubectl get svc example-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -k -v https://$SERVICE_IP

# Sprawdzenie logów aplikacji
log "Sprawdzanie logów aplikacji"
kubectl logs -l app=example

log "Testy zakończone"