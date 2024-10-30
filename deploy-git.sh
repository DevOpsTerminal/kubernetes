#!/bin/bash
set -e
LOG_FILE="git_deployment.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

if [ "$#" -ne 2 ]; then
    echo "Użycie: $0 <IP_SERWERA> <URL_REPOZYTORIUM>"
    exit 1
fi

SERVER_IP=$1
GIT_URL=$2
TEMP_DIR="k8s-temp"

ssh -t root@$SERVER_IP "
    set -x
    export KUBECONFIG=/root/.kube/config

    echo '[1/6] Sprawdzanie CNI...'
    if [ ! -d '/etc/cni/net.d' ]; then
        mkdir -p /etc/cni/net.d
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
        sleep 30
    fi

    echo '[2/6] Sprawdzanie CoreDNS...'
    kubectl -n kube-system rollout restart deployment coredns
    kubectl -n kube-system rollout status deployment coredns --timeout=60s

    echo '[3/6] Przygotowanie środowiska...'
    rm -rf $TEMP_DIR
    git clone $GIT_URL $TEMP_DIR
    cd $TEMP_DIR

    echo '[4/6] Sprawdzanie stanu klastra...'
    kubectl wait --for=condition=ready node --all --timeout=60s || true
    kubectl get nodes
    kubectl get pods -A

    echo '[5/6] Wdrażanie konfiguracji...'
    # Najpierw namespace i configmapy
    for file in \$(find . -name 'namespace.yaml' -o -name '*configmap*.yaml'); do
        if [ -f \"\$file\" ]; then
            echo \"Applying \$file...\"
            kubectl apply -f \"\$file\"
        fi
    done

    # Następnie pozostałe zasoby
    for file in \$(find . -name '*.yaml' -o -name '*.yml' | grep -v 'namespace.yaml' | grep -v 'configmap'); do
        if [ -f \"\$file\" ]; then
            echo \"Applying \$file...\"
            kubectl apply -f \"\$file\"
            sleep 5
        fi
    done

    echo '[6/6] Weryfikacja wdrożenia...'
    kubectl wait --for=condition=available deployment --all --timeout=180s || true
    kubectl get all -A
    kubectl get pods -A -o wide
    kubectl describe pods
    kubectl get events --sort-by=.metadata.creationTimestamp

    cd ..
    rm -rf $TEMP_DIR
"

log "Wdrożenie z repozytorium $GIT_URL zakończone na $SERVER_IP"