#!/bin/bash
set -e
LOG_FILE="ssh_setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

if [ "$#" -ne 2 ]; then
    echo "Użycie: $0 <REMOTE_USER> <REMOTE_IP>"
    exit 1
fi

REMOTE_USER=$1
REMOTE_IP=$2

# Generuj klucz SSH jeśli nie istnieje
if [ ! -f ~/.ssh/id_rsa ]; then
    log "Generuję nową parę kluczy SSH..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# Stwórz config SSH jeśli nie istnieje
if [ ! -f ~/.ssh/config ]; then
    log "Tworzę konfigurację SSH..."
    cat > ~/.ssh/config <<EOF
Host $REMOTE_IP
    IdentitiesOnly yes
    IdentityFile ~/.ssh/id_rsa
    PubkeyAuthentication no
EOF
fi

# Sprawdź połączenie
log "Sprawdzam połączenie z serwerem..."
if ! nc -z -w5 $REMOTE_IP 22; then
    log "BŁĄD: Port 22 jest niedostępny"
    exit 1
fi

# Wyczyść stare klucze
log "Czyszczę stare klucze..."
ssh-keygen -R $REMOTE_IP 2>/dev/null || true

# Kopiuj klucz z wymuszeniem
log "Kopiuję klucz publiczny..."
if ! ssh-copy-id -f -i ~/.ssh/id_rsa.pub -o PubkeyAuthentication=no "$REMOTE_USER@$REMOTE_IP"; then
    log "BŁĄD: Nie udało się skopiować klucza"
    exit 1
fi

# Test połączenia
log "Testuję połączenie..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_IP" echo "Test OK"; then
    log "Konfiguracja zakończona sukcesem"
else
    log "BŁĄD: Test połączenia nie powiódł się"
    exit 1
fi