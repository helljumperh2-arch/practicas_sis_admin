# ==============================================================================
# P09 - 01-Infraestructura.ps1 (VERSIÓN FINAL)
# ==============================================================================

$Dominio     = "ayala.local"
$NetBIOS     = "AYALA"
$DomainDN    = "DC=ayala,DC=local"
$StorageBase = "C:\GestionAD\Storage"
$CSVPath     = "P08-ActiveDirectory\Windows\Usuarios.csv"
$ServerName  = hostname

function Instalar-ADDS {
    if (!(Get-WindowsFeature AD-Domain-Services).Installed) {
        Write-Host "[*] Instalando AD DS..." -ForegroundColor Cyan
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
        Write-Host "[OK] AD DS instalado." -ForegroundColor Green
    } else {
        Write-Host "[*] AD DS ya instalado." -ForegroundColor Yellow
    }
}

function Promover-DC {
    try {
        Get-ADDomain -ErrorAction Stop | Out-Null
        Write-Host "[*] Dominio ya existe: $Dominio" -ForegroundColor Yellow
    } catch {
        Write-Host "[*] Promoviendo a Domain Controller..." -ForegroundColor Cyan
        $SafePass = ConvertTo-SecureString "Admin123!" -AsPlainText -Force
        Install-ADDSForest `
            -DomainName                    $Dominio `
            -DomainNetbiosName             $NetBIOS `
            -SafeModeAdministratorPassword $SafePass `
            -InstallDns -Force -NoRebootOnCompletion
        Write-Host "[OK] DC promovido. REINICIA el servidor." -ForegroundColor Green
        Pause; Exit
    }
}

function Crear-UOs {
    Import-Module ActiveDirectory
    foreach ($ou in @("Cuates","NoCuates")) {
        $path = "OU=$ou,$DomainDN"
        if (!(Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$path'" -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $ou -Path $DomainDN -ProtectedFromAccidentalDeletion $false
            Write-Host "[OK] OU creada: $ou" -ForegroundColor Green
        } else {
            Write-Host "[*] OU ya existe: $ou" -ForegroundColor Yellow
        }
    }
}

function Crear-Grupos {
    foreach ($g in @("Cuates","NoCuates")) {
        $ou = "OU=$g,$DomainDN"
        if (!(Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path $ou
            Write-Host "[OK] Grupo creado: $g" -ForegroundColor Green
        } else {
            Write-Host "[*] Grupo ya existe: $g" -ForegroundColor Yellow
        }
    }
}

function Get-LogonHoursBytes {
    param([string]$Grupo)
    $bytes    = New-Object byte[] 21
    $dias     = 1..5
    $horasUTC = if ($Grupo -eq "Cuates") { 15..21 } else { @(22,23) + (0..8) }
    foreach ($dia in $dias) {
        foreach ($hora in $horasUTC) {
            $bitPos  = ($dia * 24) + $hora
            $byteIdx = [math]::Floor($bitPos / 8)
            $bitIdx  = $bitPos % 8
            if ($byteIdx -lt 21) {
                $bytes[$byteIdx] = $bytes[$byteIdx] -bor [byte](1 -shl $bitIdx)
            }
        }
    }
    return $bytes
}

function Crear-Usuarios {
    if (!(Test-Path $CSVPath)) {
        Write-Host "[!] CSV no encontrado en: $CSVPath" -ForegroundColor Red
        return
    }

    if (!(Get-SmbShare -Name "Storage" -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name "Storage" -Path $StorageBase -FullAccess "Everyone"
    }

    $usuarios = Import-Csv $CSVPath
    Write-Host "[*] Usuarios detectados en CSV: $($usuarios.Count)" -ForegroundColor Cyan

    foreach ($u in $usuarios) {
        $sam        = $u.Cuenta.Trim()
        $nombre     = $u.Nombre.Trim()
        $pass       = $u.Password.Trim()
        $depto      = ($u.Departamento.Trim()) -replace "\s+",""
        $ouPath     = "OU=$depto,$DomainDN"
        $passSecure = ConvertTo-SecureString $pass -AsPlainText -Force

        Write-Host "`n--- Procesando: $sam ($depto) ---" -ForegroundColor White

        # 1. Crear usuario
        if (!(Get-ADUser -Filter "SamAccountName -eq '$sam'")) {
            try {
                New-ADUser -Name $nombre -DisplayName $nombre -SamAccountName $sam `
                           -UserPrincipalName "$sam@$Dominio" -Path $ouPath `
                           -AccountPassword $passSecure -Enabled $true -ChangePasswordAtLogon $false
                Write-Host "  [OK] Usuario creado: $sam" -ForegroundColor Green
            } catch {
                Write-Host "  [!] Error creando $sam : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        } else {
            Write-Host "  [*] Ya existe: $sam" -ForegroundColor Yellow
        }

        # 2. Grupo
        Add-ADGroupMember -Identity $depto -Members $sam -ErrorAction SilentlyContinue

        # 3. Horario
        try {
            $bytes = Get-LogonHoursBytes -Grupo $depto
            Set-ADUser -Identity $sam -Replace @{logonHours = $bytes}
            Write-Host "  [OK] Horario aplicado." -ForegroundColor Green
        } catch {
            Write-Host "  [!] Horario: $($_.Exception.Message)" -ForegroundColor Red
        }

        # 4. Carpeta personal
        $carpeta = "$StorageBase\$depto\$sam"
        if (!(Test-Path $carpeta)) {
            New-Item -Path $carpeta -ItemType Directory -Force | Out-Null
        }

        # 5. Permisos NTFS
        try {
            $acl  = Get-Acl $carpeta
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$NetBIOS\$sam", "Modify",
                "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.SetAccessRule($rule)
            Set-Acl -Path $carpeta -AclObject $acl
            Write-Host "  [OK] Permisos NTFS aplicados." -ForegroundColor Green
        } catch {
            Write-Host "  [!] NTFS error: $($_.Exception.Message)" -ForegroundColor Red
        }

        # 6. Home Drive
        $RutaRed = "\\$ServerName\Storage\$depto\$sam"
        Set-ADUser -Identity $sam -HomeDirectory $RutaRed -HomeDrive "H:"
        Write-Host "  [->] HomeDrive: $RutaRed" -ForegroundColor Cyan

        # 7. Cuota FSRM (NUEVO - aplica automático a nuevos usuarios)
        try {
            $plantilla = if ($depto -eq "Cuates") { "Cuota-Cuates" } else { "Cuota-NoCuates" }
            $cuotaExistente = Get-FsrmQuota -Path $carpeta -ErrorAction SilentlyContinue
            if ($cuotaExistente) {
                Set-FsrmQuota -Path $carpeta -Template $plantilla
            } else {
                New-FsrmQuota -Path $carpeta -Template $plantilla
            }
            Write-Host "  [OK] Cuota $plantilla aplicada." -ForegroundColor Green
        } catch {
            Write-Host "  [!] Cuota error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ----------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------
Clear-Host
Write-Host "=== P09 INFRAESTRUCTURA AD ===" -ForegroundColor Cyan
Instalar-ADDS

try {
    Get-ADDomain -ErrorAction Stop | Out-Null
    Write-Host "[OK] Dominio activo: $Dominio" -ForegroundColor Green

    Crear-UOs
    Crear-Grupos

    if (!(Test-Path $StorageBase)) { New-Item $StorageBase -ItemType Directory -Force | Out-Null }
    foreach ($f in @("Cuates","NoCuates")) {
        $fp = "$StorageBase\$f"
        if (!(Test-Path $fp)) { New-Item $fp -ItemType Directory -Force | Out-Null }
    }

    Crear-Usuarios
    Write-Host "`n[OK] INFRAESTRUCTURA COMPLETADA." -ForegroundColor Green
} catch {
    Promover-DC
}

sc.exe config appidsvc start= auto
Start-Service appidsvc
Pause