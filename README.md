# Red Hat Developer Hub 2.1 avec authentification Keycloak/OIDC - Installation avec Kustomize

![Red Hat Developer Hub](https://img.shields.io/badge/Red_Hat_Developer_Hub-2.1-EE0000?style=for-the-badge&logo=redhat&logoColor=white)
![OpenShift](https://img.shields.io/badge/OpenShift-4.22-EE0000?style=for-the-badge&logo=redhatopenshift&logoColor=white)
![Red Hat build of Keycloak](https://img.shields.io/badge/RHBK-26.6-4D4D4D?style=for-the-badge&logo=keycloak&logoColor=white)

Ce dépôt contient les manifests Kubernetes pour déployer Red Hat Developer Hub (RHDH) avec authentification Keycloak.

> [!IMPORTANT]
> **Version : Red Hat Developer Hub 2.1** (opérateur `rhdh-operator.v2.1.0`, canal `fast-2.1`)
>
> La configuration pour RHDH 1.9 est disponible dans la branche [`rhdh-1.9`](../../tree/rhdh-1.9).

## Fonctionnalités incluses

- ✅ Authentification OIDC via Keycloak
- ✅ Synchronisation automatique des utilisateurs/groupes depuis Keycloak
- ✅ RBAC (Role-Based Access Control) configuré
- ✅ Plugins dynamiques (activés depuis le catalog index RHDH via `ref://`) :
  - OIDC Auth Provider
  - Keycloak Catalog Backend Module
  - RBAC Plugin
- ✅ Secrets lus au runtime depuis un Secret Kubernetes (jamais écrits dans les ConfigMaps)
- ✅ Base de données locale (PostgreSQL embarqué)
- ✅ Route OpenShift automatique

## Versions testées

- OpenShift: 4.22.22
- RHDH Operator: 2.1.0 (canal `fast-2.1`)
- RHBK (pour l'authentification): 26.6.9-opr.1

## 📁 Structure

```
.
├── operator/                   # Installation de l'opérateur RHDH (OLM)
│   ├── kustomization.yaml
│   └── operator.yaml           # Namespace + OperatorGroup + Subscription fast-2.1
├── base/                       # Manifests de base Kustomize (instance RHDH)
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── app-config.yaml
│   ├── dynamic-plugins.yaml
│   ├── rbac-policy.yaml
│   └── backstage-instance.yaml
├── keycloak-rhdh-realm-simple.json
├── .env.example                # Template des variables d'environnement
├── install.sh                  # Script d'installation
└── README.md
```

## 🚀 Installation

### Prérequis

- OpenShift CLI (`oc`) installé et connecté à votre cluster (cluster-admin pour installer l'opérateur)
- Instance Keycloak (Red Hat build of Keycloak) avec le realm RHDH importé (voir [Configuration Keycloak](#-configuration-keycloak))
- `envsubst` disponible (généralement inclus avec `gettext`)

### Étapes d'installation

#### 1. Installer l'opérateur RHDH

L'opérateur RHDH ne supporte que le mode d'installation **AllNamespaces** : il est installé dans un
namespace dédié `rhdh-operator` avec un OperatorGroup sans `targetNamespaces`.

```bash
oc apply -k operator/

# Attendre que l'opérateur soit prêt (PHASE = Succeeded)
oc get csv -n rhdh-operator -w
```

> ⚠️ Le canal `fast` pointe sur la 1.10.x. Pour RHDH 2.1, utiliser le canal **`fast-2.1`** (canal par défaut).

Via la console : *Ecosystem > Software Catalog* (ou *Operators > OperatorHub*), chercher « Red Hat Developer Hub »,
choisir le canal `fast-2.1` et le mode « All namespaces ».

#### 2. Configuration des variables d'environnement

```bash
cp .env.example .env
```

Éditez `.env` avec vos valeurs :

```bash
export NAMESPACE=rhdh-demo
export CLUSTER_APPS_DOMAIN=apps.mon-cluster.example.com
export BACKEND_SECRET=$(openssl rand -base64 32)
export KEYCLOAK_BASE=https://keycloak.apps.mon-cluster.example.com
export KEYCLOAK_REALM=rhdh
export KEYCLOAK_CLIENT_ID=rhdh
export KEYCLOAK_CLIENT_SECRET=xxxxx
```

#### 3. Installation

**Option A : script d'installation (recommandé)**

```bash
./install.sh        # demande confirmation
./install.sh -y     # sans confirmation
```

Le script :
1. vérifie que l'opérateur est prêt dans `rhdh-operator` ;
2. crée le namespace et le Secret `rhdh-secrets` (variables `BACKEND_SECRET`, `OIDC_*`, `KEYCLOAK_*`) ;
3. applique les manifests en ne substituant que `${NAMESPACE}` et `${APP_BASE_URL}` ;
4. attend que RHDH soit déployé.

**Option B : installation manuelle**

```bash
source .env
export APP_BASE_URL=https://backstage-backstage-${NAMESPACE}.${CLUSTER_APPS_DOMAIN}
oc create namespace ${NAMESPACE}
oc -n ${NAMESPACE} create secret generic rhdh-secrets \
  --from-literal=BACKEND_SECRET="$BACKEND_SECRET" \
  --from-literal=OIDC_METADATA_URL="${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration" \
  --from-literal=OIDC_CLIENT_ID="$KEYCLOAK_CLIENT_ID" \
  --from-literal=OIDC_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
  --from-literal=KEYCLOAK_BASE_URL="$KEYCLOAK_BASE" \
  --from-literal=KEYCLOAK_LOGIN_REALM="$KEYCLOAK_REALM" \
  --from-literal=KEYCLOAK_REALM="$KEYCLOAK_REALM" \
  --from-literal=KEYCLOAK_CLIENT_ID="$KEYCLOAK_CLIENT_ID" \
  --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET"

# ⚠️ Substitution limitée : les autres ${VAR} sont résolues par RHDH au runtime
oc kustomize ./base | envsubst '$NAMESPACE $APP_BASE_URL' | oc apply -f -
```

#### 4. Vérification

```bash
# Statut du Backstage CR et des pods
oc get backstage,pods -n ${NAMESPACE}

# Plugins dynamiques installés (ref:// résolus vers registry.access.redhat.com/rhdh/...)
oc logs deployment/backstage-backstage -n ${NAMESPACE} -c install-dynamic-plugins | grep -v "Skipping disabled"

# Plugins chargés et synchro Keycloak
oc logs deployment/backstage-backstage -n ${NAMESPACE} -c backstage-backend | grep -iE "loaded dynamic|auth provider|keycloak"

# URL
oc get route -n ${NAMESPACE}
```

## 🔧 Configuration Keycloak

### Import du Realm RHDH

Le fichier `keycloak-rhdh-realm-simple.json` contient une configuration complète pour RHDH incluant :
- Un realm `rhdh` pré-configuré
- Un utilisateur admin de test
- Un client OIDC `rhdh` avec les bons paramètres
- Un service account pour la synchronisation des utilisateurs

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

### Fichier `.env`

| Variable                 | Description                            | Exemple                                                                    |
| ------------------------ | -------------------------------------- | -------------------------------------------------------------------------- |
| `NAMESPACE`              | Namespace OpenShift                    | `rhdh-demo`                                                                |
| `CLUSTER_APPS_DOMAIN`    | Domaine des apps du cluster            | `apps.mon-cluster.example.com`                                             |
| `BACKEND_SECRET`         | Secret pour l'authentification backend | Généré avec `openssl rand -base64 32`                                      |
| `KEYCLOAK_BASE`          | URL de base Keycloak                   | `https://keycloak.example.com`                                             |
| `KEYCLOAK_REALM`         | Nom du realm Keycloak                  | `rhdh`                                                                     |
| `KEYCLOAK_CLIENT_ID`     | ID du client Keycloak                  | `rhdh`                                                                     |
| `KEYCLOAK_CLIENT_SECRET` | Secret du client Keycloak              | `xxxxx`                                                                    |
| `APP_BASE_URL`           | URL de l'application (auto-construite) | Calculé: `https://backstage-backstage-${NAMESPACE}.${CLUSTER_APPS_DOMAIN}` |

### Secret `rhdh-secrets` (créé par `install.sh`)

| Clé | Source |
| --- | --- |
| `BACKEND_SECRET` | `BACKEND_SECRET` |
| `OIDC_METADATA_URL` | `${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration` |
| `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | `KEYCLOAK_CLIENT_ID` / `KEYCLOAK_CLIENT_SECRET` |
| `KEYCLOAK_BASE_URL` | `KEYCLOAK_BASE` |
| `KEYCLOAK_LOGIN_REALM` / `KEYCLOAK_REALM` | `KEYCLOAK_REALM` |
| `KEYCLOAK_CLIENT_ID` / `KEYCLOAK_CLIENT_SECRET` | idem |

## 🔐 Sécurité

⚠️ **Important** :

- Ne commitez JAMAIS le fichier `.env` avec vos secrets (déjà dans `.gitignore`)
- Les secrets sont injectés dans le pod depuis le Secret `rhdh-secrets` (jamais dans les ConfigMaps)
- Utilisez des secrets externes (Vault, External Secrets, Sealed Secrets) en production
- Générez un `BACKEND_SECRET` fort avec : `openssl rand -base64 32`

## 🧹 Désinstallation

```bash
source .env
oc delete namespace ${NAMESPACE}

# Optionnel : désinstaller l'opérateur
oc delete -k operator/
```

## 📚 Ressources

- [Red Hat Developer Hub Documentation](https://docs.redhat.com/en/documentation/red_hat_developer_hub/)
- [Installation des plugins dynamiques (ref://, {{inherit}}, catalog index)](https://github.com/redhat-developer/rhdh/blob/release-2.1/docs/dynamic-plugins/installing-plugins.md)
- [Plugins supportés / communautaires (rhdh-plugin-export-overlays)](https://github.com/redhat-developer/rhdh-plugin-export-overlays)
- [Backstage Documentation](https://backstage.io/docs)
- [Keycloak Documentation](https://www.keycloak.org/documentation)

## 🐛 Troubleshooting

### Les pods ne démarrent pas

```bash
oc describe backstage backstage -n ${NAMESPACE}
oc logs -n ${NAMESPACE} deployment/backstage-backstage -c install-dynamic-plugins
oc logs -n ${NAMESPACE} deployment/backstage-backstage -c backstage-backend
```

### Plugin introuvable (`ref://...`)

Le nom après `ref://` doit correspondre exactement au nom d'image d'un plugin du catalog index.
Vérifiez la liste dans les logs du conteneur `install-dynamic-plugins`.

### Page de connexion sans provider / erreur d'authentification Keycloak

Vérifiez :

- Que le plugin `backstage-plugin-auth-backend-module-oidc-provider` est bien activé (log `Configuring auth provider: oidc`)
- Les URLs dans `KEYCLOAK_BASE` et `APP_BASE_URL` sont correctes
- Le client secret est valide
- Les redirect URIs sont configurés dans Keycloak
- Le realm existe et est actif

### La route n'est pas accessible

```bash
oc get route -n ${NAMESPACE}
oc describe route backstage -n ${NAMESPACE}
```
