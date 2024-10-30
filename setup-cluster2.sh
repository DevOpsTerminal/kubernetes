#!/bin/bash
set -e
LOG_FILE="k8s_install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Dodaj oficjalne repozytorium Kubernetes
log "Dodaję repozytorium Kubernetes..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Zaktualizuj pakiety
log "Aktualizuję pakiety..."
apt-get update

# Zainstaluj wymagane pakiety
log "Instaluję komponenty Kubernetes..."
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Wyłącz swap
log "Wyłączam swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# Załaduj wymagane moduły kernela
log "Konfiguruję moduły kernela..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Ustaw parametry sysctl
log "Konfiguruję parametry sysctl..."
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Inicjalizuj klaster (tylko na master node)
log "Inicjalizuję klaster Kubernetes..."
kubeadm init --pod-network-cidr=10.244.0.0/16

# Skonfiguruj kubectl
log "Konfiguruję kubectl..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Zainstaluj Flannel CNI
log "Instaluję Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml