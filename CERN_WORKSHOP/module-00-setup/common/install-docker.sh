#!/bin/bash
set -e

# Couleurs pour l'affichage
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Début de l'installation de Docker ===${NC}"

# Vérifier si script est lancé en root ou sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ce script doit être lancé avec sudo.${NC}"
  exit 1
fi

echo -e "${BLUE}[1/5] Mise à jour des paquets et installation des dépendances...${NC}"
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

echo -e "${BLUE}[2/5] Ajout de la clé GPG et du dépôt officiel Docker...${NC}"
mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo -e "${BLUE}[3/5] Installation de Docker Engine...${NC}"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo -e "${BLUE}[4/5] Configuration des permissions utilisateur...${NC}"
# Récupérer l'utilisateur réel (SUDO_USER) s'il existe, sinon l'utilisateur courant
REAL_USER=${SUDO_USER:-$USER}

if [ "$REAL_USER" != "root" ]; then
    usermod -aG docker "$REAL_USER"
    echo -e "${GREEN}Utilisateur '$REAL_USER' ajouté au groupe docker.${NC}"
    echo -e "${RED}IMPORTANT : Vous devez vous déconnecter et reconnecter (ou lancer 'newgrp docker') pour appliquer les changements de groupe.${NC}"
else
    echo -e "${BLUE}Installation faite en tant que root pur, pas d'ajout au groupe docker nécessaire.${NC}"
fi

echo -e "${BLUE}[5/5] Installation de Cockpit (Web Terminal)...${NC}"
apt-get install -y cockpit
systemctl enable --now cockpit.socket
echo -e "${GREEN}Cockpit installé et activé sur le port 9090.${NC}"

echo -e "${GREEN}=== Installation terminée avec succès ! ===${NC}"
