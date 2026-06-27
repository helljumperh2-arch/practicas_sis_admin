# ==============================================================================
# P09 - AppLocker por HASH (VERSIÓN FINAL FUNCIONAL)
# Usa Set-AppLockerPolicy -Ldap que registra el CSE correctamente
# ==============================================================================

Import-Module GroupPolicy
Import-Module ActiveDirectory

$Dominio  = "ayala.local"
$DomainDN = "DC=ayala,DC=local"
$GpoName  = "AppLocker-FINAL-P08"

$sidNoCuates = (Get-ADGroup "NoCuates").SID.Value
$sidAdmin    = "S-1-5-32-544"
$sidEveryone = "S-1-1-0"

Write-Host "[*] SID NoCuates: $sidNoCuates" -ForegroundColor Cyan

# --- Crear GPO si no existe ---
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (!$gpo) {
    $gpo = New-GPO -Name $GpoName -Domain $Dominio
    Write-Host "[OK] GPO creada: $GpoName" -ForegroundColor Green
} else {
    Write-Host "[*] GPO ya existe: $GpoName" -ForegroundColor Yellow
}

# --- Vincular a OUs ---
foreach ($ou in @("Cuates","NoCuates")) {
    $ouPath = "OU=$ou,$DomainDN"
    $links  = (Get-GPInheritance -Target $ouPath).GpoLinks |
              Where-Object { $_.DisplayName -eq $GpoName }
    if (!$links) {
        New-GPLink -Name $GpoName -Target $ouPath -LinkEnabled Yes
        Write-Host "[OK] GPO vinculada a: $ouPath" -ForegroundColor Green
    } else {
        Write-Host "[*] Ya vinculada a: $ouPath" -ForegroundColor Yellow
    }
}

# --- AppIDSvc automático via GPO ---
Set-GPRegistryValue -Name $GpoName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\AppIDSvc" `
    -ValueName "Start" -Type DWord -Value 2

# --- XML con hash correcto del cliente ---
$gpoGuid = $gpo.Id.ToString()

$xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="$(([Guid]::NewGuid()).ToString())" Name="Permitir Administradores" Description="Admins pueden ejecutar todo" Action="Allow" UserOrGroupSid="$sidAdmin">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="$(([Guid]::NewGuid()).ToString())" Name="Permitir Windows" Description="Ejecutables del sistema" Action="Allow" UserOrGroupSid="$sidEveryone">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="$(([Guid]::NewGuid()).ToString())" Name="Permitir Program Files" Description="Ejecutables instalados" Action="Allow" UserOrGroupSid="$sidEveryone">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>
    <FileHashRule Id="$(([Guid]::NewGuid()).ToString())" Name="Bloquear Notepad NoCuates" Description="Bloquea notepad por hash aunque cambien nombre" Action="Deny" UserOrGroupSid="$sidNoCuates">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x0C386FA6ABFDEFFBBEFF5BCE97D461340A23D1981458607BD9E5EEFF4066789A" SourceFileName="notepad.exe" SourceFileLength="201216" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
  <RuleCollection Type="Script" EnforcementMode="NotConfigured" />
  <RuleCollection Type="Msi"    EnforcementMode="NotConfigured" />
  <RuleCollection Type="Appx"   EnforcementMode="NotConfigured" />
</AppLockerPolicy>
"@

# --- Aplicar con Set-AppLockerPolicy (método oficial, registra CSE correctamente) ---
$tmpXml   = "$env:TEMP\applocker_p09.xml"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tmpXml, $xmlPolicy, $utf8NoBom)

Set-AppLockerPolicy -XmlPolicy $tmpXml `
    -Ldap "LDAP://CN={$gpoGuid},CN=Policies,CN=System,DC=ayala,DC=local"

Write-Host "[OK] AppLocker aplicado via Set-AppLockerPolicy" -ForegroundColor Green

gpupdate /force
Write-Host "[OK] gpupdate completado." -ForegroundColor Green
Write-Host "`n=== EN EL CLIENTE ejecuta ===" -ForegroundColor Yellow
Write-Host "  gpupdate /force" -ForegroundColor Cyan
Write-Host "  Reinicia el cliente" -ForegroundColor Cyan
Pause