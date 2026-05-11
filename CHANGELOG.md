# Changelog

Les changements notables sont documentés ici. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le versionnage respecte [SemVer](https://semver.org/lang/fr/).

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
