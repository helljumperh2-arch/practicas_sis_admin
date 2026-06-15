# ==============================================================================
# MODULO FTP - WINDOWS
# Equivalente a: FTP_Service.sh
# ==============================================================================

Import-Module WebAdministration -ErrorAction SilentlyContinue

$Global:BASE_DATA  = "C:\inetpub\ftproot"
$Global:FTP_ROOT   = "C:\FTP_Users"
$Global:LOCAL_USER = "$Global:FTP_ROOT\LocalUser"

function Configurar_Servicio_FTP {
   Mon-Servicer -Servicio dns
    Write-Host "[+] Automatizando configuracion de FTP (IIS)..." -ForegroundColor Cyan

    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

    foreach ($dir in @($Global:BASE_DATA, $Global:FTP_ROOT, $Global:LOCAL_USER)) {
        if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    }
    foreach ($grupo in @("general", "reprobados", "recursadores")) {
        $p = Join-Path $Global:BASE_DATA $grupo
        if (!(Test-Path $p)) { New-Item $p -ItemType Directory -Force | Out-Null }
        icacls $p /grant "Todos:(OI)(CI)R" /T /Q | Out-Null
    }

    if (!(Get-Website -Name "ServidorPracticas" -ErrorAction SilentlyContinue)) {
        & $appcmd add site /name:"ServidorPracticas" /bindings:ftp://*:21 /physicalPath:"$Global:FTP_ROOT"
    }

    & $appcmd set site "ServidorPracticas" "-ftpServer.userIsolation.mode:IsolateAllDirectories"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.ssl.controlChannelPolicy:SslAllow"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.ssl.dataChannelPolicy:SslAllow"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.authentication.basicAuthentication.enabled:true"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.authentication.anonymousAuthentication.enabled:true"
    & $appcmd set config "ServidorPracticas" -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='*',permissions='Read,Write']" /commit:apphost 2>$null

    $AnonPath = Join-Path $Global:LOCAL_USER "Public"
    if (!(Test-Path $AnonPath)) { New-Item $AnonPath -ItemType Directory -Force | Out-Null }
    if (!(Test-Path "$AnonPath\general")) {
        cmd /c "mklink /D `"$AnonPath\general`" `"$Global:BASE_DATA\general`""
    }

    netsh advfirewall firewall add rule name="FTP Pasivo" dir=in action=allow protocol=TCP localport=40000-40100 2>$null | Out-Null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "[OK] FTP configurado y servicio reiniciado." -ForegroundColor Green
}

function Setup_Entorno {
    Write-Host "[+] Preparando directorios en $Global:BASE_DATA..." -ForegroundColor Cyan

    foreach ($dir in @("general", "reprobados", "recursadores")) {
        $p = Join-Path $Global:BASE_DATA $dir
        if (!(Test-Path $p)) { New-Item $p -ItemType Directory -Force | Out-Null }
    }

    Set-Content "$Global:BASE_DATA\general\LEEME.txt" "Bienvenido al servidor FTP Publico"

    foreach ($grupo in @("reprobados", "recursadores", "ftpwrite")) {
        if (!(Get-LocalGroup $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup $grupo | Out-Null
        }
    }

    icacls "$Global:BASE_DATA\general"      /grant "ftpwrite:(OI)(CI)M"     /T /Q | Out-Null
    icacls "$Global:BASE_DATA\reprobados"   /grant "reprobados:(OI)(CI)F"   /T /Q | Out-Null
    icacls "$Global:BASE_DATA\recursadores" /grant "recursadores:(OI)(CI)F" /T /Q | Out-Null

    Write-Host "[OK] Estructura de directorios y permisos listos." -ForegroundColor Green
}

function GestionUG {
    while ($true) {
        Write-Host ""
        Write-Host "[*] Gestion de Usuarios y Grupos" -ForegroundColor Cyan
        Write-Host "1) Crear Usuarios (Masivo)"
        Write-Host "2) Cambiar Usuario de Grupo"
        Write-Host "7) Volver al Menu"
        $op = Read-Host "Opcion"
        switch ($op) {
            "1" { CrearUser }
            "2" { CambiarGrupo }
            "7" { return }
            default { Write-Host "Opcion no valida." -ForegroundColor Red }
        }
    }
}

function CrearUser {
    Clear-Host
    Write-Host " [*] Creacion de Usuarios" -ForegroundColor Cyan

    $N_Usuarios = Read-Host "Cantidad de usuarios a crear"
    if (-not ($N_Usuarios -as [int])) { Write-Host "Numero invalido."; return }
    $N_Usuarios = [int]$N_Usuarios

    # Relajar politica de contrasenas
    $cfg = "C:\Windows\Temp\sec.cfg"
    secedit /export /cfg $cfg | Out-Null
    $cont = Get-Content $cfg
    $cont = $cont -replace "PasswordComplexity = 1", "PasswordComplexity = 0"
    $cont = $cont -replace "MinimumPasswordLength = .*", "MinimumPasswordLength = 0"
    $cont | Set-Content $cfg
    secedit /configure /db $env:windir\security\local.sdb /cfg $cfg /areas SECURITYPOLICY | Out-Null

    for ($i = 1; $i -le $N_Usuarios; $i++) {
        Write-Host ""
        Write-Host "--- Usuario $i de $N_Usuarios ---"
        $Nombre_Usuario = Read-Host "Nombre de usuario"
        $Passwd_Usuario = Read-Host "Contrasena" -AsSecureString

        Write-Host "Grupo: 1) reprobados | 2) recursadores"
        $G_Opt = Read-Host "Opcion"
        $Grupo = if ($G_Opt -eq "1") { "reprobados" } else { "recursadores" }

        if (Get-LocalUser $Nombre_Usuario -ErrorAction SilentlyContinue) {
            Write-Host "[!] El usuario $Nombre_Usuario ya existe. Saltando..." -ForegroundColor Yellow
            continue
        }

        if (!(Get-LocalGroup $Grupo      -ErrorAction SilentlyContinue)) { New-LocalGroup $Grupo      | Out-Null }
        if (!(Get-LocalGroup "ftpwrite"  -ErrorAction SilentlyContinue)) { New-LocalGroup "ftpwrite"  | Out-Null }

        New-LocalUser -Name $Nombre_Usuario -Password $Passwd_Usuario -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember -Group $Grupo     -Member $Nombre_Usuario -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "ftpwrite" -Member $Nombre_Usuario -ErrorAction SilentlyContinue

        $Home_User = Join-Path $Global:LOCAL_USER $Nombre_Usuario

        if (Test-Path $Home_User) { Remove-Item $Home_User -Recurse -Force }
        New-Item $Home_User -ItemType Directory -Force | Out-Null
        icacls $Home_User /inheritance:r /grant "Administradores:(OI)(CI)F" /grant "${Nombre_Usuario}:(OI)(CI)RX" /T /Q | Out-Null

        # Carpetas de acceso compartido (equivalente a mount --bind)
        if (Test-Path "$Home_User\general") { Remove-Item "$Home_User\general" -Force -Recurse }
        if (Test-Path "$Home_User\$Grupo")  { Remove-Item "$Home_User\$Grupo"  -Force -Recurse }
        cmd /c "mklink /D `"$Home_User\general`" `"$Global:BASE_DATA\general`"" | Out-Null
        cmd /c "mklink /D `"$Home_User\$Grupo`"  `"$Global:BASE_DATA\$Grupo`""  | Out-Null

        # Carpeta privada del usuario
        $Privada = "$Home_User\$Nombre_Usuario"
        New-Item $Privada -ItemType Directory -Force | Out-Null
        icacls $Privada /inheritance:r /grant "${Nombre_Usuario}:(OI)(CI)F" /T /Q | Out-Null

        Write-Host "[+] Usuario $Nombre_Usuario configurado con exito." -ForegroundColor Green
    }
    Start-Sleep -Seconds 2
}

function CambiarGrupo {
    Write-Host ""
    Write-Host "--- Cambio de Grupo Dinamico ---" -ForegroundColor Cyan
    $Nombre_Usuario = Read-Host "Nombre del usuario"

    if (!(Get-LocalUser $Nombre_Usuario -ErrorAction SilentlyContinue)) {
        Write-Host "[!] El usuario no existe." -ForegroundColor Red
        return
    }

    Write-Host "Seleccione NUEVO Grupo: 1) reprobados | 2) recursadores"
    $G_Opt = Read-Host "Opcion"

    if ($G_Opt -eq "1") {
        $NuevoGrupo = "reprobados"
        $ViejoGrupo = "recursadores"
    } else {
        $NuevoGrupo = "recursadores"
        $ViejoGrupo = "reprobados"
    }

    Remove-LocalGroupMember -Group $ViejoGrupo -Member $Nombre_Usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $NuevoGrupo -Member $Nombre_Usuario -ErrorAction SilentlyContinue

    $Home_User = Join-Path $Global:LOCAL_USER $Nombre_Usuario

    icacls "$Home_User\$Nombre_Usuario" /grant "${Nombre_Usuario}:(OI)(CI)F" /T /Q | Out-Null

    if (Test-Path "$Home_User\$ViejoGrupo") {
        Remove-Item "$Home_User\$ViejoGrupo" -Force -Recurse
    }

    if (!(Test-Path "$Home_User\$NuevoGrupo")) {
        cmd /c "mklink /D `"$Home_User\$NuevoGrupo`" `"$Global:BASE_DATA\$NuevoGrupo`"" | Out-Null
    }

    Write-Host "[OK] $Nombre_Usuario movido a $NuevoGrupo." -ForegroundColor Green
}

function Menu-FTP {
    if (Get-Command Comprobar-Instalacion -ErrorAction SilentlyContinue) {
        Comprobar-Instalacion "Web-FTP-Server" $false
    }

    Setup_Entorno
    Configurar_Servicio_FTP

    while ($true) {
        Write-Host ""
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host "          Menu FTP              " -ForegroundColor Cyan
        Write-Host "================================"
        Write-Host "1) Gestion de Usuarios (Masiva)"
        Write-Host "2) Consultar estado (ftpsvc)"
        Write-Host "3) Reiniciar servicio"
        Write-Host "4) Volver al Orquestador"
        $opcion = Read-Host "Opcion"

        switch ($opcion) {
            "1" { GestionUG }
            "2" { Get-Service ftpsvc | Format-List Name, Status, StartType; Pause }
            "3" { Restart-Service ftpsvc -ErrorAction SilentlyContinue; Write-Host "Servicio Reiniciado." -ForegroundColor Cyan }
            "4" { return }
            default { Write-Host "Opcion no valida." -ForegroundColor Red }
        }
    }
}
