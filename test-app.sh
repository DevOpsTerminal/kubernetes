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

    # Test stanu klastra
    log 'Stan klastra:'
    kubectl get nodes -o wide
    kubectl describe nodes
    kubectl get componentstatuses

    # Test stanu podów
    log 'Stan podów i deploymentów:'
    kubectl get deployments -A
    kubectl get pods -A -o wide
    kubectl describe pods -l app=example

    # Test networkingu
    log 'Stan networkingu:'
    kubectl get pods -n kube-system -l k8s-app=kube-dns
    kubectl get pods -n kube-flannel
    ip a
    ip route
    cat /etc/cni/net.d/*
    crictl info | grep -i network

    # Test storage
    log 'Stan storage:'
    df -h
    mount | grep kubernetes
    ls -la /var/lib/kubelet

    # Test logów systemowych
    log 'Logi systemowe:'
    journalctl -u kubelet --since \"5 minutes ago\" | tail -n 50
    journalctl -u containerd --since \"5 minutes ago\" | tail -n 50

    # Test portów
    log 'Stan portów:'
    netstat -tulpn
    ss -tulpn

    # Test DNS
    log 'Stan DNS:'
    kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
    kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

    # Test usług
    log 'Stan usług:'
    kubectl get all --all-namespaces
    kubectl get endpoints -A

    # Test konfiguracji
    log 'Konfiguracja:'
    kubectl get configmaps -A
    kubectl get secrets -A

    # Test zasobów
    log 'Użycie zasobów:'
    kubectl top nodes || echo 'metrics-server nie jest zainstalowany'
    kubectl top pods -A || echo 'metrics-server nie jest zainstalowany'

    # Test taint i toleracji
    log 'Tainty i toleracje:'
    kubectl get nodes -o=custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

    # Test ingress
    log 'Stan Ingress:'
    kubectl get ingress -A
    kubectl describe ingress -A

    # Test aplikacji
    if kubectl get pods -l app=example | grep Running; then
        log 'Test aplikacji:'
        POD_NAME=\$(kubectl get pods -l app=example -o jsonpath='{.items[0].metadata.name}')
        kubectl exec \$POD_NAME -- curl -sS localhost:80
        kubectl logs \$POD_NAME

        SERVICE_IP=\$(kubectl get svc example-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [ -n \"\$SERVICE_IP\" ]; then
            curl -k -v https://\$SERVICE_IP
        fi
    fi
" 2>&1 | tee -a $LOG_FILE

log "Testy diagnostyczne na $SERVER_IP zakończone"