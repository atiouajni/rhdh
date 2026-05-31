#!/bin/bash

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Vérifier les prérequis
info "Vérification des prérequis..."

command -v oc >/dev/null 2>&1 || error "oc CLI n'est pas installé"
command -v envsubst >/dev/null 2>&1 || error "envsubst n'est pas installé (installez le package gettext)"

# Vérifier que l'utilisateur est connecté à OpenShift
oc whoami >/dev/null 2>&1 || error "Vous n'êtes pas connecté à OpenShift. Utilisez 'oc login' d'abord."

# Charger les variables d'environnement
if [ ! -f .env ]; then
    warning "Le fichier .env n'existe pas. Utilisation de .env.example..."
    if [ ! -f .env.example ]; then
        error "Aucun fichier .env ou .env.example trouvé"
    fi
    cp .env.example .env
    warning "Fichier .env créé. Veuillez le modifier si nécessaire et relancer le script."
    exit 0
fi

info "Chargement des variables d'environnement depuis .env..."
source .env

# Vérifier que les variables sont définies
REQUIRED_VARS=(
    "NAMESPACE"
    "CLUSTER_APPS_DOMAIN"
    "BACKEND_SECRET"
    "KEYCLOAK_BASE"
    "KEYCLOAK_REALM"
    "KEYCLOAK_CLIENT_ID"
    "KEYCLOAK_CLIENT_SECRET"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        error "La variable $var n'est pas définie dans .env"
    fi
done

# Construire APP_BASE_URL automatiquement
export APP_BASE_URL=https://backstage-backstage-${NAMESPACE}.${CLUSTER_APPS_DOMAIN}

info "Configuration:"
echo "  - Namespace: $NAMESPACE"
echo "  - Domaine: $CLUSTER_APPS_DOMAIN"
echo "  - Keycloak: $KEYCLOAK_BASE"
echo "  - App URL: $APP_BASE_URL"

# Demander confirmation
read -p "Continuer avec cette configuration? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warning "Installation annulée"
    exit 0
fi

# Vérifier que le namespace existe
info "Vérification du namespace..."
if ! oc get project $NAMESPACE >/dev/null 2>&1; then
    error "Le namespace $NAMESPACE n'existe pas. Créez-le d'abord avec: oc new-project $NAMESPACE"
fi

# Vérifier que le RHDH Operator est installé dans le namespace
info "Vérification de l'installation du RHDH Operator dans le namespace $NAMESPACE..."
if ! oc get csv -n $NAMESPACE | grep -q rhdh-operator 2>/dev/null; then
    error "Le RHDH Operator n'est pas installé dans le namespace $NAMESPACE. Installez-le depuis OperatorHub avant de continuer."
fi
info "✓ RHDH Operator détecté"

# Déployer les ressources
info "Déploiement des ressources..."
oc kustomize ./base | envsubst | oc apply -f -

# Attendre que les ressources soient prêtes
info "Attente du démarrage de RHDH..."
oc wait --for=condition=Deployed backstage/backstage -n $NAMESPACE --timeout=10m || warning "Timeout en attendant RHDH"

# Afficher le statut
info "Statut du déploiement:"
oc get pods -n $NAMESPACE

# Afficher l'URL d'accès
info ""
info "✅ Déploiement terminé avec succès!"
info ""
info "URL d'accès RHDH: $APP_BASE_URL"
info ""
info "Commandes utiles:"
echo "  - Voir les logs: oc logs -f deployment/backstage-backstage -n $NAMESPACE"
echo "  - Voir les pods: oc get pods -n $NAMESPACE"
echo "  - Voir la route: oc get route -n $NAMESPACE"
