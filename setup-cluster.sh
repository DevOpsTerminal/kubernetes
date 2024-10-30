#!/bin/bash
# Skrypt do konfiguracji klastra Kubernetes

set -e
LOG_FILE="cluster_setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

if [ "$#" -ne 2 ]; then
    echo "Użycie: $0 <IP_MASTER> <IP_WORKER>"
    exit 1
fi

MASTER_IP=$1
WORKER_IP=$2

# Konfiguracja master node
log "Rozpoczynam konfigurację master node na $MASTER_IP"
ssh root@$MASTER_IP "
    # Instalacja wymaganych pakietów
    apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable'
    apt-get update && apt-get install -y docker-ce

    # Instalacja kubeadm, kubelet i kubectl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' > /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubeadm kubelet kubectl

    # Inicjalizacja klastra
    kubeadm init --pod-network-cidr=10.244.0.0/16 > kubeadm-init.log

    # Konfiguracja kubectl dla roota
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config

    # Instalacja Flannel network plugin
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
"

# Pobierz token dołączenia do klastra
JOIN_COMMAND=$(ssh root@$MASTER_IP "kubeadm token create --print-join-command")

# Konfiguracja worker node
log "Rozpoczynam konfigurację worker node na $WORKER_IP"
ssh root@$WORKER_IP "
    # Instalacja wymaganych pakietów
    apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable'
    apt-get update && apt-get install -y docker-ce

    # Instalacja kubeadm i kubelet
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' > /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubeadm kubelet

    # Dołączenie do klastra
    $JOIN_COMMAND
"

log "Klaster został pomyślnie skonfigurowany"
