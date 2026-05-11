# Changelog

Les changements notables sont documentés ici. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le versionnage respecte [SemVer](https://semver.org/lang/fr/).

## [1.4.4] - 2026-05-12

### Modifié
- **Bouton "Planifier" du header supprimé** : redondant avec la carte « Planifier » centrale du dashboard.
- **Bouton "← Accueil" déplacé du footer vers le header** (top-right), pour être visible au premier coup d'œil. Reste désactivé sur la vue d'accueil (où il n'a pas d'utilité), s'active automatiquement quand on est sur la vue résultats ou en cours de scan.
- **Footer rééquilibré** : 4 boutons centrés (Vue technique / Historique / Relancer / Fermer) au lieu de 5.

## [1.4.3] - 2026-05-11

### Corrigé
- **Crash en cascade « 128197 en System.Char » → « Null method » → « Location introuvable »** : trois emojis du dashboard (📅 calendrier, 📂 dossier, 🔒 cadenas) étaient écrits `[char]0x1F4C5` etc. Ces codepoints sont hors BMP (>U+FFFF) et ne tiennent pas dans un `System.Char` 16 bits, ce qui levait une exception, empêchait la création des cartes "Planifier" et "Historique", et faisait planter le layout responsive en chaîne. Remplacé par `[char]::ConvertFromUtf32(...)` qui renvoie correctement une paire de substitution.

## [1.4.2] - 2026-05-11

### Corrigé
- **Crash au lancement « op_Subtraction » et « DrawRectangle 2 arguments »** : sur certaines machines, le binding PowerShell des handlers `Add_Paint` du hero card et des cartes d'action levait des exceptions au premier affichage (`$s.Width - 1` interprété comme opération sur tableau, et surcharge `DrawRectangle(Pen, Rectangle)` non résolue). Correctif : cast explicite via `[System.Windows.Forms.Control]$s`, utilisation de la surcharge `DrawRectangle(Pen, int, int, int, int)` (5 args), et try/catch protecteur autour de chaque handler de peinture.
- **Parsing de la date du dernier scan** : `[datetime]$prevScan.Date` pouvait échouer si la valeur arrivait sous forme de tableau ou de string avec format régional. Remplacé par `[datetime]::Parse([string]$rawDate, [CultureInfo]::InvariantCulture)`.

## [1.4.1] - 2026-05-11

### Corrigé
- **Installateur — erreur 740 à la fin de l'installation** : le binaire Le Druide nécessite les droits administrateur (Defender API), mais le post-install "Lancer maintenant" du wizard tentait un `CreateProcess` direct (sans escalade UAC possible). Ajout du flag `shellexec` au step `[Run]` de l'installateur, ce qui permet à Windows de proposer l'élévation UAC normalement. Le binaire applicatif est inchangé fonctionnellement vs v1.4.0.

## [1.4.0] - 2026-05-11

### Ajouté
- **Protection en temps réel orchestrée** : Le Druide reflète désormais l'état complet de la protection système (antivirus actif, surveillance temps réel, signatures à jour). Si la protection est désactivée, un bouton "Réactiver" rouge apparaît directement sur la carte de statut et la rétablit en un clic.
- **Refonte complète de la vue d'accueil** en dashboard style antivirus moderne : carte hero qui adapte titre, sous-titre et badge selon l'état de protection ET le dernier scan ; 4 cartes d'action cliquables (Scanner mon PC / Scan express / Planifier / Historique) avec hover doré et clic centralisé.
- **Scan antivirus en arrière-plan automatique** : à chaque déclenchement de "Scanner mon PC" ou "Scan express", un scan rapide Defender est lancé en parallèle de manière asynchrone. Les résultats sont visibles dans la prochaine ouverture du Druide.
- **Bouton flottant "Demander à l'Œil" (FAB)** : sorti du footer, attaché en bas-droite de la fenêtre, animé en or-vert avec respiration. Effet "appel à l'action" sans agression.
- **Module d'orchestration Defender** (section interne `DEFENDER ORCHESTRATION` dans `le-druide-antavirus.ps1`) avec sept fonctions wrapper : `Get-DefenderProtectionStatus`, `Enable-DefenderRealtimeProtection`, `Start-DefenderQuickScan`, `Start-DefenderFullScan`, `Get-DefenderThreats`, `Remove-DefenderThreat`, `Update-DefenderSignatures`.

### Modifié
- Positionnement produit : Le Druide passe d'outil de diagnostic à "antivirus français + assistant intelligent". Le code n'embarque pas son propre moteur — il orchestre les moteurs natifs de Windows (zéro conflit avec un AV tiers, signatures auto à jour, binaire toujours ~360 Ko en portable).
- Coins arrondis 14 px sur les cartes d'action, 16 px sur le hero, 12 px sur le bouton de réactivation.

## [1.3.2] - 2026-05-11

### Ajouté
- **Installateur Windows officiel (Inno Setup)** : nouveau binaire `LeDruideAntavirus-Setup-v1.3.2.exe` qui crée automatiquement un raccourci sur le bureau, une entrée dans le menu Démarrer, et inscrit l'application dans la liste des programmes Windows (Apps & Features). Installation par utilisateur (sans UAC), désinstallation propre incluse. Le binaire portable `LeDruideAntavirus-v1.3.2.exe` reste disponible pour les utilisateurs préférant zéro installation.
- **Script `installer/installer.iss`** : configuration Inno Setup versionnée. Build reproductible via `ISCC installer/installer.iss` après compilation du portable via ps2exe.

### Modifié
- Le téléchargement par défaut sur antavirus.fr pointe désormais sur l'installateur. Le portable reste accessible depuis la page Transparence (avec hash SHA256 à vérifier).

## [1.3.1] - 2026-05-11

### Ajouté
- **Chat de L'Œil d'Antavirus en bulles arrondies** : refonte complète du chat de l'assistant IA en `FlowLayoutPanel` avec bulles distinctes (L'Œil à gauche en crème, Vous à droite en vert sombre, Système/Confidentialité/Erreur centrés avec emojis dédiés). Calcul de hauteur via `TextRenderer.MeasureText` pour wrap propre. Coins arrondis 14 px.
- **Auto-update GitHub Releases au démarrage** : appel asynchrone à `api.github.com/repos/Jordan-Bourillot/le-druide-antavirus/releases/latest` (timeout 8 s, non bloquant via `Start-Job`). Si nouvelle version disponible, bandeau or doré sous le header avec lien cliquable vers la page Release.
- **Bouton flottant L'Œil (FAB) animé** : sorti du footer, attaché au form en bas-droite, circulaire (76 × 76). Animation de pulsation **Or ↔ Vert sage** (cycle 4 s, interpolation sinusoïdale) + **respiration de taille** (76 → 82 → 76 px synchronisée). Effet "appel à l'action" sans agression.
- **Coins arrondis sur tous les boutons** : nouvelle fonction `Set-RoundedRegion` qui applique une `Region` arrondie à n'importe quel `Button`. Appliquée au footer (10 px), header (10 px), Analyser mon PC (18 px, style pill), Scan express (14 px).
- **Footer centré** : les 5 boutons (Vue technique / Historique / Accueil / Relancer / Fermer) sont centrés horizontalement dans le footer via le handler `$repositionAnchored` qui calcule la position selon la largeur courante.

### Modifié
- Boutons header en couleurs solides : Planifier (vert sombre) + Paramètres (or). Plus d'invisibilité blanc-sur-blanc.
- Footer height 56 → 64 px pour aérer les boutons (hauteur 32 → 36 px).
- Animation pendant scan : druide qui tourne comme une **pièce sur une table** (rotation sur l'axe vertical, effet face/pile) au lieu d'une pulsation. 72 frames pré-calculées + timer 40 ms pour fluidité maximale.
- "Mon plan" → "Demander à l'Œil" pour clarifier ce que fait le bouton (ouvre l'assistant IA).

### Corrigé
- Logo héraldique : remplacement du base64 obsolète (oscilloscope violet) par le PNG officiel du druide (256 × 256) embarqué dans le binaire.
- Boutons header Planifier + Paramètres : repositionnement explicite via `Form.Add_Shown` / `Add_Resize` (contournement d'un bug d'ancrage Right de WinForms quand le parent est `Dock=Top`).
- Tutoiements oubliés dans le chat (`Va dans` → `Allez dans`, `Re-saisis-la` → `Re-saisissez-la`, `Attends/change` → `Patientez/changez`).
- Animation du druide pendant scan : précalcul des frames + `DoEvents()` systématique en début et fin de chaque `Invoke-Check` → reste fluide entre les sections (limite intrinsèque PowerShell : un check synchrone très lent comme `Get-WinEvent` peut encore figer brièvement).

## [1.2.6] - 2026-05-11

### Modifié
- Animation pendant le scan : le druide tourne comme une pièce de monnaie sur une table (rotation sur l'axe vertical, face/pile) au lieu d'une pulsation.

## [1.2.5] - 2026-05-11

### Modifié
- L'animation du druide pendant le scan passe d'une pulsation à une rotation continue (effet médaillon).

## [1.2.4] - 2026-05-11

### Ajouté
- Repositionnement explicite des boutons ancrés à droite (Planifier, Paramètres, Fermer) — contourne un bug d'ancrage WinForms.
- Boutons header solides : « Planifier » (vert sombre) et « Paramètres » (or doré).
- Bordures des boutons footer en vert sombre + texte gras pour meilleure lisibilité.

### Modifié
- « Mon plan » renommé « Demander à l'Œil » (clarification du rôle du bouton).

## [1.2.3] - 2026-05-11

### Modifié
- L'animation de l'œil emoji pendant le scan est remplacée par le druide héraldique en grand avec pulsation douce.

## [1.2.2] - 2026-05-11

### Ajouté
- Logo héraldique embarqué en base64 directement dans le binaire (256 × 256 PNG).

### Modifié
- Baseline header en or doré gras pour mise en avant marketing.
- « by Triskell Studio » devient « par Triskell Studio » (anglicisme corrigé).
- « Protege » devient « Protège » (accent rétabli).
- Boutons header crème avec bordure verte (au lieu de blanc invisible sur blanc).

### Corrigé
- L'ancienne icône violette embarquée en base64 est remplacée par le druide officiel.

## [1.2.1] - 2026-05-11

### Modifié
- Rebrand complet de l'assistant IA : **Druidix** → **L'Œil d'Antavirus**.

## [1.2.0] - 2026-05-11

### Ajouté
- **Planification hebdomadaire** : nouveau dialog accessible depuis le header, crée une tâche planifiée Windows qui lance un scan en mode `-Silent` avec notification système si critique.
- **Mode scan Express (15 s)** : 5 checks essentiels au lieu de 14, pour les utilisateurs pressés.
- **Diff entre scans** : carte « Évolution depuis le dernier scan » affichée en tête des résultats (résolus, nouveaux, persistants).
- **CTAs profilés** : détection automatique du profil utilisateur (Pro / Créatif / Lambda) selon les logiciels installés, et carte contextuelle non agressive en fin de rapport.

## [1.1.0] - 2026-05-11

### Ajouté
- **Anonymisation IA** : fonction `ConvertTo-AnonymizedText` qui remplace chemins utilisateur, nom de la machine, MAC, IP privées et numéros de série avant tout envoi à l'IA. Message de consentement explicite dans le chat.
- **Anti-alarmisme** : seuils relevés sur les signatures Defender (CRIT seulement après 30 jours), RAM (95 % au lieu de 92 %), uptime (14 j), boot (180 s).
- **Check Extensions navigateurs** : Chrome, Edge, Brave, Firefox — détecte les extensions aux permissions sensibles (`<all_urls>`, history, cookies, webRequest…).
- **Check Maintenance + nettoyage 1-clic** : calcule l'espace récupérable dans les caches navigateurs + temp ; bouton qui exécute réellement `Remove-Item`.
- **MAJ Defender 1-clic** : exécute `Update-MpSignature` directement.
- **Historique des rapports** : archive auto dans `%APPDATA%\LeDruide\Reports\` (20 derniers) + dialog viewer avec Ouvrir / Supprimer / Ouvrir le dossier.
- **Onboarding au premier lancement** : 3 cartes (Découvrir / BYOK / Plus tard).
- **L'Œil auto post-scan** : bouton « Mon plan » qui demande directement à l'IA un plan d'action priorisé.

### Modifié
- Tutoiements UI → vouvoiement (10 occurrences corrigées).
- System prompt IA : impose vouvoiement, interdit anglicismes, exige l'ordre « ce que c'est / pourquoi gênant / quoi faire », anti-alarmisme.

## [1.0.1] - 2026-05-11

### Ajouté
- Refonte complète de la palette : violet/indigo → vert sombre `#1F4D3A` + or `#C8A45C` + crème `#F4ECD8` + bleu nuit `#0E1E2E`.
- Sous-titre header : baseline officielle « Analyse · Protège · Rassure ».

### Modifié
- Renommage produit : **« Le Druide »** → **« Le Druide Antavirus »**.

## [1.0.0] - 2026-05-11

### Ajouté
- Première version publiée sous le nom **Le Druide Antavirus**.
- Moteur de scan en lecture seule (13 catégories de checks).
- Interface graphique WinForms.
- Assistant IA intégré avec 5 fournisseurs au choix (Anthropic, OpenAI, Google, Mistral, DeepSeek).
- Stockage local chiffré des clés API via Windows DPAPI.
