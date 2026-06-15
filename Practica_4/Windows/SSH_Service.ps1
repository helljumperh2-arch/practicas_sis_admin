function Configurar-SSH {
    Write-Host "--- INSTALANDO OPENSSH (MODO CAPABILITY) ---" -ForegroundColor Cyan
    
    $check = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    
    if ($check.State -ne 'Installed') {
        Write-Host "[*] Instalando paquete oficial de Microsoft..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name $check.Name | Out-Null
    } else {
        Write-Host "[v] El servicio OpenSSH ya esta presente." -ForegroundColor Green
    }

    Write-Host "[*] Configurando demonio SSHD..." -ForegroundColor Yellow
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic

    # Abrir Firewall (Puerto 22)
    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "SSH" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
    }
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -like "Ethernet").IPv4Address | Select-Object -First 1
    
    Write-Host "`n================================================"
    Write-Host " HITO CRITICO: SSH CONFIGURADO EN NAT" -ForegroundColor Green
    Write-Host " IP para Administracion: $ip" -ForegroundColor Yellow
    Write-Host " Conectate con: ssh $($env:USERNAME)@$ip" -ForegroundColor Cyan
    Write-Host "================================================"
    Pause
}
