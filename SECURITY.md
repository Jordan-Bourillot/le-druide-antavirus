# Politique de sécurité

Merci de prendre la sécurité de Le Druide Antavirus au sérieux.

## Signaler une faille

**Ne créez pas une issue publique pour signaler une vulnérabilité de sécurité.**

Envoyez plutôt un email à : **contact@antavirus.fr**

Incluez :

- Une description claire de la faille
- Les étapes pour la reproduire
- La version du logiciel concernée (visible dans **Paramètres › À propos** ou dans les propriétés du `.exe`)
- Votre système d'exploitation et version (Windows 10 build XXXX, etc.)
- Si possible, un correctif ou une idée de correctif

Nous nous engageons à :

- Accuser réception sous **48 heures**
- Donner un premier diagnostic sous **7 jours**
- Publier un correctif et un avis de sécurité dans un délai raisonnable, proportionnel à la gravité

## Périmètre

Sont **dans le périmètre** :

- Les versions stables publiées sur [antavirus.fr](https://antavirus.fr) ou via [les releases GitHub](../../releases)
- Le code de ce dépôt
- Les communications réseau initiées par l'application

Sont **hors périmètre** :

- Les vulnérabilités de Windows ou de logiciels tiers que l'application interroge (Defender, Chrome, etc.)
- Les versions de développement non publiées
- Les vulnérabilités nécessitant un accès physique préalable à la machine

## Modèle de menace

Le Druide Antavirus est un **scanneur en lecture seule** qui :

- Ne s'exécute que sur invocation explicite de l'utilisateur (ou via une tâche planifiée Windows configurée par lui)
- Demande les droits administrateur pour interroger l'état système (UAC à chaque lancement)
- N'ouvre **aucun port réseau** entrant
- Initie des connexions sortantes **uniquement** :
  - Vers le backend Triskell pour la vérification de licence et le proxy IA (clé serveur)
  - Vers le fournisseur d'IA choisi (Anthropic, OpenAI, Google, Mistral, DeepSeek) si l'utilisateur a configuré sa propre clé
  - Vers `antavirus.fr/api/version` pour la vérification de mise à jour (anonyme)

Les chemins de fuite de données auxquels nous attachons une attention particulière :

- L'anonymisation **avant** envoi à l'IA (fonction `ConvertTo-AnonymizedText` dans `src/le-druide-antavirus.ps1`)
- Le stockage local de la clé API utilisateur, chiffrée via **Windows DPAPI** (jamais en clair sur disque)
- L'absence de télémétrie cachée

## Vérification du binaire

Chaque release publie le hash SHA256 du binaire dans la description GitHub Releases et sur [antavirus.fr/transparence](https://antavirus.fr/transparence).

Vérifiez avant exécution :

```powershell
Get-FileHash -Algorithm SHA256 .\LeDruideAntavirus.exe
```

Si le hash diffère, **n'exécutez pas le binaire** et signalez-le à `contact@antavirus.fr`.

## Build reproductible

Le binaire publié est produit par `ps2exe` (module PowerShell communautaire) à partir du fichier `src/le-druide-antavirus.ps1`. La commande exacte est documentée dans [README.md › Compilation](README.md#compilation-depuis-les-sources).

Toute personne disposant du même fichier source et de la même version de `ps2exe` doit obtenir un binaire fonctionnellement identique. Des différences de hash mineures peuvent apparaître dues aux timestamps internes du fichier PE Windows.

## Code-signing

Les versions distribuées publiquement sont **signées** par Triskell Studio via Azure Trusted Signing à partir de la version `1.X.X` *(à venir)*.

Avant cette étape, les binaires non signés peuvent déclencher un avertissement SmartScreen au téléchargement. Cela ne signifie pas que le binaire est malveillant — vérifiez le hash SHA256 et soumettez-le à [VirusTotal](https://www.virustotal.com) si vous avez un doute.

## Contact

- Email sécurité : **contact@antavirus.fr**
- Éditeur : [Triskell Studio](https://triskellstudio.fr)
- Hébergement : OVH (Roubaix, France)
