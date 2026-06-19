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
  $shouldContinue = $true
  if ($null -ne $ExistingAuth) {
    $hasChatGptAuth = ($ExistingAuth.auth_mode -eq "chatgpt") -or ($null -ne $ExistingAuth.PSObject.Properties["tokens"])
  }

  if ($hasChatGptAuth) {
    Write-Host "检测到 Codex 已经登录过 ChatGPT 账号。"
    Write-Host "将把 Codex 切换为 API key 模式，并从 auth.json 中移除旧的 ChatGPT 登录缓存。"
    Write-Host "安装完成后，请完全退出并重新打开 Codex，让新的认证配置生效。"
    if (-not $env:CODEX_SUB2API_CONFIRM) {
      $answer = Read-Host "是否继续？直接回车表示继续，[n] 取消"
      if ($answer -match '^(n|no)$') {
        Write-Host "已取消，没有修改文件。"
        $shouldContinue = $false
      }
    }
  } else {
    Write-Host "未检测到已有的 Codex ChatGPT 登录态。"
  }
  $shouldContinue
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
  $lines.Add('  Write-Host "已从备份恢复 Codex 配置和认证文件。"')
  $lines.Add('  Write-Host "请完全退出并重新打开 Codex，让恢复后的配置生效。"')
  $lines.Add('} else {')
  $lines.Add('  Write-Host "没有可恢复的备份文件。"')
  $lines.Add('}')

  [System.IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Codex Sub2API 安装器"
Write-Host "Base URL: $BaseUrl"
if ($env:CODEX_SUB2API_KEY) {
  $apiKey = $env:CODEX_SUB2API_KEY
} else {
  $secureApiKey = Read-Host "请粘贴 API key（输入时不会显示）" -AsSecureString
  $apiKeyBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
  try {
    $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($apiKeyBstr)
  } finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($apiKeyBstr)
  }
}
$apiKey = $apiKey.Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw "API key 为空。"
}

$codexDir = Join-Path $env:USERPROFILE ".codex"
$configPath = Join-Path $codexDir "config.toml"
$authPath = Join-Path $codexDir "auth.json"
$restorePath = Join-Path $codexDir "restore-sub2api-backup.ps1"
New-Item -ItemType Directory -Path $codexDir -Force | Out-Null

$existingAuth = Read-ExistingAuth $authPath
$continueInstall = Confirm-AuthSwitch $existingAuth

if ($continueInstall) {
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
  Write-Host "已更新："
  Write-Host "  $configPath"
  Write-Host "  $authPath"
  Write-Host "如需恢复到安装前的配置，请运行："
  Write-Host "  powershell -ExecutionPolicy Bypass -File `"$restorePath`""
  Write-Host "已为现有配置文件创建备份。"
  Write-Host "请完全退出并重新打开 Codex，让新的配置和 API key 认证模式生效。"
  Write-Host "完成。"
}
