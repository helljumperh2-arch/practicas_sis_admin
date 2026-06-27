# ==============================================================================
# P09 - GPO LOGOFF (VERSIÓN FINAL - sin cambios, ya funcionaba)
# ==============================================================================

Import-Module ActiveDirectory
Import-Module GroupPolicy

$Dominio  = "ayala.local"
$DomainDN = "DC=ayala,DC=local"

function Crear-GPO-Logoff {
    param([string]$NombreGPO, [string]$OU)

    $gpo = Get-GPO -Name $NombreGPO -ErrorAction SilentlyContinue
    if (!$gpo) {
        $gpo = New-GPO -Name $NombreGPO -Domain $Dominio
        Write-Host "[OK] GPO creada: $NombreGPO" -ForegroundColor Green
    } else {
        Write-Host "[*] GPO ya existe: $NombreGPO" -ForegroundColor Yellow
    }

    Set-GPRegistryValue `
        -Name $NombreGPO `
        -Key "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters" `
        -ValueName "EnableForcedLogOff" `
        -Type DWord -Value 1

    $ouPath = "OU=$OU,$DomainDN"
    $links  = (Get-GPInheritance -Target $ouPath).GpoLinks |
              Where-Object { $_.DisplayName -eq $NombreGPO }
    if (!$links) {
        New-GPLink -Name $NombreGPO -Target $ouPath -LinkEnabled Yes
        Write-Host "[OK] GPO vinculada a: $ouPath" -ForegroundColor Green
    } else {
        Write-Host "[*] GPO ya vinculada a: $ouPath" -ForegroundColor Yellow
    }

    Invoke-GPUpdate -Force -ErrorAction SilentlyContinue
}

Write-Host "=== P09 GPO LOGOFF ===" -ForegroundColor Cyan
Crear-GPO-Logoff -NombreGPO "GPO-Logoff-Cuates"   -OU "Cuates"
Crear-GPO-Logoff -NombreGPO "GPO-Logoff-NoCuates" -OU "NoCuates"

# Aplicar secedit globalmente
$infContent = @"
[Unicode]
Unicode=yes
[System Access]
ForceLogoffWhenHourExpire = 1
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

$infPath = "$env:TEMP\force_logoff.inf"
$dbPath  = "$env:TEMP\force_logoff.sdb"
Set-Content $infPath $infContent -Encoding Unicode
secedit /configure /db $dbPath /cfg $infPath /areas SECURITYPOLICY /quiet
Remove-Item $infPath, $dbPath -Force -ErrorAction SilentlyContinue

Write-Host "[OK] GPOs de Logoff configuradas." -ForegroundColor Green
Pause