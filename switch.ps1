# Toggle Claude Code between Anthropic (default) and MiniMax API
# Usage: . .\switch.ps1
#
# API key resolution (first match wins):
#   1. $env:MINIMAX_API_KEY
#   2. <script-dir>\.minimax-key   (one line, just the key — gitignored)

$ProfilePath = $PROFILE
$MarkerStart = "# === Claude MiniMax Toggle ==="
$MarkerEnd = "# === End Claude MiniMax Toggle ==="

$MiniMaxBaseURL = "https://api.minimax.io/anthropic"

function Get-MiniMaxAPIKey {
    if ($env:MINIMAX_API_KEY) { return $env:MINIMAX_API_KEY.Trim() }
    $keyFile = Join-Path $PSScriptRoot ".minimax-key"
    if (Test-Path $keyFile) {
        $val = (Get-Content $keyFile -Raw).Trim()
        if ($val) { return $val }
    }
    Write-Host "MiniMax API key not found." -ForegroundColor Red
    Write-Host "Set it one of these ways, then re-run:" -ForegroundColor Yellow
    Write-Host "  - `$env:MINIMAX_API_KEY = 'sk-cp-...'" -ForegroundColor DarkGray
    Write-Host "  - or create $keyFile containing just the key" -ForegroundColor DarkGray
    return $null
}

function Remove-MiniMaxBlock {
    if (Test-Path $ProfilePath) {
        $lines = Get-Content $ProfilePath
        $newLines = @()
        $skipping = $false
        foreach ($line in $lines) {
            if ($line -eq $MarkerStart) { $skipping = $true; continue }
            if ($line -eq $MarkerEnd) { $skipping = $false; continue }
            if (-not $skipping) { $newLines += $line }
        }
        # Trim trailing blank lines left behind
        while ($newLines.Count -gt 0 -and $newLines[-1] -match '^\s*$') {
            $newLines = $newLines[0..($newLines.Count - 2)]
        }
        Set-Content $ProfilePath -Value $newLines
    }
}

function Add-MiniMaxBlock {
    param([string]$Key)
    $block = @"

$MarkerStart
`$env:ANTHROPIC_BASE_URL = "$MiniMaxBaseURL"
`$env:ANTHROPIC_API_KEY = "$Key"
$MarkerEnd
"@
    Add-Content $ProfilePath -Value $block
}

# Detect current state and toggle
if ($env:ANTHROPIC_BASE_URL -eq $MiniMaxBaseURL) {
    # Currently MiniMax -> switch to Anthropic
    Remove-Variable -Name ANTHROPIC_BASE_URL -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ANTHROPIC_API_KEY -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-MiniMaxBlock
    Write-Host "Switched to Anthropic (default OAuth)" -ForegroundColor Green
    Write-Host "  ANTHROPIC_BASE_URL: (unset)" -ForegroundColor DarkGray
    Write-Host "  ANTHROPIC_API_KEY:  (unset)" -ForegroundColor DarkGray
} else {
    # Currently Anthropic -> switch to MiniMax
    $MiniMaxAPIKey = Get-MiniMaxAPIKey
    if (-not $MiniMaxAPIKey) { return }
    $env:ANTHROPIC_BASE_URL = $MiniMaxBaseURL
    $env:ANTHROPIC_API_KEY = $MiniMaxAPIKey
    Remove-MiniMaxBlock
    Add-MiniMaxBlock -Key $MiniMaxAPIKey
    Write-Host "Switched to MiniMax" -ForegroundColor Cyan
    Write-Host "  ANTHROPIC_BASE_URL: $MiniMaxBaseURL" -ForegroundColor DarkGray
    $tail = if ($MiniMaxAPIKey.Length -ge 4) { $MiniMaxAPIKey.Substring($MiniMaxAPIKey.Length - 4) } else { $MiniMaxAPIKey }
    Write-Host "  ANTHROPIC_API_KEY:  sk-cp-...$tail" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "This applies to this session + all new PowerShell windows." -ForegroundColor Yellow
Write-Host "Restart Claude Code for the change to take effect." -ForegroundColor Yellow
