function Menu-DHCP {
     Mon-Servicer "DHCPServer"
    
    Write-Host "=== CONFIGURACION DHCP (GATEWAY OPCIONAL) ===" -ForegroundColor Yellow
    $Global:InterfazActiva = Read-Host "Interfaz (ej: Ethernet 2)"
    $ip_s = Read-Host "IP Servidor (ej: 10.10.10.3)"
    $mask = Read-Host "Mascara (ej: 255.255.255.0)"
    $gw   = Read-Host "Gateway (Enter para dejar VACIO)"
    $ip_f = Read-Host "IP Final Rango"
    $dns  = Read-Host "DNS (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[*] Limpiando y fijando IP estática..." -ForegroundColor Cyan
    Stop-Service DHCPServer -Force -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $Global:InterfazActiva -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    $p = @{ InterfaceAlias = $Global:InterfazActiva; IPAddress = $ip_s; PrefixLength = 24 }
    if ($gw) { $p.DefaultGateway = $gw }
    New-NetIPAddress @p -ErrorAction SilentlyContinue | Out-Null

    Write-Host "[*] Iniciando DHCP (Esperando sincronización RPC)..." -ForegroundColor Yellow
    Start-Service DHCPServer
    while ((Get-Service DHCPServer).Status -ne "Running") { Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 4 

    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue
    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    
    Add-DhcpServerv4Scope -Name "Red_Scope" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force
    Set-DhcpServerv4Binding -InterfaceAlias $Global:InterfazActiva -BindingState $true
    
    Restart-Service DHCPServer -Force
    Write-Host "[OK] DHCP Configurado." -ForegroundColor Green; Pause
}
