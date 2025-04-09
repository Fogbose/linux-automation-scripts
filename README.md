# 🛠️ Linux Automation Scripts

Une collection de scripts Bash d'automatisation sur Linux (Fedora).

Ce projet regroupe des scripts shell simples, reproductibles et bien documentés pour automatiser des tâches.

---

## 📌 Objectifs

- Automatiser des tâches courantes d'administration système
- Offrir des outils modulaires, faciles à comprendre et à adapter
- Promouvoir la documentation et la reproductibilité des actions

---

## 📁 Contenu du dépôt

Le projet est organisé comme suit :

```bash
.
├── scripts/                     # Dossier contenant les scripts
│   └── usb_prepare_secure.sh    # Script pour préparer une clé USB 
├── README.md                    # Documentation principale du projet
├── LICENSE                      # Licence du projet (MIT)
└── CONTRIBUTING.md              # Guide pour contribuer (à venir)
```

---

## 🔐 `usb_prepare_secure.sh` — Préparation d'une clé USB sécurisée

Un script interactif pour créer une clé USB de 124 Go structurée comme suit :

| Partition       | Système de fichiers | Taille  | Usage                          |
|----------------|----------------------|---------|--------------------------------|
| `LIVE`         | FAT32                | 16 Go   | Systèmes live, boot            |
| `DATA_PUBLIC`  | exFAT                | 60 Go   | Partage de fichiers en clair   |
| `DATA_SECURE`  | LUKS + ext4          | 30 Go   | Stockage chiffré               |
| `BACKUPS_APPS` | ext4                 | 18 Go   | Sauvegardes et apps portables  |

### ✅ Fonctionnalités

- Création automatique de la table de partition GPT
- Formatage de chaque partition avec le bon système de fichiers
- Chiffrement via LUKS de la partition `DATA_SECURE`
- Journalisation complète dans `usb_setup.log`
- Détection des erreurs et nettoyage en cas d’interruption

### ⚙️ Prérequis

Les utilitaires suivants doivent être installés (disponibles dans la plupart des distributions) :

```bash
lsblk parted mkfs.vfat mkfs.exfat mkfs.ext4 cryptsetup sudo grep awk sed tee
```

🧪 Un script de vérification automatique des dépendances sera bientôt ajouté.

### 🚀 Utilisation

```bash
chmod +x usb_prepare_secure.sh
./usb_prepare_secure.sh
```

⚠️ Attention : ce script supprime toutes les données du périphérique sélectionné. Utilisez-le avec précaution.

---

## ✅ Fonctionnalités à venir

- Support étdendu : gestion de différentes tailles de clefs USB
- Script de vérification automatique des dépendances

---

## 🤝 Contribuer

Vous êtes les bienvenu·es pour :

- Proposer vos propres scripts ou modules
- Suggérer des améliorations ou optimisations
- Signaler des bugs ou des cas d’usage supplémentaires

Un fichier CONTRIBUTING.md est prévu pour faciliter les contributions à venir.

---

## 📄 Licence

Ce projet est distribué sous licence MIT. Voir le fichier LICENSE pour plus d’informations.

---

## 👤 Auteur

Simon POLET  
Scripts conçus pour des usages pédagogiques et personnels.

---

## 🔗 Ressources utiles

- [cryptsetup / LUKS](https://gitlab.com/cryptsetup/cryptsetup)
- [GNU Parted](https://www.gnu.org/software/parted/)
- [Arch Wiki — File systems](https://wiki.archlinux.org/title/File_systems)
