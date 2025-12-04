#!/bin/bash
set -e

# Versions cibles (compatibles avec le workshop)
KIND_VERSION="v0.30.0"
KUBECTL_VERSION="v1.34.2"
CLUSTERCTL_VERSION="v1.11.1"
HELM_VERSION="v3.19.2"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Installation des outils Kubernetes ===${NC}"

# Vérifier sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[0;31mCe script doit être lancé avec sudo pour écrire dans /usr/local/bin\033[0m"
  exit 1
fi

ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "arm64" ]; then
    ARCH="arm64"
else
    echo "Architecture $ARCH non supportée par ce script simple."
    exit 1
fi

echo -e "${BLUE}[1/5] Installation de Kubectl ($KUBECTL_VERSION)...${NC}"
# curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# chmod +x kubectl
# mv kubectl /usr/local/bin/
#echo -e "${GREEN}Kubectl installé.${NC}"
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
sudo apt-get update
sudo apt-get install -y kubectl

echo -e "${BLUE}[2/5] Installation de Kind ($KIND_VERSION)...${NC}"
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
chmod +x ./kind
mv ./kind /usr/local/bin/kind
echo -e "${GREEN}Kind installé.${NC}"

echo -e "${BLUE}[3/5] Installation de Clusterctl ($CLUSTERCTL_VERSION)...${NC}"
curl -L "https://github.com/kubernetes-sigs/cluster-api/releases/download/${CLUSTERCTL_VERSION}/clusterctl-linux-${ARCH}" -o clusterctl
chmod +x clusterctl
mv clusterctl /usr/local/bin/clusterctl
echo -e "${GREEN}Clusterctl installé.${NC}"

echo -e "${BLUE}[4/5] Installation de Helm ($HELM_VERSION)...${NC}"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh --version $HELM_VERSION
rm get_helm.sh
echo -e "${GREEN}Helm installé.${NC}"

echo -e "${BLUE}[5/5] Installation des outils additionnels & Plugins Krew...${NC}"

# 1. System Tools
apt-get update && apt-get install -y jq tree git

# 2. yq
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH} -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# 3. Krew
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

# Add Krew to PATH for all users (persistently)
if ! grep -q "krew" /etc/profile; then
    echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> /etc/profile
    echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> /etc/bash.bashrc
fi

# Export PATH for current session
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# 4. Plugins
echo "Installation des plugins Kubectl..."
# We run krew as the SUDO_USER if possible to install in their home, 
# otherwise root installs it in root's home.
# Ideally for a workshop, we want the USER to have access.
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)

# Function to run krew as the real user
install_plugin() {
    sudo -u $REAL_USER -H bash -c "export PATH=\"$USER_HOME/.krew/bin:$PATH\"; kubectl krew install $1"
}

# Install Krew for the user as well (since the block above might have run as root)
if [ "$REAL_USER" != "root" ]; then
    sudo -u $REAL_USER -H bash -c "(
      set -x; cd \"\$(mktemp -d)\" &&
      OS=\"\$(uname | tr '[:upper:]' '[:lower:]')\" &&
      ARCH=\"\$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')\" &&
      KREW=\"krew-\${OS}_\${ARCH}\" &&
      curl -fsSLO \"https://github.com/kubernetes-sigs/krew/releases/latest/download/\${KREW}.tar.gz\" &&
      tar zxvf \"\${KREW}.tar.gz\" &&
      ./\"\${KREW}\" install krew
    )"
fi

PLUGINS=(ctx ns slice klock get-all doctor ktop neat status stern view-secret)
for plugin in "${PLUGINS[@]}"; do
    echo " -> Installing $plugin..."
    install_plugin $plugin
done

echo -e "${GREEN}=== Tous les outils sont installés ! ===${NC}"
echo "Veuillez relancer votre terminal ou taper 'source /etc/profile' pour activer Krew."
