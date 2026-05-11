<#
.SYNOPSIS
    Diagnostic PC - Outil d'analyse de santé Windows 10/11

.DESCRIPTION
    Script de diagnostic en lecture seule pour identifier les causes de :
      A. Ralentissements progressifs après plusieurs heures d'utilisation
      B. Cycles de démarrage anormalement longs (>5 min)

    Aucune modification système. 100% PowerShell natif. Compatible 5.1 et 7.x.
    Le script se relance automatiquement avec les droits administrateur.

.PARAMETER Full
    Active les checks lents (recherche de mises à jour Windows en attente).
    Par défaut : mode rapide.

.PARAMETER OutputDir
    Dossier où écrire le rapport texte. Défaut : Bureau.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Diagnostic-PC.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Diagnostic-PC.ps1 -Full

.NOTES
    Version : 1.0
    Date    : 2026-05-09
    Auteur  : Claude (Anthropic)
    Lancement recommandé : clic droit > "Exécuter avec PowerShell"
    ou via une console PowerShell admin.
#>

[CmdletBinding()]
param(
    [switch]$Full,
    [switch]$Express,
    [switch]$Silent,
    [switch]$SkipElevation,
    [switch]$NoPause,
    [switch]$GUI,
    [switch]$Console,
    [string]$OutputDir = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Continue'

# Détection auto du mode : GUI par défaut quand exécuté depuis le .exe compilé
# (où $PSCommandPath est vide), console quand exécuté depuis le .ps1.
if (-not $GUI -and -not $Console) {
    if ([string]::IsNullOrEmpty($PSCommandPath)) { $GUI = $true } else { $Console = $true }
}

# ============================================================
# AUTO-ÉLÉVATION
# ============================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
$isAdmin = $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if ($Console -and -not $isAdmin -and $PSCommandPath -and -not $SkipElevation) {
    Write-Host "Élévation des privilèges nécessaire pour les checks complets..." -ForegroundColor Yellow
    try {
        $argList = @('-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($Full) { $argList += '-Full' }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -ErrorAction Stop
        exit
    }
    catch {
        Write-Host "Élévation refusée. Continuation en mode limité." -ForegroundColor Yellow
    }
}

# ============================================================
# CONFIGURATION (seuils ajustables)
# ============================================================
$Thresholds = @{
    DiskFreePctWarning       = 15
    DiskFreePctCritical      = 5
    RamUsedPctWarning        = 85
    RamUsedPctCritical       = 95
    BootTimeSecWarning       = 180
    StartupItemsWarning      = 30
    SignatureAgeDaysWarning  = 14
    SignatureAgeDaysCritical = 30
    EventLookbackHours       = 48
    MaxEventsToShow          = 15
    UptimeDaysWarning        = 14
    SsdWearWarning           = 85
    DiskTempWarning          = 70
    AppRamCumulMbWarning     = 6144
}

$startTime  = Get-Date
$timestamp  = $startTime.ToString('yyyyMMdd_HHmmss')
$reportPath = Join-Path $OutputDir "Diagnostic-PC_$timestamp.txt"

$script:Findings   = New-Object System.Collections.ArrayList
$script:Report     = New-Object System.Text.StringBuilder
$script:GuiContext = $null  # défini quand GUI active : @{ Rtb=...; Status=...; Form=... }

# ============================================================
# FONCTIONS UTILITAIRES
# ============================================================

function Append-GuiLine {
    param([string]$Text, [System.Drawing.Color]$Color)
    if (-not $script:GuiContext) { return }
    $rtb = $script:GuiContext.Rtb
    $rtb.SelectionStart  = $rtb.TextLength
    $rtb.SelectionLength = 0
    $rtb.SelectionColor  = $Color
    $rtb.AppendText($Text + "`r`n")
    $rtb.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-GuiColor {
    param([string]$Level)
    switch ($Level) {
        'OK'      { [System.Drawing.Color]::FromArgb(107, 166, 114) }
        'WARN'    { [System.Drawing.Color]::FromArgb(217, 137, 46) }
        'CRIT'    { [System.Drawing.Color]::FromArgb(178, 59, 59) }
        'INFO'    { [System.Drawing.Color]::FromArgb(200, 200, 200) }
        'ERR'     { [System.Drawing.Color]::FromArgb(178, 59, 59) }
        'SECTION' { [System.Drawing.Color]::FromArgb(200, 164, 92) }
        default   { [System.Drawing.Color]::White }
    }
}

function Write-Both {
    param([string]$Text)
    if ($script:GuiContext) {
        Append-GuiLine -Text $Text -Color (Get-GuiColor 'INFO')
    }
    else {
        Write-Host $Text
    }
    [void]$script:Report.AppendLine($Text)
}

function Write-Section {
    param([string]$Title)
    $line = '=' * 64
    if ($script:GuiContext) {
        $col = Get-GuiColor 'SECTION'
        Append-GuiLine -Text '' -Color $col
        Append-GuiLine -Text $line -Color $col
        Append-GuiLine -Text (" $Title") -Color $col
        Append-GuiLine -Text $line -Color $col
        if ($script:GuiContext.Status) {
            $script:GuiContext.Status.Text = "En cours : $Title"
        }
        if ($script:GuiContext.Progress) {
            $script:GuiContext.SectionCount++
            $pct = [math]::Min(100, [math]::Floor(100 * $script:GuiContext.SectionCount / [math]::Max(1, $script:GuiContext.SectionTotal)))
            try {
                $script:GuiContext.Progress.Value = $pct
                if ($script:GuiContext.ProgressPercent) {
                    $script:GuiContext.ProgressPercent.Text = "$pct %"
                }
            } catch {}
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
    else {
        Write-Host ''
        Write-Host $line -ForegroundColor Cyan
        Write-Host (" $Title").PadRight(64) -ForegroundColor Cyan
        Write-Host $line -ForegroundColor Cyan
    }
    [void]$script:Report.AppendLine('')
    [void]$script:Report.AppendLine($line)
    [void]$script:Report.AppendLine(" $Title")
    [void]$script:Report.AppendLine($line)
}

function Write-Result {
    param(
        [ValidateSet('OK','WARN','CRIT','INFO','ERR')]
        [string]$Level,
        [string]$Message
    )
    $prefix = "[$Level]".PadRight(6)
    $line   = "$prefix $Message"
    if ($script:GuiContext) {
        Append-GuiLine -Text $line -Color (Get-GuiColor $Level)
    }
    else {
        $color = switch ($Level) {
            'OK'   { 'Green' }
            'WARN' { 'Yellow' }
            'CRIT' { 'Red' }
            'INFO' { 'Gray' }
            'ERR'  { 'DarkRed' }
        }
        Write-Host $line -ForegroundColor $color
    }
    [void]$script:Report.AppendLine($line)
}

function Add-Finding {
    param(
        [ValidateSet('Info','Warning','Critical')]
        [string]$Severity,
        [string]$Category,
        [string]$Description,
        [string]$Recommendation,
        [string[]]$Symptom = @()
    )
    [void]$script:Findings.Add([pscustomobject]@{
        Severity       = $Severity
        Category       = $Category
        Description    = $Description
        Recommendation = $Recommendation
        Symptom        = $Symptom
    })
}

function Invoke-Check {
    param([string]$Name, [scriptblock]$Block)
    # On laisse respirer la pompe de messages avant chaque check pour que
    # l'animation du druide reste fluide entre les operations bloquantes.
    if ($script:GuiContext) { try { [System.Windows.Forms.Application]::DoEvents() } catch {} }
    try {
        & $Block
    }
    catch {
        Write-Result -Level ERR -Message "$Name : $($_.Exception.Message)"
    }
    if ($script:GuiContext) { try { [System.Windows.Forms.Application]::DoEvents() } catch {} }
}

# ============================================================
# CHECK 1 - IDENTITÉ DE LA MACHINE
# ============================================================

function Show-MachineIdentity {
    Write-Section 'IDENTITÉ DE LA MACHINE'
    Invoke-Check 'Identité' {
        $cs = Get-CimInstance Win32_ComputerSystem
        $os = Get-CimInstance Win32_OperatingSystem

        $bootTime = $os.LastBootUpTime
        $uptime   = (Get-Date) - $bootTime
        $uptimeStr = "{0}j {1}h {2}min" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

        Write-Result INFO ("Nom         : {0}" -f $cs.Name)
        Write-Result INFO ("Fabricant   : {0}" -f $cs.Manufacturer)
        Write-Result INFO ("Modèle      : {0}" -f $cs.Model)
        Write-Result INFO ("Windows     : {0} (build {1})" -f $os.Caption, $os.BuildNumber)
        Write-Result INFO ("Architecture: {0}" -f $os.OSArchitecture)
        Write-Result INFO ("Dernier boot: {0}" -f $bootTime.ToString('yyyy-MM-dd HH:mm'))
        Write-Result INFO ("Uptime      : {0}" -f $uptimeStr)
        Write-Result INFO ("Admin       : {0}" -f $isAdmin)

        if ($uptime.TotalDays -gt $Thresholds.UptimeDaysWarning) {
            Write-Result WARN "PC allumé depuis plus de $($Thresholds.UptimeDaysWarning) jours"
            Add-Finding -Severity Warning -Category 'Uptime' `
                -Description "Uptime de $uptimeStr sans redémarrage complet" `
                -Recommendation "Redémarrer le PC pour libérer la RAM et appliquer d'éventuelles mises à jour" `
                -Symptom Slowdown
        }
    }
}

# ============================================================
# CHECK 2 - SANTÉ DES DISQUES
# ============================================================

function Test-DiskHealth {
    Write-Section 'SANTÉ DES DISQUES'

    Invoke-Check 'Disques physiques' {
        $disks = Get-PhysicalDisk
        foreach ($d in $disks) {
            $sizeGB = [math]::Round($d.Size / 1GB, 0)
            $line = "{0} | {1} | {2} Go | Santé: {3}" -f $d.FriendlyName, $d.MediaType, $sizeGB, $d.HealthStatus
            switch ($d.HealthStatus) {
                'Healthy' { Write-Result OK $line }
                'Warning' {
                    Write-Result WARN $line
                    Add-Finding -Severity Warning -Category 'Disk' `
                        -Description "Disque $($d.FriendlyName) en état Warning" `
                        -Recommendation "Sauvegarder les données et envisager un remplacement" `
                        -Symptom @('Slowdown','BootSlow')
                }
                default {
                    Write-Result CRIT $line
                    Add-Finding -Severity Critical -Category 'Disk' `
                        -Description "Disque $($d.FriendlyName) en état $($d.HealthStatus)" `
                        -Recommendation "URGENT : sauvegarder les données. Le disque est défaillant." `
                        -Symptom @('Slowdown','BootSlow')
                }
            }

            try {
                $rel = $d | Get-StorageReliabilityCounter -ErrorAction Stop
                if ($rel) {
                    $details = @()
                    if ($null -ne $rel.Wear)             { $details += "Usure: $($rel.Wear)%" }
                    if ($null -ne $rel.Temperature)      { $details += "Temp: $($rel.Temperature)°C" }
                    if ($null -ne $rel.ReadErrorsTotal)  { $details += "Err. lecture: $($rel.ReadErrorsTotal)" }
                    if ($null -ne $rel.WriteErrorsTotal) { $details += "Err. écriture: $($rel.WriteErrorsTotal)" }
                    if ($details.Count -gt 0) {
                        Write-Result INFO ("  -> " + ($details -join ' | '))
                    }
                    if ($null -ne $rel.Wear -and $rel.Wear -gt $Thresholds.SsdWearWarning) {
                        Add-Finding -Severity Warning -Category 'Disk' `
                            -Description "SSD $($d.FriendlyName) usé à $($rel.Wear)%" `
                            -Recommendation "Prévoir le remplacement du SSD à moyen terme" `
                            -Symptom Slowdown
                    }
                    if ($null -ne $rel.Temperature -and $rel.Temperature -gt $Thresholds.DiskTempWarning) {
                        Write-Result WARN "  -> Température disque élevée ($($rel.Temperature)°C)"
                    }
                    if ($null -ne $rel.ReadErrorsTotal -and $rel.ReadErrorsTotal -gt 0) {
                        Add-Finding -Severity Warning -Category 'Disk' `
                            -Description "Erreurs de lecture sur $($d.FriendlyName) : $($rel.ReadErrorsTotal)" `
                            -Recommendation "Sauvegarder et surveiller ; envisager un remplacement si ça augmente" `
                            -Symptom @('Slowdown','BootSlow')
                    }
                }
            }
            catch {
                # Pas tous les disques exposent ces compteurs (NVMe externes par ex.)
            }
        }
    }

    Invoke-Check 'Volumes' {
        $vols = Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 }
        foreach ($v in $vols) {
            $totalGB = [math]::Round($v.Size / 1GB, 1)
            $freeGB  = [math]::Round($v.SizeRemaining / 1GB, 1)
            $pctFree = [math]::Round(($v.SizeRemaining / $v.Size) * 100, 1)
            $label   = if ($v.FileSystemLabel) { $v.FileSystemLabel } else { '(sans nom)' }
            $line    = "{0}: ({1}) | {2} Go libres / {3} Go ({4}%)" -f $v.DriveLetter, $label, $freeGB, $totalGB, $pctFree

            if ($pctFree -lt $Thresholds.DiskFreePctCritical) {
                Write-Result CRIT $line
                Add-Finding -Severity Critical -Category 'Disk' `
                    -Description "Volume $($v.DriveLetter): seulement $pctFree% libre ($freeGB Go)" `
                    -Recommendation "Libérer de l'espace immédiatement (Stockage > Sens du stockage, désinstaller programmes, vider caches)" `
                    -Symptom Slowdown
            }
            elseif ($pctFree -lt $Thresholds.DiskFreePctWarning) {
                Write-Result WARN $line
                Add-Finding -Severity Warning -Category 'Disk' `
                    -Description "Volume $($v.DriveLetter): $pctFree% libre" `
                    -Recommendation "Libérer de l'espace pour rester sous 85% d'occupation" `
                    -Symptom Slowdown
            }
            else {
                Write-Result OK $line
            }
        }
    }
}

# ============================================================
# CHECK 3 - MÉMOIRE ET PROCESSUS
# ============================================================

function Test-MemoryUsage {
    Write-Section 'MÉMOIRE ET PROCESSUS'

    Invoke-Check 'RAM' {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
        $freeMB  = [math]::Round($os.FreePhysicalMemory / 1024, 0)
        $usedMB  = $totalMB - $freeMB
        $pctUsed = [math]::Round(($usedMB / $totalMB) * 100, 1)

        $line = "RAM: {0} Mo utilisés / {1} Mo total ({2}%)" -f $usedMB, $totalMB, $pctUsed
        if ($pctUsed -ge $Thresholds.RamUsedPctCritical) {
            Write-Result CRIT $line
            Add-Finding -Severity Critical -Category 'Memory' `
                -Description "RAM saturée à $pctUsed%" `
                -Recommendation "Fermer des applications gourmandes, redémarrer le navigateur, ou ajouter de la RAM si chronique" `
                -Symptom Slowdown
        }
        elseif ($pctUsed -ge $Thresholds.RamUsedPctWarning) {
            Write-Result WARN $line
            Add-Finding -Severity Warning -Category 'Memory' `
                -Description "RAM utilisée à $pctUsed%" `
                -Recommendation "Surveiller les processus gourmands listés ci-dessous" `
                -Symptom Slowdown
        }
        else {
            Write-Result OK $line
        }

        $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
        if ($pf) {
            foreach ($p in $pf) {
                Write-Result INFO ("Pagefile {0}: {1} Mo utilisés / {2} Mo alloués" -f $p.Name, $p.CurrentUsage, $p.AllocatedBaseSize)
            }
        }
    }

    Invoke-Check 'Top processus RAM' {
        Write-Both ''
        Write-Both 'Top 10 processus par RAM (WorkingSet) :'
        $top = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
        $i = 1
        foreach ($p in $top) {
            $mb = [math]::Round($p.WorkingSet64 / 1MB, 0)
            Write-Result INFO ("  {0,2}. {1,-30} {2,6} Mo" -f $i, $p.ProcessName, $mb)
            $i++
        }

        $byName = Get-Process | Group-Object ProcessName | ForEach-Object {
            [pscustomobject]@{
                Name    = $_.Name
                Count   = $_.Count
                TotalMB = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 0)
            }
        } | Sort-Object TotalMB -Descending | Select-Object -First 5

        Write-Both ''
        Write-Both 'Cumul RAM par application (top 5) :'
        foreach ($g in $byName) {
            Write-Result INFO ("  {0,-25} {1,3} instances {2,6} Mo" -f $g.Name, $g.Count, $g.TotalMB)
            if ($g.TotalMB -gt $Thresholds.AppRamCumulMbWarning) {
                Add-Finding -Severity Warning -Category 'Memory' `
                    -Description "$($g.Name) consomme $($g.TotalMB) Mo cumulés ($($g.Count) instances)" `
                    -Recommendation "Fermer les onglets/fenêtres inutiles ou redémarrer cette application" `
                    -Symptom Slowdown
            }
        }
    }

    Invoke-Check 'Top processus CPU' {
        Write-Both ''
        Write-Both 'Échantillonnage CPU sur 5 secondes...'
        try {
            $procs1 = Get-Process | Select-Object Id, ProcessName, @{N='CPU';E={$_.CPU}}
            Start-Sleep -Seconds 5
            $procs2 = Get-Process | Select-Object Id, ProcessName, @{N='CPU';E={$_.CPU}}

            $delta = foreach ($p2 in $procs2) {
                $p1 = $procs1 | Where-Object { $_.Id -eq $p2.Id } | Select-Object -First 1
                if ($p1 -and $p1.CPU -ne $null -and $p2.CPU -ne $null) {
                    [pscustomobject]@{
                        Name     = $p2.ProcessName
                        DeltaCpu = [math]::Round(($p2.CPU - $p1.CPU), 2)
                    }
                }
            }
            $top = $delta | Where-Object { $_.DeltaCpu -gt 0 } | Sort-Object DeltaCpu -Descending | Select-Object -First 10
            if ($top) {
                $i = 1
                foreach ($p in $top) {
                    Write-Result INFO ("  {0,2}. {1,-30} {2,6} sec CPU" -f $i, $p.Name, $p.DeltaCpu)
                    $i++
                }
            } else {
                Write-Result INFO "  (aucune activité CPU significative pendant l'échantillon)"
            }
        }
        catch {
            Write-Result ERR "Échec échantillonnage CPU : $($_.Exception.Message)"
        }

        $totalProc = (Get-Process).Count
        Write-Both ''
        Write-Result INFO ("Nombre total de processus : {0}" -f $totalProc)
    }
}

# ============================================================
# CHECK 4 - REDÉMARRAGE EN ATTENTE
# ============================================================

function Test-PendingReboot {
    Write-Section 'REDÉMARRAGE EN ATTENTE'
    Invoke-Check 'Pending reboot' {
        $pending = $false
        $reasons = @()

        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $pending = $true
            $reasons += 'Component Based Servicing (CBS)'
        }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $pending = $true
            $reasons += 'Windows Update'
        }
        try {
            $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
            if ($sm.PendingFileRenameOperations) {
                $pending = $true
                $reasons += 'PendingFileRenameOperations'
            }
        } catch {}

        if ($pending) {
            Write-Result CRIT ("Redémarrage requis - cause(s) : " + ($reasons -join ', '))
            Add-Finding -Severity Critical -Category 'Reboot' `
                -Description "Redémarrage en attente : $($reasons -join ', ')" `
                -Recommendation "C'est probablement la cause du boot lent. Redémarrer maintenant pour finaliser l'installation des mises à jour." `
                -Symptom BootSlow
        }
        else {
            Write-Result OK 'Aucun redémarrage en attente'
        }
    }
}

# ============================================================
# CHECK 5 - MISES À JOUR WINDOWS
# ============================================================

function Test-WindowsUpdates {
    Write-Section 'MISES À JOUR WINDOWS'

    Invoke-Check 'Dernières maj installées' {
        $hf = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5
        Write-Both 'Dernières mises à jour installées :'
        foreach ($h in $hf) {
            $date = if ($h.InstalledOn) { $h.InstalledOn.ToString('yyyy-MM-dd') } else { 'inconnu' }
            Write-Result INFO ("  {0} | {1} | {2}" -f $date, $h.HotFixID, $h.Description)
        }
    }

    if (-not $Full) {
        Write-Result INFO "Recherche des maj en attente ignorée (lance avec -Full pour l'activer)"
        return
    }

    Invoke-Check 'Maj en attente' {
        try {
            Write-Both ''
            Write-Both "Recherche des mises à jour en attente (peut prendre 30 sec)..."
            $session  = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $result   = $searcher.Search("IsInstalled=0 and IsHidden=0")
            $count    = $result.Updates.Count

            if ($count -eq 0) {
                Write-Result OK 'Aucune mise à jour en attente'
            }
            else {
                Write-Result WARN "$count mise(s) à jour en attente"
                $i = 0
                foreach ($u in $result.Updates) {
                    if ($i -ge 5) { break }
                    Write-Result INFO ("  - " + $u.Title)
                    $i++
                }
                Add-Finding -Severity Warning -Category 'Updates' `
                    -Description "$count mise(s) à jour Windows en attente" `
                    -Recommendation "Lancer Windows Update et installer en heures creuses" `
                    -Symptom @('Slowdown','BootSlow')
            }
        }
        catch {
            Write-Result INFO "Recherche maj non disponible : $($_.Exception.Message)"
        }
    }
}

# ============================================================
# CHECK 6 - PERFORMANCE DE BOOT
# ============================================================

function Test-BootPerformance {
    Write-Section 'PERFORMANCE DE BOOT'
    if (-not $isAdmin) {
        Write-Result INFO 'Nécessite des droits administrateur. Section ignorée.'
        return
    }

    Invoke-Check 'Events Diagnostics-Performance' {
        try {
            $events = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 100 -ErrorAction Stop |
                Where-Object { $_.Id -in 100,101,102,103 }
        }
        catch {
            Write-Result INFO "Journal Diagnostics-Performance non disponible"
            return
        }

        $boots = $events | Where-Object { $_.Id -eq 100 } | Select-Object -First 5
        if ($boots.Count -eq 0) {
            Write-Result INFO 'Aucun event de boot trouvé'
            return
        }

        Write-Both 'Derniers boots enregistrés :'
        $latestBootSec = $null
        foreach ($b in $boots) {
            try {
                $xml    = [xml]$b.ToXml()
                $bootMs = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text'
                if ($bootMs) {
                    $bootSec = [math]::Round([int64]$bootMs / 1000, 1)
                    if ($null -eq $latestBootSec) { $latestBootSec = $bootSec }
                    $date = $b.TimeCreated.ToString('yyyy-MM-dd HH:mm')
                    if ($bootSec -gt $Thresholds.BootTimeSecWarning) {
                        Write-Result WARN ("  {0} - {1} sec" -f $date, $bootSec)
                    } else {
                        Write-Result OK ("  {0} - {1} sec" -f $date, $bootSec)
                    }
                }
            } catch {}
        }

        if ($null -ne $latestBootSec -and $latestBootSec -gt $Thresholds.BootTimeSecWarning) {
            Add-Finding -Severity Warning -Category 'Boot' `
                -Description "Dernier boot a duré $([math]::Round($latestBootSec)) secondes" `
                -Recommendation "Voir les programmes au démarrage et les pilotes en erreur ci-dessous" `
                -Symptom BootSlow
        }

        $slow = $events | Where-Object { $_.Id -in 101,102,103 } | Select-Object -First 10
        if ($slow.Count -gt 0) {
            Write-Both ''
            Write-Both 'Composants ayant ralenti le boot (nom + durée) :'
            foreach ($s in $slow) {
                $xml = $null
                try { $xml = [xml]$s.ToXml() } catch {}
                $name     = $null
                $fileName = $null
                $duration = $null
                if ($xml) {
                    $name     = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'Name' }).'#text'
                    $fileName = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'FileName' }).'#text'
                    $duration = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TotalTime' }).'#text'
                    if (-not $duration) {
                        $duration = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'Duration' }).'#text'
                    }
                }
                $label = if ($name) { $name } elseif ($fileName) { $fileName } else { '(inconnu)' }
                $durStr = if ($duration) { " [{0} ms]" -f $duration } else { '' }
                $type = switch ($s.Id) {
                    101 { 'app' }
                    102 { 'pilote' }
                    103 { 'service' }
                }
                Write-Result WARN ("  [{0}] {1}{2}" -f $type, $label, $durStr)
            }
        }
    }
}

# ============================================================
# CHECK 7 - PROGRAMMES AU DÉMARRAGE
# ============================================================

function Get-StartupPrograms {
    Write-Section 'PROGRAMMES AU DÉMARRAGE'
    Invoke-Check 'Programmes démarrage' {
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )
        $items = @()
        foreach ($k in $keys) {
            if (Test-Path $k) {
                $props = Get-ItemProperty $k
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -notmatch '^PS') {
                        $items += [pscustomobject]@{
                            Source = "Run"
                            Name   = $p.Name
                            Value  = "$($p.Value)"
                        }
                    }
                }
            }
        }

        $startupFolders = @(
            [Environment]::GetFolderPath('Startup'),
            [Environment]::GetFolderPath('CommonStartup')
        )
        foreach ($f in $startupFolders) {
            if ($f -and (Test-Path $f)) {
                Get-ChildItem $f -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $items += [pscustomobject]@{
                        Source = 'Dossier Startup'
                        Name   = $_.Name
                        Value  = $_.FullName
                    }
                }
            }
        }

        try {
            $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object {
                $_.State -ne 'Disabled' -and
                ($_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
            }
            foreach ($t in $tasks) {
                $items += [pscustomobject]@{
                    Source = 'Tâche planifiée (logon)'
                    Name   = $t.TaskName
                    Value  = $t.TaskPath
                }
            }
        } catch {}

        Write-Both "Total : $($items.Count) éléments lancés au démarrage / logon"
        Write-Both ''
        $shown = 0
        foreach ($i in $items) {
            if ($shown -ge 30) { break }
            $val = if ($i.Value.Length -gt 70) { $i.Value.Substring(0, 70) + '...' } else { $i.Value }
            Write-Result INFO ("  [{0}] {1} -> {2}" -f $i.Source, $i.Name, $val)
            $shown++
        }
        if ($items.Count -gt 30) {
            Write-Both "  ... et $($items.Count - 30) autres"
        }

        if ($items.Count -gt $Thresholds.StartupItemsWarning) {
            Add-Finding -Severity Warning -Category 'Startup' `
                -Description "$($items.Count) programmes lancés au démarrage" `
                -Recommendation "Désactiver les programmes inutiles via Gestionnaire des tâches > Démarrage" `
                -Symptom BootSlow
        }
    }
}

# ============================================================
# CHECK 8 - PILOTES EN ERREUR
# ============================================================

function Test-DriverErrors {
    Write-Section 'PILOTES EN ERREUR'
    Invoke-Check 'Pilotes' {
        try {
            $bad = Get-PnpDevice -ErrorAction Stop | Where-Object {
                $_.Status -in 'Error','Degraded','Unknown' -and $_.Present
            }
            if ($bad.Count -eq 0) {
                Write-Result OK 'Tous les pilotes présents fonctionnent'
                return
            }
            Write-Result WARN "$($bad.Count) pilote(s) en problème :"
            $shown = 0
            foreach ($d in $bad) {
                if ($shown -ge 20) { break }
                Write-Result WARN ("  [{0}] {1} - {2}" -f $d.Status, $d.Class, $d.FriendlyName)
                $shown++
            }
            $critical = $bad | Where-Object { $_.Class -in 'Net','Display','DiskDrive','SCSIAdapter','Storage','HDC' }
            if ($critical.Count -gt 0) {
                Add-Finding -Severity Critical -Category 'Drivers' `
                    -Description "$($critical.Count) pilote(s) critique(s) en erreur (réseau/affichage/stockage)" `
                    -Recommendation "Mettre à jour via Gestionnaire de périphériques ou site du fabricant" `
                    -Symptom @('Slowdown','BootSlow')
            }
            else {
                Add-Finding -Severity Warning -Category 'Drivers' `
                    -Description "$($bad.Count) pilote(s) en erreur" `
                    -Recommendation "Examiner via Gestionnaire de périphériques (devmgmt.msc)" `
                    -Symptom BootSlow
            }
        }
        catch {
            Write-Result ERR "Get-PnpDevice non disponible : $($_.Exception.Message)"
        }
    }
}

# ============================================================
# CHECK 9 - JOURNAL SYSTÈME
# ============================================================

function Get-CriticalSystemEvents {
    Write-Section 'JOURNAL SYSTÈME - ERREURS RÉCENTES'
    if (-not $isAdmin) {
        Write-Result INFO 'Nécessite des droits administrateur. Section ignorée.'
        return
    }
    Invoke-Check 'Events critiques' {
        $since = (Get-Date).AddHours(-$Thresholds.EventLookbackHours)
        $events = $null
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                Level     = 1,2
                StartTime = $since
            } -ErrorAction Stop -MaxEvents 500
        }
        catch {
            Write-Result OK "Aucune erreur critique sur les $($Thresholds.EventLookbackHours)h"
            return
        }

        if (-not $events -or $events.Count -eq 0) {
            Write-Result OK "Aucune erreur critique sur les $($Thresholds.EventLookbackHours)h"
            return
        }

        Write-Both "$($events.Count) erreur(s) sur les $($Thresholds.EventLookbackHours) dernières heures"

        $grouped = $events | Group-Object ProviderName, Id |
            Sort-Object Count -Descending |
            Select-Object -First $Thresholds.MaxEventsToShow

        Write-Both ''
        Write-Both 'Top erreurs (regroupées par source + ID) :'
        foreach ($g in $grouped) {
            $sample = $g.Group[0]
            $msg = ($sample.Message -split "`n" | Select-Object -First 1)
            if ($msg -and $msg.Length -gt 120) { $msg = $msg.Substring(0, 120) + '...' }
            Write-Result WARN ("{0,3}x [ID {1}] {2} : {3}" -f $g.Count, $sample.Id, $sample.ProviderName, $msg)
        }

        $diskErrs = $events | Where-Object { $_.ProviderName -in 'disk','Ntfs','volmgr','Disk' }
        if ($diskErrs.Count -gt 0) {
            Add-Finding -Severity Critical -Category 'Events' `
                -Description "$($diskErrs.Count) erreur(s) disque/NTFS dans le journal" `
                -Recommendation "Lancer 'chkdsk C: /scan' (lecture seule) et vérifier l'état SMART. Sauvegarder." `
                -Symptom @('Slowdown','BootSlow')
        }
        $whea = $events | Where-Object { $_.ProviderName -like '*WHEA*' }
        if ($whea.Count -gt 0) {
            Add-Finding -Severity Critical -Category 'Events' `
                -Description "$($whea.Count) erreur(s) WHEA-Logger (matériel)" `
                -Recommendation "Erreur matérielle (CPU/RAM/PCIe). Vérifier températures et tester RAM via mdsched.exe" `
                -Symptom Slowdown
        }
        $kp41 = $events | Where-Object { $_.ProviderName -like '*Kernel-Power*' -and $_.Id -eq 41 }
        if ($kp41.Count -gt 0) {
            Add-Finding -Severity Warning -Category 'Events' `
                -Description "$($kp41.Count) extinction(s) inattendue(s) (Kernel-Power 41)" `
                -Recommendation "Vérifier l'alimentation, températures et stabilité système" `
                -Symptom BootSlow
        }
    }
}

# ============================================================
# CHECK 10 - SERVICES WINDOWS
# ============================================================

function Test-WindowsServices {
    Write-Section 'SERVICES WINDOWS CLÉS'
    Invoke-Check 'Services' {
        $watch = @('wuauserv','BITS','WSearch','WinDefend','EventLog','Schedule','Themes','Spooler')
        foreach ($s in $watch) {
            try {
                $svc = Get-Service -Name $s -ErrorAction Stop
                $startMode = (Get-CimInstance Win32_Service -Filter "Name='$s'" -ErrorAction SilentlyContinue).StartMode
                $line = "{0,-12} {1,-10} (démarrage: {2})" -f $s, $svc.Status, $startMode
                if ($svc.Status -ne 'Running' -and $startMode -in 'Auto','Automatic') {
                    Write-Result WARN $line
                    Add-Finding -Severity Warning -Category 'Services' `
                        -Description "Service '$s' arrêté alors qu'il devrait démarrer automatiquement" `
                        -Recommendation "Vérifier dans services.msc pourquoi il est arrêté" `
                        -Symptom Slowdown
                }
                else {
                    Write-Result OK $line
                }
            }
            catch {
                Write-Result INFO ("{0,-12} introuvable" -f $s)
            }
        }
    }
}

# ============================================================
# CHECK 11 - ANTIVIRUS
# ============================================================

function Test-AntivirusStatus {
    Write-Section 'ANTIVIRUS / SÉCURITÉ'

    Invoke-Check 'Defender' {
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            $line = "Defender actif: {0} | Real-time: {1}" -f $mp.AntivirusEnabled, $mp.RealTimeProtectionEnabled
            if ($mp.AntivirusEnabled) { Write-Result OK $line } else { Write-Result WARN $line }

            if ($mp.AntivirusSignatureLastUpdated) {
                $sigAge = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
                $sigLine = "Signatures mises à jour il y a {0:N1} jours" -f $sigAge
                if ($sigAge -gt $Thresholds.SignatureAgeDaysCritical) {
                    Write-Result CRIT $sigLine
                    Add-Finding -Severity Critical -Category 'Security' `
                        -Description "Signatures Defender vieilles de $([math]::Round($sigAge,1)) jours" `
                        -Recommendation "Mettre à jour Defender via Windows Update"
                }
                elseif ($sigAge -gt $Thresholds.SignatureAgeDaysWarning) {
                    Write-Result WARN $sigLine
                    Add-Finding -Severity Warning -Category 'Security' `
                        -Description "Signatures Defender datant de $([math]::Round($sigAge,1)) jours" `
                        -Recommendation "Mettre à jour Defender via Windows Update prochainement"
                }
                else {
                    Write-Result OK $sigLine
                }
            }

            Write-Result INFO ("Dernier scan rapide : il y a {0} jour(s)" -f $mp.QuickScanAge)
            Write-Result INFO ("Dernier scan complet: il y a {0} jour(s)" -f $mp.FullScanAge)
        }
        catch {
            Write-Result INFO "Defender non interrogeable : $($_.Exception.Message)"
        }
    }

    Invoke-Check 'AV tiers' {
        try {
            $av = Get-CimInstance -Namespace 'root\SecurityCenter2' -Class AntivirusProduct -ErrorAction Stop
            if ($av) {
                Write-Both ''
                Write-Both 'Produits antivirus enregistrés :'
                foreach ($a in $av) {
                    Write-Result INFO ("  - $($a.displayName)")
                }
            }
        }
        catch {}
    }
}

# ============================================================
# CHECK 11b - EXTENSIONS NAVIGATEURS
# ============================================================

function Get-ChromiumExtensions {
    param([string]$RootPath, [string]$BrowserName)
    $results = @()
    if (-not (Test-Path -LiteralPath $RootPath)) { return $results }

    # Permissions considerees a risque pour un usage grand public
    $riskyPerms = @(
        '<all_urls>','*://*/*','http://*/*','https://*/*',
        'history','tabs','cookies','browsingData',
        'webRequest','webRequestBlocking','declarativeNetRequest',
        'proxy','management','privacy','clipboardRead','debugger',
        'desktopCapture','nativeMessaging','contentSettings'
    )

    # Parcours des profils (Default, Profile 1, Profile 2, etc.)
    $profiles = Get-ChildItem -LiteralPath $RootPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }

    foreach ($prof in $profiles) {
        $extDir = Join-Path $prof.FullName 'Extensions'
        if (-not (Test-Path -LiteralPath $extDir)) { continue }
        $extIds = Get-ChildItem -LiteralPath $extDir -Directory -ErrorAction SilentlyContinue
        foreach ($extId in $extIds) {
            # Une extension peut avoir plusieurs versions, on prend la plus recente
            $versionDirs = Get-ChildItem -LiteralPath $extId.FullName -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending
            $manifest = $null
            $manifestPath = $null
            foreach ($v in $versionDirs) {
                $p = Join-Path $v.FullName 'manifest.json'
                if (Test-Path -LiteralPath $p) {
                    try {
                        $raw = Get-Content -LiteralPath $p -Raw -ErrorAction Stop
                        $manifest = $raw | ConvertFrom-Json -ErrorAction Stop
                        $manifestPath = $p
                        break
                    } catch { continue }
                }
            }
            if (-not $manifest) { continue }

            # Nom (parfois localise via __MSG_xxx__)
            $name = $manifest.name
            if ($name -and $name -like '__MSG_*__') {
                # Tentative de resolution via _locales/en/messages.json
                try {
                    $vdir = Split-Path $manifestPath -Parent
                    $locales = @('fr','en','en_US')
                    foreach ($loc in $locales) {
                        $msgPath = Join-Path $vdir "_locales\$loc\messages.json"
                        if (Test-Path -LiteralPath $msgPath) {
                            $msgKey = $name -replace '^__MSG_(.+)__$','$1'
                            $msgs = Get-Content -LiteralPath $msgPath -Raw | ConvertFrom-Json
                            if ($msgs.$msgKey -and $msgs.$msgKey.message) {
                                $name = $msgs.$msgKey.message
                                break
                            }
                        }
                    }
                } catch {}
            }
            if (-not $name) { $name = "(sans nom)" }

            # Permissions
            $perms = @()
            if ($manifest.permissions) { $perms += $manifest.permissions }
            if ($manifest.host_permissions) { $perms += $manifest.host_permissions }
            if ($manifest.optional_permissions) { $perms += $manifest.optional_permissions }
            $permsStr = $perms -join ','

            $risky = @($perms | Where-Object {
                $p = $_
                $riskyPerms | Where-Object { $p -eq $_ -or $p -like $_ }
            })

            $results += [PSCustomObject]@{
                Browser     = $BrowserName
                Profile     = $prof.Name
                Id          = $extId.Name
                Name        = $name
                Version     = $manifest.version
                Permissions = $permsStr
                RiskyCount  = $risky.Count
                RiskyPerms  = ($risky -join ',')
            }
        }
    }
    return $results
}

function Get-FirefoxExtensions {
    $results = @()
    $ffRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    if (-not (Test-Path -LiteralPath $ffRoot)) { return $results }
    $profs = Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue
    foreach ($prof in $profs) {
        $extsJson = Join-Path $prof.FullName 'extensions.json'
        if (-not (Test-Path -LiteralPath $extsJson)) { continue }
        try {
            $data = Get-Content -LiteralPath $extsJson -Raw | ConvertFrom-Json
            foreach ($addon in $data.addons) {
                # On ignore les addons systeme/Mozilla
                if ($addon.location -eq 'app-system-defaults' -or $addon.location -eq 'app-builtin') { continue }
                if (-not $addon.active) { continue }
                $perms = @()
                if ($addon.userPermissions -and $addon.userPermissions.permissions) {
                    $perms += $addon.userPermissions.permissions
                }
                if ($addon.userPermissions -and $addon.userPermissions.origins) {
                    $perms += $addon.userPermissions.origins
                }
                $risky = @($perms | Where-Object { $_ -eq '<all_urls>' -or $_ -like '*://*/*' -or $_ -in @('history','cookies','tabs','browsingData','proxy','privacy') })
                $name = $addon.defaultLocale.name
                if (-not $name) { $name = $addon.id }
                $results += [PSCustomObject]@{
                    Browser     = 'Firefox'
                    Profile     = $prof.Name
                    Id          = $addon.id
                    Name        = $name
                    Version     = $addon.version
                    Permissions = ($perms -join ',')
                    RiskyCount  = $risky.Count
                    RiskyPerms  = ($risky -join ',')
                }
            }
        } catch {}
    }
    return $results
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        $bytes = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object -Property Length -Sum).Sum
        if (-not $bytes) { return 0 }
        return [math]::Round($bytes / 1MB, 0)
    } catch { return 0 }
}

function Test-MaintenanceSlots {
    Write-Section 'MAINTENANCE - CACHES ET FICHIERS TEMPORAIRES'

    Invoke-Check 'Espace récupérable' {
        $slots = @(
            @{ Label = 'Cache Chrome'; Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache') }
            @{ Label = 'Cache Edge';   Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache') }
            @{ Label = 'Cache Brave';  Path = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default\Cache') }
            @{ Label = 'Temp utilisateur'; Path = $env:TEMP }
            @{ Label = 'Temp Windows'; Path = 'C:\Windows\Temp' }
            @{ Label = 'Cache miniatures'; Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') }
        )
        $totalMb = 0
        $detail = @()
        foreach ($s in $slots) {
            $sz = Get-FolderSizeMB -Path $s.Path
            if ($sz -gt 0) {
                $totalMb += $sz
                $detail += "{0,-22} {1,6} MB" -f $s.Label, $sz
                Write-Result INFO ("  {0,-22} {1,6} MB" -f $s.Label, $sz)
            }
        }
        if ($totalMb -gt 500) {
            Add-Finding -Severity Info -Category 'Maintenance' `
                -Description ("Environ {0} Mo d'espace recuperable dans les caches et fichiers temporaires" -f $totalMb) `
                -Recommendation "Nettoyage 1 clic disponible dans Le Druide. Aucun risque : ces fichiers sont regeneres automatiquement par les logiciels."
        }
        Write-Result INFO ("Total recuperable estime : {0} MB" -f $totalMb)
    }
}

function Invoke-CleanupCaches {
    $targets = @(
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache')
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Code Cache')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Code Cache')
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default\Cache')
        $env:TEMP
        'C:\Windows\Temp'
    )
    $freedMb = 0
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        try {
            $before = Get-FolderSizeMB -Path $t
            Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer -or $_.Name -ne '.' } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            $after = Get-FolderSizeMB -Path $t
            $freedMb += ($before - $after)
        } catch {}
    }
    return [math]::Max(0, $freedMb)
}

function Test-BrowserExtensions {
    Write-Section 'EXTENSIONS NAVIGATEURS'

    Invoke-Check 'Extensions Chrome/Edge/Firefox' {
        $all = @()
        $chromeRoot = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
        $edgeRoot   = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
        $braveRoot  = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'

        if (Test-Path -LiteralPath $chromeRoot) { $all += Get-ChromiumExtensions -RootPath $chromeRoot -BrowserName 'Chrome' }
        if (Test-Path -LiteralPath $edgeRoot)   { $all += Get-ChromiumExtensions -RootPath $edgeRoot   -BrowserName 'Edge' }
        if (Test-Path -LiteralPath $braveRoot)  { $all += Get-ChromiumExtensions -RootPath $braveRoot  -BrowserName 'Brave' }
        $all += Get-FirefoxExtensions

        if ($all.Count -eq 0) {
            Write-Result INFO 'Aucune extension trouvee (ou navigateurs non installes).'
            return
        }

        Write-Result INFO "$($all.Count) extension(s) detectee(s) sur les navigateurs installes"

        # Regroupe par navigateur
        $byBrowser = $all | Group-Object Browser
        foreach ($g in $byBrowser) {
            Write-Both ''
            Write-Both "$($g.Name) ($($g.Count) extension(s)) :"
            foreach ($e in $g.Group) {
                $tag = 'INFO'
                if ($e.RiskyCount -ge 3) { $tag = 'WARN' }
                Write-Result $tag ("  [{0} perm. sensibles] {1} (v{2})" -f $e.RiskyCount, $e.Name, $e.Version)
            }
        }

        $suspicious = $all | Where-Object { $_.RiskyCount -ge 3 }
        if ($suspicious.Count -gt 0) {
            $names = ($suspicious | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', '
            Add-Finding -Severity Warning -Category 'Browser' `
                -Description "$($suspicious.Count) extension(s) avec permissions sensibles (>= 3) : $names" `
                -Recommendation "Verifiez dans le gestionnaire d'extensions de votre navigateur que vous reconnaissez bien chaque extension. Supprimez celles que vous ne reconnaissez pas."
        }
    }
}

# ============================================================
# CHECK 12 - RÉSEAU
# ============================================================

function Get-NetworkStatus {
    Write-Section 'RÉSEAU'
    Invoke-Check 'Adaptateurs' {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -in 'Up','Disconnected' }
        foreach ($a in $adapters) {
            $line = "{0,-25} {1,-12} {2}" -f $a.Name, $a.Status, $a.LinkSpeed
            if ($a.Status -eq 'Up') { Write-Result OK $line } else { Write-Result INFO $line }
        }
        $tcp = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue).Count
        Write-Result INFO ("Connexions TCP établies : {0}" -f $tcp)
    }
}

# ============================================================
# CHECK 13 - PLAN D'ALIMENTATION
# ============================================================

function Get-PowerPlan {
    Write-Section 'PLAN D''ALIMENTATION'
    Invoke-Check 'Power' {
        $out = powercfg /getactivescheme 2>&1 | Out-String
        $match = [regex]::Match($out, '\(([^)]+)\)')
        $name = if ($match.Success) { $match.Groups[1].Value.Trim() } else { $out.Trim() }
        Write-Result INFO "Plan actif : $name"

        $cs = Get-CimInstance Win32_ComputerSystem
        $isLaptop = $cs.PCSystemType -in 2,8
        if (-not $isLaptop -and $name -match 'conomie') {
            Write-Result WARN 'Plan "Économie d''énergie" sur poste fixe : peut brider les performances'
            Add-Finding -Severity Warning -Category 'Power' `
                -Description "Plan d'alimentation économique actif sur poste fixe" `
                -Recommendation "Passer en 'Performances élevées' ou 'Utilisation normale' (powercfg.cpl)" `
                -Symptom Slowdown
        }
    }
}

# ============================================================
# VERDICT FINAL
# ============================================================

function Write-Verdict {
    Write-Section 'VERDICT GLOBAL'
    $duration = (Get-Date) - $startTime
    Write-Result INFO ("Diagnostic exécuté en {0:N0} secondes" -f $duration.TotalSeconds)
    Write-Result INFO ("Findings totaux : {0}" -f $script:Findings.Count)

    $crit = @($script:Findings | Where-Object { $_.Severity -eq 'Critical' })
    $warn = @($script:Findings | Where-Object { $_.Severity -eq 'Warning' })

    Write-Result INFO ("  Critiques : {0}" -f $crit.Count)
    Write-Result INFO ("  Warnings  : {0}" -f $warn.Count)

    if ($crit.Count -eq 0 -and $warn.Count -eq 0) {
        Write-Both ''
        Write-Result OK 'Aucun problème majeur détecté'
        Write-Both 'Si les ralentissements persistent, lance avec -Full ou utilise des outils complémentaires (HWiNFO pour températures, CrystalDiskInfo pour SMART détaillé).'
        return
    }

    $sortKey = { if ($_.Severity -eq 'Critical') { 0 } else { 1 } }

    Write-Both ''
    Write-Both '--- SYMPTÔME A : Ralentissement progressif ---'
    $aFindings = @($script:Findings | Where-Object { $_.Symptom -contains 'Slowdown' } | Sort-Object $sortKey)
    if ($aFindings.Count -eq 0) {
        Write-Result OK 'Aucune cause directe identifiée'
    } else {
        $i = 1
        foreach ($f in $aFindings) {
            $lvl = if ($f.Severity -eq 'Critical') { 'CRIT' } else { 'WARN' }
            Write-Result $lvl ("$i. [$($f.Category)] $($f.Description)")
            Write-Both ("    -> $($f.Recommendation)")
            $i++
        }
    }

    Write-Both ''
    Write-Both '--- SYMPTÔME B : Boot/redémarrage anormalement long ---'
    $bFindings = @($script:Findings | Where-Object { $_.Symptom -contains 'BootSlow' } | Sort-Object $sortKey)
    if ($bFindings.Count -eq 0) {
        Write-Result OK 'Aucune cause directe identifiée'
    } else {
        $i = 1
        foreach ($f in $bFindings) {
            $lvl = if ($f.Severity -eq 'Critical') { 'CRIT' } else { 'WARN' }
            Write-Result $lvl ("$i. [$($f.Category)] $($f.Description)")
            Write-Both ("    -> $($f.Recommendation)")
            $i++
        }
    }

    Write-Both ''
    Write-Both '--- TOP 5 ACTIONS PRIORITAIRES ---'
    $priority = @($script:Findings | Sort-Object $sortKey | Select-Object -First 5)
    $i = 1
    foreach ($f in $priority) {
        $lvl = if ($f.Severity -eq 'Critical') { 'CRIT' } else { 'WARN' }
        Write-Result $lvl ("$i. [$($f.Category)] $($f.Recommendation)")
        $i++
    }
}

# ============================================================
# PIPELINE DE CHECKS (factorisé pour console + GUI)
# ============================================================

function Invoke-AllChecks {
    Show-MachineIdentity
    Test-DiskHealth
    Test-MemoryUsage
    Test-PendingReboot
    Test-WindowsUpdates
    Test-BootPerformance
    Get-StartupPrograms
    Test-DriverErrors
    Get-CriticalSystemEvents
    Test-WindowsServices
    Test-AntivirusStatus
    Test-BrowserExtensions
    Test-MaintenanceSlots
    Get-NetworkStatus
    Get-PowerPlan
    Write-Verdict
}

function Invoke-ExpressChecks {
    Show-MachineIdentity
    Test-DiskHealth
    Test-MemoryUsage
    Test-PendingReboot
    Test-AntivirusStatus
    Write-Verdict
}

function Save-Report {
    param([string]$Path)
    try {
        $script:Report.ToString() | Out-File -FilePath $Path -Encoding UTF8 -Force
        return $true
    }
    catch {
        return $false
    }
}

# ============================================================
# DRUIDIX - Assistant IA (5 fournisseurs) + stockage des clés
# ============================================================

$script:Druidix_Providers = @(
    @{ Id='openai';    Name='OpenAI (ChatGPT)';   Url='https://api.openai.com/v1/chat/completions';        Model='gpt-4o-mini' },
    @{ Id='anthropic'; Name='Anthropic (Claude)'; Url='https://api.anthropic.com/v1/messages';             Model='claude-haiku-4-5' },
    @{ Id='google';    Name='Google (Gemini)';    Url='https://generativelanguage.googleapis.com/v1beta';  Model='gemini-2.5-flash' },
    @{ Id='mistral';   Name='Mistral';            Url='https://api.mistral.ai/v1/chat/completions';        Model='mistral-small-latest' },
    @{ Id='deepseek';  Name='DeepSeek';           Url='https://api.deepseek.com/v1/chat/completions';      Model='deepseek-chat' }
)

function Get-DruidixSettingsPath {
    $dir = Join-Path $env:APPDATA 'LeDruide'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return Join-Path $dir 'settings.json'
}

function Read-DruidixSettings {
    $path = Get-DruidixSettingsPath
    if (-not (Test-Path $path)) { return @{ DefaultProvider='openai'; Keys=@{}; Models=@{} } }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $keys = @{}
        if ($raw.Keys) {
            foreach ($p in $raw.Keys.PSObject.Properties) { $keys[$p.Name] = $p.Value }
        }
        $models = @{}
        if ($raw.Models) {
            foreach ($p in $raw.Models.PSObject.Properties) { $models[$p.Name] = $p.Value }
        }
        $def = if ($raw.DefaultProvider) { $raw.DefaultProvider } else { 'openai' }
        return @{ DefaultProvider = $def; Keys = $keys; Models = $models }
    } catch {
        return @{ DefaultProvider='openai'; Keys=@{}; Models=@{} }
    }
}

function Save-DruidixSettings {
    param($Settings)
    $path = Get-DruidixSettingsPath
    try {
        $obj = [PSCustomObject]@{ DefaultProvider = $Settings.DefaultProvider; Keys = $Settings.Keys; Models = $Settings.Models }
        $obj | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding UTF8 -Force
        return $true
    } catch { return $false }
}

function Protect-DruidixKey {
    param([string]$Plain)
    if ([string]::IsNullOrEmpty($Plain)) { return '' }
    try {
        $secure = ConvertTo-SecureString $Plain -AsPlainText -Force
        return ConvertFrom-SecureString $secure
    } catch { return '' }
}

function Unprotect-DruidixKey {
    param([string]$Encrypted)
    if ([string]::IsNullOrEmpty($Encrypted)) { return '' }
    try {
        $secure = ConvertTo-SecureString $Encrypted -ErrorAction Stop
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch { return '' }
}

function Invoke-DruidixHttp {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Body,
        [int]$TimeoutSec = 60
    )
    # HTTP POST avec encodage UTF-8 explicite request + response (Invoke-RestMethod foire l'UTF-8 en PS5.1)
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $req = [System.Net.HttpWebRequest]::Create($Uri)
    $req.Method = 'POST'
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.ContentType = 'application/json; charset=utf-8'
    if ($Headers) {
        foreach ($k in $Headers.Keys) {
            $v = "$($Headers[$k])"
            switch -Regex ($k) {
                '^(?i)Content-Type$'   { $req.ContentType = $v; break }
                '^(?i)User-Agent$'     { $req.UserAgent = $v; break }
                '^(?i)Accept$'         { $req.Accept = $v; break }
                default                { $req.Headers.Add($k, $v) }
            }
        }
    }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $req.ContentLength = $bodyBytes.Length
    $reqStream = $req.GetRequestStream()
    $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
    $reqStream.Close()
    try {
        $resp = $req.GetResponse()
    } catch [System.Net.WebException] {
        $errResp = $_.Exception.Response
        if ($errResp) {
            try {
                $errStream = $errResp.GetResponseStream()
                $errReader = New-Object System.IO.StreamReader($errStream, [System.Text.Encoding]::UTF8)
                $errBody = $errReader.ReadToEnd()
                $errReader.Close()
            } catch { $errBody = '' }
            $code = [int]$errResp.StatusCode
            $errResp.Close()
            $msg = "HTTP $code"
            if ($errBody) {
                $short = if ($errBody.Length -gt 240) { $errBody.Substring(0, 240) + '...' } else { $errBody }
                $msg += " - $short"
            }
            throw $msg
        }
        throw
    }
    $respStream = $resp.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd()
    $reader.Close()
    $resp.Close()
    return ($text | ConvertFrom-Json)
}

function Invoke-DruidixApi {
    param(
        [string]$ProviderId,
        [string]$ApiKey,
        [string]$SystemPrompt,
        [string]$Question,
        [string]$ModelOverride
    )
    $provider = $script:Druidix_Providers | Where-Object { $_.Id -eq $ProviderId } | Select-Object -First 1
    if (-not $provider) { throw "Provider inconnu : $ProviderId" }
    $model = if (-not [string]::IsNullOrWhiteSpace($ModelOverride)) { $ModelOverride.Trim() } else { $provider.Model }

    switch ($ProviderId) {
        'openai' {
            $body = @{
                model = $model
                messages = @(
                    @{ role='system'; content=$SystemPrompt },
                    @{ role='user'; content=$Question }
                )
                temperature = 0.5
            } | ConvertTo-Json -Depth 5 -Compress
            $headers = @{ Authorization="Bearer $ApiKey" }
            $resp = Invoke-DruidixHttp -Uri $provider.Url -Headers $headers -Body $body
            return $resp.choices[0].message.content
        }
        'anthropic' {
            $body = @{
                model = $model
                max_tokens = 1024
                system = $SystemPrompt
                messages = @(@{ role='user'; content=$Question })
            } | ConvertTo-Json -Depth 5 -Compress
            $headers = @{
                'x-api-key' = $ApiKey
                'anthropic-version' = '2023-06-01'
            }
            $resp = Invoke-DruidixHttp -Uri $provider.Url -Headers $headers -Body $body
            return $resp.content[0].text
        }
        'google' {
            $body = @{
                systemInstruction = @{ parts = @(@{ text = $SystemPrompt }) }
                contents = @(@{ role='user'; parts = @(@{ text = $Question }) })
            } | ConvertTo-Json -Depth 5 -Compress
            $url = "$($provider.Url)/models/$($model):generateContent?key=$ApiKey"
            $resp = Invoke-DruidixHttp -Uri $url -Headers @{} -Body $body
            return $resp.candidates[0].content.parts[0].text
        }
        'mistral' {
            $body = @{
                model = $model
                messages = @(
                    @{ role='system'; content=$SystemPrompt },
                    @{ role='user'; content=$Question }
                )
            } | ConvertTo-Json -Depth 5 -Compress
            $headers = @{ Authorization="Bearer $ApiKey" }
            $resp = Invoke-DruidixHttp -Uri $provider.Url -Headers $headers -Body $body
            return $resp.choices[0].message.content
        }
        'deepseek' {
            $body = @{
                model = $model
                messages = @(
                    @{ role='system'; content=$SystemPrompt },
                    @{ role='user'; content=$Question }
                )
            } | ConvertTo-Json -Depth 5 -Compress
            $headers = @{ Authorization="Bearer $ApiKey" }
            $resp = Invoke-DruidixHttp -Uri $provider.Url -Headers $headers -Body $body
            return $resp.choices[0].message.content
        }
    }
}

function Show-SettingsDialog {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $cBg = [System.Drawing.Color]::FromArgb(0xF4, 0xEC, 0xD8)
    $cCard = [System.Drawing.Color]::White
    $cBorder = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $cText = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
    $cTextMuted = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
    $cAccent = [System.Drawing.Color]::FromArgb(0x1F, 0x4D, 0x3A)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Paramètres - Clés API'
    $form.Size = New-Object System.Drawing.Size(640, 740)
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = $cBg
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $form.ForeColor = $cText
    try { $ic = Get-DruideIcon; if ($ic) { $form.Icon = $ic } } catch {}

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Paramètres - L'Oeil d'Antavirus"
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $cText
    $titleLabel.Location = New-Object System.Drawing.Point(20, 16)
    $titleLabel.AutoSize = $true
    $form.Controls.Add($titleLabel)

    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = "Renseignez au moins une clé API pour discuter avec L'Oeil d'Antavirus. Les clés sont chiffrées (DPAPI) sur ce compte utilisateur."
    $infoLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $infoLabel.ForeColor = $cTextMuted
    $infoLabel.Location = New-Object System.Drawing.Point(22, 48)
    $infoLabel.Size = New-Object System.Drawing.Size(580, 32)
    $form.Controls.Add($infoLabel)

    $settings = Read-DruidixSettings
    $script:Druidix_TextBoxes = @{}
    $script:Druidix_ModelBoxes = @{}
    $y = 95

    foreach ($provider in $script:Druidix_Providers) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $y)
        $card.Size = New-Object System.Drawing.Size(580, 90)
        $card.BackColor = $cCard
        $card.Add_Paint({
            param($s, $e)
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8))
            $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width-1, $s.Height-1)
            $pen.Dispose()
        })
        $form.Controls.Add($card)

        $nameLabel = New-Object System.Windows.Forms.Label
        $nameLabel.Text = $provider.Name
        $nameLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $nameLabel.Location = New-Object System.Drawing.Point(15, 8)
        $nameLabel.AutoSize = $true
        $card.Controls.Add($nameLabel)

        $keyHint = New-Object System.Windows.Forms.Label
        $keyHint.Text = 'Cle :'
        $keyHint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $keyHint.ForeColor = $cTextMuted
        $keyHint.Location = New-Object System.Drawing.Point(15, 33)
        $keyHint.AutoSize = $true
        $card.Controls.Add($keyHint)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(50, 31)
        $tb.Size = New-Object System.Drawing.Size(405, 22)
        $tb.UseSystemPasswordChar = $true
        $tb.Font = New-Object System.Drawing.Font('Consolas', 9)
        $existing = ''
        if ($settings.Keys -and $settings.Keys.ContainsKey($provider.Id)) {
            $existing = Unprotect-DruidixKey $settings.Keys[$provider.Id]
        }
        $tb.Text = $existing
        $card.Controls.Add($tb)
        $script:Druidix_TextBoxes[$provider.Id] = $tb

        $btnTest = New-Object System.Windows.Forms.Button
        $btnTest.Text = 'Tester'
        $btnTest.Location = New-Object System.Drawing.Point(465, 30)
        $btnTest.Size = New-Object System.Drawing.Size(95, 24)
        $btnTest.FlatStyle = 'Flat'
        $btnTest.BackColor = $cBg
        $btnTest.FlatAppearance.BorderColor = $cBorder
        $btnTest.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $btnTest.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnTest.Tag = $provider.Id
        $btnTest.Add_Click({
            param($s, $e)
            $pid_ = $s.Tag
            $key = $script:Druidix_TextBoxes[$pid_].Text
            $modelOverride = $script:Druidix_ModelBoxes[$pid_].Text
            if ([string]::IsNullOrWhiteSpace($key)) {
                [System.Windows.Forms.MessageBox]::Show('Cle vide.', 'Test', 'OK', 'Warning') | Out-Null
                return
            }
            $orig = $s.Text
            $s.Text = '...'
            $s.Enabled = $false
            [System.Windows.Forms.Application]::DoEvents()
            try {
                $r = Invoke-DruidixApi -ProviderId $pid_ -ApiKey $key -SystemPrompt 'Reponds en un mot : OK' -Question 'Test' -ModelOverride $modelOverride
                $preview = if ($r.Length -gt 80) { $r.Substring(0, 80) + '...' } else { $r }
                [System.Windows.Forms.MessageBox]::Show("Connexion OK.`nReponse : $preview", 'Test reussi', 'OK', 'Information') | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Echec : $($_.Exception.Message)", 'Test echoue', 'OK', 'Error') | Out-Null
            } finally {
                $s.Text = $orig
                $s.Enabled = $true
            }
        })
        $card.Controls.Add($btnTest)

        $modelHint = New-Object System.Windows.Forms.Label
        $modelHint.Text = 'Modele :'
        $modelHint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $modelHint.ForeColor = $cTextMuted
        $modelHint.Location = New-Object System.Drawing.Point(15, 60)
        $modelHint.AutoSize = $true
        $card.Controls.Add($modelHint)

        $tbModel = New-Object System.Windows.Forms.TextBox
        $tbModel.Location = New-Object System.Drawing.Point(70, 58)
        $tbModel.Size = New-Object System.Drawing.Size(280, 22)
        $tbModel.Font = New-Object System.Drawing.Font('Consolas', 9)
        $existingModel = ''
        if ($settings.Models -and $settings.Models.ContainsKey($provider.Id)) {
            $existingModel = $settings.Models[$provider.Id]
        }
        $tbModel.Text = $existingModel
        $card.Controls.Add($tbModel)
        $script:Druidix_ModelBoxes[$provider.Id] = $tbModel

        $modelDefaultLabel = New-Object System.Windows.Forms.Label
        $modelDefaultLabel.Text = "(defaut : $($provider.Model))"
        $modelDefaultLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Italic)
        $modelDefaultLabel.ForeColor = $cTextMuted
        $modelDefaultLabel.Location = New-Object System.Drawing.Point(360, 60)
        $modelDefaultLabel.AutoSize = $true
        $card.Controls.Add($modelDefaultLabel)

        $y += 96
    }

    $defLabel = New-Object System.Windows.Forms.Label
    $defLabel.Text = 'Provider par defaut :'
    $defLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $defLabel.Location = New-Object System.Drawing.Point(22, ($y + 8))
    $defLabel.AutoSize = $true
    $form.Controls.Add($defLabel)

    $cmbDefault = New-Object System.Windows.Forms.ComboBox
    $cmbDefault.DropDownStyle = 'DropDownList'
    $cmbDefault.Location = New-Object System.Drawing.Point(160, ($y + 5))
    $cmbDefault.Size = New-Object System.Drawing.Size(200, 24)
    foreach ($p in $script:Druidix_Providers) { [void]$cmbDefault.Items.Add($p.Name) }
    $defaultIdx = 0
    for ($i=0; $i -lt $script:Druidix_Providers.Count; $i++) {
        if ($script:Druidix_Providers[$i].Id -eq $settings.DefaultProvider) { $defaultIdx = $i; break }
    }
    $cmbDefault.SelectedIndex = $defaultIdx
    $form.Controls.Add($cmbDefault)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Enregistrer'
    $btnSave.Location = New-Object System.Drawing.Point(380, ($y + 50))
    $btnSave.Size = New-Object System.Drawing.Size(110, 32)
    $btnSave.FlatStyle = 'Flat'
    $btnSave.BackColor = $cAccent
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.FlatAppearance.BorderSize = 0
    $btnSave.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnSave.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSave.Add_Click({
        $newKeys = @{}
        $newModels = @{}
        foreach ($p in $script:Druidix_Providers) {
            $val = $script:Druidix_TextBoxes[$p.Id].Text
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $newKeys[$p.Id] = Protect-DruidixKey $val
            }
            $modelVal = $script:Druidix_ModelBoxes[$p.Id].Text
            if (-not [string]::IsNullOrWhiteSpace($modelVal)) {
                $newModels[$p.Id] = $modelVal.Trim()
            }
        }
        $newSettings = @{
            DefaultProvider = $script:Druidix_Providers[$cmbDefault.SelectedIndex].Id
            Keys = $newKeys
            Models = $newModels
        }
        if (Save-DruidixSettings $newSettings) {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show('Echec sauvegarde.', 'Erreur', 'OK', 'Error') | Out-Null
        }
    })
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Annuler'
    $btnCancel.Location = New-Object System.Drawing.Point(497, ($y + 50))
    $btnCancel.Size = New-Object System.Drawing.Size(100, 32)
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.BackColor = $cCard
    $btnCancel.ForeColor = $cText
    $btnCancel.FlatAppearance.BorderColor = $cBorder
    $btnCancel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancel.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $form.Close() })
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel

    [void]$form.ShowDialog()
}

$script:ScheduledTaskName = 'LeDruideAntavirus_WeeklyScan'

function Get-ScheduledScanInfo {
    $info = [PSCustomObject]@{
        Active   = $false
        NextRun  = $null
        DayOfWeek = 'Sunday'
        Hour     = 10
    }
    try {
        $t = Get-ScheduledTask -TaskName $script:ScheduledTaskName -ErrorAction Stop
        $info.Active = $true
        $trig = $t.Triggers | Select-Object -First 1
        if ($trig -and $trig.StartBoundary) {
            try {
                $dt = [datetime]$trig.StartBoundary
                $info.Hour = $dt.Hour
            } catch {}
        }
        if ($trig -and $trig.DaysOfWeek) { $info.DayOfWeek = "$($trig.DaysOfWeek)" }
        try {
            $i = Get-ScheduledTaskInfo -TaskName $script:ScheduledTaskName -ErrorAction Stop
            $info.NextRun = $i.NextRunTime
        } catch {}
    } catch {}
    return $info
}

function Enable-ScheduledScan {
    param(
        [string]$ExePath,
        [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
        [string]$DayOfWeek = 'Sunday',
        [int]$Hour = 10
    )
    if (-not (Test-Path -LiteralPath $ExePath)) { return $false }
    try {
        $time = ('{0:D2}:00' -f $Hour)
        $action = New-ScheduledTaskAction -Execute $ExePath -Argument '-Silent'
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $time
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
        Register-ScheduledTask -TaskName $script:ScheduledTaskName -Action $action -Trigger $trigger -Settings $settings `
            -Description "Le Druide Antavirus - scanneur hebdomadaire automatique" `
            -Force -RunLevel Highest | Out-Null
        return $true
    } catch { return $false }
}

function Disable-ScheduledScan {
    try {
        Unregister-ScheduledTask -TaskName $script:ScheduledTaskName -Confirm:$false -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Show-CriticalToast {
    param([int]$Count, [string]$ReportPath)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $notify = New-Object System.Windows.Forms.NotifyIcon
        try {
            $ic = Get-DruideIcon
            if ($ic) { $notify.Icon = $ic } else { $notify.Icon = [System.Drawing.SystemIcons]::Warning }
        } catch { $notify.Icon = [System.Drawing.SystemIcons]::Warning }
        $notify.Visible = $true
        $notify.BalloonTipTitle = 'Le Druide Antavirus'
        $msg = if ($Count -eq 1) {
            "Le scan hebdomadaire a trouvé 1 point critique sur votre PC. Cliquez pour voir le rapport."
        } else {
            "Le scan hebdomadaire a trouvé $Count points critiques sur votre PC. Cliquez pour voir le rapport."
        }
        $notify.BalloonTipText = $msg
        $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
        $notify.Text = 'Le Druide Antavirus'
        $notify.Add_BalloonTipClicked({
            try { if ($ReportPath -and (Test-Path -LiteralPath $ReportPath)) { Start-Process notepad.exe $ReportPath } } catch {}
        })
        $notify.ShowBalloonTip(10000)
        Start-Sleep -Seconds 12
        $notify.Dispose()
    } catch {}
}

function Get-ReportsArchiveDir {
    $dir = Join-Path $env:APPDATA 'LeDruide\Reports'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    return $dir
}

function Get-ArchivedReports {
    $dir = Get-ReportsArchiveDir
    return Get-ChildItem -LiteralPath $dir -Filter 'Diagnostic-PC_*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}

function Add-ReportToArchive {
    param([string]$Path, [int]$KeepMax = 20)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $dir = Get-ReportsArchiveDir
    try {
        Copy-Item -LiteralPath $Path -Destination $dir -Force -ErrorAction Stop
        # Purge : on garde les N plus recents
        $all = Get-ArchivedReports
        if ($all.Count -gt $KeepMax) {
            $all | Select-Object -Skip $KeepMax | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Save-FindingsSnapshot {
    # Archive les findings en JSON pour permettre la comparaison entre scans
    $dir = Get-ReportsArchiveDir
    try {
        $ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $snap = [PSCustomObject]@{
            Timestamp = $ts
            Date      = (Get-Date).ToString('o')
            Findings  = @($script:Findings | ForEach-Object {
                [PSCustomObject]@{
                    Severity       = $_.Severity
                    Category       = $_.Category
                    Description    = $_.Description
                    Recommendation = $_.Recommendation
                }
            })
        }
        $path = Join-Path $dir "Findings_$ts.json"
        $snap | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding UTF8 -Force
        # Purge : on garde les 20 plus recents
        $jsons = Get-ChildItem -LiteralPath $dir -Filter 'Findings_*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if ($jsons.Count -gt 20) {
            $jsons | Select-Object -Skip 20 | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Get-PreviousFindings {
    # Retourne les findings du scan precedent (le plus recent dans l'archive).
    # IMPORTANT : appeler AVANT Save-FindingsSnapshot pour le scan courant.
    $dir = Get-ReportsArchiveDir
    try {
        $last = Get-ChildItem -LiteralPath $dir -Filter 'Findings_*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $last) { return $null }
        $data = Get-Content -LiteralPath $last.FullName -Raw | ConvertFrom-Json
        return $data
    } catch { return $null }
}

function Get-FindingsDiff {
    param($Previous)
    if (-not $Previous -or -not $Previous.Findings) {
        return $null
    }
    $prevKeys = @($Previous.Findings | ForEach-Object { "$($_.Category)|$($_.Severity)" })
    $currKeys = @($script:Findings | ForEach-Object { "$($_.Category)|$($_.Severity)" })

    $resolved   = @($Previous.Findings | Where-Object { $currKeys -notcontains "$($_.Category)|$($_.Severity)" })
    $newOnes    = @($script:Findings | Where-Object { $prevKeys -notcontains "$($_.Category)|$($_.Severity)" })
    $persistent = @($script:Findings | Where-Object { $prevKeys -contains "$($_.Category)|$($_.Severity)" })

    return [PSCustomObject]@{
        PreviousDate = $Previous.Date
        Resolved     = $resolved
        New          = $newOnes
        Persistent   = $persistent
    }
}

function ConvertTo-AnonymizedText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $out = $Text
    # Paths utilisateurs Windows
    $out = [regex]::Replace($out, '([A-Za-z]:\\Users\\)([^\\/:*?"<>|]+)', '$1<USER>')
    $out = [regex]::Replace($out, '(/Users/)([^/]+)', '$1<USER>')
    # Nom machine
    try {
        $host_ = $env:COMPUTERNAME
        if ($host_) { $out = $out -replace [regex]::Escape($host_), '<PC>' }
    } catch {}
    # Numero de serie disques (SMART)
    $out = [regex]::Replace($out, '(SerialNumber|SN)\s*[:=]\s*\S+', '$1=<SN>')
    # Adresses MAC
    $out = [regex]::Replace($out, '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b', '<MAC>')
    # Adresses IP privees (on garde l'info "reseau prive" sans la valeur exacte)
    $out = [regex]::Replace($out, '\b(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))\.\d+\.\d+\b', '<IP_PRIVEE>')
    return $out
}

function Show-DruidixDialog {
    param([string]$InitialQuestion)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $cBg = [System.Drawing.Color]::FromArgb(0xF4, 0xEC, 0xD8)
    $cCard = [System.Drawing.Color]::White
    $cBorder = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $cText = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
    $cTextMuted = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
    $cAccent = [System.Drawing.Color]::FromArgb(0x1F, 0x4D, 0x3A)
    $cBrand = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "L'Oeil d'Antavirus - votre assistant numerique"
    $form.Size = New-Object System.Drawing.Size(820, 680)
    $form.StartPosition = 'CenterParent'
    $form.MinimumSize = New-Object System.Drawing.Size(620, 460)
    $form.BackColor = $cBg
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $form.ForeColor = $cText
    try { $ic = Get-DruideIcon; if ($ic) { $form.Icon = $ic } } catch {}

    $chatFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $chatFlow.Dock = 'Fill'
    $chatFlow.BackColor = $cBg
    $chatFlow.AutoScroll = $true
    $chatFlow.FlowDirection = 'TopDown'
    $chatFlow.WrapContents = $false
    $chatFlow.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 16)
    $form.Controls.Add($chatFlow)

    $inputPanel = New-Object System.Windows.Forms.Panel
    $inputPanel.Dock = 'Bottom'
    $inputPanel.Height = 80
    $inputPanel.BackColor = $cCard
    $inputPanel.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8))
        $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
        $pen.Dispose()
    })
    $tbInput = New-Object System.Windows.Forms.TextBox
    $tbInput.Location = New-Object System.Drawing.Point(20, 22)
    $tbInput.Size = New-Object System.Drawing.Size(($form.ClientSize.Width - 150), 36)
    $tbInput.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $tbInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $inputPanel.Controls.Add($tbInput)

    $btnSend = New-Object System.Windows.Forms.Button
    $btnSend.Text = 'Envoyer'
    $btnSend.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 120), 21)
    $btnSend.Size = New-Object System.Drawing.Size(100, 36)
    $btnSend.FlatStyle = 'Flat'
    $btnSend.BackColor = $cAccent
    $btnSend.ForeColor = [System.Drawing.Color]::White
    $btnSend.FlatAppearance.BorderSize = 0
    $btnSend.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnSend.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSend.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $inputPanel.Controls.Add($btnSend)
    $form.Controls.Add($inputPanel)

    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = 'Top'
    $headerPanel.Height = 96
    $headerPanel.BackColor = $cCard
    $headerPanel.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8))
        $e.Graphics.DrawLine($pen, 0, $s.Height-1, $s.Width, $s.Height-1)
        $pen.Dispose()
    })
    $eyeLabel = New-Object System.Windows.Forms.Label
    $eyeLabel.Text = [char]::ConvertFromUtf32(0x1F441) + [char]0xFE0F
    $eyeLabel.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 22)
    $eyeLabel.UseCompatibleTextRendering = $true
    $eyeLabel.Location = New-Object System.Drawing.Point(22, 26)
    $eyeLabel.Size = New-Object System.Drawing.Size(48, 48)
    $eyeLabel.TextAlign = 'MiddleCenter'
    $headerPanel.Controls.Add($eyeLabel)
    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = "L'Oeil d'Antavirus"
    $nameLabel.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $nameLabel.ForeColor = $cText
    $nameLabel.Location = New-Object System.Drawing.Point(82, 18)
    $nameLabel.AutoSize = $true
    $headerPanel.Controls.Add($nameLabel)
    $tagLabel = New-Object System.Windows.Forms.Label
    $tagLabel.Text = "Il veille sur votre PC - Posez vos questions"
    $tagLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $tagLabel.ForeColor = $cTextMuted
    $tagLabel.Location = New-Object System.Drawing.Point(84, 56)
    $tagLabel.AutoSize = $true
    $headerPanel.Controls.Add($tagLabel)
    $btnSettingsTopRight = New-Object System.Windows.Forms.Button
    $btnSettingsTopRight.Text = [char]0x2699 + ' Paramètres'
    $btnSettingsTopRight.Size = New-Object System.Drawing.Size(130, 32)
    $btnSettingsTopRight.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 150), 32)
    $btnSettingsTopRight.FlatStyle = 'Flat'
    $btnSettingsTopRight.BackColor = $cBg
    $btnSettingsTopRight.ForeColor = $cText
    $btnSettingsTopRight.FlatAppearance.BorderColor = $cBorder
    $btnSettingsTopRight.UseCompatibleTextRendering = $true
    $btnSettingsTopRight.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnSettingsTopRight.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSettingsTopRight.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnSettingsTopRight.Add_Click({ Show-SettingsDialog })
    $headerPanel.Controls.Add($btnSettingsTopRight)
    $form.Controls.Add($headerPanel)

    $findingsText = ''
    if ($script:Findings -and $script:Findings.Count -gt 0) {
        $findingsText = "Diagnostic actuel ($($script:Findings.Count) findings, anonymise) :`n"
        foreach ($f in $script:Findings) {
            $desc = ConvertTo-AnonymizedText $f.Description
            $reco = ConvertTo-AnonymizedText $f.Recommendation
            $findingsText += "- [$($f.Severity)] [$($f.Category)] $desc -> $reco`n"
        }
    } else {
        $findingsText = "Aucun diagnostic n'a encore ete lance dans cette session."
    }

    $systemPrompt = "Tu es l'Oeil d'Antavirus, l'assistant IA de l'application 'Le Druide Antavirus' qui diagnostique et protege les PC Windows pour Triskell Studio.`nTu reponds toujours en francais, avec un ton bienveillant, clair et accessible aux non-techniciens.`nTu vouvoies TOUJOURS l'utilisateur (jamais de tutoiement).`nTu evites les anglicismes : 'mise a jour' au lieu de 'update', 'scanneur' / 'analyse' au lieu de 'scan', 'parametres' au lieu de 'settings'.`nTu n'es jamais alarmiste ni condescendant. Pas de majuscules en cris, pas d'urgence factice.`nSois concis (2-4 paragraphes max) et propose des actions concretes.`nQuand tu signales un probleme, dis dans cet ordre : ce que c'est, pourquoi c'est genant, quoi faire.`nSi l'utilisateur demande quelque chose hors du contexte du diagnostic PC, redirige-le poliment.`n`nIMPORTANT - format de reponse :`n- Reponds en TEXTE PLAIN, sans aucun formatage Markdown.`n- N'utilise JAMAIS d'asterisques pour le gras (**) ni d'italique (*) ni de titres (#).`n- N'utilise PAS d'emojis (le rendu de l'app ne les supporte pas correctement).`n- Pour les listes, utilise des tirets simples (- item) ou des numeros (1. item).`n`nContexte du diagnostic :`n$findingsText"

    $cBodyText = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
    $cWarn     = [System.Drawing.Color]::FromArgb(0xD9, 0x89, 0x2E)
    $cDanger   = [System.Drawing.Color]::FromArgb(0xB2, 0x3B, 0x3B)
    $cMuted    = $cTextMuted
    $fontSenderBold = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $fontBody       = New-Object System.Drawing.Font('Segoe UI', 10)
    $fontMutedItalic = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Italic)

    $script:Druidix_AppendChat = {
        param([string]$Sender, [string]$Text, [System.Drawing.Color]$SenderColor, [System.Drawing.Color]$BodyColor, [System.Drawing.Font]$BodyFont)
        if (-not $BodyColor) { $BodyColor = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E) }
        if (-not $BodyFont)  { $BodyFont  = New-Object System.Drawing.Font('Segoe UI', 10) }

        $isUser    = ($Sender -eq 'Vous')
        $isSpecial = ($Sender -in @('Système', 'Confidentialité', 'Erreur'))

        # Style selon le type de message
        $showHeader = $true
        if ($isUser) {
            $bubbleBg   = [System.Drawing.Color]::FromArgb(0x1F, 0x4D, 0x3A)
            $bubbleFg   = [System.Drawing.Color]::White
            $headerFg   = [System.Drawing.Color]::FromArgb(0xF4, 0xEC, 0xD8)
            $align      = 'Right'
            $avatar     = ''
            $showHeader = $false
        }
        elseif ($Sender -eq 'Erreur') {
            $bubbleBg = [System.Drawing.Color]::FromArgb(0xFA, 0xE5, 0xE5)
            $bubbleFg = [System.Drawing.Color]::FromArgb(0xB2, 0x3B, 0x3B)
            $headerFg = [System.Drawing.Color]::FromArgb(0xB2, 0x3B, 0x3B)
            $align    = 'Center'
            $avatar   = [string]([char]0x26A0) + [string]([char]0xFE0F)
        }
        elseif ($Sender -eq 'Confidentialité') {
            $bubbleBg = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
            $bubbleFg = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
            $headerFg = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)
            $align    = 'Center'
            $avatar   = [char]::ConvertFromUtf32(0x1F512)
        }
        elseif ($isSpecial) {
            # Système
            $bubbleBg = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
            $bubbleFg = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
            $headerFg = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)
            $align    = 'Center'
            $avatar   = [string]([char]0x2699) + [string]([char]0xFE0F)
        }
        else {
            # L'Oeil d'Antavirus
            $bubbleBg = [System.Drawing.Color]::FromArgb(0xFA, 0xF6, 0xEA)
            $bubbleFg = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
            $headerFg = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)
            $align    = 'Left'
            $avatar   = [char]::ConvertFromUtf32(0x1F441) + [char]0xFE0F
        }

        # Largeurs
        $availableW = $chatFlow.ClientSize.Width - 50
        if ($availableW -lt 200) { $availableW = 400 }
        $bubbleMaxW = [int]($availableW * 0.80)
        $textInnerW = $bubbleMaxW - 32

        # Mesure du texte (avec wrap)
        $proposed = New-Object System.Drawing.Size($textInnerW, [int]::MaxValue)
        $measured = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $BodyFont, $proposed, [System.Windows.Forms.TextFormatFlags]::WordBreak)

        $textW = [Math]::Min($textInnerW, $measured.Width)
        $bubbleWidth = $textW + 32
        if ($bubbleWidth -lt 140) { $bubbleWidth = 140 }
        if ($bubbleWidth -gt $bubbleMaxW) { $bubbleWidth = $bubbleMaxW }

        $hdrHeight = 0
        if ($showHeader) { $hdrHeight = 26 }
        $bubbleHeight = $hdrHeight + $measured.Height + 22

        # Wrapper qui gere l'alignement gauche / centre / droite
        $wrapper = New-Object System.Windows.Forms.Panel
        $wrapper.Width = $availableW
        $wrapper.Height = $bubbleHeight + 12
        $wrapper.BackColor = $cBg
        $wrapper.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

        # Bulle
        $bubble = New-Object System.Windows.Forms.Panel
        $bubble.Width = $bubbleWidth
        $bubble.Height = $bubbleHeight
        $bubble.BackColor = $bubbleBg
        switch ($align) {
            'Right'  { $bubble.Location = New-Object System.Drawing.Point(($wrapper.Width - $bubbleWidth - 4), 0) }
            'Center' { $bubble.Location = New-Object System.Drawing.Point([int](($wrapper.Width - $bubbleWidth) / 2), 0) }
            default  { $bubble.Location = New-Object System.Drawing.Point(4, 0) }
        }

        if ($showHeader) {
            $headerText = if ($avatar) { "$avatar   $Sender" } else { $Sender }
            $headerLabel = New-Object System.Windows.Forms.Label
            $headerLabel.Text = $headerText
            $headerLabel.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 10.5, [System.Drawing.FontStyle]::Bold)
            $headerLabel.UseCompatibleTextRendering = $true
            $headerLabel.ForeColor = $headerFg
            $headerLabel.Location = New-Object System.Drawing.Point(14, 7)
            $headerLabel.AutoSize = $true
            $headerLabel.BackColor = [System.Drawing.Color]::Transparent
            $bubble.Controls.Add($headerLabel)
        }

        $textLabel = New-Object System.Windows.Forms.Label
        $textLabel.Text = $Text
        $textLabel.Font = $BodyFont
        $textLabel.ForeColor = $bubbleFg
        $textLabel.Location = New-Object System.Drawing.Point(14, ($hdrHeight + 6))
        $textLabel.Size = New-Object System.Drawing.Size(($bubbleWidth - 28), $measured.Height)
        $textLabel.AutoSize = $false
        $textLabel.BackColor = [System.Drawing.Color]::Transparent
        $textLabel.UseCompatibleTextRendering = $true
        $bubble.Controls.Add($textLabel)

        $wrapper.Controls.Add($bubble)

        # Coins arrondis sur la bulle
        Set-RoundedRegion -Button $bubble -Radius 14

        $chatFlow.Controls.Add($wrapper)

        # Auto-scroll vers le bas
        try {
            $chatFlow.PerformLayout()
            if ($chatFlow.VerticalScroll.Visible) {
                $chatFlow.VerticalScroll.Value = [Math]::Max(0, $chatFlow.VerticalScroll.Maximum)
            }
            $chatFlow.ScrollControlIntoView($wrapper)
        } catch {}

        return $wrapper
    }

    $script:Druidix_ThinkingPanel = $null
    $script:Druidix_RemoveThinking = {
        if ($script:Druidix_ThinkingPanel) {
            try {
                $chatFlow.Controls.Remove($script:Druidix_ThinkingPanel)
                $script:Druidix_ThinkingPanel.Dispose()
            } catch {}
            $script:Druidix_ThinkingPanel = $null
        }
    }

    & $script:Druidix_AppendChat "L'Oeil d'Antavirus" "Bonjour ! Je suis l'Oeil d'Antavirus, l'assistant qui veille sur votre PC. Je peux vous expliquer le diagnostic et vous conseiller en mots simples.`r`n`r`nExemples : `"Pourquoi mon PC est lent ?`", `"C'est quoi ce 'redemarrage en attente' ?`", `"Quels programmes je peux desactiver au demarrage ?`"" $cBrand $cBodyText $fontBody

    & $script:Druidix_AppendChat 'Confidentialité' "Vos questions et un resume anonymise du diagnostic sont envoyes au fournisseur d'IA que vous avez configure. Les chemins utilisateur, le nom de la machine, les adresses IP et MAC sont remplaces par des etiquettes avant envoi. Aucun fichier personnel n'est partage. Vous gardez le controle : pas de cle = pas d'envoi." $cMuted $cBodyText $fontMutedItalic

    $settings = Read-DruidixSettings
    if (-not $settings.Keys -or $settings.Keys.Count -eq 0) {
        & $script:Druidix_AppendChat 'Système' "Aucune cle API n'est configuree. Cliquez sur 'Parametres' en haut a droite pour brancher OpenAI, Anthropic, Google, Mistral ou DeepSeek." $cWarn $cBodyText $fontBody
    } else {
        $activeProvider = $settings.DefaultProvider
        if (-not $settings.Keys.ContainsKey($activeProvider)) {
            $activeProvider = ($settings.Keys.Keys | Select-Object -First 1)
        }
        $providerName = ($script:Druidix_Providers | Where-Object { $_.Id -eq $activeProvider }).Name
        & $script:Druidix_AppendChat 'Système' "Connecté à : $providerName" $cBrand $cMuted $fontMutedItalic
    }

    $sendHandler = {
        $q = $tbInput.Text.Trim()
        if ([string]::IsNullOrEmpty($q)) { return }
        $settings = Read-DruidixSettings
        if (-not $settings.Keys -or $settings.Keys.Count -eq 0) {
            & $script:Druidix_AppendChat 'Erreur' "Aucune cle API. Allez dans Parametres en haut a droite." $cDanger $cBodyText $fontBody
            return
        }
        $providerId = $settings.DefaultProvider
        if (-not $settings.Keys.ContainsKey($providerId)) {
            $providerId = ($settings.Keys.Keys | Select-Object -First 1)
        }
        $apiKey = Unprotect-DruidixKey $settings.Keys[$providerId]
        if ([string]::IsNullOrEmpty($apiKey)) {
            & $script:Druidix_AppendChat 'Erreur' "Cle API illisible pour '$providerId'. Re-saisissez-la dans Parametres." $cDanger $cBodyText $fontBody
            return
        }

        & $script:Druidix_AppendChat 'Vous' $q $cAccent $cBodyText $fontBody
        $tbInput.Text = ''
        $btnSend.Enabled = $false
        $tbInput.Enabled = $false
        $script:Druidix_ThinkingPanel = & $script:Druidix_AppendChat "L'Oeil d'Antavirus" '... (reflexion en cours)' $cBrand $cMuted $fontMutedItalic
        [System.Windows.Forms.Application]::DoEvents()

        # Read model override from settings
        $modelOverride = $null
        if ($settings.Models -and $settings.Models.ContainsKey($providerId)) {
            $modelOverride = $settings.Models[$providerId]
        }

        try {
            $qAnon = ConvertTo-AnonymizedText $q
            $response = Invoke-DruidixApi -ProviderId $providerId -ApiKey $apiKey -SystemPrompt $systemPrompt -Question $qAnon -ModelOverride $modelOverride
            & $script:Druidix_RemoveThinking
            & $script:Druidix_AppendChat "L'Oeil d'Antavirus" $response $cBrand $cBodyText $fontBody
        }
        catch {
            & $script:Druidix_RemoveThinking
            $errMsg = $_.Exception.Message
            $hint = ''
            if ($errMsg -match '\(401\)|Unauthorized') {
                $hint = "`r`n=> Cle API invalide ou expiree. Verifiez la cle dans Parametres."
            } elseif ($errMsg -match '\(404\)|Introuvable|Not Found') {
                $hint = "`r`n=> Endpoint ou modele introuvable. Le provider '$providerId' a peut-etre change de modele."
            } elseif ($errMsg -match '\(429\)') {
                $hint = "`r`n=> Trop de requetes. Patientez un peu ou changez de fournisseur."
            } elseif ($errMsg -match '\(403\)|Forbidden') {
                $hint = "`r`n=> Acces refuse. Verifiez que votre compte a bien acces au modele."
            } elseif ($errMsg -match 'timeout|timed out') {
                $hint = "`r`n=> Delai depasse. Reseau lent ou serveur indisponible, reessayez."
            }
            $providerName = ($script:Druidix_Providers | Where-Object { $_.Id -eq $providerId }).Name
            & $script:Druidix_AppendChat 'Erreur' "[$providerName] $errMsg$hint" $cDanger $cBodyText $fontBody
        }
        finally {
            $btnSend.Enabled = $true
            $tbInput.Enabled = $true
            try { $tbInput.Focus() | Out-Null } catch {}
        }
    }

    $btnSend.Add_Click($sendHandler)
    $tbInput.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Return -and -not $e.Shift) {
            $e.SuppressKeyPress = $true
            & $sendHandler
        }
    })

    $form.Add_Shown({
        # Repositionne les controles ancres a droite (les valeurs ClientSize ne sont fiables qu'apres Shown)
        try {
            $cw = $form.ClientSize.Width
            $btnSettingsTopRight.Location = New-Object System.Drawing.Point(($cw - 150), 32)
            $btnSend.Location              = New-Object System.Drawing.Point(($cw - 120), 21)
            $tbInput.Width                 = ($cw - 150)
        } catch {}
        try { $tbInput.Focus() | Out-Null } catch {}

        # Si une question initiale est fournie (mode "plan d'action auto"), on la pose
        if (-not [string]::IsNullOrWhiteSpace($InitialQuestion)) {
            $tbInput.Text = $InitialQuestion
            [System.Windows.Forms.Application]::DoEvents()
            & $sendHandler
        }
    })
    [void]$form.ShowDialog()
}

# ============================================================
# MODE GUI - Présentation des résultats en langage simple
# ============================================================

# Logo embarqué (Base64 PNG, injecté à la compilation)
$script:Druide_LogoB64 = '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'

function Show-ScheduleDialog {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $cBg          = [System.Drawing.Color]::FromArgb(0xF4, 0xEC, 0xD8)
    $cCard        = [System.Drawing.Color]::White
    $cBorder      = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $cText        = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
    $cTextMuted   = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
    $cAccent      = [System.Drawing.Color]::FromArgb(0x1F, 0x4D, 0x3A)
    $cAccentHover = [System.Drawing.Color]::FromArgb(0x2E, 0x6B, 0x4F)
    $cBrand       = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Planification automatique'
    $form.Size = New-Object System.Drawing.Size(560, 420)
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = $cBg
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    try { $ic = Get-DruideIcon; if ($ic) { $form.Icon = $ic } } catch {}

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Scanner mon PC automatiquement'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $cText
    $title.Location = New-Object System.Drawing.Point(20, 18)
    $title.AutoSize = $true
    $form.Controls.Add($title)

    $info = New-Object System.Windows.Forms.Label
    $info.Text = "Le druide peut veiller chaque semaine en silence. Vous recevez une notification uniquement si quelque chose d'important est detecte."
    $info.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $info.ForeColor = $cTextMuted
    $info.Location = New-Object System.Drawing.Point(20, 50)
    $info.Size = New-Object System.Drawing.Size(500, 36)
    $form.Controls.Add($info)

    # Carte de configuration
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(20, 95)
    $card.Size = New-Object System.Drawing.Size(500, 180)
    $card.BackColor = $cCard
    $card.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8))
        $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width-1, $s.Height-1)
        $pen.Dispose()
    })
    $form.Controls.Add($card)

    $info0 = Get-ScheduledScanInfo

    $chkEnable = New-Object System.Windows.Forms.CheckBox
    $chkEnable.Text = "Activer la planification hebdomadaire"
    $chkEnable.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $chkEnable.ForeColor = $cText
    $chkEnable.Location = New-Object System.Drawing.Point(16, 16)
    $chkEnable.Size = New-Object System.Drawing.Size(470, 28)
    $chkEnable.Checked = $info0.Active
    $card.Controls.Add($chkEnable)

    $lblDay = New-Object System.Windows.Forms.Label
    $lblDay.Text = 'Jour'
    $lblDay.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lblDay.ForeColor = $cTextMuted
    $lblDay.Location = New-Object System.Drawing.Point(16, 58)
    $lblDay.AutoSize = $true
    $card.Controls.Add($lblDay)

    $cbDay = New-Object System.Windows.Forms.ComboBox
    $cbDay.DropDownStyle = 'DropDownList'
    $cbDay.Location = New-Object System.Drawing.Point(16, 80)
    $cbDay.Size = New-Object System.Drawing.Size(220, 24)
    $cbDay.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $days = @('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')
    $daysFr = @('Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche')
    for ($i=0; $i -lt $days.Count; $i++) {
        [void]$cbDay.Items.Add($daysFr[$i])
    }
    $defaultIdx = [Array]::IndexOf($days, $info0.DayOfWeek)
    if ($defaultIdx -lt 0) { $defaultIdx = 6 }
    $cbDay.SelectedIndex = $defaultIdx
    $card.Controls.Add($cbDay)

    $lblHour = New-Object System.Windows.Forms.Label
    $lblHour.Text = 'Heure'
    $lblHour.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lblHour.ForeColor = $cTextMuted
    $lblHour.Location = New-Object System.Drawing.Point(266, 58)
    $lblHour.AutoSize = $true
    $card.Controls.Add($lblHour)

    $cbHour = New-Object System.Windows.Forms.ComboBox
    $cbHour.DropDownStyle = 'DropDownList'
    $cbHour.Location = New-Object System.Drawing.Point(266, 80)
    $cbHour.Size = New-Object System.Drawing.Size(110, 24)
    $cbHour.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    for ($h=0; $h -lt 24; $h++) { [void]$cbHour.Items.Add(("{0:D2}h00" -f $h)) }
    $cbHour.SelectedIndex = [math]::Min(23, [math]::Max(0, $info0.Hour))
    $card.Controls.Add($cbHour)

    $statusLbl = New-Object System.Windows.Forms.Label
    if ($info0.Active -and $info0.NextRun) {
        $statusLbl.Text = "Prochain passage prévu : " + $info0.NextRun.ToString('dddd dd MMMM HH:mm')
    } elseif ($info0.Active) {
        $statusLbl.Text = "Planification active"
    } else {
        $statusLbl.Text = "Pas de planification active"
    }
    $statusLbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Italic)
    $statusLbl.ForeColor = $cBrand
    $statusLbl.Location = New-Object System.Drawing.Point(16, 130)
    $statusLbl.Size = New-Object System.Drawing.Size(470, 22)
    $card.Controls.Add($statusLbl)

    # Boutons
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Enregistrer'
    $btnSave.Location = New-Object System.Drawing.Point(20, 320)
    $btnSave.Size = New-Object System.Drawing.Size(160, 36)
    $btnSave.FlatStyle = 'Flat'
    $btnSave.BackColor = $cAccent
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.FlatAppearance.BorderSize = 0
    $btnSave.FlatAppearance.MouseOverBackColor = $cAccentHover
    $btnSave.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnSave.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSave.Add_Click({
        # Resolve exe path
        $exe = $null
        try {
            $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        } catch {}
        if (-not $exe -or $exe -like '*powershell*') {
            # On est en mode .ps1 : pas d'.exe, on cherche sur le Bureau
            $candidate = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Le Druide Antavirus.exe'
            if (Test-Path -LiteralPath $candidate) { $exe = $candidate }
        }
        if ($chkEnable.Checked) {
            if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
                [System.Windows.Forms.MessageBox]::Show("Impossible de trouver l'executable de l'application. Lancez Le Druide depuis le .exe pour planifier.", 'Planification', 'OK', 'Warning') | Out-Null
                return
            }
            $dayIdx = $cbDay.SelectedIndex
            $hour   = $cbHour.SelectedIndex
            $ok = Enable-ScheduledScan -ExePath $exe -DayOfWeek $days[$dayIdx] -Hour $hour
            if ($ok) {
                [System.Windows.Forms.MessageBox]::Show("Planification activée. Prochain scan : $($daysFr[$dayIdx]) à $('{0:D2}h00' -f $hour).", 'Planification', 'OK', 'Information') | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show("Echec : il faut probablement relancer Le Druide en tant qu'administrateur.", 'Planification', 'OK', 'Warning') | Out-Null
            }
        } else {
            [void](Disable-ScheduledScan)
            [System.Windows.Forms.MessageBox]::Show("Planification désactivée.", 'Planification', 'OK', 'Information') | Out-Null
        }
        $form.Close()
    })
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Annuler'
    $btnCancel.Location = New-Object System.Drawing.Point(440, 320)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 36)
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.BackColor = $cCard
    $btnCancel.ForeColor = $cText
    $btnCancel.FlatAppearance.BorderColor = $cBorder
    $btnCancel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancel.Add_Click({ $form.Close() })
    $form.Controls.Add($btnCancel)

    [void]$form.ShowDialog()
}

function Show-HistoryDialog {
    $cBg          = [System.Drawing.Color]::FromArgb(0xF4, 0xEC, 0xD8)
    $cCard        = [System.Drawing.Color]::White
    $cBorder      = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $cText        = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
    $cTextMuted   = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
    $cAccent      = [System.Drawing.Color]::FromArgb(0x1F, 0x4D, 0x3A)
    $cBrand       = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Historique des rapports"
    $form.Size = New-Object System.Drawing.Size(720, 520)
    $form.StartPosition = 'CenterParent'
    $form.BackColor = $cBg
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    try { $ic = Get-DruideIcon; if ($ic) { $form.Icon = $ic } } catch {}

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Vos derniers diagnostics"
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $cText
    $titleLabel.Location = New-Object System.Drawing.Point(20, 16)
    $titleLabel.AutoSize = $true
    $form.Controls.Add($titleLabel)

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Text = "Conservés localement dans " + (Get-ReportsArchiveDir)
    $hintLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $hintLabel.ForeColor = $cTextMuted
    $hintLabel.Location = New-Object System.Drawing.Point(20, 44)
    $hintLabel.AutoSize = $true
    $form.Controls.Add($hintLabel)

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(20, 72)
    $listView.Size = New-Object System.Drawing.Size(670, 360)
    $listView.View = 'Details'
    $listView.FullRowSelect = $true
    $listView.GridLines = $false
    $listView.MultiSelect = $false
    $listView.BackColor = $cCard
    $listView.ForeColor = $cText
    [void]$listView.Columns.Add('Date', 200)
    [void]$listView.Columns.Add('Nom du fichier', 320)
    [void]$listView.Columns.Add('Taille', 80)
    $listView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

    $reports = Get-ArchivedReports
    foreach ($r in $reports) {
        $item = New-Object System.Windows.Forms.ListViewItem($r.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
        [void]$item.SubItems.Add($r.Name)
        [void]$item.SubItems.Add("{0:N0} Ko" -f ($r.Length / 1KB))
        $item.Tag = $r.FullName
        [void]$listView.Items.Add($item)
    }
    $form.Controls.Add($listView)

    if ($reports.Count -eq 0) {
        $emptyLabel = New-Object System.Windows.Forms.Label
        $emptyLabel.Text = "Aucun rapport archivé pour le moment.`nLes prochains diagnostics seront conservés ici automatiquement."
        $emptyLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $emptyLabel.ForeColor = $cTextMuted
        $emptyLabel.Location = New-Object System.Drawing.Point(40, 200)
        $emptyLabel.AutoSize = $true
        $form.Controls.Add($emptyLabel)
        $listView.Visible = $false
    }

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = 'Ouvrir le rapport'
    $btnOpen.Location = New-Object System.Drawing.Point(20, 444)
    $btnOpen.Size = New-Object System.Drawing.Size(160, 32)
    $btnOpen.FlatStyle = 'Flat'
    $btnOpen.BackColor = $cAccent
    $btnOpen.ForeColor = [System.Drawing.Color]::White
    $btnOpen.FlatAppearance.BorderSize = 0
    $btnOpen.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btnOpen.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnOpen.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnOpen.Add_Click({
        if ($listView.SelectedItems.Count -gt 0) {
            $path = $listView.SelectedItems[0].Tag
            if (Test-Path -LiteralPath $path) { Start-Process notepad.exe $path }
        }
    })
    $form.Controls.Add($btnOpen)

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = 'Supprimer'
    $btnDelete.Location = New-Object System.Drawing.Point(190, 444)
    $btnDelete.Size = New-Object System.Drawing.Size(120, 32)
    $btnDelete.FlatStyle = 'Flat'
    $btnDelete.BackColor = $cCard
    $btnDelete.ForeColor = $cText
    $btnDelete.FlatAppearance.BorderColor = $cBorder
    $btnDelete.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnDelete.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnDelete.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnDelete.Add_Click({
        if ($listView.SelectedItems.Count -gt 0) {
            $path = $listView.SelectedItems[0].Tag
            $r = [System.Windows.Forms.MessageBox]::Show(
                "Supprimer ce rapport ?",
                'Confirmation',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                $listView.Items.Remove($listView.SelectedItems[0])
            }
        }
    })
    $form.Controls.Add($btnDelete)

    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Text = 'Ouvrir le dossier'
    $btnOpenFolder.Location = New-Object System.Drawing.Point(320, 444)
    $btnOpenFolder.Size = New-Object System.Drawing.Size(140, 32)
    $btnOpenFolder.FlatStyle = 'Flat'
    $btnOpenFolder.BackColor = $cCard
    $btnOpenFolder.ForeColor = $cText
    $btnOpenFolder.FlatAppearance.BorderColor = $cBorder
    $btnOpenFolder.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnOpenFolder.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnOpenFolder.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnOpenFolder.Add_Click({ Start-Process explorer.exe (Get-ReportsArchiveDir) })
    $form.Controls.Add($btnOpenFolder)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Fermer'
    $btnClose.Location = New-Object System.Drawing.Point(590, 444)
    $btnClose.Size = New-Object System.Drawing.Size(100, 32)
    $btnClose.FlatStyle = 'Flat'
    $btnClose.BackColor = $cCard
    $btnClose.ForeColor = $cText
    $btnClose.FlatAppearance.BorderColor = $cBorder
    $btnClose.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    [void]$form.ShowDialog()
}

function Test-FirstLaunch {
    $cfgPath = Get-DruidixSettingsPath
    return -not (Test-Path -LiteralPath $cfgPath)
}

function Save-OnboardingDone {
    # Cree un settings.json minimal pour marquer l'onboarding effectue
    try {
        $path = Get-DruidixSettingsPath
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        if (-not (Test-Path -LiteralPath $path)) {
            $stub = [PSCustomObject]@{
                DefaultProvider = 'anthropic'
                Keys = @{}
                Models = @{}
                OnboardingDone = $true
                OnboardingDate = (Get-Date).ToString('o')
            }
            $stub | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding UTF8 -Force
        }
    } catch {}
}

function Show-OnboardingDialog {
    $cBg          = [System.Drawing.Color]::FromArgb(0xF4, 0xEC, 0xD8)
    $cCard        = [System.Drawing.Color]::White
    $cBorder      = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $cText        = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
    $cTextMuted   = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
    $cAccent      = [System.Drawing.Color]::FromArgb(0x1F, 0x4D, 0x3A)
    $cAccentHover = [System.Drawing.Color]::FromArgb(0x2E, 0x6B, 0x4F)
    $cBrand       = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)
    $cMutedBg     = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Bienvenue chez Le Druide Antavirus'
    $form.Size = New-Object System.Drawing.Size(640, 580)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = $cBg
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    try { $ic = Get-DruideIcon; if ($ic) { $form.Icon = $ic } } catch {}

    # Logo en haut
    $logoBox = New-Object System.Windows.Forms.PictureBox
    $logoBox.Size = New-Object System.Drawing.Size(96, 96)
    $logoBox.Location = New-Object System.Drawing.Point(272, 20)
    $logoBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $logoBox.BackColor = [System.Drawing.Color]::Transparent
    try { $bmp = Get-DruideLogo -Size 256; if ($bmp) { $logoBox.Image = $bmp } } catch {}
    $form.Controls.Add($logoBox)

    # Titre
    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Bienvenue !'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $cText
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(0, 130)
    $title.TextAlign = 'MiddleCenter'
    $title.Width = 640
    $title.AutoSize = $false
    $title.Height = 40
    $form.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "Le druide veille sur votre PC. Souhaitez-vous activer L'Oeil d'Antavirus pour qu'il vous explique chaque diagnostic en mots simples ?"
    $sub.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $sub.ForeColor = $cTextMuted
    $sub.AutoSize = $false
    $sub.TextAlign = 'MiddleCenter'
    $sub.Location = New-Object System.Drawing.Point(40, 178)
    $sub.Size = New-Object System.Drawing.Size(560, 56)
    $form.Controls.Add($sub)

    # 3 cards d'options
    $optTop = 246
    $optHeight = 78
    $optGap = 8

    $makeOption = {
        param([int]$Y, [string]$Title, [string]$Desc, [string]$Badge, [bool]$Enabled = $true)
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Size = New-Object System.Drawing.Size(560, $optHeight)
        $panel.Location = New-Object System.Drawing.Point(40, $Y)
        if ($Enabled) { $panel.BackColor = $cCard } else { $panel.BackColor = $cMutedBg }
        $panel.Cursor = if ($Enabled) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }
        $panel.Add_Paint({
            param($s, $e)
            $pen = New-Object System.Drawing.Pen($cBorder)
            $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1)
            $pen.Dispose()
        }.GetNewClosure())

        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = $Title
        $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
        $lblTitle.ForeColor = if ($Enabled) { $cText } else { $cTextMuted }
        $lblTitle.Location = New-Object System.Drawing.Point(16, 12)
        $lblTitle.AutoSize = $true
        $panel.Controls.Add($lblTitle)

        if ($Badge) {
            $lblBadge = New-Object System.Windows.Forms.Label
            $lblBadge.Text = $Badge
            $lblBadge.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
            $lblBadge.ForeColor = $cBrand
            $lblBadge.Location = New-Object System.Drawing.Point(520, 14)
            $lblBadge.AutoSize = $true
            $panel.Controls.Add($lblBadge)
        }

        $lblDesc = New-Object System.Windows.Forms.Label
        $lblDesc.Text = $Desc
        $lblDesc.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $lblDesc.ForeColor = $cTextMuted
        $lblDesc.Location = New-Object System.Drawing.Point(16, 40)
        $lblDesc.AutoSize = $false
        $lblDesc.Size = New-Object System.Drawing.Size(530, 30)
        $panel.Controls.Add($lblDesc)

        return $panel
    }

    $script:OnboardingChoice = $null

    # Option A : Decouvrir (clef Triskell) - desactivee tant que backend pas pret
    $optA = & $makeOption $optTop "Decouvrir gratuitement" "Quelques questions IA offertes par mois via Triskell, sans cle a configurer. (Disponible prochainement)" "BIENTOT" $false
    $form.Controls.Add($optA)

    # Option B : BYOK
    $optB = & $makeOption ($optTop + ($optHeight + $optGap)) "J'ai deja une cle d'API" "Vous utilisez votre cle Anthropic, OpenAI, Google, Mistral ou DeepSeek. Sans limite, gratuit, votre cle ne quitte pas votre PC."
    $optB.Add_Click({
        $script:OnboardingChoice = 'BYOK'
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    foreach ($c in $optB.Controls) {
        $c.Add_Click({ $script:OnboardingChoice = 'BYOK'; $form.DialogResult = 'OK'; $form.Close() })
    }
    $form.Controls.Add($optB)

    # Option C : Plus tard
    $optC = & $makeOption ($optTop + 2 * ($optHeight + $optGap)) "Continuer sans IA" "Le scanneur fonctionne entierement sans IA. Vous pourrez activer L'Oeil d'Antavirus plus tard depuis les Parametres."
    $optC.Add_Click({
        $script:OnboardingChoice = 'Later'
        $form.DialogResult = 'OK'
        $form.Close()
    })
    foreach ($c in $optC.Controls) {
        $c.Add_Click({ $script:OnboardingChoice = 'Later'; $form.DialogResult = 'OK'; $form.Close() })
    }
    $form.Controls.Add($optC)

    # Pied : confidentialite
    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = "Confidentialite : aucune donnee personnelle n'est envoyee a Triskell. Vos cles sont chiffrees localement (Windows DPAPI)."
    $privacy.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
    $privacy.ForeColor = $cTextMuted
    $privacy.AutoSize = $false
    $privacy.TextAlign = 'MiddleCenter'
    $privacy.Location = New-Object System.Drawing.Point(20, 510)
    $privacy.Size = New-Object System.Drawing.Size(600, 30)
    $form.Controls.Add($privacy)

    [void]$form.ShowDialog()

    # Marquer l'onboarding comme fait
    Save-OnboardingDone

    # Si l'utilisateur a choisi BYOK, ouvrir directement le dialog settings
    if ($script:OnboardingChoice -eq 'BYOK') {
        Show-SettingsDialog
    }
}

$script:UpdateRepoApi = 'https://api.github.com/repos/Jordan-Bourillot/le-druide-antavirus/releases/latest'

function Get-CurrentAppVersion {
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exe -and ($exe -notlike '*powershell*')) {
            $v = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
            if ($v) { return $v }
        }
    } catch {}
    return '0.0.0.0'
}

function Compare-AppVersion {
    param([string]$Latest, [string]$Current)
    try {
        $lv = [version]($Latest -replace '^v', '')
        $cv = [version]($Current -replace '^v', '')
        return ($lv -gt $cv)
    } catch { return $false }
}

function Start-UpdateCheck {
    # Lance un check de mise a jour en arriere-plan. Quand termine, appelle
    # $OnFound avec un objet @{Tag, Url, Body} si une nouvelle version existe.
    param(
        [Parameter(Mandatory)][scriptblock]$OnFound,
        [string]$ApiUrl = $script:UpdateRepoApi
    )
    $current = Get-CurrentAppVersion
    try {
        $job = Start-Job -ScriptBlock {
            param($url)
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $r = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'LeDruideAntavirus' } -TimeoutSec 8
                return [PSCustomObject]@{
                    Tag  = $r.tag_name
                    Url  = $r.html_url
                    Body = $r.body
                    Date = $r.published_at
                }
            } catch { return $null }
        } -ArgumentList $ApiUrl
    } catch { return }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 800
    $timer.Tag = @{ Job = $job; Current = $current; OnFound = $OnFound; Self = $timer }
    $timer.Add_Tick({
        try {
            $ctx = $this.Tag
            $j = $ctx.Job
            if ($j.State -in @('Completed','Failed','Stopped')) {
                $this.Stop()
                try {
                    $result = $null
                    if ($j.State -eq 'Completed') {
                        $result = Receive-Job -Job $j -ErrorAction SilentlyContinue
                    }
                    Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
                    if ($result -and $result.Tag) {
                        if (Compare-AppVersion -Latest $result.Tag -Current $ctx.Current) {
                            try { & $ctx.OnFound $result } catch {}
                        }
                    }
                } catch {}
                try { $this.Dispose() } catch {}
            }
        } catch {}
    })
    $timer.Start()
}

function Set-RoundedRegion {
    param(
        [Parameter(Mandatory)]$Button,
        [int]$Radius = 8
    )
    try {
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = $Radius * 2
        $w = $Button.Width
        $h = $Button.Height
        if ($r -gt $w) { $r = $w }
        if ($r -gt $h) { $r = $h }
        $gp.AddArc(0, 0, $r, $r, 180, 90)
        $gp.AddArc($w - $r, 0, $r, $r, 270, 90)
        $gp.AddArc($w - $r, $h - $r, $r, $r, 0, 90)
        $gp.AddArc(0, $h - $r, $r, $r, 90, 90)
        $gp.CloseFigure()
        $Button.Region = New-Object System.Drawing.Region($gp)
    } catch {}
}

function Get-DruideLogo {
    param([int]$Size = 128)
    if ([string]::IsNullOrEmpty($script:Druide_LogoB64) -or $script:Druide_LogoB64.Length -lt 100) {
        try {
            $candidates = @()
            $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            if ($exePath) {
                $candidates += (Join-Path (Split-Path $exePath -Parent) 'druide-antavirus.ico')
                $candidates += (Join-Path (Split-Path $exePath -Parent) 'le-druide.ico')
            }
            $candidates += "$([Environment]::GetFolderPath('Desktop'))\druide-antavirus.ico"
            $candidates += "$([Environment]::GetFolderPath('Desktop'))\le-druide.ico"
            foreach ($p in $candidates) {
                if ($p -and (Test-Path $p)) {
                    $icon = New-Object System.Drawing.Icon($p, $Size, $Size)
                    return $icon.ToBitmap()
                }
            }
        } catch {}
        return $null
    }
    try {
        $bytes = [Convert]::FromBase64String($script:Druide_LogoB64)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $orig = [System.Drawing.Bitmap]::FromStream($ms)
        if ($Size -le 0 -or $Size -eq $orig.Width) { return $orig }
        $resized = New-Object System.Drawing.Bitmap $Size, $Size
        $g = [System.Drawing.Graphics]::FromImage($resized)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.DrawImage($orig, 0, 0, $Size, $Size)
        $g.Dispose()
        $orig.Dispose()
        return $resized
    } catch {
        return $null
    }
}

function Get-DruideIcon {
    try {
        $bmp = Get-DruideLogo -Size 32
        if ($bmp) {
            $h = $bmp.GetHicon()
            return [System.Drawing.Icon]::FromHandle($h)
        }
    } catch {}
    try {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exePath -and ($exePath -notlike '*powershell*')) {
            return [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        }
    } catch {}
    return $null
}

function Get-FindingPresentation {
    param($Finding)

    $sev  = $Finding.Severity
    $cat  = $Finding.Category
    $desc = $Finding.Description

    $p = @{
        Title        = $cat
        Explanation  = $Finding.Recommendation
        Icon         = '!'
        Severity     = $sev
        ActionLabel  = $null
        ActionScript = $null
    }

    switch ($cat) {
        'Reboot' {
            $p.Title       = 'Redémarrage en attente'
            $p.Explanation = "Windows attend de redémarrer pour finaliser des mises à jour. C'est très probablement la cause des longs cycles de démarrage que vous observez."
            $p.Icon        = '🔄'
            $p.ActionLabel = 'Redémarrer maintenant'
            $p.ActionScript = {
                $r = [System.Windows.Forms.MessageBox]::Show(
                    "Voulez-vous vraiment redémarrer maintenant ?`n`nFermez d'abord vos applications.",
                    'Confirmation',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Restart-Computer -Force
                }
            }
        }
        'Updates' {
            $p.Title       = 'Mises à jour Windows en attente'
            $p.Explanation = "Des mises à jour Windows sont disponibles mais pas encore installées. Elles peuvent ralentir le PC le temps de l'installation."
            $p.Icon        = '⬇️'
            $p.ActionLabel = 'Ouvrir Windows Update'
            $p.ActionScript = { Start-Process 'ms-settings:windowsupdate' }
        }
        'Disk' {
            if ($desc -match 'libre') {
                if ($desc -match 'Volume D:.*Recovery' -or $desc -match '^Volume D:') {
                    $p.Title       = 'Partition Recovery presque pleine'
                    $p.Explanation = "Le disque D: est la partition de récupération du fabricant. Il est NORMAL qu'elle soit presque pleine. Ne supprimez rien dessus."
                    $p.Icon        = 'ℹ️'
                    $p.Severity    = 'Info'
                }
                else {
                    $p.Title       = 'Espace disque insuffisant'
                    $p.Explanation = "Un de vos disques est presque plein. Au-dessus de 85% d'occupation, Windows ralentit nettement (mémoire virtuelle et fichiers temporaires manquent de place)."
                    $p.Icon        = '💾'
                    $p.ActionLabel = 'Nettoyer'
                    $p.ActionScript = { Start-Process 'ms-settings:storagesense' }
                }
            }
            elseif ($desc -match 'rreurs de lecture') {
                $p.Title       = 'Erreurs détectées sur le disque'
                $p.Explanation = "Le disque a signalé des erreurs de lecture. Ce n'est pas critique tant que le nombre n'augmente pas, mais sauvegardez vos données importantes par précaution."
                $p.Icon        = '⚠️'
            }
            elseif ($desc -match 'usé à') {
                $p.Title       = 'SSD usé'
                $p.Explanation = "Votre SSD a déjà bien servi. Pas urgent, mais commencez à penser au remplacement."
                $p.Icon        = '⌛'
            }
            elseif ($desc -match 'état Warning' -or $desc -match 'défaillant') {
                $p.Title       = 'Disque en mauvaise santé'
                $p.Explanation = "Votre disque montre des signes de fatigue. Sauvegardez vos données rapidement."
                $p.Icon        = '🚨'
            }
            else {
                $p.Title       = 'Disque - point à surveiller'
                $p.Explanation = $Finding.Recommendation
            }
        }
        'Memory' {
            if ($desc -match 'saturée') {
                $p.Title       = 'Mémoire RAM saturée'
                $p.Explanation = "Votre RAM est presque pleine. Le PC va commencer à utiliser le disque comme mémoire d'appoint, ce qui le rend très lent."
                $p.Icon        = '🧠'
                $p.ActionLabel = 'Ouvrir gestionnaire des tâches'
                $p.ActionScript = { Start-Process 'taskmgr.exe' }
            }
            elseif ($desc -match 'utilisée à') {
                $p.Title       = 'Mémoire RAM bien remplie'
                $p.Explanation = "La RAM commence à se remplir. Pas critique mais à surveiller, surtout si vous gardez beaucoup d'onglets de navigateur ouverts."
                $p.Icon        = '🧠'
            }
            elseif ($desc -match 'consomme') {
                $p.Title       = 'Application gourmande en mémoire'
                $p.Explanation = "$desc. Pensez à fermer les onglets inutiles ou à redémarrer cette application de temps en temps."
                $p.Icon        = '🧠'
            }
            else {
                $p.Title       = 'Mémoire - point à surveiller'
                $p.Explanation = $Finding.Recommendation
            }
        }
        'Boot' {
            $p.Title       = 'Démarrage lent'
            $p.Explanation = "Le dernier démarrage a pris plus de 2 minutes (mesure côté Windows). À combiner avec les autres pistes ci-dessous : programmes au démarrage, pilotes, mises à jour."
            $p.Icon        = '⌚'
        }
        'Startup' {
            $p.Title       = 'Trop de programmes au démarrage'
            $p.Explanation = "Beaucoup de programmes se lancent automatiquement avec Windows. Désactivez ceux dont vous n'avez pas besoin tout le temps (Adobe Sync, GoPro, uTorrent, etc.)."
            $p.Icon        = '⚡'
            $p.ActionLabel = 'Ouvrir gestionnaire'
            $p.ActionScript = { Start-Process 'taskmgr.exe' }
        }
        'Drivers' {
            $p.Title       = 'Pilotes en erreur'
            $p.Explanation = "Certains pilotes sont marqués en erreur. À vérifier dans le Gestionnaire de périphériques (souvent des composants logiciels fantômes, parfois plus sérieux)."
            $p.Icon        = '🔧'
            $p.ActionLabel = 'Gestionnaire de périphériques'
            $p.ActionScript = { Start-Process 'devmgmt.msc' }
        }
        'Events' {
            if ($desc -match 'isque' -or $desc -match 'NTFS') {
                $p.Title       = 'Erreurs disque dans le journal'
                $p.Explanation = "Windows a enregistré des erreurs de disque. Sauvegardez vos données et envisagez un test du disque (CrystalDiskInfo)."
                $p.Icon        = '🚨'
            }
            elseif ($desc -match 'WHEA') {
                $p.Title       = 'Erreurs matérielles détectées'
                $p.Explanation = "Le matériel (CPU, RAM ou bus système) a signalé des erreurs. Vérifiez les températures et testez la mémoire RAM."
                $p.Icon        = '🛠️'
                $p.ActionLabel = 'Tester la RAM'
                $p.ActionScript = { Start-Process 'mdsched.exe' }
            }
            elseif ($desc -match 'inattendue') {
                $p.Title       = 'Extinctions inattendues'
                $p.Explanation = "Le PC s'est éteint plusieurs fois sans raison claire (coupure de courant, plantage, surchauffe)."
                $p.Icon        = '🔌'
            }
            else {
                $p.Title       = 'Erreurs dans le journal système'
                $p.Explanation = $Finding.Recommendation
                $p.Icon        = '⚠️'
            }
        }
        'Services' {
            $p.Title       = 'Service Windows arrêté'
            $p.Explanation = "Un service Windows qui devrait tourner automatiquement est arrêté. À vérifier dans la console des services."
            $p.Icon        = '⚙️'
            $p.ActionLabel = 'Ouvrir les services'
            $p.ActionScript = { Start-Process 'services.msc' }
        }
        'Security' {
            $p.Title       = "Antivirus pas à jour"
            $p.Explanation = "Les signatures de Windows Defender datent de plus d'une semaine. Lancez Windows Update pour les rafraîchir."
            $p.Icon        = '🛡️'
            $p.ActionLabel = 'Ouvrir Windows Security'
            $p.ActionScript = { Start-Process 'ms-settings:windowsdefender' }
        }
        'Power' {
            $p.Title       = "Mode économie d'énergie actif"
            $p.Explanation = "Votre PC est configuré en mode économique. Pour de meilleures performances, passez en mode équilibré ou performances."
            $p.Icon        = '🔋'
            $p.ActionLabel = "Options d'alimentation"
            $p.ActionScript = { Start-Process 'powercfg.cpl' }
        }
        'Uptime' {
            $p.Title       = 'PC allumé depuis longtemps'
            $p.Explanation = "Votre PC tourne depuis plusieurs jours sans redémarrage complet. Un redémarrage régulier libère la RAM et applique les mises à jour."
            $p.Icon        = '🔄'
            $p.ActionLabel = 'Redémarrer maintenant'
            $p.ActionScript = {
                $r = [System.Windows.Forms.MessageBox]::Show(
                    'Voulez-vous redémarrer maintenant ?',
                    'Confirmation',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Restart-Computer -Force
                }
            }
        }
        'Browser' {
            $p.Title       = 'Extensions navigateur à vérifier'
            $p.Explanation = "Une ou plusieurs extensions installées dans vos navigateurs demandent des permissions sensibles (accès à toutes les pages, à l'historique, aux cookies). Vérifiez que vous les reconnaissez bien — les extensions douteuses sont un des moyens les plus fréquents pour ralentir et espionner un PC."
            $p.Icon        = '🧩'
            $p.ActionLabel = "Ouvrir Edge sur Extensions"
            $p.ActionScript = {
                try { Start-Process 'msedge.exe' 'edge://extensions/' } catch { Start-Process 'edge://extensions/' }
            }
        }
        'Maintenance' {
            $p.Title       = 'Espace récupérable détecté'
            $p.Explanation = "Vos navigateurs et Windows ont accumulé des fichiers temporaires. Ils ne servent plus à rien et sont régénérés automatiquement. Vous pouvez les nettoyer en un clic sans aucun risque."
            $p.Icon        = '🧹'
            $p.ActionLabel = 'Nettoyer maintenant'
            $p.ActionScript = {
                $r = [System.Windows.Forms.MessageBox]::Show(
                    "Le druide va supprimer les caches navigateurs et fichiers temporaires.`n`nFermez vos navigateurs avant pour de meilleurs résultats.`n`nContinuer ?",
                    'Nettoyage',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $freed = Invoke-CleanupCaches
                    [System.Windows.Forms.MessageBox]::Show(
                        "$freed Mo libérés.",
                        'Le Druide Antavirus',
                        'OK', 'Information') | Out-Null
                }
            }
        }
    }

    # Action 1-clic supplementaire pour mise a jour Defender (signatures vieilles)
    if ($cat -eq 'Security' -and ($desc -match 'Signatures Defender' -or $desc -match 'signatures' )) {
        $p.ActionLabel  = 'Mettre à jour Defender maintenant'
        $p.ActionScript = {
            try {
                Update-MpSignature -ErrorAction Stop
                [System.Windows.Forms.MessageBox]::Show('Signatures Defender mises à jour avec succès.', 'Le Druide Antavirus', 'OK', 'Information') | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Échec de la mise à jour : $($_.Exception.Message)`n`nUtilisez Windows Update à la place.", 'Le Druide Antavirus', 'OK', 'Warning') | Out-Null
                Start-Process 'ms-settings:windowsupdate'
            }
        }
    }

    return $p
}

function New-FindingCard {
    param($Presentation, [int]$Width)

    $sev = $Presentation.Severity
    $stripe = switch ($sev) {
        'Critical' { [System.Drawing.Color]::FromArgb(178, 59, 59) }
        'Warning'  { [System.Drawing.Color]::FromArgb(217, 137, 46) }
        'Info'     { [System.Drawing.Color]::FromArgb(74, 111, 165) }
        default    { [System.Drawing.Color]::FromArgb(107, 114, 128) }
    }

    $card = New-Object System.Windows.Forms.Panel
    $card.Width  = $Width
    $card.Height = 140
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
    $card.BackColor = [System.Drawing.Color]::White
    $card.Tag = @{ Stripe = $stripe }

    $card.Add_Paint({
        param($s, $e)
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184))
        $e.Graphics.DrawRectangle($border, 0, 0, $s.Width - 1, $s.Height - 1)
        $border.Dispose()
        $brush = New-Object System.Drawing.SolidBrush($s.Tag.Stripe)
        $e.Graphics.FillRectangle($brush, 0, 0, 4, $s.Height)
        $brush.Dispose()
    })

    $icon = New-Object System.Windows.Forms.Label
    $icon.Text = $Presentation.Icon
    $icon.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 22)
    $icon.ForeColor = $stripe
    $icon.UseCompatibleTextRendering = $true
    $icon.Location = New-Object System.Drawing.Point(20, 22)
    $icon.AutoSize = $true
    $card.Controls.Add($icon)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = $Presentation.Title
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(14, 30, 46)
    $title.Location = New-Object System.Drawing.Point(72, 18)
    $title.AutoSize = $true
    $card.Controls.Add($title)

    $hasButton = -not [string]::IsNullOrEmpty($Presentation.ActionLabel)
    $explWidth = if ($hasButton) { $Width - 280 } else { $Width - 92 }
    if ($explWidth -lt 200) { $explWidth = 200 }

    # v1.4.5 : mesure la hauteur reelle du texte pour eviter qu'il soit coupe.
    $explFont = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $measureSize = [System.Windows.Forms.TextRenderer]::MeasureText(
        [string]$Presentation.Explanation,
        $explFont,
        (New-Object System.Drawing.Size $explWidth, 2000),
        ([System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl)
    )
    $explHeight = [Math]::Max(88, $measureSize.Height + 6)

    $expl = New-Object System.Windows.Forms.Label
    $expl.Text = $Presentation.Explanation
    $expl.Font = $explFont
    $expl.ForeColor = [System.Drawing.Color]::FromArgb(90, 107, 95)
    $expl.Location = New-Object System.Drawing.Point(72, 44)
    $expl.Size = New-Object System.Drawing.Size($explWidth, $explHeight)
    $card.Controls.Add($expl)

    # Ajuste la hauteur du card pour englober l'explication + le bouton eventuel.
    $bottomOfExpl = 44 + $explHeight + 18
    $bottomOfButton = if ($hasButton) { 52 + 36 + 18 } else { 0 }
    $card.Height = [Math]::Max([Math]::Max(140, $bottomOfExpl), $bottomOfButton)

    if ($hasButton) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Presentation.ActionLabel
        $btn.Size = New-Object System.Drawing.Size(190, 36)
        $btn.Location = New-Object System.Drawing.Point(($Width - 210), 52)
        $btn.FlatStyle = 'Flat'
        $btn.BackColor = [System.Drawing.Color]::FromArgb(244, 236, 216)
        $btn.ForeColor = [System.Drawing.Color]::FromArgb(14, 30, 46)
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(216, 207, 184)
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $btn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
        $btn.Tag = $Presentation.ActionScript
        $btn.Add_Click({
            param($s, $e)
            try {
                if ($s.Tag) { & $s.Tag }
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Erreur : $($_.Exception.Message)", 'Action impossible',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
        })
        $card.Controls.Add($btn)
    }

    return $card
}

function Get-UserProfile {
    # Heuristique : detecte si l'utilisateur est pro, creatif ou particulier lambda
    # en fonction des logiciels installes et des processus actifs.
    try {
        $names = @()
        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $names += Get-ChildItem -Path $p -ErrorAction SilentlyContinue |
                    ForEach-Object { (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DisplayName } |
                    Where-Object { $_ }
            }
        }
        $procs = @()
        try { $procs = (Get-Process -ErrorAction SilentlyContinue).Name } catch {}
        $all = @($names + $procs) -join '|'

        $proPatterns = 'Sage|EBP|Cegid|Ciel|QuickBooks|AutoCAD|SolidWorks|Visual Studio|JetBrains|IntelliJ|PyCharm|WebStorm|Rider|Salesforce|HubSpot|SAP|AutoEntrepreneur|Indy|Tiime'
        $creativePatterns = 'Photoshop|Illustrator|Premiere|After Effects|Lightroom|InDesign|Blender|DaVinci|Final Cut|Logic Pro|Ableton|FL Studio|Audacity|OBS Studio|Cubase|Reaper|Cinema 4D|Autodesk Maya|3ds Max|ZBrush|Affinity'

        if ($all -match $proPatterns) { return 'Pro' }
        if ($all -match $creativePatterns) { return 'Creative' }
        return 'Lambda'
    } catch {
        return 'Lambda'
    }
}

function New-CtaCard {
    param([string]$Profile, [int]$Width)
    $card = New-Object System.Windows.Forms.Panel
    $card.Width = $Width
    $card.Height = 120
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 12)
    $card.BackColor = [System.Drawing.Color]::FromArgb(0xFA, 0xF6, 0xEA)
    $card.Add_Paint({
        param($s, $e)
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184))
        $e.Graphics.DrawRectangle($border, 0, 0, $s.Width-1, $s.Height-1)
        $border.Dispose()
    })

    $message = switch ($Profile) {
        'Pro' {
            @{
                Title = 'Vous utilisez ce PC pour votre activité ?'
                Body  = "Triskell Studio crée des sites web sobres et performants pour les indépendants et artisans. Un PC qui tourne bien, c'est aussi un site qui marche bien."
                Btn   = 'Découvrir Triskell Studio'
                Url   = 'https://triskellstudio.fr'
            }
        }
        'Creative' {
            @{
                Title = 'Créatif ? Découvrez les autres outils du druide'
                Body  = "Triskell Studio développe d'autres outils sobres pour les créatifs : Trisnap (captures), Murmur (transcription locale), Trimind (notes). Sans pub, sans cloud."
                Btn   = "Voir l'écosystème Triskell"
                Url   = 'https://triskellstudio.fr'
            }
        }
        default {
            @{
                Title = 'Restez en bonne santé numérique'
                Body  = "Recevez les conseils du druide chaque mois (une fois, jamais plus) : entretien PC, sécurité, vie privée. Pas de pub, pas de spam, désinscription en 1 clic."
                Btn   = "S'abonner à la newsletter"
                Url   = 'https://triskellstudio.fr/newsletter'
            }
        }
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = $message.Title
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(31, 77, 58)
    $title.Location = New-Object System.Drawing.Point(20, 14)
    $title.AutoSize = $true
    $card.Controls.Add($title)

    $body = New-Object System.Windows.Forms.Label
    $body.Text = $message.Body
    $body.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $body.ForeColor = [System.Drawing.Color]::FromArgb(90, 107, 95)
    $body.Location = New-Object System.Drawing.Point(20, 40)
    $body.Size = New-Object System.Drawing.Size($Width - 220, 50)
    $card.Controls.Add($body)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $message.Btn
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btn.Size = New-Object System.Drawing.Size(180, 34)
    $btn.Location = New-Object System.Drawing.Point(($Width - 200), 40)
    $btn.FlatStyle = 'Flat'
    $btn.BackColor = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $url = $message.Url
    $btn.Add_Click({ try { Start-Process $url } catch {} }.GetNewClosure())
    $card.Controls.Add($btn)

    $footer = New-Object System.Windows.Forms.Label
    $footer.Text = "Suggestion contextuelle - aucune donnée n'a été envoyée pour ça."
    $footer.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
    $footer.ForeColor = [System.Drawing.Color]::FromArgb(90, 107, 95)
    $footer.Location = New-Object System.Drawing.Point(20, 92)
    $footer.AutoSize = $true
    $card.Controls.Add($footer)

    return $card
}

function New-EvolutionCard {
    param($Diff, [int]$Width)
    $card = New-Object System.Windows.Forms.Panel
    $card.Width = $Width
    $card.Height = 110
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
    $card.BackColor = [System.Drawing.Color]::White
    $stripe = [System.Drawing.Color]::FromArgb(200, 164, 92) # or doré
    $card.Tag = @{ Stripe = $stripe }
    $card.Add_Paint({
        param($s, $e)
        $stripeCol = $s.Tag.Stripe
        $brush = New-Object System.Drawing.SolidBrush($stripeCol)
        $e.Graphics.FillRectangle($brush, 0, 0, 5, $s.Height)
        $brush.Dispose()
        $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184))
        $e.Graphics.DrawRectangle($border, 0, 0, $s.Width-1, $s.Height-1)
        $border.Dispose()
    })

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Evolution depuis le dernier scan"
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(14, 30, 46)
    $title.Location = New-Object System.Drawing.Point(20, 12)
    $title.AutoSize = $true
    $card.Controls.Add($title)

    $date = ''
    try {
        $d = [datetime]$Diff.PreviousDate
        $date = $d.ToString('dddd dd MMMM HH:mm')
    } catch {}

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = if ($date) { "Comparé au scan du $date" } else { 'Comparé au scan précédent' }
    $sub.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Italic)
    $sub.ForeColor = [System.Drawing.Color]::FromArgb(90, 107, 95)
    $sub.Location = New-Object System.Drawing.Point(20, 36)
    $sub.AutoSize = $true
    $card.Controls.Add($sub)

    $parts = @()
    if ($Diff.Resolved.Count -gt 0) { $parts += "✓ $($Diff.Resolved.Count) résolu(s)" }
    if ($Diff.New.Count -gt 0) { $parts += "+ $($Diff.New.Count) nouveau(x)" }
    if ($Diff.Persistent.Count -gt 0) { $parts += "= $($Diff.Persistent.Count) persistant(s)" }
    if ($parts.Count -eq 0) { $parts += "Aucun changement depuis le scan précédent." }

    $line = New-Object System.Windows.Forms.Label
    $line.Text = $parts -join '   '
    $line.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $line.ForeColor = [System.Drawing.Color]::FromArgb(14, 30, 46)
    $line.Location = New-Object System.Drawing.Point(20, 64)
    $line.AutoSize = $true
    $card.Controls.Add($line)

    return $card
}

function Render-Findings {
    param($Container, $Banner, $Diff)

    $Container.Controls.Clear()

    $crit = @($script:Findings | Where-Object { $_.Severity -eq 'Critical' })
    $warn = @($script:Findings | Where-Object { $_.Severity -eq 'Warning' })

    $iconLbl  = $Banner.Controls['statusIcon']
    $titleLbl = $Banner.Controls['statusTitle']
    $subLbl   = $Banner.Controls['statusSubtitle']

    if ($crit.Count -eq 0 -and $warn.Count -eq 0) {
        $iconLbl.Text      = '🟢'
        $iconLbl.ForeColor = [System.Drawing.Color]::FromArgb(107, 166, 114)
        $titleLbl.Text     = 'Tout va bien'
        $subLbl.Text       = "Aucun problème détecté."
    }
    elseif ($crit.Count -gt 0) {
        $iconLbl.Text      = '🔴'
        $iconLbl.ForeColor = [System.Drawing.Color]::FromArgb(178, 59, 59)
        $titleLbl.Text     = 'Problèmes détectés'
        if ($warn.Count -gt 0) {
            $subLbl.Text = "$($crit.Count) problème(s) important(s) et $($warn.Count) point(s) à surveiller."
        } else {
            $subLbl.Text = "$($crit.Count) problème(s) important(s) à régler."
        }
    }
    else {
        $iconLbl.Text      = '🟡'
        $iconLbl.ForeColor = [System.Drawing.Color]::FromArgb(217, 137, 46)
        $titleLbl.Text     = 'Quelques points à vérifier'
        $subLbl.Text       = "$($warn.Count) point(s) à surveiller, rien d'urgent."
    }

    $sortKey = { switch ($_.Severity) { 'Critical' {0} 'Warning' {1} 'Info' {2} default {3} } }
    $sorted  = @($script:Findings | Sort-Object $sortKey)

    $w = $Container.ClientSize.Width - 48 - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    if ($w -lt 400) { $w = 400 }

    # Carte d'evolution si on a un diff
    if ($Diff) {
        $evCard = New-EvolutionCard -Diff $Diff -Width $w
        $Container.Controls.Add($evCard)
    }

    # Déduplication par titre humain (les findings techniques peuvent se répéter)
    $seen = @{}
    foreach ($f in $sorted) {
        $pres = Get-FindingPresentation -Finding $f
        if ($seen.ContainsKey($pres.Title)) { continue }
        $seen[$pres.Title] = $true

        $card = New-FindingCard -Presentation $pres -Width $w
        $Container.Controls.Add($card)
    }

    if ($Container.Controls.Count -eq 0) {
        $emptyLabel = New-Object System.Windows.Forms.Label
        $emptyLabel.Text      = "Tout est en ordre. Bonne journée !"
        $emptyLabel.Font      = New-Object System.Drawing.Font('Segoe UI', 12)
        $emptyLabel.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
        $emptyLabel.AutoSize  = $true
        $emptyLabel.Margin    = New-Object System.Windows.Forms.Padding(20, 40, 20, 20)
        $Container.Controls.Add($emptyLabel)
    }

    # CTA contextuel selon profil utilisateur (toujours en dernier)
    try {
        $userProfile = Get-UserProfile
        $cta = New-CtaCard -Profile $userProfile -Width $w
        $Container.Controls.Add($cta)
    } catch {}
}

# ============================================================
# DEFENDER ORCHESTRATION (v1.4.0)
# ------------------------------------------------------------
# Le Druide n'embarque pas son propre moteur antivirus : il
# orchestre les moteurs natifs de Windows déjà présents sur
# la machine de l'utilisateur. Cela garantit signatures à jour
# et zéro conflit avec un AV tiers.
# ============================================================

function Get-DefenderProtectionStatus {
    <#
    .SYNOPSIS
    Retourne l'état complet de la protection : objet structuré
    consommable par l'UI (carte de statut, bandeau "Vous êtes protégé").

    .OUTPUTS
    PSCustomObject avec : IsProtected (bool global), AntivirusEnabled,
    RealTimeProtectionEnabled, SignaturesUpToDate, SignatureAgeDays,
    QuickScanAge, FullScanAge, ProtectionLabel (texte court pour l'UI),
    ProtectionDetail (phrase d'explication), Error (string ou $null).
    #>
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $sigAge = if ($mp.AntivirusSignatureLastUpdated) {
            ((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
        } else { 999 }
        $sigOk = $sigAge -le $Thresholds.SignatureAgeDaysWarning

        $isProtected = $mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled -and $sigOk

        $label = if ($isProtected) { 'Vous êtes protégé' }
                 elseif (-not $mp.AntivirusEnabled) { 'Protection désactivée' }
                 elseif (-not $mp.RealTimeProtectionEnabled) { 'Temps réel désactivé' }
                 else { 'Signatures à mettre à jour' }

        $detail = if ($isProtected) {
            "Surveillance active en arrière-plan. Signatures à jour il y a {0:N0} jours." -f $sigAge
        } elseif (-not $mp.AntivirusEnabled) {
            "La protection principale est désactivée. Le Druide peut la réactiver en 1 clic."
        } elseif (-not $mp.RealTimeProtectionEnabled) {
            "La surveillance en temps réel est éteinte. Cliquez pour la réactiver."
        } else {
            "Vos signatures ont {0:N0} jours. Mise à jour recommandée." -f $sigAge
        }

        return [PSCustomObject]@{
            IsProtected                = $isProtected
            AntivirusEnabled           = [bool]$mp.AntivirusEnabled
            RealTimeProtectionEnabled  = [bool]$mp.RealTimeProtectionEnabled
            SignaturesUpToDate         = $sigOk
            SignatureAgeDays           = [math]::Round($sigAge, 1)
            QuickScanAge               = $mp.QuickScanAge
            FullScanAge                = $mp.FullScanAge
            ProtectionLabel            = $label
            ProtectionDetail           = $detail
            Error                      = $null
        }
    } catch {
        return [PSCustomObject]@{
            IsProtected                = $false
            AntivirusEnabled           = $false
            RealTimeProtectionEnabled  = $false
            SignaturesUpToDate         = $false
            SignatureAgeDays           = 999
            QuickScanAge               = 999
            FullScanAge                = 999
            ProtectionLabel            = 'Statut indisponible'
            ProtectionDetail           = "Impossible de lire l'état de la protection : $($_.Exception.Message)"
            Error                      = $_.Exception.Message
        }
    }
}

function Enable-DefenderRealtimeProtection {
    <#
    .SYNOPSIS
    Active la protection temps réel. Retourne $true si succès, $false sinon.
    Nécessite des droits admin (déjà demandés au lancement par ps2exe).
    #>
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Start-Sleep -Milliseconds 800
        $mp = Get-MpComputerStatus -ErrorAction Stop
        return [bool]$mp.RealTimeProtectionEnabled
    } catch {
        return $false
    }
}

function Start-DefenderQuickScan {
    <#
    .SYNOPSIS
    Lance un scan rapide (~3 min). Asynchrone : retourne immédiatement.
    Utilisez Get-DefenderScanResult pour récupérer les résultats.
    #>
    try {
        Start-MpScan -ScanType QuickScan -AsJob -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Start-DefenderFullScan {
    <#
    .SYNOPSIS
    Lance un scan complet (~30 min - 2h). Asynchrone.
    #>
    try {
        Start-MpScan -ScanType FullScan -AsJob -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-DefenderThreats {
    <#
    .SYNOPSIS
    Liste les menaces détectées (historique + quarantaine).

    .OUTPUTS
    Tableau d'objets PSCustomObject : ThreatID, Name, SeverityID,
    ActionSuccess, InitialDetectionTime, Resources (chemins concernés),
    DisplayName (nom lisible), SeverityLabel (Élevé / Moyen / Faible).
    #>
    try {
        $detections = Get-MpThreatDetection -ErrorAction Stop
        if (-not $detections) { return @() }

        return $detections | ForEach-Object {
            $sevId = $_.ThreatID  # ThreatStatusID en réalité, mais on simplifie
            $label = switch ($_.InitialDetectionTime) {
                $null { 'Inconnu' }
                default {
                    if ($_ -is [datetime]) { 'Détecté' } else { 'Inconnu' }
                }
            }
            [PSCustomObject]@{
                ThreatID              = $_.ThreatID
                Name                  = $_.ThreatID
                ActionSuccess         = $_.ActionSuccess
                InitialDetectionTime  = $_.InitialDetectionTime
                Resources             = $_.Resources
                ProcessName           = $_.ProcessName
                DomainUser            = $_.DomainUser
                RemediationTime       = $_.RemediationTime
            }
        }
    } catch {
        return @()
    }
}

function Remove-DefenderThreat {
    <#
    .SYNOPSIS
    Supprime/met en quarantaine une menace par son ThreatID.
    Si aucun ID fourni, supprime toutes les menaces détectées.
    #>
    param([Parameter()][int64]$ThreatID)
    try {
        if ($ThreatID) {
            Remove-MpThreat -ThreatID $ThreatID -ErrorAction Stop
        } else {
            Remove-MpThreat -ErrorAction Stop
        }
        return $true
    } catch {
        return $false
    }
}

function Update-DefenderSignatures {
    <#
    .SYNOPSIS
    Force la mise à jour des signatures (équivalent à 'Windows Update' côté Defender).
    Synchrone, peut prendre ~30 secondes selon la connexion.
    #>
    try {
        Update-MpSignature -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Show-DiagnosticGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Palette light theme
    $cBg          = [System.Drawing.Color]::FromArgb(0xF4, 0xEC, 0xD8)
    $cCard        = [System.Drawing.Color]::White
    $cBorder      = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $cText        = [System.Drawing.Color]::FromArgb(0x0E, 0x1E, 0x2E)
    $cTextMuted   = [System.Drawing.Color]::FromArgb(0x5A, 0x6B, 0x5F)
    $cAccent      = [System.Drawing.Color]::FromArgb(0x1F, 0x4D, 0x3A)
    $cAccentHover = [System.Drawing.Color]::FromArgb(0x2E, 0x6B, 0x4F)
    $cAccentDown  = [System.Drawing.Color]::FromArgb(0x15, 0x37, 0x28)
    $cBrand       = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Le Druide Antavirus'
    $form.Size = New-Object System.Drawing.Size(900, 720)
    $form.MinimumSize = New-Object System.Drawing.Size(740, 560)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = $cBg
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $form.ForeColor = $cText
    try { $appIcon = Get-DruideIcon; if ($appIcon) { $form.Icon = $appIcon } } catch {}

    # ========== HEADER ==========
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = 'Top'
    $headerPanel.Height = 100
    $headerPanel.BackColor = $cCard
    $headerPanel.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184))
        $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1)
        $pen.Dispose()
    })

    $logoBoxHeader = New-Object System.Windows.Forms.PictureBox
    $logoBoxHeader.Size = New-Object System.Drawing.Size(64, 64)
    $logoBoxHeader.Location = New-Object System.Drawing.Point(20, 18)
    $logoBoxHeader.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $logoBoxHeader.BackColor = [System.Drawing.Color]::Transparent
    try { $logoBmpHeader = Get-DruideLogo -Size 128; if ($logoBmpHeader) { $logoBoxHeader.Image = $logoBmpHeader } } catch {}
    $headerPanel.Controls.Add($logoBoxHeader)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = 'Le Druide Antavirus'
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $cText
    $titleLabel.Location = New-Object System.Drawing.Point(98, 14)
    $titleLabel.AutoSize = $true
    $headerPanel.Controls.Add($titleLabel)

    $subtitleLabel = New-Object System.Windows.Forms.Label
    $subtitleLabel.Text = "Analyse  ·  Protège  ·  Rassure"
    $subtitleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $subtitleLabel.ForeColor = $cBrand
    $subtitleLabel.Location = New-Object System.Drawing.Point(100, 50)
    $subtitleLabel.AutoSize = $true
    $headerPanel.Controls.Add($subtitleLabel)

    $brandLabel = New-Object System.Windows.Forms.Label
    $brandLabel.Text = "par Triskell Studio"
    $brandLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $brandLabel.ForeColor = $cTextMuted
    $brandLabel.Location = New-Object System.Drawing.Point(100, 74)
    $brandLabel.AutoSize = $true
    $headerPanel.Controls.Add($brandLabel)

    # ($btnScheduleHeader retire en v1.4.4 : redondant avec la carte "Planifier" du dashboard)

    $btnSettingsHeader = New-Object System.Windows.Forms.Button
    $btnSettingsHeader.Text = 'Paramètres'
    $btnSettingsHeader.Size = New-Object System.Drawing.Size(120, 36)
    $btnSettingsHeader.Location = New-Object System.Drawing.Point(760, 32)
    $btnSettingsHeader.FlatStyle = 'Flat'
    $btnSettingsHeader.BackColor = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)
    $btnSettingsHeader.ForeColor = [System.Drawing.Color]::White
    $btnSettingsHeader.FlatAppearance.BorderSize = 0
    $btnSettingsHeader.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xD4, 0xB6, 0x6A)
    $btnSettingsHeader.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0xB8, 0x94, 0x4C)
    $btnSettingsHeader.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnSettingsHeader.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSettingsHeader.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnSettingsHeader.Add_Click({ Show-SettingsDialog })
    $headerPanel.Controls.Add($btnSettingsHeader)
    Set-RoundedRegion -Button $btnSettingsHeader -Radius 10

    # ========== FOOTER ==========
    $footerPanel = New-Object System.Windows.Forms.Panel
    $footerPanel.Dock = 'Bottom'
    $footerPanel.Height = 64
    $footerPanel.BackColor = $cCard
    $footerPanel.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184))
        $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
        $pen.Dispose()
    })

    $btnTechnical = New-Object System.Windows.Forms.Button
    $btnTechnical.Text = 'Vue technique'
    $btnTechnical.Location = New-Object System.Drawing.Point(20, 12)
    $btnTechnical.Size = New-Object System.Drawing.Size(130, 36)
    $btnTechnical.FlatStyle = 'Flat'
    $btnTechnical.BackColor = $cBg
    $btnTechnical.ForeColor = $cText
    $btnTechnical.FlatAppearance.BorderSize = 0
    $btnTechnical.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
    $btnTechnical.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $btnTechnical.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnTechnical.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnTechnical.Enabled = $false
    $footerPanel.Controls.Add($btnTechnical)
    Set-RoundedRegion -Button $btnTechnical -Radius 10

    $btnReport = New-Object System.Windows.Forms.Button
    $btnReport.Text = 'Historique'
    $btnReport.Location = New-Object System.Drawing.Point(160, 12)
    $btnReport.Size = New-Object System.Drawing.Size(130, 36)
    $btnReport.FlatStyle = 'Flat'
    $btnReport.BackColor = $cBg
    $btnReport.ForeColor = $cText
    $btnReport.FlatAppearance.BorderSize = 0
    $btnReport.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
    $btnReport.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $btnReport.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnReport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnReport.Enabled = $true
    $footerPanel.Controls.Add($btnReport)
    Set-RoundedRegion -Button $btnReport -Radius 10

    # $btnHome est cree ici mais ajoute au HEADER (v1.4.4 : visible au premier coup d'oeil)
    $btnHome = New-Object System.Windows.Forms.Button
    $btnHome.Text = [char]0x2190 + ' Accueil'
    $btnHome.Size = New-Object System.Drawing.Size(110, 36)
    $btnHome.Location = New-Object System.Drawing.Point(640, 32)
    $btnHome.FlatStyle = 'Flat'
    $btnHome.BackColor = $cBg
    $btnHome.ForeColor = $cText
    $btnHome.FlatAppearance.BorderSize = 0
    $btnHome.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
    $btnHome.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $btnHome.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnHome.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnHome.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnHome.Enabled = $false
    $headerPanel.Controls.Add($btnHome)
    Set-RoundedRegion -Button $btnHome -Radius 10

    $btnRerun = New-Object System.Windows.Forms.Button
    $btnRerun.Text = 'Relancer'
    $btnRerun.Location = New-Object System.Drawing.Point(420, 12)
    $btnRerun.Size = New-Object System.Drawing.Size(110, 36)
    $btnRerun.FlatStyle = 'Flat'
    $btnRerun.BackColor = $cBg
    $btnRerun.ForeColor = $cText
    $btnRerun.FlatAppearance.BorderSize = 0
    $btnRerun.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
    $btnRerun.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $btnRerun.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnRerun.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnRerun.Enabled = $false
    $footerPanel.Controls.Add($btnRerun)
    Set-RoundedRegion -Button $btnRerun -Radius 10

    $btnQuit = New-Object System.Windows.Forms.Button
    $btnQuit.Text = 'Fermer'
    $btnQuit.Location = New-Object System.Drawing.Point(770, 12)
    $btnQuit.Size = New-Object System.Drawing.Size(100, 36)
    $btnQuit.FlatStyle = 'Flat'
    $btnQuit.BackColor = $cBg
    $btnQuit.ForeColor = $cText
    $btnQuit.FlatAppearance.BorderSize = 0
    $btnQuit.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
    $btnQuit.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $btnQuit.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnQuit.Cursor = [System.Windows.Forms.Cursors]::Hand
    $footerPanel.Controls.Add($btnQuit)
    Set-RoundedRegion -Button $btnQuit -Radius 10

    # ========== BOUTON FLOTTANT (FAB) : Assistant L'Oeil d'Antavirus ==========
    # Bouton rond dore, attache au form (au-dessus du contentPanel et du footer),
    # avec animation de pulsation pour signaler qu'il s'agit de l'assistant IA.
    $btnDruidix = New-Object System.Windows.Forms.Button
    $btnDruidix.Text = [char]::ConvertFromUtf32(0x1F441) + [char]0xFE0F
    $btnDruidix.Size = New-Object System.Drawing.Size(76, 76)
    $btnDruidix.FlatStyle = 'Flat'
    $btnDruidix.BackColor = $cBrand
    $btnDruidix.ForeColor = [System.Drawing.Color]::White
    $btnDruidix.FlatAppearance.BorderSize = 0
    $btnDruidix.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xD4, 0xB6, 0x6A)
    $btnDruidix.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 26, [System.Drawing.FontStyle]::Bold)
    $btnDruidix.UseCompatibleTextRendering = $true
    $btnDruidix.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $btnDruidix.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnDruidix.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    # Forme circulaire
    try {
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $gp.AddEllipse(0, 0, 76, 76)
        $btnDruidix.Region = New-Object System.Drawing.Region($gp)
    } catch {}
    # Tooltip pour expliquer ce que c'est
    $druidixTooltip = New-Object System.Windows.Forms.ToolTip
    $druidixTooltip.InitialDelay = 200
    $druidixTooltip.SetToolTip($btnDruidix, "L'Oeil d'Antavirus - assistant IA qui vous explique le diagnostic en mots simples")
    $btnDruidix.Add_Click({
        $auto = $null
        if ($script:Findings -and $script:Findings.Count -gt 0) {
            $auto = "Donnez-moi un plan d'action en 3 a 5 etapes priorisees pour mon PC, base sur le diagnostic ci-dessus. Pour chaque etape, expliquez en une phrase pourquoi c'est utile et indiquez si c'est urgent ou pas. Vouvoyez-moi."
        }
        Show-DruidixDialog -InitialQuestion $auto
    })
    $form.Controls.Add($btnDruidix)
    $btnDruidix.BringToFront()

    # Animation : alternance Or <-> Vert pour signaler que c'est l'assistant
    # (changement de teinte plus marque qu'une simple pulsation Or/Or clair)
    $druidixGlowTimer = New-Object System.Windows.Forms.Timer
    $druidixGlowTimer.Interval = 40
    $script:Druidix_GlowPhase = 0
    $druidixGlowTimer.Add_Tick({
        try {
            $script:Druidix_GlowPhase = ($script:Druidix_GlowPhase + 1) % 100
            # sinus 0..1 sur 100 ticks (4 secondes par cycle complet)
            $t = (1.0 - [Math]::Cos($script:Druidix_GlowPhase * [Math]::PI / 50.0)) / 2.0
            # Or (200, 164, 92) -> Vert sage (46, 107, 79)
            $r  = [int](200 + (46 - 200) * $t)
            $gr = [int](164 + (107 - 164) * $t)
            $b  = [int](92 + (79 - 92) * $t)
            $btnDruidix.BackColor = [System.Drawing.Color]::FromArgb($r, $gr, $b)

            # Pulsation legere de taille (76 <-> 82) pour effet "respiration"
            $newSize = 76 + [int](6 * $t)
            if ($btnDruidix.Width -ne $newSize) {
                $delta = [int](($newSize - $btnDruidix.Width) / 2)
                $oldX = $btnDruidix.Left
                $oldY = $btnDruidix.Top
                $btnDruidix.Size = New-Object System.Drawing.Size($newSize, $newSize)
                $btnDruidix.Location = New-Object System.Drawing.Point(($oldX - $delta), ($oldY - $delta))
                try {
                    $gp2 = New-Object System.Drawing.Drawing2D.GraphicsPath
                    $gp2.AddEllipse(0, 0, $newSize, $newSize)
                    $btnDruidix.Region = New-Object System.Drawing.Region($gp2)
                } catch {}
            }
        } catch {}
    })
    $druidixGlowTimer.Start()

    # ========== ZONE PRINCIPALE ==========
    $contentPanel = New-Object System.Windows.Forms.Panel
    $contentPanel.Dock = 'Fill'
    $contentPanel.BackColor = $cBg

    # ----- VUE 1 : ACCUEIL (dashboard style antivirus) -----
    $initialView = New-Object System.Windows.Forms.Panel
    $initialView.Dock = 'Fill'
    $initialView.BackColor = $cBg
    $initialView.AutoScroll = $true

    # ====== HERO : carte de statut de protection ======
    $heroCard = New-Object System.Windows.Forms.Panel
    $heroCard.BackColor = $cCard
    $heroCard.Size = New-Object System.Drawing.Size(740, 132)
    $heroCard.Add_Paint({
        param($s, $e)
        try {
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184), 1)
            $w = [int]([System.Windows.Forms.Control]$s).Width - 1
            $h = [int]([System.Windows.Forms.Control]$s).Height - 1
            # Surcharge 5-arguments (Pen, int, int, int, int) - plus fiable que (Pen, Rectangle) sous PowerShell
            $e.Graphics.DrawRectangle($pen, [int]0, [int]0, [int]$w, [int]$h)
            $pen.Dispose()
        } catch {}
    })
    Set-RoundedRegion -Button $heroCard -Radius 16
    $initialView.Controls.Add($heroCard)

    # Logo druide a gauche
    $heroIcon = New-Object System.Windows.Forms.PictureBox
    $heroIcon.Size = New-Object System.Drawing.Size(96, 96)
    $heroIcon.Location = New-Object System.Drawing.Point(20, 18)
    $heroIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $heroIcon.BackColor = [System.Drawing.Color]::Transparent
    try { $heroBmp = Get-DruideLogo -Size 192; if ($heroBmp) { $heroIcon.Image = $heroBmp } } catch {}
    $heroCard.Controls.Add($heroIcon)

    # Etat de protection deduit du dernier scan archive
    $heroTitleText     = "Bonjour"
    $heroSubtitleText  = "Vous n'avez pas encore lance de diagnostic."
    $heroSubtitle2Text = "Le premier scan ne prend qu'une trentaine de secondes."
    $heroBadgeColor    = $cBrand
    $heroBadgeText     = "Bienvenue"
    try {
        $prevScan = Get-PreviousFindings
        if ($prevScan -and $prevScan.Date) {
            # Parsing defensif : on force scalaire et conversion str->datetime explicite
            $rawDate = @($prevScan.Date)[0]
            $scanDate = [datetime]::Parse([string]$rawDate, [System.Globalization.CultureInfo]::InvariantCulture)
            $now = Get-Date
            $diff = [TimeSpan]($now - $scanDate)
            $days = [int]$diff.TotalDays
            $crit = @($prevScan.Findings | Where-Object { $_.Severity -eq 'Critical' }).Count
            $warn = @($prevScan.Findings | Where-Object { $_.Severity -eq 'Warning' }).Count

            if ($days -le 0)       { $relTime = "aujourd'hui" }
            elseif ($days -eq 1)   { $relTime = "hier" }
            elseif ($days -lt 7)   { $relTime = "il y a $days jours" }
            elseif ($days -lt 14)  { $relTime = "il y a 1 semaine" }
            else                   { $relTime = "il y a $([int]($days/7)) semaines" }

            if ($crit -gt 0) {
                $heroTitleText    = "Action recommandee"
                $heroSubtitleText = "Dernier scan $relTime  -  $crit point(s) critique(s) a corriger."
                $heroBadgeColor   = [System.Drawing.Color]::FromArgb(0xC8, 0x3A, 0x3A)
                $heroBadgeText    = "A SURVEILLER"
            } elseif ($warn -gt 0) {
                $heroTitleText    = "PC en bonne forme"
                $heroSubtitleText = "Dernier scan $relTime  -  $warn avertissement(s) a noter."
                $heroBadgeColor   = $cBrand
                $heroBadgeText    = "QUELQUES NOTES"
            } else {
                $heroTitleText    = "Vous etes protege"
                $heroSubtitleText = "Dernier scan $relTime  -  aucune anomalie detectee."
                $heroBadgeColor   = $cAccent
                $heroBadgeText    = "TOUT VA BIEN"
            }
            $heroSubtitle2Text = "Relancez un diagnostic quand vous le souhaitez."
        }
    } catch {}

    # Si un scan automatique est planifie, on remplace la 2e ligne par "Prochain scan : ..."
    try {
        $sched = Get-ScheduledScanInfo
        if ($sched -and $sched.Active -and $sched.NextRun) {
            $nr = [datetime]$sched.NextRun
            $heroSubtitle2Text = "Prochain scan planifie : " + $nr.ToString('dddd d MMMM "a" HH"h"mm', [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR'))
        }
    } catch {}

    # ----- Surcouche Defender (v1.4.0) -----
    # Reflete l'etat temps reel de la protection systeme. Prioritise sur tout :
    # si la protection est inactive, on remplace le hero pour pousser au fix.
    $defenderStatus = $null
    try { $defenderStatus = Get-DefenderProtectionStatus } catch {}
    if ($defenderStatus -and -not $defenderStatus.Error) {
        if (-not $defenderStatus.IsProtected) {
            $heroTitleText     = $defenderStatus.ProtectionLabel
            $heroSubtitleText  = $defenderStatus.ProtectionDetail
            $heroSubtitle2Text = "Cliquez sur " + [char]0x00AB + " Reactiver " + [char]0x00BB + " pour retablir la surveillance."
            $heroBadgeColor    = [System.Drawing.Color]::FromArgb(0xC8, 0x3A, 0x3A)
            $heroBadgeText     = "PROTECTION INACTIVE"
        } elseif ($heroBadgeText -eq "Bienvenue") {
            # Pas de scan precedent + protection active : on remonte un etat positif
            $heroTitleText    = "Vous etes protege"
            $heroSubtitleText = $defenderStatus.ProtectionDetail
            $heroBadgeColor   = $cAccent
            $heroBadgeText    = "PROTECTION ACTIVE"
        }
    }

    $heroBadge = New-Object System.Windows.Forms.Label
    $heroBadge.Text = "  $heroBadgeText  "
    $heroBadge.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $heroBadge.ForeColor = [System.Drawing.Color]::White
    $heroBadge.BackColor = $heroBadgeColor
    $heroBadge.AutoSize = $true
    $heroBadge.Location = New-Object System.Drawing.Point(132, 22)
    $heroBadge.Padding = New-Object System.Windows.Forms.Padding(2, 4, 2, 4)
    $heroCard.Controls.Add($heroBadge)

    $heroTitle = New-Object System.Windows.Forms.Label
    $heroTitle.Text = $heroTitleText
    $heroTitle.Font = New-Object System.Drawing.Font('Segoe UI', 19, [System.Drawing.FontStyle]::Bold)
    $heroTitle.ForeColor = $cText
    $heroTitle.AutoSize = $true
    $heroTitle.Location = New-Object System.Drawing.Point(130, 46)
    $heroCard.Controls.Add($heroTitle)

    $heroSubtitle = New-Object System.Windows.Forms.Label
    $heroSubtitle.Text = $heroSubtitleText
    $heroSubtitle.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $heroSubtitle.ForeColor = $cTextMuted
    $heroSubtitle.AutoSize = $true
    $heroSubtitle.Location = New-Object System.Drawing.Point(132, 86)
    $heroCard.Controls.Add($heroSubtitle)

    $heroSubtitle2 = New-Object System.Windows.Forms.Label
    $heroSubtitle2.Text = $heroSubtitle2Text
    $heroSubtitle2.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $heroSubtitle2.ForeColor = $cTextMuted
    $heroSubtitle2.AutoSize = $true
    $heroSubtitle2.Location = New-Object System.Drawing.Point(132, 106)
    $heroCard.Controls.Add($heroSubtitle2)

    # ----- Bouton de reactivation Defender (v1.4.0) -----
    # Visible uniquement si la protection temps reel est coupee.
    # Ancre a droite du hero pour rester visible meme apres resize.
    if ($defenderStatus -and -not $defenderStatus.IsProtected -and -not $defenderStatus.Error) {
        $btnReactivate = New-Object System.Windows.Forms.Button
        $btnReactivate.Text = "Reactiver"
        $btnReactivate.Size = New-Object System.Drawing.Size(130, 38)
        $btnReactivate.BackColor = [System.Drawing.Color]::FromArgb(0xC8, 0x3A, 0x3A)
        $btnReactivate.ForeColor = [System.Drawing.Color]::White
        $btnReactivate.FlatStyle = 'Flat'
        $btnReactivate.FlatAppearance.BorderSize = 0
        $btnReactivate.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xD8, 0x4A, 0x4A)
        $btnReactivate.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $btnReactivate.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnReactivate.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
        $btnReactivate.Location = New-Object System.Drawing.Point(($heroCard.Width - 150), 47)
        Set-RoundedRegion -Button $btnReactivate -Radius 12
        $btnReactivate.Add_Click({
            $btnReactivate.Enabled = $false
            $btnReactivate.Text = "Patience..."
            $ok = Enable-DefenderRealtimeProtection
            if ($ok) {
                $newStatus = Get-DefenderProtectionStatus
                if ($newStatus -and $newStatus.IsProtected) {
                    $heroTitle.Text     = "Vous etes protege"
                    $heroSubtitle.Text  = $newStatus.ProtectionDetail
                    $heroSubtitle2.Text = "Surveillance active. Lancez un diagnostic quand vous le souhaitez."
                    $heroBadge.Text     = "  PROTECTION ACTIVE  "
                    $heroBadge.BackColor = $cAccent
                    $btnReactivate.Visible = $false
                    [System.Windows.Forms.MessageBox]::Show($form, "Protection temps reel reactivee.", "Le Druide", 'OK', 'Information') | Out-Null
                }
            } else {
                $btnReactivate.Enabled = $true
                $btnReactivate.Text = "Reactiver"
                [System.Windows.Forms.MessageBox]::Show($form, "Impossible de reactiver automatiquement. Verifiez que Le Druide est lance en tant qu'administrateur, ou ouvrez Securite Windows pour l'activer manuellement.", "Le Druide", 'OK', 'Warning') | Out-Null
            }
        })
        $heroCard.Controls.Add($btnReactivate)
        $btnReactivate.BringToFront()
    }

    # ====== Fabrique : creer une "carte action" cliquable ======
    # Approche : la carte est un Panel "visible" + un Button INVISIBLE hors-ecran
    # qui sert de relais pour Add_Click (compatible avec le code existant
    # qui fait $btnAnalyze.Add_Click({...})). Tous les enfants forwardent leur
    # clic vers ce bouton via PerformClick. Le hover est gere manuellement sur
    # le Panel + tous ses enfants, ce qui evite le scintillement.
    $newActionCard = {
        param(
            [string]$IconChar,
            [string]$Title,
            [string]$Desc,
            [bool]$IsPrimary,
            [int]$Width,
            [int]$Height
        )

        if ($IsPrimary) {
            $bgNormal = $cAccent
            $bgHover  = $cAccentHover
            $bgDown   = $cAccentDown
        } else {
            $bgNormal = $cCard
            $bgHover  = [System.Drawing.Color]::FromArgb(0xFA, 0xF5, 0xE6)
            $bgDown   = [System.Drawing.Color]::FromArgb(0xEC, 0xE5, 0xD0)
        }

        $card = New-Object System.Windows.Forms.Panel
        $card.Size = New-Object System.Drawing.Size($Width, $Height)
        $card.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.BackColor = $bgNormal
        if (-not $IsPrimary) {
            $card.Add_Paint({
                param($s, $e)
                try {
                    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184), 1)
                    $w = [int]([System.Windows.Forms.Control]$s).Width - 1
                    $h = [int]([System.Windows.Forms.Control]$s).Height - 1
                    $e.Graphics.DrawRectangle($pen, [int]0, [int]0, [int]$w, [int]$h)
                    $pen.Dispose()
                } catch {}
            })
        }
        Set-RoundedRegion -Button $card -Radius 14

        $iconColor  = if ($IsPrimary) { [System.Drawing.Color]::White } else { $cAccent }
        $titleColor = if ($IsPrimary) { [System.Drawing.Color]::White } else { $cText }
        $descColor  = if ($IsPrimary) { [System.Drawing.Color]::FromArgb(0xDF, 0xE9, 0xE2) } else { $cTextMuted }

        $iconLabel = New-Object System.Windows.Forms.Label
        $iconLabel.Text = $IconChar
        $iconLabel.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 26)
        $iconLabel.ForeColor = $iconColor
        $iconLabel.BackColor = [System.Drawing.Color]::Transparent
        $iconLabel.AutoSize = $true
        $iconLabel.Location = New-Object System.Drawing.Point(20, 28)
        $iconLabel.UseCompatibleTextRendering = $true
        $iconLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.Controls.Add($iconLabel)

        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = $Title
        $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = $titleColor
        $titleLabel.BackColor = [System.Drawing.Color]::Transparent
        $titleLabel.AutoSize = $true
        $titleLabel.Location = New-Object System.Drawing.Point(78, 28)
        $titleLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.Controls.Add($titleLabel)

        $descLabel = New-Object System.Windows.Forms.Label
        $descLabel.Text = $Desc
        $descLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
        $descLabel.ForeColor = $descColor
        $descLabel.BackColor = [System.Drawing.Color]::Transparent
        $descLabel.AutoSize = $true
        $descLabel.Location = New-Object System.Drawing.Point(80, 58)
        $descLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.Controls.Add($descLabel)

        # Bouton relais invisible (hors ecran) : sert juste pour Add_Click
        $btn = New-Object System.Windows.Forms.Button
        $btn.Size = New-Object System.Drawing.Size(1, 1)
        $btn.Location = New-Object System.Drawing.Point(-1000, -1000)
        $btn.TabStop = $false
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderSize = 0
        $card.Controls.Add($btn)

        # Hover : on met a jour la couleur de fond sur MouseEnter de la carte
        # et de TOUS ses enfants. MouseLeave n'est attache qu'a la carte (le
        # MouseLeave d'un enfant signifie souvent qu'on entre dans un autre
        # enfant ou dans la carte, ce qui ne doit pas reinitialiser le hover).
        $setHover = { $card.BackColor = $bgHover }.GetNewClosure()
        $setNormal = {
            try {
                $pos = [System.Windows.Forms.Cursor]::Position
                $cardScreen = $card.RectangleToScreen($card.ClientRectangle)
                if (-not $cardScreen.Contains($pos)) {
                    $card.BackColor = $bgNormal
                }
            } catch { $card.BackColor = $bgNormal }
        }.GetNewClosure()
        $setDown = { $card.BackColor = $bgDown }.GetNewClosure()
        $setUp   = { $card.BackColor = $bgHover }.GetNewClosure()

        $card.Add_MouseEnter($setHover)
        $card.Add_MouseLeave($setNormal)
        $card.Add_MouseDown($setDown)
        $card.Add_MouseUp($setUp)

        $iconLabel.Add_MouseEnter($setHover)
        $iconLabel.Add_MouseLeave($setNormal)
        $iconLabel.Add_MouseDown($setDown)
        $iconLabel.Add_MouseUp($setUp)
        $titleLabel.Add_MouseEnter($setHover)
        $titleLabel.Add_MouseLeave($setNormal)
        $titleLabel.Add_MouseDown($setDown)
        $titleLabel.Add_MouseUp($setUp)
        $descLabel.Add_MouseEnter($setHover)
        $descLabel.Add_MouseLeave($setNormal)
        $descLabel.Add_MouseDown($setDown)
        $descLabel.Add_MouseUp($setUp)

        # Forwarder les clics vers le bouton relais
        $forward = { $btn.PerformClick() }.GetNewClosure()
        $iconLabel.Add_Click($forward)
        $titleLabel.Add_Click($forward)
        $descLabel.Add_Click($forward)
        $card.Add_Click($forward)

        return @{
            Card   = $card
            Button = $btn
            Icon   = $iconLabel
            Title  = $titleLabel
            Desc   = $descLabel
        }
    }

    # ====== 4 cartes d'action (2x2) ======
    $cardW = 362
    $cardH = 108

    $scanCard = & $newActionCard ([char]::ConvertFromUtf32(0x1F50D)) "Scanner mon PC" "Diagnostic complet  -  environ 30 sec" $true  $cardW $cardH
    $exprCard = & $newActionCard ([char]0x26A1)                       "Scan express"    "Verification rapide  -  15 sec"        $false $cardW $cardH
    $planCard = & $newActionCard ([char]::ConvertFromUtf32(0x1F4C5))  "Planifier"       "Scan automatique hebdomadaire"         $false $cardW $cardH
    $histCard = & $newActionCard ([char]::ConvertFromUtf32(0x1F4C2))  "Historique"      "Consulter vos rapports precedents"     $false $cardW $cardH

    $cardScan     = $scanCard.Card
    $cardExpress  = $exprCard.Card
    $cardSchedule = $planCard.Card
    $cardHistory  = $histCard.Card

    # On expose $btnAnalyze et $btnExpress (referencees plus bas dans les handlers)
    $btnAnalyze = $scanCard.Button
    $btnExpress = $exprCard.Button
    $btnHomeSchedule = $planCard.Button
    $btnHomeHistory  = $histCard.Button

    $btnHomeSchedule.Add_Click({ Show-ScheduleDialog })
    $btnHomeHistory.Add_Click({ Show-HistoryDialog })

    $initialView.Controls.Add($cardScan)
    $initialView.Controls.Add($cardExpress)
    $initialView.Controls.Add($cardSchedule)
    $initialView.Controls.Add($cardHistory)

    # ====== Bas de page : mode complet + rassurance ======
    $chkFullCard = New-Object System.Windows.Forms.CheckBox
    $chkFullCard.Text = "Mode complet (plus long, verifie aussi les mises a jour Windows)"
    $chkFullCard.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $chkFullCard.ForeColor = $cTextMuted
    $chkFullCard.AutoSize = $true
    $chkFullCard.BackColor = $cBg
    $chkFullCard.Checked = $Full.IsPresent
    $initialView.Controls.Add($chkFullCard)

    $initInfoLabel = New-Object System.Windows.Forms.Label
    $initInfoLabel.Text = [char]::ConvertFromUtf32(0x1F512) + "  Lecture seule. Le Druide ne modifie jamais votre PC sans votre accord."
    $initInfoLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $initInfoLabel.ForeColor = $cTextMuted
    $initInfoLabel.AutoSize = $true
    $initInfoLabel.UseCompatibleTextRendering = $true
    $initialView.Controls.Add($initInfoLabel)

    # ====== Layout responsive ======
    $initialView.Add_Resize({
        $cw = $initialView.ClientSize.Width
        $gap = 16

        # Bloc total : hero (132) + gap + 2 rangees de cartes (2 * 108 + gap) + gap + checkbox (22) + gap + info (18)
        $heroW = [math]::Min(740, $cw - 40)
        $cardsTotalW = ($cardW * 2) + $gap
        if ($cardsTotalW + 40 -gt $cw) {
            # Largeur insuffisante : on reduit la largeur des cartes
            $cardW2 = [math]::Max(240, [int](($cw - 40 - $gap) / 2))
            $cardScan.Size     = New-Object System.Drawing.Size($cardW2, $cardH)
            $cardExpress.Size  = New-Object System.Drawing.Size($cardW2, $cardH)
            $cardSchedule.Size = New-Object System.Drawing.Size($cardW2, $cardH)
            $cardHistory.Size  = New-Object System.Drawing.Size($cardW2, $cardH)
            Set-RoundedRegion -Button $cardScan     -Radius 14
            Set-RoundedRegion -Button $cardExpress  -Radius 14
            Set-RoundedRegion -Button $cardSchedule -Radius 14
            Set-RoundedRegion -Button $cardHistory  -Radius 14
            $cardsTotalW = ($cardW2 * 2) + $gap
        }

        $heroCard.Size = New-Object System.Drawing.Size($heroW, 132)
        Set-RoundedRegion -Button $heroCard -Radius 16

        $totalH = 132 + 18 + $cardH + $gap + $cardH + 22 + 22 + 14
        $top = [math]::Max(24, [int](($initialView.ClientSize.Height - $totalH) / 2))

        $heroCard.Location     = New-Object System.Drawing.Point([int](($cw - $heroCard.Width)/2), $top)

        $rowY1 = $heroCard.Bottom + 18
        $rowY2 = $rowY1 + $cardH + $gap
        $colX1 = [int](($cw - $cardsTotalW) / 2)
        $colX2 = $colX1 + $cardScan.Width + $gap

        $cardScan.Location     = New-Object System.Drawing.Point($colX1, $rowY1)
        $cardExpress.Location  = New-Object System.Drawing.Point($colX2, $rowY1)
        $cardSchedule.Location = New-Object System.Drawing.Point($colX1, $rowY2)
        $cardHistory.Location  = New-Object System.Drawing.Point($colX2, $rowY2)

        $chkFullCard.Location  = New-Object System.Drawing.Point([int](($cw - $chkFullCard.Width)/2), [int]($rowY2 + $cardH + 22))
        $initInfoLabel.Location = New-Object System.Drawing.Point([int](($cw - $initInfoLabel.Width)/2), [int]($chkFullCard.Bottom + 12))
    })

    # ----- VUE 2 : RUNNING -----
    $runningView = New-Object System.Windows.Forms.Panel
    $runningView.Dock = 'Fill'
    $runningView.BackColor = $cBg
    $runningView.Visible = $false

    $runningTitle = New-Object System.Windows.Forms.Label
    $runningTitle.Text = 'Analyse en cours...'
    $runningTitle.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $runningTitle.ForeColor = $cText
    $runningTitle.AutoSize = $true
    $runningView.Controls.Add($runningTitle)

    # Druide en grand pendant le scan (PictureBox au lieu d'un emoji)
    $scanIconLabel = New-Object System.Windows.Forms.PictureBox
    $scanIconLabel.Size = New-Object System.Drawing.Size(190, 190)
    $scanIconLabel.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $scanIconLabel.BackColor = [System.Drawing.Color]::Transparent
    try {
        $scanBmp = Get-DruideLogo -Size 256
        if ($scanBmp) {
            $script:Druidix_ScanSourceBmp = $scanBmp
            $scanIconLabel.Image = $scanBmp
        }
    } catch {}
    $runningView.Controls.Add($scanIconLabel)

    # Pre-compilation des frames de l'animation "piece sur une table"
    # On precalcule 72 frames (un tour complet, 5 degres par frame) une seule
    # fois, pour que le timer ne fasse plus que swap (ultra rapide, garde
    # l'animation fluide meme entre deux checks lents).
    $script:Druidix_ScanFrames = @()
    if ($script:Druidix_ScanSourceBmp) {
        $src = $script:Druidix_ScanSourceBmp
        $w = $src.Width
        $h = $src.Height
        for ($i = 0; $i -lt 72; $i++) {
            $rad = $i * 5 * [Math]::PI / 180.0
            $cos = [Math]::Cos($rad)
            $absCos = [Math]::Max(0.06, [Math]::Abs($cos))
            $newW = [int]($w * $absCos)
            if ($newW -lt 4) { $newW = 4 }
            $x = [int](($w - $newW) / 2)
            $bmp = New-Object System.Drawing.Bitmap($w, $h)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            if ($cos -ge 0) {
                $g.DrawImage($src, $x, 0, $newW, $h)
            } else {
                $g.TranslateTransform([float]($w / 2.0), 0)
                $g.ScaleTransform(-1.0, 1.0)
                $g.TranslateTransform([float](-$w / 2.0), 0)
                $g.DrawImage($src, $x, 0, $newW, $h)
            }
            $g.Dispose()
            $script:Druidix_ScanFrames += $bmp
        }
    }

    # Barre de progression custom (indigo Triskell) au lieu du ProgressBar Windows vert
    $progressBarFrame = New-Object System.Windows.Forms.Panel
    $progressBarFrame.Size = New-Object System.Drawing.Size(440, 8)
    $progressBarFrame.BackColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCF, 0xB8)
    $runningView.Controls.Add($progressBarFrame)

    $progressBarFill = New-Object System.Windows.Forms.Panel
    $progressBarFill.Location = New-Object System.Drawing.Point(0, 0)
    $progressBarFill.Size = New-Object System.Drawing.Size(0, 8)
    $progressBarFill.BackColor = $cAccent
    $progressBarFrame.Controls.Add($progressBarFill)

    # Variable factice pour compatibilite (Write-Section utilise GuiContext.Progress)
    $progressBar = [PSCustomObject]@{
        Frame = $progressBarFrame
        Fill  = $progressBarFill
    }
    Add-Member -InputObject $progressBar -MemberType ScriptProperty -Name Value -Value { 0 } -SecondValue { param($v); try { $newW = [int]($this.Frame.Width * [math]::Min(100, [math]::Max(0, $v)) / 100); $this.Fill.Width = $newW } catch {} }

    $progressStatus = New-Object System.Windows.Forms.Label
    $progressStatus.Text = 'Initialisation'
    $progressStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $progressStatus.ForeColor = $cTextMuted
    $progressStatus.AutoSize = $true
    $runningView.Controls.Add($progressStatus)

    $progressPercent = New-Object System.Windows.Forms.Label
    $progressPercent.Text = '0 %'
    $progressPercent.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $progressPercent.ForeColor = $cBrand
    $progressPercent.AutoSize = $true
    $runningView.Controls.Add($progressPercent)

    # Animation : medaillon qui tourne sur son axe vertical (piece sur une table)
    # Les frames sont precalculees, le timer ne fait qu'un swap d'image -> tres rapide.
    $scanTimer = New-Object System.Windows.Forms.Timer
    $scanTimer.Interval = 40
    $script:Druidix_ScanIdx = 0
    $scanTimer.Add_Tick({
        try {
            if ($script:Druidix_ScanFrames -and $script:Druidix_ScanFrames.Count -gt 0) {
                $script:Druidix_ScanIdx = ($script:Druidix_ScanIdx + 1) % $script:Druidix_ScanFrames.Count
                $scanIconLabel.Image = $script:Druidix_ScanFrames[$script:Druidix_ScanIdx]
            }
        } catch {}
    })

    # Animation points dans "Analyse en cours..."
    $dotsTimer = New-Object System.Windows.Forms.Timer
    $dotsTimer.Interval = 350
    $script:Druidix_DotsIdx = 0
    $dotsTimer.Add_Tick({
        $script:Druidix_DotsIdx = ($script:Druidix_DotsIdx + 1) % 4
        $dots = '.' * $script:Druidix_DotsIdx
        $runningTitle.Text = "Analyse en cours$dots"
    })

    $runningView.Add_Resize({
        $cw = $runningView.ClientSize.Width
        $ch = $runningView.ClientSize.Height
        $scanIconLabel.Location   = New-Object System.Drawing.Point([int](($cw - $scanIconLabel.Width)/2), [int]($ch/2 - 165))
        $runningTitle.Location    = New-Object System.Drawing.Point([int](($cw - $runningTitle.Width)/2), [int]($scanIconLabel.Bottom + 8))
        $progressBarFrame.Location = New-Object System.Drawing.Point([int](($cw - $progressBarFrame.Width)/2), [int]($runningTitle.Bottom + 24))
        $progressPercent.Location = New-Object System.Drawing.Point([int](($cw - $progressPercent.Width)/2), [int]($progressBarFrame.Bottom + 12))
        $progressStatus.Location  = New-Object System.Drawing.Point([int](($cw - $progressStatus.Width)/2), [int]($progressPercent.Bottom + 8))
    })

    # ----- VUE 3 : RESULTS -----
    $resultsView = New-Object System.Windows.Forms.Panel
    $resultsView.Dock = 'Fill'
    $resultsView.BackColor = $cBg
    $resultsView.Visible = $false

    $cardsContainer = New-Object System.Windows.Forms.FlowLayoutPanel
    $cardsContainer.Dock = 'Fill'
    $cardsContainer.AutoScroll = $true
    $cardsContainer.FlowDirection = 'TopDown'
    $cardsContainer.WrapContents = $false
    $cardsContainer.BackColor = $cBg
    $cardsContainer.Padding = New-Object System.Windows.Forms.Padding(24, 20, 24, 20)
    $cardsContainer.TabStop = $true
    $cardsContainer.Add_MouseEnter({ try { $cardsContainer.Focus() | Out-Null } catch {} })
    $cardsContainer.Add_Resize({
        $w = $cardsContainer.ClientSize.Width - 48 - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
        if ($w -lt 200) { $w = 200 }
        foreach ($c in $cardsContainer.Controls) {
            if ($c -is [System.Windows.Forms.Panel]) { $c.Width = $w }
        }
    })

    $statusBanner = New-Object System.Windows.Forms.Panel
    $statusBanner.Dock = 'Top'
    $statusBanner.Height = 110
    $statusBanner.BackColor = $cCard
    $statusBanner.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(216, 207, 184))
        $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1)
        $pen.Dispose()
    })

    $statusIcon = New-Object System.Windows.Forms.Label
    $statusIcon.Name = 'statusIcon'
    $statusIcon.Text = '...'
    $statusIcon.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 36)
    $statusIcon.UseCompatibleTextRendering = $true
    $statusIcon.AutoSize = $true
    $statusIcon.Location = New-Object System.Drawing.Point(28, 22)
    $statusBanner.Controls.Add($statusIcon)

    $statusTitle = New-Object System.Windows.Forms.Label
    $statusTitle.Name = 'statusTitle'
    $statusTitle.Text = ''
    $statusTitle.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $statusTitle.ForeColor = $cText
    $statusTitle.AutoSize = $true
    $statusTitle.Location = New-Object System.Drawing.Point(106, 26)
    $statusBanner.Controls.Add($statusTitle)

    $statusSubtitle = New-Object System.Windows.Forms.Label
    $statusSubtitle.Name = 'statusSubtitle'
    $statusSubtitle.Text = ''
    $statusSubtitle.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $statusSubtitle.ForeColor = $cTextMuted
    $statusSubtitle.AutoSize = $true
    $statusSubtitle.Location = New-Object System.Drawing.Point(108, 60)
    $statusBanner.Controls.Add($statusSubtitle)

    # IMPORTANT : ajouter cardsContainer AVANT statusBanner pour que Dock=Fill fonctionne
    $resultsView.Controls.Add($cardsContainer)
    $resultsView.Controls.Add($statusBanner)

    # ----- VUE 4 : TECHNICAL -----
    $technicalView = New-Object System.Windows.Forms.Panel
    $technicalView.Dock = 'Fill'
    $technicalView.BackColor = [System.Drawing.Color]::FromArgb(14, 30, 46)
    $technicalView.Visible = $false

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Dock = 'Fill'
    $rtb.BackColor = [System.Drawing.Color]::FromArgb(14, 30, 46)
    $rtb.ForeColor = [System.Drawing.Color]::White
    $rtb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $rtb.ReadOnly = $true
    $rtb.WordWrap = $false
    $rtb.ScrollBars = 'Both'
    $rtb.BorderStyle = 'None'
    $technicalView.Controls.Add($rtb)

    # Empilage des vues (Fill : la dernière ajoutée est sur le dessus)
    $contentPanel.Controls.Add($technicalView)
    $contentPanel.Controls.Add($resultsView)
    $contentPanel.Controls.Add($runningView)
    $contentPanel.Controls.Add($initialView)

    # Bandeau de mise a jour (visible seulement si nouvelle version detectee)
    $updateBanner = New-Object System.Windows.Forms.Panel
    $updateBanner.Dock = 'Top'
    $updateBanner.Height = 44
    $updateBanner.BackColor = [System.Drawing.Color]::FromArgb(0xC8, 0xA4, 0x5C)
    $updateBanner.Visible = $false
    $updateBanner.Cursor = [System.Windows.Forms.Cursors]::Hand

    $updateBannerLabel = New-Object System.Windows.Forms.Label
    $updateBannerLabel.Dock = 'Fill'
    $updateBannerLabel.TextAlign = 'MiddleCenter'
    $updateBannerLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
    $updateBannerLabel.ForeColor = [System.Drawing.Color]::White
    $updateBannerLabel.Text = ''
    $updateBannerLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $updateBanner.Controls.Add($updateBannerLabel)

    $script:UpdateBannerUrl = $null
    $openUpdateUrl = { if ($script:UpdateBannerUrl) { try { Start-Process $script:UpdateBannerUrl } catch {} } }
    $updateBanner.Add_Click($openUpdateUrl)
    $updateBannerLabel.Add_Click($openUpdateUrl)

    # Ajout en dernier dans le contentPanel pour qu'il soit en haut (Dock layout inverse)
    $contentPanel.Controls.Add($updateBanner)

    # Empilage des panels du form (Fill ajouté en premier, puis Bottom, puis Top)
    $form.Controls.Add($contentPanel)
    $form.Controls.Add($footerPanel)
    $form.Controls.Add($headerPanel)

    # ========== ÉTAT ==========
    $script:LastReportPath = $null
    $script:CurrentView    = 'initial'

    $switchView = {
        param([string]$v)
        $initialView.Visible   = ($v -eq 'initial')
        $runningView.Visible   = ($v -eq 'running')
        $resultsView.Visible   = ($v -eq 'results')
        $technicalView.Visible = ($v -eq 'technical')
        $script:CurrentView = $v
    }

    # ========== HANDLERS ==========

    $runAnalysis = {
        & $switchView 'running'
        $progressStatus.Text = 'Démarrage...'
        $progressBar.Value = 0
        $progressPercent.Text = '0 %'
        try { $scanTimer.Start() } catch {}
        try { $dotsTimer.Start() } catch {}
        [System.Windows.Forms.Application]::DoEvents()

        $rtb.Clear()
        $script:Findings.Clear()
        $script:Report = New-Object System.Text.StringBuilder
        $script:GuiContext = @{
            Rtb = $rtb
            Status = $progressStatus
            Form = $form
            Progress = $progressBar
            ProgressPercent = $progressPercent
            SectionTotal = 15
            SectionCount = 0
        }

        $script:Full       = $chkFullCard.Checked
        $script:startTime  = Get-Date
        $ts                = $script:startTime.ToString('yyyyMMdd_HHmmss')
        $script:reportPath = Join-Path $OutputDir "Diagnostic-PC_$ts.txt"

        Append-GuiLine '+--------------------------------------------------------------+' (Get-GuiColor 'SECTION')
        Append-GuiLine '|                LE DRUIDE - Diagnostic Windows                |' (Get-GuiColor 'SECTION')
        Append-GuiLine '+--------------------------------------------------------------+' (Get-GuiColor 'SECTION')
        [void]$script:Report.AppendLine("Démarré le  : $($script:startTime.ToString('yyyy-MM-dd HH:mm:ss'))")
        [void]$script:Report.AppendLine("Mode admin  : $isAdmin")
        [void]$script:Report.AppendLine("Mode Full   : $script:Full")

        try {
            if ($script:NextScanMode -eq 'Express') {
                $script:GuiContext.SectionTotal = 6
                Invoke-ExpressChecks
            } else {
                Invoke-AllChecks
            }
            [void](Save-Report -Path $script:reportPath)
            $script:LastReportPath = $script:reportPath
            Add-ReportToArchive -Path $script:reportPath

            # Diff vs scan precedent (Get-PreviousFindings AVANT Save-FindingsSnapshot)
            $prev = Get-PreviousFindings
            Save-FindingsSnapshot
            $diff = if ($prev) { Get-FindingsDiff -Previous $prev } else { $null }

            Render-Findings -Container $cardsContainer -Banner $statusBanner -Diff $diff

            $btnReport.Enabled    = $true
            $btnTechnical.Enabled = $true
            $btnRerun.Enabled     = $true
            $btnHome.Enabled      = $true

            & $switchView 'results'
        }
        catch {
            Append-GuiLine "ERREUR : $($_.Exception.Message)" (Get-GuiColor 'CRIT')
            & $switchView 'technical'
        }
        finally {
            $script:GuiContext = $null
            try { $scanTimer.Stop() } catch {}
            try { $dotsTimer.Stop() } catch {}
        }
    }

    $btnAnalyze.Add_Click({
        $script:NextScanMode = 'Standard'
        # v1.4.0 : declenche en parallele un scan rapide Defender (background async).
        try { Start-DefenderQuickScan | Out-Null } catch {}
        & $runAnalysis
    })
    $btnExpress.Add_Click({
        $script:NextScanMode = 'Express'
        try { Start-DefenderQuickScan | Out-Null } catch {}
        & $runAnalysis
    })
    $btnRerun.Add_Click({
        # Conserve le mode du scan precedent
        & $runAnalysis
    })
    $btnHome.Add_Click({
        & $switchView 'initial'
        if ($script:CurrentView -ne 'technical') { $btnTechnical.Text = 'Vue technique' }
    })

    $btnTechnical.Add_Click({
        if ($script:CurrentView -eq 'technical') {
            & $switchView 'results'
            $btnTechnical.Text = 'Vue technique'
        } else {
            & $switchView 'technical'
            $btnTechnical.Text = 'Vue simple'
        }
    })

    $btnReport.Add_Click({ Show-HistoryDialog })

    $btnQuit.Add_Click({ $form.Close() })

    # Repositionnement explicite des boutons header (ancrage Right capricieux en WinForms)
    # + centrage des boutons du footer + FAB en bas-droite
    $repositionAnchored = {
        try {
            $fw = $form.ClientSize.Width
            $fh = $form.ClientSize.Height
            if ($fw -lt 800) { $fw = 800 }
            if ($fh -lt 600) { $fh = 600 }

            # Boutons header : alignes a droite (Accueil + Parametres)
            $btnHome.Location           = New-Object System.Drawing.Point(($fw - 260), 33)
            $btnSettingsHeader.Location = New-Object System.Drawing.Point(($fw - 140), 33)

            # Centrage des 4 boutons du footer (Accueil a deplace dans le header)
            # Tailles : 130 + 130 + 110 + 100 = 470, gaps 14*3 = 42 -> total 512
            $gap = 14
            $w1 = 130; $w2 = 130; $w3 = 110; $w4 = 100
            $total = $w1 + $gap + $w2 + $gap + $w3 + $gap + $w4
            $startX = [int](($fw - $total) / 2)
            $y = 14
            $btnTechnical.Location = New-Object System.Drawing.Point($startX, $y)
            $x = $startX + $w1 + $gap
            $btnReport.Location    = New-Object System.Drawing.Point($x, $y)
            $x = $x + $w2 + $gap
            $btnRerun.Location     = New-Object System.Drawing.Point($x, $y)
            $x = $x + $w3 + $gap
            $btnQuit.Location      = New-Object System.Drawing.Point($x, $y)

            # FAB "L'Oeil d'Antavirus" en bas-droite (flottant, chevauche le footer)
            $fabMargin = 22
            $btnDruidix.Location = New-Object System.Drawing.Point(($fw - 76 - $fabMargin), ($fh - 76 - $fabMargin))
            $btnDruidix.BringToFront()
        } catch {}
    }
    $form.Add_Shown($repositionAnchored)
    $form.Add_Resize($repositionAnchored)

    # Check de mise a jour en arriere-plan, au demarrage uniquement
    $form.Add_Shown({
        try {
            Start-UpdateCheck -OnFound {
                param($release)
                $script:UpdateBannerUrl = $release.Url
                $tag = $release.Tag
                $updateBannerLabel.Text = "Nouvelle version $tag disponible - Cliquez pour la telecharger"
                $updateBanner.Visible = $true
            }
        } catch {}
    })

    [void]$form.ShowDialog()
}

# ============================================================
# EXÉCUTION
# ============================================================

if ($Console) {
    Clear-Host
    $banner = @(
        '+--------------------------------------------------------------+',
        '|                LE DRUIDE - Diagnostic Windows                |',
        '|             Outil bienveillant en lecture seule              |',
        '+--------------------------------------------------------------+'
    )
    foreach ($l in $banner) { Write-Host $l -ForegroundColor Cyan; [void]$script:Report.AppendLine($l) }
    [void]$script:Report.AppendLine("Démarré le  : $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$script:Report.AppendLine("Mode admin  : $isAdmin")
    [void]$script:Report.AppendLine("Mode Full   : $($Full.IsPresent)")

    Invoke-AllChecks

    if (Save-Report -Path $reportPath) {
        Write-Host ''
        Write-Host "Rapport texte écrit : $reportPath" -ForegroundColor Green
    }
    else {
        Write-Host ''
        Write-Host "Impossible d'écrire le rapport : $reportPath" -ForegroundColor Red
    }

    if (-not $NoPause -and [Environment]::UserInteractive) {
        Write-Host ''
        Write-Host 'Appuyez sur Entrée pour fermer...' -ForegroundColor DarkGray
        try { $null = Read-Host } catch {}
    }
}
else {
    if ($Silent) {
        # Mode planifie : scan sans GUI, archive, notif si critique
        try {
            if ($Express) { Invoke-ExpressChecks } else { Invoke-AllChecks }
            [void](Save-Report -Path $reportPath)
            Add-ReportToArchive -Path $reportPath
            Save-FindingsSnapshot
            $crits = @($script:Findings | Where-Object { $_.Severity -eq 'Critical' })
            if ($crits.Count -gt 0) {
                Show-CriticalToast -Count $crits.Count -ReportPath $reportPath
            }
        } catch {}
        exit 0
    }
    if (Test-FirstLaunch) {
        try { Show-OnboardingDialog } catch {}
    }
    Show-DiagnosticGui
}
