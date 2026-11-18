#requires -Version 7.0
<#
.SYNOPSIS
  Exports the single-file Windows executable (PCK embedded).

.DESCRIPTION
  Requires the Godot 4.6.3 export templates. Install them once:
    $dir = Join-Path $env:APPDATA 'Godot/export_templates/4.6.3.stable'
    Expand-Archive .dependency/templates/templates.tpz .dependency/templates/unpack -Force
    Copy-Item .dependency/templates/unpack/templates/* $dir -Recurse -Force

  Then run this script. Output: dist/gai-pi.exe (PCK embedded, single file).
#>
param([string]$Preset = "Windows Desktop", [string]$Output = "dist/gai-pi.exe")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root ".dependency/godot/Godot_v4.6.3-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    throw "Godot console binary not found: $godot"
}
$templates = Join-Path $env:APPDATA "Godot/export_templates/4.6.3.stable"
if (-not (Test-Path $templates)) {
    throw "Export templates missing. Install them into $templates first (see the header of this script)."
}
New-Item -ItemType Directory -Path (Join-Path $root "dist") -Force | Out-Null
Push-Location $root
try {
    & $godot --headless --path . --export-release $Preset $Output
    Write-Host "Exported: $(Join-Path $root $Output)"
}
finally {
    Pop-Location
}
