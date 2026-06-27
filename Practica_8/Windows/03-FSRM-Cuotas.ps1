# ==============================================================================
# P09 - FSRM: CUOTAS Y APANTALLAMIENTO (VERSIÓN FINAL)
# ==============================================================================

$StorageBase = "C:\GestionAD\Storage"
$Dominio     = "ayala.local"
$DomainDN    = "DC=ayala,DC=local"

function Instalar-FSRM {
    if (!(Get-WindowsFeature FS-Resource-Manager).Installed) {
        Write-Host "[*] Instalando FSRM..." -ForegroundColor Cyan
        Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools | Out-Null
        Write-Host "[OK] FSRM instalado." -ForegroundColor Green
    } else {
        Write-Host "[*] FSRM ya instalado." -ForegroundColor Yellow
    }
    Import-Module FileServerResourceManager
}

function Crear-Plantillas-Cuota {
    if (!(Get-FsrmQuotaTemplate -Name "Cuota-Cuates" -ErrorAction SilentlyContinue)) {
        New-FsrmQuotaTemplate -Name "Cuota-Cuates" -Size 10MB -SoftLimit:$false
        Write-Host "[OK] Plantilla Cuota-Cuates (10MB) creada." -ForegroundColor Green
    } else {
        Write-Host "[*] Plantilla Cuota-Cuates ya existe." -ForegroundColor Yellow
    }

    if (!(Get-FsrmQuotaTemplate -Name "Cuota-NoCuates" -ErrorAction SilentlyContinue)) {
        New-FsrmQuotaTemplate -Name "Cuota-NoCuates" -Size 5MB -SoftLimit:$false
        Write-Host "[OK] Plantilla Cuota-NoCuates (5MB) creada." -ForegroundColor Green
    } else {
        Write-Host "[*] Plantilla Cuota-NoCuates ya existe." -ForegroundColor Yellow
    }
}

function Aplicar-Cuotas {
    Import-Module ActiveDirectory
    $usuarios = Get-ADUser -Filter * -SearchBase $DomainDN -Properties HomeDirectory, MemberOf |
                Where-Object { $_.HomeDirectory -ne $null }

    foreach ($u in $usuarios) {
        # Convertir ruta UNC a ruta local
        $carpeta = $u.HomeDirectory -replace "\\\\[^\\]+\\Storage", $StorageBase
        if (!(Test-Path $carpeta)) { continue }

        $grupos = $u.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
        if ($grupos -contains "Cuates") {
            $plantilla = "Cuota-Cuates"; $limite = "10MB"
        } elseif ($grupos -contains "NoCuates") {
            $plantilla = "Cuota-NoCuates"; $limite = "5MB"
        } else { continue }

        $cuotaExistente = Get-FsrmQuota -Path $carpeta -ErrorAction SilentlyContinue
        if ($cuotaExistente) {
            Set-FsrmQuota -Path $carpeta -Template $plantilla
        } else {
            New-FsrmQuota -Path $carpeta -Template $plantilla
        }
        Write-Host "[OK] Cuota ${limite}: $($u.SamAccountName) -> $carpeta" -ForegroundColor Green
    }
}

function Crear-Grupo-Archivos-Bloqueados {
    $nombre = "Archivos-Prohibidos"
    $ext    = @("*.mp3","*.mp4","*.exe","*.msi","*.bat","*.cmd","*.vbs")
    if (!(Get-FsrmFileGroup -Name $nombre -ErrorAction SilentlyContinue)) {
        New-FsrmFileGroup -Name $nombre -IncludePattern $ext
        Write-Host "[OK] Grupo archivos bloqueados creado." -ForegroundColor Green
    } else {
        Set-FsrmFileGroup -Name $nombre -IncludePattern $ext
        Write-Host "[*] Grupo archivos bloqueados actualizado." -ForegroundColor Yellow
    }
}

function Aplicar-Apantallamiento {
    foreach ($grupo in @("Cuates","NoCuates")) {
        $carpetaGrupo = "$StorageBase\$grupo"
        if (!(Test-Path $carpetaGrupo)) { continue }

        $scr = Get-FsrmFileScreen -Path $carpetaGrupo -ErrorAction SilentlyContinue
        if ($scr) {
            Set-FsrmFileScreen -Path $carpetaGrupo -IncludeGroup @("Archivos-Prohibidos") -Active:$true
        } else {
            New-FsrmFileScreen -Path $carpetaGrupo -IncludeGroup @("Archivos-Prohibidos") -Active:$true
        }
        Write-Host "[OK] Apantallamiento en: $carpetaGrupo" -ForegroundColor Green

        Get-ChildItem $carpetaGrupo -Directory | ForEach-Object {
            $sub = $_.FullName
            $scrSub = Get-FsrmFileScreen -Path $sub -ErrorAction SilentlyContinue
            if ($scrSub) {
                Set-FsrmFileScreen -Path $sub -IncludeGroup @("Archivos-Prohibidos") -Active:$true
            } else {
                New-FsrmFileScreen -Path $sub -IncludeGroup @("Archivos-Prohibidos") -Active:$true
            }
            Write-Host "  [->] Apantallamiento en: $sub" -ForegroundColor Cyan
        }
    }
}

# ----------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------
Write-Host "=== P09 FSRM ===" -ForegroundColor Cyan
Instalar-FSRM
Crear-Plantillas-Cuota
Aplicar-Cuotas
Crear-Grupo-Archivos-Bloqueados
Aplicar-Apantallamiento
Write-Host "[OK] FSRM configurado." -ForegroundColor Green
Pause