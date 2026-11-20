#!/bin/bash
# Installation de Red Hat Developer Hub 2.1 avec authentification Keycloak/OIDC.
# Usage : ./install.sh [-y]   (-y : pas de confirmation)
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

ASSUME_YES=false
[[ "${1:-}" == "-y" ]] && ASSUME_YES=true
cd "$(dirname "$0")"

info "Vérification des prérequis..."
command -v oc >/dev/null 2>&1       || error "oc CLI n'est pas installé"
command -v envsubst >/dev/null 2>&1 || error "envsubst n'est pas installé (package gettext)"
oc whoami >/dev/null 2>&1           || error "Non connecté à OpenShift. Utilisez 'oc login' d'abord."

if [ ! -f .env ]; then
    cp .env.example .env
    warning "Fichier .env créé depuis .env.example : complétez-le puis relancez le script."
    exit 0
fi
info "Chargement des variables depuis .env..."
# shellcheck disable=SC1091
source .env

for var in NAMESPACE CLUSTER_APPS_DOMAIN BACKEND_SECRET KEYCLOAK_BASE KEYCLOAK_REALM KEYCLOAK_CLIENT_ID KEYCLOAK_CLIENT_SECRET; do
    [ -n "${!var:-}" ] || error "La variable $var n'est pas définie dans .env"
done
export NAMESPACE
export APP_BASE_URL="https://backstage-backstage-${NAMESPACE}.${CLUSTER_APPS_DOMAIN}"

info "Configuration :"
echo "  - Namespace : $NAMESPACE"
echo "  - Keycloak  : $KEYCLOAK_BASE (realm $KEYCLOAK_REALM)"
echo "  - URL RHDH  : $APP_BASE_URL"
if ! $ASSUME_YES; then
    read -p "Continuer avec cette configuration ? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || { warning "Installation annulée"; exit 0; }
fi

info "Vérification de l'opérateur RHDH (namespace rhdh-operator)..."
oc get csv -n rhdh-operator 2>/dev/null | grep rhdh-operator | grep -q Succeeded \
    || error "Opérateur RHDH absent ou pas prêt. Installez-le : oc apply -k operator/"
info "✓ $(oc get csv -n rhdh-operator -o name | grep rhdh-operator)"

info "Namespace $NAMESPACE..."
oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - >/dev/null

info "Secret rhdh-secrets (lu par RHDH au runtime, jamais écrit dans les ConfigMaps)..."
oc -n "$NAMESPACE" create secret generic rhdh-secrets \
    --from-literal=BACKEND_SECRET="$BACKEND_SECRET" \
    --from-literal=OIDC_METADATA_URL="${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration" \
    --from-literal=OIDC_CLIENT_ID="$KEYCLOAK_CLIENT_ID" \
    --from-literal=OIDC_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
    --from-literal=KEYCLOAK_BASE_URL="$KEYCLOAK_BASE" \
    --from-literal=KEYCLOAK_LOGIN_REALM="$KEYCLOAK_REALM" \
    --from-literal=KEYCLOAK_REALM="$KEYCLOAK_REALM" \
    --from-literal=KEYCLOAK_CLIENT_ID="$KEYCLOAK_CLIENT_ID" \
    --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
    --dry-run=client -o yaml | oc apply -f -

info "Déploiement des ressources..."
# Substitution limitée : les autres ${VAR} doivent rester pour être résolues par RHDH
oc kustomize ./base | envsubst '$NAMESPACE $APP_BASE_URL' | oc apply -f -

info "Attente du démarrage de RHDH (jusqu'à 10 min)..."
oc -n "$NAMESPACE" wait --for=condition=Deployed backstage/backstage --timeout=10m \
    || warning "Timeout en attendant RHDH"
oc -n "$NAMESPACE" rollout status deployment/backstage-backstage --timeout=10m \
    || warning "Le déploiement n'est pas encore prêt"

oc get pods -n "$NAMESPACE"
info "✅ Déploiement terminé. URL : $APP_BASE_URL"
echo "  - Logs : oc logs -f deployment/backstage-backstage -n $NAMESPACE"
echo "  - Plugins installés : oc logs deployment/backstage-backstage -n $NAMESPACE -c install-dynamic-plugins"
