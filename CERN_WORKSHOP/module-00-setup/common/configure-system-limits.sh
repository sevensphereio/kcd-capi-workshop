#!/bin/bash

# ==============================================================================
# Module 00: Configuration des Limites Système pour Workshop ClusterAPI
# ==============================================================================
# Ce script configure automatiquement les limites kernel et filesystem pour
# supporter un grand nombre de clusters et containers.
#
# Usage: ./configure-system-limits.sh
# ==============================================================================

set -e  # Arrêt immédiat en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Fonctions utilitaires
# ==============================================================================

print_header() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=================================================${NC}"
}

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# ==============================================================================
# Vérifier les permissions sudo
# ==============================================================================

check_sudo() {
    print_step "Vérification des permissions sudo..."

    if ! sudo -n true 2>/dev/null; then
        print_warning "Ce script nécessite les permissions sudo"
        echo "Veuillez entrer votre mot de passe sudo:"
        sudo -v
    fi

    print_success "Permissions sudo vérifiées"
    echo ""
}

# ==============================================================================
# Détecter le système d'exploitation
# ==============================================================================

detect_os() {
    print_step "Détection du système d'exploitation..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$OS" in
        linux)
            print_success "Système détecté: Linux"
            ;;
        darwin)
            print_success "Système détecté: macOS"
            ;;
        *)
            print_error "Système d'exploitation non supporté: $OS"
            exit 1
            ;;
    esac

    echo ""
}

# ==============================================================================
# Configuration Linux
# ==============================================================================

configure_linux() {
    print_header "Configuration des limites système Linux (Ubuntu 22.04+ / 25.04 Compatible)"
    echo ""

    # Configuration sysctl via /etc/sysctl.d/ (Best Practice for modern systemd)
    print_step "Configuration des paramètres kernel (sysctl.d)..."
    
    SYSCTL_FILE="/etc/sysctl.d/99-capi-workshop.conf"

    cat <<EOF | sudo tee "$SYSCTL_FILE" > /dev/null
# Workshop ClusterAPI - Optimized Limits
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
fs.file-max=2097152
kernel.pid_max=4194304
kernel.threads-max=4194304
net.core.somaxconn=32768
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_max_syn_backlog=8192
vm.max_map_count=262144
EOF

    print_success "Fichier de configuration créé: $SYSCTL_FILE"

    # Appliquer les changements
    print_step "Application des paramètres kernel..."
    # Use --system to load all configs, allow failure for read-only filesystems (containers)
    if sudo sysctl --system; then
        print_success "Paramètres kernel appliqués avec succès"
    else
        print_warning "Certains paramètres n'ont pas pu être appliqués (normal dans un conteneur LXC/Docker)"
    fi

    echo ""

    # Configuration limits.conf
    print_step "Configuration des limites utilisateur (/etc/security/limits.d/)..."
    
    LIMITS_FILE="/etc/security/limits.d/99-capi-workshop.conf"

    cat << 'EOF' | sudo tee "$LIMITS_FILE" > /dev/null
# Workshop ClusterAPI - Limites augmentées
*               soft    nofile          1048576
*               hard    nofile          1048576
*               soft    nproc           unlimited
*               hard    nproc           unlimited
*               soft    memlock         unlimited
*               hard    memlock         unlimited
root            soft    nofile          1048576
root            hard    nofile          1048576
root            soft    nproc           unlimited
root            hard    nproc           unlimited
EOF
    print_success "Fichier de limites créé: $LIMITS_FILE"

    echo ""

    # Configuration Docker systemd
    if command -v docker &> /dev/null; then
        print_step "Configuration des limites Docker (systemd)..."

        sudo mkdir -p /etc/systemd/system/docker.service.d

        cat << 'EOF' | sudo tee /etc/systemd/system/docker.service.d/limits.conf > /dev/null
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
EOF

        print_step "Rechargement de systemd et redémarrage de Docker..."
        sudo systemctl daemon-reload
        sudo systemctl restart docker

        print_success "Docker configuré avec limites augmentées"
    else
        print_warning "Docker non installé, configuration Docker ignorée"
    fi

    echo ""

    print_success "Configuration Linux terminée!"
    print_warning "IMPORTANT: Reconnectez-vous pour que les limites utilisateur prennent effet"
}

# ==============================================================================
# Configuration macOS
# ==============================================================================

configure_macos() {
    print_header "Configuration des limites système macOS"
    echo ""

    print_step "Configuration des limites de fichiers ouverts..."

    # Configuration temporaire (session courante)
    sudo launchctl limit maxfiles 1048576 1048576
    print_success "Limites session courante appliquées"

    # Configuration permanente
    print_step "Création de la configuration permanente..."

    cat << 'EOF' | sudo tee /Library/LaunchDaemons/limit.maxfiles.plist > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>limit.maxfiles</string>
    <key>ProgramArguments</key>
    <array>
      <string>launchctl</string>
      <string>limit</string>
      <string>maxfiles</string>
      <string>1048576</string>
      <string>1048576</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ServiceIPC</key>
    <false/>
  </dict>
</plist>
EOF

    # Charger la configuration
    print_step "Chargement de la configuration..."
    sudo launchctl load -w /Library/LaunchDaemons/limit.maxfiles.plist 2>/dev/null || true

    print_success "Configuration permanente créée"

    echo ""

    print_success "Configuration macOS terminée!"
    print_warning "Vérifiez également les ressources Docker Desktop:"
    echo "  - Docker Desktop → Settings → Resources"
    echo "  - CPUs: 4+ cores"
    echo "  - Memory: 8+ GB"
    echo "  - Swap: 2+ GB"
    echo "  - Disk: 50+ GB"
}

# ==============================================================================
# Vérification de la configuration
# ==============================================================================

verify_configuration() {
    print_header "Vérification de la Configuration"
    echo ""

    if [ "$OS" = "linux" ]; then
        print_step "Limites Kernel:"
        echo "  fs.inotify.max_user_watches = $(sudo sysctl -n fs.inotify.max_user_watches)"
        echo "  fs.inotify.max_user_instances = $(sudo sysctl -n fs.inotify.max_user_instances)"
        echo "  fs.file-max = $(sudo sysctl -n fs.file-max)"
        echo "  kernel.pid_max = $(sudo sysctl -n kernel.pid_max)"
        echo "  net.core.somaxconn = $(sudo sysctl -n net.core.somaxconn)"
        echo ""

        print_step "Limites Utilisateur (après reconnexion):"
        echo "  Fichiers ouverts: $(ulimit -n)"
        echo "  Processus: $(ulimit -u)"
        echo ""

        if command -v docker &> /dev/null; then
            print_step "Docker Info:"
            docker info 2>/dev/null | grep -E "(CPUs|Total Memory|Server Version)" | sed 's/^/  /'
        fi
    elif [ "$OS" = "darwin" ]; then
        print_step "Limites macOS:"
        launchctl limit maxfiles
        echo "  ulimit -n: $(ulimit -n)"
    fi

    echo ""
}

# ==============================================================================
# Afficher les recommandations
# ==============================================================================

show_recommendations() {
    print_header "Recommandations Post-Installation"
    echo ""

    if [ "$OS" = "linux" ]; then
        echo "✅ Actions recommandées:"
        echo "  1. Reconnectez-vous (logout/login) pour appliquer les limites utilisateur"
        echo "  2. Vérifiez avec: ulimit -n (devrait afficher 1048576)"
        echo "  3. Vérifiez Docker: docker info | grep -E '(CPUs|Memory)'"
        echo ""
        echo "✅ Fichiers de backup créés:"
        echo "  - /etc/sysctl.conf.backup.*"
        echo "  - /etc/security/limits.conf.backup.*"
    elif [ "$OS" = "darwin" ]; then
        echo "✅ Actions recommandées:"
        echo "  1. Redémarrez votre Mac pour appliquer les changements permanents"
        echo "  2. Configurez Docker Desktop → Settings → Resources"
        echo "  3. Vérifiez avec: launchctl limit maxfiles"
    fi

    echo ""
    print_success "Configuration terminée avec succès!"
}

# ==============================================================================
# Programme principal
# ==============================================================================

main() {
    # Check for non-interactive flag
    FORCE_YES=false
    for arg in "$@"; do
        if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
            FORCE_YES=true
            break
        fi
    done

    # Only clear if terminal
    if [ -t 1 ]; then clear; fi

    print_header "Configuration des Limites Système - Workshop ClusterAPI"
    echo ""
    echo "Ce script va configurer les limites système optimales pour:"
    echo "  • Surveillance de fichiers (inotify)"
    echo "  • Fichiers ouverts (file descriptors)"
    echo "  • Processus et threads"
    echo "  • Connexions réseau"
    echo "  • Configuration Docker"
    echo ""

    if [ "$FORCE_YES" = false ]; then
        read -p "Voulez-vous continuer? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Configuration annulée"
            exit 0
        fi
    else
        print_step "Mode non-interactif activé (-y). Démarrage..."
    fi

    echo ""

    # Vérifications préalables
    check_sudo
    detect_os

    # Configuration selon l'OS
    if [ "$OS" = "linux" ]; then
        configure_linux
    elif [ "$OS" = "darwin" ]; then
        configure_macos
    fi

    # Vérification
    verify_configuration

    # Recommandations
    show_recommendations
}

# Exécution du programme principal avec tous les arguments passés
main "$@"
