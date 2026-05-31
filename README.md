# Red Hat Developer Hub avec authentification Keycloak/OIDC - Installation avec Kustomize

Ce dépôt contient les manifests Kubernetes pour déployer Red Hat Developer Hub (RHDH) avec authentification Keycloak.

## Fonctionnalités incluses

- ✅ Authentification OIDC via Keycloak
- ✅ Synchronisation automatique des utilisateurs/groupes depuis Keycloak
- ✅ RBAC (Role-Based Access Control) configuré
- ✅ Plugins dynamiques :
  - Keycloak Catalog Backend Module
  - RBAC Plugin
- ✅ Base de données locale (PostgreSQL embarqué)
- ✅ Route OpenShift automatique

## Versions testées

- OpenShift: 4.21.6
- RHDH Operator: 1.9.4
- RHBK (pour l'authentification): 26.4.12-opr.1

## 📁 Structure

```
.
├── base/                       # Manifests de base Kustomize
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── secret.yaml
│   ├── app-config.yaml
│   ├── dynamic-plugins.yaml
│   ├── rbac-policy.yaml
│   └── backstage-instance.yaml
├── .env.example                # Template des variables d'environnement
├── install.sh                  # Script d'installation
└── README.md
```

## 🚀 Installation

### Prérequis

- OpenShift CLI (`oc`) installé et connecté à votre cluster
- Instance Keycloak configurée avec un client OIDC
- `envsubst` disponible (généralement inclus avec `gettext`)

### Étapes d'installation

#### 1. Créer le namespace et installer l'opérateur

```bash
# 1. Créer le namespace
oc new-project rhdh-demo

# 2. Installer l'opérateur RHDH depuis OperatorHub
# Via la console OpenShift:
#   - Operators > OperatorHub
#   - Chercher "Red Hat Developer Hub"
#   - Installer dans le namespace "rhdh-demo"

# Ou via CLI:
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhdh-operator
  namespace: rhdh-demo
spec:
  channel: fast
  name: rhdh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# 3. Attendre que l'opérateur soit prêt
oc get csv -n rhdh-demo -w
```

#### 2. Configuration des variables d'environnement

Copiez le fichier d'exemple et configurez vos valeurs :

```bash
cp .env.example .env
```

Éditez `.env` avec vos valeurs :

```bash
# Exemple de valeurs
export NAMESPACE=rhdh-demo
export CLUSTER_APPS_DOMAIN=apps.sno4.anissetiouajni.com
export KEYCLOAK_BASE=https://kc-rhbk.apps.sno4.anissetiouajni.com
```

#### 3. Charger les variables

```bash
source .env
```

#### 4. Installation

**Option A : Utiliser le script d'installation (recommandé)**

```bash
chmod +x install.sh
./install.sh
```

**Option B : Installation manuelle**

```bash
oc kustomize ./base | envsubst | oc apply -f -
```

#### 5. Vérification

```bash
# Vérifier le déploiement
oc get all -n ${NAMESPACE}

# Suivre le statut du Backstage CR
oc get backstage -n ${NAMESPACE} -w

# Récupérer l'URL de la route
oc get route -n ${NAMESPACE}
```

## 🔧 Configuration Keycloak

### Import du Realm RHDH

Le fichier `keycloak-rhdh-realm-simple.json` contient une configuration complète pour RHDH incluant :
- Un realm `rhdh` pré-configuré
- Un utilisateur admin de test
- Un client OIDC `rhdh` avec les bons paramètres
- Un service account pour la synchronisation des utilisateurs

**Pour importer le realm dans Keycloak :**

1. Connectez-vous à la console admin Keycloak (voir [repo rhbk](https://github.com/atiouajni/rhbk) pour déployer Keycloak)
2. Dans le menu déroulant des realms (en haut à gauche), cliquez sur **"Create Realm"**
3. Cliquez sur **"Browse"** pour sélectionner le fichier `keycloak-rhdh-realm-simple.json`
4. Cliquez sur **"Create"**

### Credentials créés par l'import

#### Utilisateur Admin (pour tester RHDH)
- **Username:** `admin`
- **Password:** `admin123`
- **Email:** `admin@example.com`
- **Nom complet:** Admin User

#### Client OIDC
- **Client ID:** `rhdh`
- **Client Secret:** `my-new-rhdh-secret-12345`
- **Redirect URIs:** `*` (configuré pour accepter toutes les URLs)

⚠️ **IMPORTANT - Sécurité :**
- Ces credentials sont pour **DEV/TEST uniquement**
- En production :
  - Changez le mot de passe admin
  - Générez un nouveau client secret : `openssl rand -base64 32`
  - Configurez des redirect URIs spécifiques (pas `*`)
  - Activez la protection contre les attaques par force brute
  - Utilisez des certificats TLS valides

### Service Account

Un service account `service-account-rhdh` est automatiquement créé avec les permissions suivantes :
- `view-users` : Lecture des utilisateurs
- `view-clients` : Lecture des clients
- `view-realm` : Lecture du realm
- `query-users` : Requêtes sur les utilisateurs
- `query-groups` : Requêtes sur les groupes

Ce compte permet à RHDH de synchroniser automatiquement les utilisateurs et groupes depuis Keycloak.

## 📝 Variables d'environnement


| Variable                 | Description                            | Exemple                                                                    |
| ------------------------ | -------------------------------------- | -------------------------------------------------------------------------- |
| `NAMESPACE`              | Namespace OpenShift                    | `rhdh-demo`                                                                |
| `CLUSTER_APPS_DOMAIN`    | Domaine des apps du cluster            | `apps.sno4.anissetiouajni.com`                                             |
| `BACKEND_SECRET`         | Secret pour l'authentification backend | Généré avec `openssl rand -base64 32`                                      |
| `KEYCLOAK_BASE`          | URL de base Keycloak                   | `https://keycloak.example.com`                                             |
| `KEYCLOAK_REALM`         | Nom du realm Keycloak                  | `rhdh`                                                                     |
| `KEYCLOAK_CLIENT_ID`     | ID du client Keycloak                  | `rhdh`                                                                     |
| `KEYCLOAK_CLIENT_SECRET` | Secret du client Keycloak              | `xxxxx`                                                                    |
| `APP_BASE_URL`           | URL de l'application (auto-construite) | Calculé: `https://backstage-backstage-${NAMESPACE}.${CLUSTER_APPS_DOMAIN}` |


## 🔐 Sécurité

⚠️ **Important** :

- Ne commitez JAMAIS le fichier `.env` avec vos secrets
- Le fichier `.env` est déjà dans `.gitignore`
- Utilisez des secrets externes (Vault, Sealed Secrets) en production
- Générez un `BACKEND_SECRET` fort avec : `openssl rand -base64 32`

## 🧹 Désinstallation

```bash
source .env
oc delete namespace ${NAMESPACE}
```

## 📚 Ressources

- [Red Hat Developer Hub Documentation](https://access.redhat.com/documentation/en-us/red_hat_developer_hub)
- [Backstage Documentation](https://backstage.io/docs)
- [Keycloak Documentation](https://www.keycloak.org/documentation)

## 🐛 Troubleshooting

### Les pods ne démarrent pas

```bash
oc describe backstage backstage -n ${NAMESPACE}
oc logs -n ${NAMESPACE} -l app.kubernetes.io/name=backstage
```

### Erreur d'authentification Keycloak

Vérifiez :

- Les URLs dans `KEYCLOAK_BASE` et `APP_BASE_URL` sont correctes
- Le client secret est valide
- Les redirect URIs sont configurés dans Keycloak
- Le realm existe et est actif

### La route n'est pas accessible

```bash
oc get route -n ${NAMESPACE}
oc describe route backstage -n ${NAMESPACE}
```

