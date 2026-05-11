; Le Druide Antavirus — installateur Inno Setup
; Crée un raccourci bureau + entrée menu Démarrer + inscription Apps & Features.
; Installation par utilisateur (pas d'UAC à l'install), sans Program Files admin.
; L'exécutable lui-même demande l'élévation au lancement (requireAdmin via ps2exe).

#define MyAppName          "Le Druide Antavirus"
#define MyAppVersion       "1.4.6"
#define MyAppPublisher     "Triskell Studio"
#define MyAppURL           "https://antavirus.fr"
#define MyAppSupportEmail  "contact@antavirus.fr"
#define MyAppExeName       "LeDruideAntavirus.exe"
#define SourceExe          "..\dist\LeDruideAntavirus-v" + MyAppVersion + ".exe"

[Setup]
; AppId stable — NE PAS modifier entre versions (sinon Apps & Features voit ça comme un autre soft)
AppId={{B71F4D3A-1F4D-4D3A-9E5D-DA1F4D3A1F4D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppContact={#MyAppSupportEmail}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} — installateur
VersionInfoCopyright=© 2026 {#MyAppPublisher}

; Installation par utilisateur (sans UAC à l'install)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={localappdata}\Programs\LeDruideAntavirus
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
LicenseFile=..\LICENSE

; Sortie
OutputDir=..\dist
OutputBaseFilename=LeDruideAntavirus-Setup-v{#MyAppVersion}
SetupIconFile=..\assets\druide-antavirus.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

; Apps & Features
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; Branding wizard
WizardImageStretch=yes
ShowLanguageDialog=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le &Bureau"; GroupDescription: "Icônes supplémentaires :"; Flags: checkedonce

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Site web — antavirus.fr"; Filename: "{#MyAppURL}"
Name: "{group}\Désinstaller {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; shellexec : permet l'élévation UAC car le binaire requiert les droits admin
; (ps2exe -requireAdmin). Sans ce flag, CreateProcess échoue avec code 740.
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName} maintenant"; Flags: shellexec nowait postinstall skipifsilent unchecked
