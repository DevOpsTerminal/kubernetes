#!/bin/bash
set -e
LOG_FILE="cluster_setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

error_handler() {
    log "ERROR: $1"
    exit 1
}

check_prerequisites() {
    local host=$1
    ssh root@$host "
        if ! command -v curl > /dev/null; then
            apt-get update && apt-get install -y curl
        fi
    "
}

configure_containerd() {
    local host=$1
    log "Konfiguracja containerd na $host"
    ssh root@$host "
        mkdir -p /etc/containerd
        cat > /etc/containerd/config.toml << EOF
version = 2
[plugins]
  [plugins.\"io.containerd.grpc.v1.cri\"]
   [plugins.\"io.containerd.grpc.v1.cri\".containerd]
      [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes]
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runc]
          runtime_type = \"io.containerd.runc.v2\"
          [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF
        systemctl restart containerd
        systemctl enable containerd
        sleep 5
    " || error_handler "Błąd konfiguracji containerd na $host"
}

cleanup_docker_repos() {
    local host=$1
    log "Czyszczenie repozytoriów Docker na $host"
    ssh root@$host "
        rm -f /etc/apt/sources.list.d/archive_uri-https_download_docker_com_linux_ubuntu-*.list
    "
}

setup_prerequisites() {
    local host=$1
    log "Konfiguracja wymagań wstępnych na $host"
    ssh root@$host "
        # Wyłączenie swap
        swapoff -a
        sed -i '/swap/d' /etc/fstab

        # Konfiguracja modułów kernela
        cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
        modprobe overlay || true
        modprobe br_netfilter || true

        # Konfiguracja sysctl
        cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
        sysctl --system || true

        # Instalacja wymaganych pakietów
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    " || error_handler "Błąd konfiguracji wymagań wstępnych na $host"
}

install_docker() {
    local host=$1
    log "Instalacja Docker na $host"
    ssh root@$host "
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu focal stable' > /etc/apt/sources.list.d/docker.list
        apt-get update
        apt-get install -y docker-ce
        systemctl enable docker
        systemctl start docker
    " || error_handler "Błąd instalacji Docker na $host"
}

install_kubernetes() {
    local host=$1
    log "Instalacja Kubernetes na $host"
    ssh root@$host "
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
        apt-get update
        apt-get install -y kubelet kubeadm kubectl
        apt-mark hold kubelet kubeadm kubectl
    " || error_handler "Błąd instalacji Kubernetes na $host"
}

initialize_master() {
    local host=$1
    log "Inicjalizacja master node na $host"
    ssh root@$host "
        # Próba inicjalizacji z różnymi opcjami
        kubeadm init --pod-network-cidr=10.244.0.0/16 || \
        kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=all || \
        kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket unix:///run/containerd/containerd.sock

        # Konfiguracja kubectl
        mkdir -p /root/.kube
        cp -i /etc/kubernetes/admin.conf /root/.kube/config

        # Instalacja Flannel
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

        # Czekaj na gotowość węzła
        kubectl wait --for=condition=ready node --all --timeout=300s
    " || error_handler "Błąd inicjalizacji master node na $host"
}

if [ "$#" -ne 2 ]; then
    echo "Użycie: $0 <IP_MASTER> <IP_WORKER>"
    exit 1
fi

MASTER_IP=$1
WORKER_IP=$2

for host in $MASTER_IP $WORKER_IP; do
    check_prerequisites $host
    cleanup_docker_repos $host
    setup_prerequisites $host
    install_docker $host
    configure_containerd $host
    install_kubernetes $host
done

initialize_master $MASTER_IP

# Pobierz token dołączenia
JOIN_COMMAND=$(ssh root@$MASTER_IP "kubeadm token create --print-join-command")

# Dołącz worker node
log "Dołączanie worker node na $WORKER_IP"
ssh root@$WORKER_IP "
    $JOIN_COMMAND
" || error_handler "Błąd dołączania worker node"

log "Klaster został pomyślnie skonfigurowany"