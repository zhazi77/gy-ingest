param(
  [string]$BaseUrl = "https://771to8vw3580.vicp.fun"
)

$ErrorActionPreference = "Stop"

function Backup-IfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    Copy-Item -LiteralPath $Path -Destination "$Path.bak-$stamp" -Force
  }
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
New-Item -ItemType Directory -Path $codexDir -Force | Out-Null

Backup-IfExists $configPath
Backup-IfExists $authPath

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
Write-Host "Backups were created for existing files."
Write-Host "Done."
