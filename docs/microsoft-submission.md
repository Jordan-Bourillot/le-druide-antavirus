# Soumission à Microsoft Defender (procédure)

> Objectif : faire ajouter `Le Druide Antavirus.exe` à la liste blanche Microsoft pour réduire l'avertissement SmartScreen au téléchargement.

## URL de soumission

**https://www.microsoft.com/en-us/wdsi/filesubmission**

Connectez-vous avec un compte Microsoft (perso ou organisation). Choisissez **« Software Developer »** comme catégorie.

## Informations à fournir

### Section 1 — File submission

| Champ | Valeur |
|---|---|
| File | `LeDruideAntavirus-v1.2.6.exe` (depuis la GitHub Release) |
| **SHA256** | `BED64E5BE3065BCAF63441A0AF74A72359BB340A762936AE8FF8E0A9CF435248` |
| **SHA1** | `8D7021F7C36FEB8001E70D311C8C4406DDBE093E` |
| **MD5** | `EFA52CE61AAB4B2BB7DDC2CA9FAA7D0C` |
| Detection name (si Defender flag) | *(vide, ou nom de la détection s'il y en a une)* |
| Detected by | Microsoft Defender |

### Section 2 — Submission details

**Submission type** : `False positive`

**Definition version detecting** : *(vide ou la version Defender qui flag)*

**Additional information** :

```
Le Druide Antavirus is a French Windows PC diagnostic and scanning tool
edited by Triskell Studio (https://triskellstudio.fr), distributed on
https://antavirus.fr.

Key facts :
- Read-only scanner : the tool performs no modification on the system without
  explicit user click on a 1-click action button.
- 100 % local : no file content leaves the user's machine. Only the optional
  AI assistant (user opt-in) communicates with the chosen AI provider
  (Anthropic, OpenAI, Google, Mistral, DeepSeek), and only with anonymized
  diagnostic text (paths, hostname, MAC, IP and serial numbers are replaced
  by placeholders before sending — see ConvertTo-AnonymizedText function).
- Open source : the full source code is published under AGPL-3.0 on GitHub :
  https://github.com/Jordan-Bourillot/le-druide-antavirus
- Compiled from PowerShell via the public ps2exe module ; build is
  reproducible from source.
- Requires administrator privileges to query system state (Get-MpComputerStatus,
  Get-PnpDevice, Get-WinEvent, etc.) ; this is the reason for the requireAdmin
  manifest flag.
- The application makes no inbound network connections, opens no listening
  ports, and does no background telemetry.

If you can confirm the file is clean, please add it to your trusted list to
spare French Windows users an unnecessary SmartScreen warning at download
time. Code-signing via Azure Trusted Signing is planned for a later release.

Hashes :
  SHA256 : BED64E5BE3065BCAF63441A0AF74A72359BB340A762936AE8FF8E0A9CF435248
  SHA1   : 8D7021F7C36FEB8001E70D311C8C4406DDBE093E
  MD5    : EFA52CE61AAB4B2BB7DDC2CA9FAA7D0C

Source code : https://github.com/Jordan-Bourillot/le-druide-antavirus
Release page : https://github.com/Jordan-Bourillot/le-druide-antavirus/releases/tag/v1.2.6
Vendor : Triskell Studio (France)
Contact : contact@antavirus.fr
```

### Section 3 — Contact

| Champ | Valeur |
|---|---|
| Email | `contact@antavirus.fr` |
| Company | `Triskell Studio` |
| Country | `France` |

### Section 4 — Privacy

Cochez la case pour autoriser Microsoft à publier les résultats si nécessaire.

## Après la soumission

- Microsoft envoie un email d'accusé de réception sous quelques heures.
- L'analyse prend généralement **24 à 72 heures**.
- Si validé, le binaire est ajouté à la liste de bons fichiers connus → plus de SmartScreen warning.
- Si rejeté, vous recevez la raison (rare pour un binaire propre + open source).

**À refaire à chaque nouvelle version publiée** (le hash change à chaque rebuild).

## Soumission à VirusTotal (en parallèle)

URL : **https://www.virustotal.com/gui/home/upload**

1. Téléverser `LeDruideAntavirus-v1.2.6.exe`
2. Attendre quelques secondes pour le résultat
3. **Objectif : 0/70 détections**
4. Copier le lien permanent (de la forme `https://www.virustotal.com/gui/file/<sha256>/detection`)
5. L'afficher dans la page Transparence comme badge de confiance
6. Si une détection apparaît, l'ouvrir comme false positive sur VirusTotal et auprès de l'antivirus concerné

## Autres soumissions utiles (à plus long terme)

- **Avast / AVG** : https://www.avast.com/false-positive-file-form.php
- **Bitdefender** : https://www.bitdefender.com/consumer/support/answer/29358/
- **ESET** : https://www.eset.com/int/support/contact/false-positive/
- **Kaspersky** : https://opentip.kaspersky.com/ (search by hash)
- **Norton (NortonLifeLock)** : https://submit.norton.com/

À faire si un antivirus particulier signale Le Druide comme false positive sur la version publique.
