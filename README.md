# Le Druide Antavirus

> Scanneur et diagnostic PC français, bienveillant et respectueux de la vie privée.

[![Site](https://img.shields.io/badge/site-antavirus.fr-1F4D3A)](https://antavirus.fr)
[![Édité par](https://img.shields.io/badge/par-Triskell%20Studio-C8A45C)](https://triskellstudio.fr)
[![Licence](https://img.shields.io/badge/licence-AGPL--3.0-green)](LICENSE)
[![Made in France](https://img.shields.io/badge/Made%20in-France-blue)](https://fr.wikipedia.org/wiki/France)

**Le Druide Antavirus** analyse votre PC Windows sans rien modifier, vous explique en français clair ce qui ralentit la machine ou pose un risque, et vous propose des actions en un clic pour y remédier.

## Pourquoi ce logiciel

Les grands antivirus américains sont anxiogènes, gavés de publicité, et revendent des données utilisateurs. **Le Druide Antavirus** est l'inverse :

- 🇫🇷 **Édité en France** par Triskell Studio
- 🚫 **Sans publicité, sans tracking caché** — la page Transparence détaille chaque octet envoyé
- 🤖 **Assistant IA optionnel (L'Œil d'Antavirus)** — soit votre propre clé Anthropic/OpenAI/Google/Mistral/DeepSeek (BYOK, illimité, ne quitte pas votre PC), soit la clé Triskell avec quota
- 🔒 **Aucune revente de données** — le code est ouvert, vérifiez par vous-même
- 💬 **Langage humain** — pas de jargon, pas d'alarmisme, pas de majuscules en panique

## Ce que le logiciel détecte

| Catégorie | Vérifications |
|---|---|
| **Démarrage** | Programmes lancés au démarrage Windows, durée du dernier boot, redémarrages en attente |
| **Disque** | Espace libre, SMART, températures, erreurs NTFS, usure SSD |
| **Mémoire** | Saturation RAM, applications gourmandes |
| **Mises à jour** | Windows Update en attente, ancienneté des signatures Defender |
| **Sécurité** | Defender, antivirus tiers, services critiques |
| **Navigateurs** | Extensions Chrome/Edge/Brave/Firefox aux permissions sensibles |
| **Maintenance** | Caches navigateurs, fichiers temporaires, espace récupérable |
| **Réseau** | Adaptateurs, plan d'alimentation, événements critiques |

## Téléchargement

Le binaire signé est distribué sur **[antavirus.fr](https://antavirus.fr)**.

- Plateforme : **Windows 10 et 11 (64-bit)**
- Deux variantes au choix :
  - **`LeDruideAntavirus-Setup-vX.Y.Z.exe`** (~2 Mo) — installateur recommandé. Crée un raccourci bureau + entrée menu Démarrer, désinstallable depuis Paramètres > Applications.
  - **`LeDruideAntavirus-vX.Y.Z.exe`** (~360 Ko) — binaire portable, zéro installation.

Si vous préférez compiler vous-même depuis ce dépôt, suivez la section [Compilation](#compilation).

## Vérification de l'intégrité

Chaque release publie le hash SHA256 du binaire. Vérifiez avant d'exécuter :

```powershell
Get-FileHash -Algorithm SHA256 .\LeDruideAntavirus.exe
```

Comparez avec le hash publié sur la [page Releases](../../releases) ou sur [antavirus.fr/transparence](https://antavirus.fr/transparence).

## Confidentialité

**Le scan tourne 100 % localement.** Aucune donnée de fichier ne quitte votre machine.

Seul l'assistant IA (optionnel) communique avec l'extérieur :
- Si vous configurez votre propre clé API (BYOK) → l'app appelle directement Anthropic/OpenAI/Google/Mistral/DeepSeek. Triskell n'a aucune visibilité.
- Si vous utilisez la clé Triskell → un proxy backend Triskell relaie l'appel pour appliquer les quotas free (3 questions par scan + 10 par mois).

**Avant tout envoi à l'IA**, le rapport est anonymisé :
- Chemins utilisateur `C:\Users\jordan\…` → `C:\Users\<USER>\…`
- Nom de la machine → `<PC>`
- Adresses MAC → `<MAC>`
- Adresses IP privées → `<IP_PRIVEE>`
- Numéros de série de disques → `<SN>`

La fonction `ConvertTo-AnonymizedText` dans `src/le-druide-antavirus.ps1` est auditable.

## Compilation depuis les sources

### Prérequis

- Windows 10 ou 11 (64-bit)
- PowerShell 5.1+ (inclus dans Windows)
- Module `ps2exe` (gratuit, communautaire) :
  ```powershell
  Install-Module -Name ps2exe -Scope CurrentUser
  ```

### Build

**1. Compiler le binaire portable** (avec ps2exe) :

```powershell
Import-Module ps2exe
Invoke-PS2EXE `
    -inputFile  '.\src\le-druide-antavirus.ps1' `
    -outputFile '.\dist\LeDruideAntavirus-v1.3.2.exe' `
    -iconFile   '.\assets\druide-antavirus.ico' `
    -title      'Le Druide Antavirus' `
    -company    'Triskell Studio' `
    -product    'Le Druide Antavirus' `
    -version    '1.3.2.0' `
    -copyright  '(C) 2026 Triskell Studio' `
    -noConsole `
    -requireAdmin
```

**2. Compiler l'installateur** (avec [Inno Setup 6](https://jrsoftware.org/isdl.php)) :

```powershell
& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' '.\installer\installer.iss'
```

L'installateur final est généré dans `.\dist\LeDruideAntavirus-Setup-v1.3.2.exe`. Adaptez la version dans `installer/installer.iss` (`#define MyAppVersion`) pour publier une nouvelle release.

### Exécution directe (sans compilation)

```powershell
powershell -ExecutionPolicy Bypass -File .\src\le-druide-antavirus.ps1
```

## Structure du dépôt

```
le-druide-antavirus/
├── src/
│   └── le-druide-antavirus.ps1   # Source unique (moteur + UI + intégration IA)
├── installer/
│   └── installer.iss             # Configuration Inno Setup pour le binaire setup
├── assets/
│   ├── druide-antavirus.ico       # Icône Windows multi-tailles
│   └── logo.png                   # Logo héraldique (référence)
├── README.md
├── LICENSE                        # AGPL-3.0
├── SECURITY.md                    # Politique de divulgation des failles
└── CHANGELOG.md                   # Historique des versions
```

## Architecture

Le code est volontairement monolithique (un seul `.ps1`) pour faciliter l'audit et la portabilité. Les grandes sections :

- **Lignes 1–250** : configuration, seuils, primitives (`Add-Finding`, `Write-Result`)
- **Lignes 250–1000** : moteur de scan (les fonctions `Test-*`)
- **Lignes 1000–1500** : pipeline `Invoke-AllChecks` + `Invoke-ExpressChecks`
- **Lignes 1500–2300** : intégration IA (5 providers) + anonymisation
- **Lignes 2300–4000** : interface graphique WinForms (onboarding, scan, résultats, historique, planification)

## Contribuer

Les contributions sont bienvenues, en particulier :

- Nouveaux **checks de diagnostic** (caches d'applications, points de restauration, BitLocker, etc.)
- Amélioration de la **détection d'extensions douteuses** (croisement avec listes publiques)
- **Traductions** (l'app est aujourd'hui 100 % en français)
- Améliorations d'**accessibilité** (lecteurs d'écran, contrastes)

Merci de :

1. Ouvrir une **issue** avant une grosse pull request, pour discuter de l'approche
2. Garder le **ton du druide** dans les messages utilisateurs (cf le brief produit, section ton)
3. Ne **rien ajouter qui envoie des données à l'extérieur** sans consentement explicite

## Licence

Le code est publié sous licence **AGPL-3.0**. Voir [LICENSE](LICENSE).

En résumé :
- ✅ Vous pouvez l'utiliser, le copier, le modifier
- ✅ Vous pouvez le redistribuer
- ⚠️ Si vous le distribuez modifié, **vous devez aussi publier vos modifications sous AGPL-3.0**
- ⚠️ Si vous l'utilisez via un service en ligne, vous devez aussi publier les modifications du service

Cette licence protège l'écosystème ouvert tout en permettant à Triskell Studio de maintenir une version commerciale (Pro).

La marque « Le Druide Antavirus », le logo héraldique du druide, et le nom « Triskell Studio » sont des marques de Triskell Studio. Leur usage hors du cadre d'utilisation directe du logiciel nécessite une autorisation écrite.

## Liens

- Site officiel : [antavirus.fr](https://antavirus.fr)
- Page Transparence : [antavirus.fr/transparence](https://antavirus.fr/transparence)
- Politique de confidentialité : [antavirus.fr/confidentialite](https://antavirus.fr/confidentialite)
- Éditeur : [Triskell Studio](https://triskellstudio.fr)
- Contact : [contact@antavirus.fr](mailto:contact@antavirus.fr)

---

*Édité avec soin en France par [Triskell Studio](https://triskellstudio.fr).*
