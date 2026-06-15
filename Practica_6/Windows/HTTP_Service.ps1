# ==============================================================================
# MODULO HTTP - WINDOWS (P06)
# ==============================================================================

function Detener-Competencia {
    param($actual)
    # Matar TODOS los servidores web para liberar el puerto
    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process httpd -ErrorAction SilentlyContinue | Stop-Process -Force
    Stop-Service nginx    -Force -ErrorAction SilentlyContinue
    Stop-Service Apache   -Force -ErrorAction SilentlyContinue
    Stop-Service Apache2.4 -Force -ErrorAction SilentlyContinue
    Stop-Service W3SVC    -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

function Aplicar-Puerto-HTTP {
    param($servicio)

    $p = $global:PUERTO_ACTUAL
    if (-not ($p -match '^\d+$')) {
        Write-Host "[!] Puerto invalido. Configura el puerto primero (opcion 7)." -ForegroundColor Red
        Pause; return
    }
    $p = [int]$p
    Write-Host "[*] Configurando $servicio en puerto $p..." -ForegroundColor Blue

    switch ($servicio) {

        "nginx" {
            $nginxDir = "C:\tools\nginx"
            if (!(Test-Path "$nginxDir\nginx.exe")) {
                Write-Host "[!] nginx no encontrado en $nginxDir" -ForegroundColor Red; Pause; return
            }

            Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Seconds 2

            $conf    = "$nginxDir\conf\nginx.conf"
            $webRoot = "$nginxDir\html"
            if (!(Test-Path $webRoot)) { New-Item $webRoot -ItemType Directory -Force | Out-Null }

            $nginxConf = @"
worker_processes  1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server {
        listen $p;
        server_name localhost;
        location / { root html; index index.html; }
    }
}
"@
            Set-Content $conf $nginxConf -Encoding ASCII
            Set-Content "$webRoot\index.html" "<html><body style='background:#1a1a2e;color:#0f9b58;font-family:Arial;text-align:center;padding:100px'><h1>NGINX - Puerto $p</h1></body></html>" -Encoding ASCII

            Write-Host "[*] Iniciando nginx en puerto $p..." -ForegroundColor Cyan
            Start-Process "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
            Start-Sleep -Seconds 4
        }

        "apache2" {
            # Detectar ruta REAL del servicio Apache instalado
            $rutaApache = $null

            # Primero buscar en el servicio de Windows (fuente de verdad)
            $svcApache = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svcApache) {
                $svcPath = (Get-WmiObject Win32_Service | Where-Object { $_.Name -like "Apache*" } | Select-Object -First 1).PathName
                if ($svcPath -match '"?([A-Za-z]:\[^"]+\bin\httpd\.exe)') {
                    $rutaApache = Split-Path (Split-Path $matches[1] -Parent) -Parent
                }
            }

            # Si no se obtuvo del servicio, buscar en rutas conocidas
            if (!$rutaApache) {
                foreach ($c in @("C:\Apache24","$env:APPDATA\Apache24","C:\tools\Apache24")) {
                    if (Test-Path "$c\bin\httpd.exe") { $rutaApache = $c; break }
                }
            }

            if (!$rutaApache) { Write-Host "[!] Apache no encontrado." -ForegroundColor Red; Pause; return }
            Write-Host "[*] Apache real en: $rutaApache" -ForegroundColor Cyan

            # Detener completamente
            Get-Process httpd -ErrorAction SilentlyContinue | Stop-Process -Force
            & "$rutaApache\bin\httpd.exe" -k stop 2>$null
            if ($svcApache) { Stop-Service $svcApache.Name -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2

            # Editar httpd.conf de la ruta REAL
            $conf = "$rutaApache\conf\httpd.conf"
            $lineas = Get-Content $conf
            $lineas = $lineas | ForEach-Object {
                if ($_ -match '^Listen \d+')        { "Listen $p" }
                elseif ($_ -match '^#?ServerName ') { "ServerName localhost:$p" }
                else { $_ }
            }
            Set-Content $conf $lineas -Encoding ASCII

            # Index en htdocs de la ruta real
            Set-Content "$rutaApache\htdocs\index.html" "<html><body style='background:#1a1a2e;color:#d4380d;font-family:Arial;text-align:center;padding:100px'><h1>APACHE - Puerto $p</h1></body></html>" -Encoding ASCII

            # Iniciar
            if ($svcApache) {
                Write-Host "[*] Iniciando $($svcApache.Name)..." -ForegroundColor Cyan
                Start-Service $svcApache.Name -ErrorAction SilentlyContinue
            } else {
                Write-Host "[*] Iniciando Apache directamente..." -ForegroundColor Cyan
                Start-Process "$rutaApache\bin\httpd.exe" -WindowStyle Hidden
            }
            Start-Sleep -Seconds 4
        }

        "tomcat10" {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            $webRoot = "C:\inetpub\wwwroot"
            if (!(Test-Path $webRoot)) { New-Item $webRoot -ItemType Directory -Force | Out-Null }
            Set-Content "$webRoot\index.html" "<html><body style='background:#1a1a2e;color:#0078d7;font-family:Arial;text-align:center;padding:100px'><h1>IIS - Puerto $p</h1></body></html>" -Encoding ASCII

            # Detener W3SVC antes de cambiar bindings
            Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            # Recrear Default Web Site con el puerto correcto
            try {
                Remove-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
                New-Website -Name "Default Web Site" -Port $p -PhysicalPath $webRoot -Force | Out-Null
            } catch {
                # Si falla, usar appcmd directamente
                $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
                & $appcmd set site "Default Web Site" /bindings:"http/*:$p`:" 2>$null
            }

            Start-Service W3SVC -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    }

    # Verificacion
    $activo = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($activo) {
        Write-Host "[OK] $servicio ONLINE en http://localhost:$p" -ForegroundColor Green
    } else {
        Write-Host "[!] Error: $servicio no escucha en puerto $p" -ForegroundColor Red

        # Mostrar ultimo error de Apache si aplica
        if ($servicio -eq "apache2") {
            $logPath = "C:\Apache24\logs\error.log"
            if (!(Test-Path $logPath)) { $logPath = "$env:APPDATA\Apache24\logs\error.log" }
            if (Test-Path $logPath) {
                Write-Host "    Ultimo error Apache:" -ForegroundColor Yellow
                Get-Content $logPath -Tail 3 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
            }
        }
    }
    Pause
}

function Menu-HTTP {
    while ($true) {
        Clear-Host
        $mostrar_puerto = if ($global:PUERTO_ACTUAL -and $global:PUERTO_ACTUAL -ne "N/A") { $global:PUERTO_ACTUAL } else { "N/A" }
        Write-Host ""
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "                MODULO HTTP                     " -ForegroundColor Cyan
        Write-Host "  Puerto configurado: $mostrar_puerto" -ForegroundColor Yellow
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "1) Instalar Nginx"
        Write-Host "2) Instalar Apache"
        Write-Host "3) Instalar IIS (Rol Windows)"
        Write-Host "4) Desplegar Nginx en puerto $mostrar_puerto"
        Write-Host "5) Desplegar Apache en puerto $mostrar_puerto"
        Write-Host "6) Desplegar IIS en puerto $mostrar_puerto"
        Write-Host "7) Configurar Puerto"
        Write-Host "8) Volver al Orquestador"
        Write-Host "------------------------------------------------"
        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {
            "1" {
                Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
                $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
                if (Test-Path $chocoExe) { & $chocoExe install nginx -y | Out-Null; Write-Host "[OK] nginx instalado" -ForegroundColor Green }
                Pause
            }
            "2" {
                $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
                if (Test-Path $chocoExe) { & $chocoExe install apache-httpd -y | Out-Null; Write-Host "[OK] apache instalado" -ForegroundColor Green }
                Pause
            }
            "3" { Install-WindowsFeature -Name Web-Server -IncludeManagementTools; Pause }
            "4" { Detener-Competencia "nginx";    Aplicar-Puerto-HTTP "nginx"    }
            "5" { Detener-Competencia "apache2";  Aplicar-Puerto-HTTP "apache2"  }
            "6" { Detener-Competencia "tomcat10"; Aplicar-Puerto-HTTP "tomcat10" }
            "7" {
                $nuevo = Read-Host "Ingrese el puerto HTTP (ej: 8080)"
                if ($nuevo -match '^\d+$' -and [int]$nuevo -ge 1 -and [int]$nuevo -le 65535) {
                    $global:PUERTO_ACTUAL = $nuevo
                    Write-Host "[OK] Puerto configurado a $nuevo" -ForegroundColor Green
                } else {
                    Write-Host "[!] Puerto invalido." -ForegroundColor Red
                }
                Pause
            }
            "8" { return }
            default { Write-Host "Opcion no valida." -ForegroundColor Red }
        }
    }
}
