function Menu-DNS {

    do {
        Mon-Servicer -Servicio dns
       
        if (Get-Command Monitor-Servicios -ErrorAction SilentlyContinue) { Monitor-Servicios }
        
        Write-Host "=== GESTION DNS (INTEGRADO EN AD) ===" -ForegroundColor Yellow
        Write-Host "1) ALTA (Directa e Inversa)"
        Write-Host "2) BAJA (Remocion de Zonas)"
        Write-Host "3) CONSULTA DE REGISTROS"
        Write-Host "4) Volver"
        $op = Read-Host "Opcion"

        switch ($op) {
            "1" {
                $zona = Read-Host "Nombre del Dominio (ej: ayala.local)"
                # Detectar IP si no hay interfaz activa global
                $ip_actual = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }).IPAddress[0]
                $ip = Read-Host "IP del Servidor (Enter para $ip_actual)"
                if (-not $ip) { $ip = $ip_actual }

                # --- ZONA DIRECTA ---
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ReplicationScope Forest
                    Write-Host "[+] Zona Directa '$zona' creada." -ForegroundColor Green
                }
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                
                # --- ZONA INVERSA ---
                $oct = $ip.Split('.')
                $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $inv -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $inv -ReplicationScope Forest
                    Write-Host "[+] Zona Inversa '$inv' creada." -ForegroundColor Green
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $inv -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                
                Write-Host "[OK] Proceso finalizado." -ForegroundColor Cyan; Pause
            }

            "2" {
                $zona = Read-Host "Dominio a borrar"
                if ($zona) {
                    Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                    Write-Host "[!] Zona $zona eliminada." -ForegroundColor Yellow
                }
                Pause
            }

            "3" {
                Get-DnsServerZone | Where-Object { $_.ZoneName -notlike "TrustAnchors*" } | ForEach-Object {
                    Write-Host "`n>> $($_.ZoneName)" -ForegroundColor Magenta
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName | Format-Table HostName, RecordType, RecordData -AutoSize
                }
                Pause
            }
        }
    } while ($op -ne "4")
}