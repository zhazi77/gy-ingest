param(
  [string]$BaseUrl = "https://771to8vw3580.vicp.fun"
)

$ErrorActionPreference = "Stop"

function Backup-IfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupPath = "$Path.bak-$stamp"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
  }
  return $null
}

function Set-TomlValue {
  param(
    [string[]]$Lines,
    [AllowNull()][string]$Section,
    [string]$Key,
    [string]$Value
  )

  $isTopLevel = [string]::IsNullOrEmpty($Section)
  $sectionHeader = if ($isTopLevel) { $null } else { "[$Section]" }
  $currentSection = $null
  $sectionFound = $isTopLevel
  $keySet = $false
  $out = New-Object System.Collections.Generic.List[string]

  for ($i = 0; $i -lt $Lines.Count; $i++) {
    $line = $Lines[$i]
    $trimmed = $line.Trim()
    $isHeader = $trimmed -match '^\[[^\]]+\]$'

    if ($isHeader) {
      $leavingTargetSection = if ($isTopLevel) { $null -eq $currentSection } else { $currentSection -eq $Section }
      if ($sectionFound -and -not $keySet -and $leavingTargetSection) {
        $out.Add("$Key = $Value")
        $keySet = $true
      }
      $currentSection = $trimmed.Trim('[', ']')
      if (-not $isTopLevel -and $currentSection -eq $Section) {
        $sectionFound = $true
      }
      $out.Add($line)
      continue
    }

    $inTargetSection = if ($isTopLevel) { $null -eq $currentSection } else { $currentSection -eq $Section }
    if ($inTargetSection -and $trimmed -match "^\s*$([regex]::Escape($Key))\s*=") {
      if (-not $keySet) {
        $out.Add("$Key = $Value")
        $keySet = $true
      }
      continue
    }

    $out.Add($line)
  }

  if (-not $sectionFound -and -not $isTopLevel) {
    if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -ne "") {
      $out.Add("")
    }
    $out.Add($sectionHeader)
    $out.Add("$Key = $Value")
    $keySet = $true
  } elseif (-not $keySet) {
    $out.Add("$Key = $Value")
  }

  return $out.ToArray()
}

function Set-CodexApiKeyAuth {
  param(
    [string]$Path,
    [string]$ApiKey
  )

  if (Test-Path -LiteralPath $Path) {
    try {
      $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    } catch {
      $json = [pscustomobject]@{}
    }
  } else {
    $json = [pscustomobject]@{}
  }

  $json.PSObject.Properties.Remove("tokens")
  $json.PSObject.Properties.Remove("last_refresh")
  $json | Add-Member -NotePropertyName "auth_mode" -NotePropertyValue "api_key" -Force
  $json | Add-Member -NotePropertyName "OPENAI_API_KEY" -NotePropertyValue $ApiKey -Force
  $jsonText = ($json | ConvertTo-Json -Depth 20) + "`n"
  [System.IO.File]::WriteAllText($Path, $jsonText, [System.Text.UTF8Encoding]::new($false))
}

function Read-ExistingAuth {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  try {
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Confirm-AuthSwitch {
  param([AllowNull()]$ExistingAuth)

  $hasChatGptAuth = $false
  if ($null -ne $ExistingAuth) {
    $hasChatGptAuth = ($ExistingAuth.auth_mode -eq "chatgpt") -or ($null -ne $ExistingAuth.PSObject.Properties["tokens"])
  }

  if ($hasChatGptAuth) {
    Write-Host "Detected existing Codex ChatGPT login."
    Write-Host "Switching Codex auth mode to API key and removing cached ChatGPT tokens from auth.json."
    Write-Host "Restart Codex after this installer finishes so the new auth mode is loaded."
    if (-not $env:CODEX_SUB2API_CONFIRM) {
      $answer = Read-Host "Continue? [Y/n]"
      if ($answer -match '^(n|no)$') {
        Write-Host "Aborted. No files were changed."
        exit 4
      }
    }
  } else {
    Write-Host "No existing Codex ChatGPT login detected."
  }
}

function Escape-SingleQuotedPowerShell {
  param([string]$Value)
  return $Value.Replace("'", "''")
}

function Write-RestoreScript {
  param(
    [string]$Path,
    [AllowNull()][string]$ConfigBackup,
    [AllowNull()][string]$AuthBackup,
    [string]$ConfigPath,
    [string]$AuthPath
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('$ErrorActionPreference = "Stop"')
  $lines.Add('$restored = $false')
  if ($ConfigBackup) {
    $lines.Add("Copy-Item -LiteralPath '$(Escape-SingleQuotedPowerShell $ConfigBackup)' -Destination '$(Escape-SingleQuotedPowerShell $ConfigPath)' -Force")
    $lines.Add('$restored = $true')
  }
  if ($AuthBackup) {
    $lines.Add("Copy-Item -LiteralPath '$(Escape-SingleQuotedPowerShell $AuthBackup)' -Destination '$(Escape-SingleQuotedPowerShell $AuthPath)' -Force")
    $lines.Add('$restored = $true')
  }
  $lines.Add('if ($restored) {')
  $lines.Add('  Write-Host "Restored Codex config/auth from backup."')
  $lines.Add('  Write-Host "Restart Codex so the restored files are loaded."')
  $lines.Add('} else {')
  $lines.Add('  Write-Host "No backup files were available to restore."')
  $lines.Add('}')

  [System.IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Codex Sub2API installer"
Write-Host "Base URL: $BaseUrl"
if ($env:CODEX_SUB2API_KEY) {
  $apiKey = $env:CODEX_SUB2API_KEY
} else {
  $secureApiKey = Read-Host "Paste API key" -AsSecureString
  $apiKeyBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
  try {
    $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($apiKeyBstr)
  } finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($apiKeyBstr)
  }
}
$apiKey = $apiKey.Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw "API key is empty."
}

$codexDir = Join-Path $env:USERPROFILE ".codex"
$configPath = Join-Path $codexDir "config.toml"
$authPath = Join-Path $codexDir "auth.json"
$restorePath = Join-Path $codexDir "restore-sub2api-backup.ps1"
New-Item -ItemType Directory -Path $codexDir -Force | Out-Null

$existingAuth = Read-ExistingAuth $authPath
Confirm-AuthSwitch $existingAuth

$configBackup = Backup-IfExists $configPath
$authBackup = Backup-IfExists $authPath
Write-RestoreScript $restorePath $configBackup $authBackup $configPath $authPath

$lines = if (Test-Path -LiteralPath $configPath) {
  @(Get-Content -LiteralPath $configPath)
} else {
  @()
}

$lines = Set-TomlValue -Lines $lines -Section $null -Key "model_provider" -Value '"OpenAI"'
$lines = Set-TomlValue -Lines $lines -Section $null -Key "model" -Value '"gpt-5.5"'
$lines = Set-TomlValue -Lines $lines -Section $null -Key "review_model" -Value '"gpt-5.5"'
$lines = Set-TomlValue -Lines $lines -Section $null -Key "model_reasoning_effort" -Value '"high"'
$lines = Set-TomlValue -Lines $lines -Section $null -Key "disable_response_storage" -Value "true"
$lines = Set-TomlValue -Lines $lines -Section $null -Key "network_access" -Value '"enabled"'
$lines = Set-TomlValue -Lines $lines -Section $null -Key "windows_wsl_setup_acknowledged" -Value "true"

$lines = Set-TomlValue -Lines $lines -Section "model_providers.OpenAI" -Key "name" -Value '"OpenAI"'
$lines = Set-TomlValue -Lines $lines -Section "model_providers.OpenAI" -Key "base_url" -Value "`"$BaseUrl`""
$lines = Set-TomlValue -Lines $lines -Section "model_providers.OpenAI" -Key "wire_api" -Value '"responses"'
$lines = Set-TomlValue -Lines $lines -Section "model_providers.OpenAI" -Key "requires_openai_auth" -Value "true"

$lines = Set-TomlValue -Lines $lines -Section "features" -Key "goals" -Value "false"

$configText = ($lines -join "`n").TrimEnd() + "`n"
[System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
Set-CodexApiKeyAuth $authPath $apiKey

Write-Host ""
Write-Host "Updated:"
Write-Host "  $configPath"
Write-Host "  $authPath"
Write-Host "Restore helper:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$restorePath`""
Write-Host "Backups were created for existing files."
Write-Host "Restart Codex to load the new config and API key auth mode."
Write-Host "Done."
