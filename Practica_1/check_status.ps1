Clear-Host
Write-Host "--------------------" -ForegroundColor Cyan
Write-Host " "

$hostName = hostname
Write-Host "Nombre del equipo: `t$hostName"

$ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet*' | Where-Object { $_.IPAddress -notlike "169*" }).IPAddress
Write-Host "Direcciones IP: `t$ip"

Write-Host "--------------------"
Write-Host "Espacio en disco: " 

Get-Volume -DriveLetter C | Select-Object @{Name="Drive";Expression={$_.DriveLetter}}, 
    @{Name="Size(GB)";Expression={[math]::Round($_.Size / 1GB,2)}}, 
    @{Name="Free(GB)";Expression={[math]::Round($_.SizeRemaining / 1GB,2)}},
    @{Name="Type";Expression={$_.FileSystemType}} | Format-Table