#requires -Version 7.0
<#
.SYNOPSIS
  Builds a portable gai-pi folder (engine + project) and zips it.

.DESCRIPTION
  Godot export templates are not required: the package ships the engine binary next to the
  project and launches it with --path, the same way the repository runs. pi and Node.js stay
  external on purpose — the app drives the user's own installation.

.EXAMPLE
  pwsh -File tools/package.ps1
  pwsh -File tools/package.ps1 -NoZip
#>
param(
    [string]$OutputRoot = "dist",
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$engineName = "Godot_v4.6.3-stable_win64.exe"
$engineSource = Join-Path $root ".dependency/godot/$engineName"
$target = Join-Path $root "$OutputRoot/gai-pi-portable"
$archive = Join-Path $root "$OutputRoot/gai-pi-portable.zip"

if (-not (Test-Path $engineSource)) {
    throw "Godot engine not found at $engineSource (see README, Environment)."
}

if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Path $target | Out-Null

# Project sources and the import cache, so first launch does not re-import fonts and shaders.
$files = @("project.godot", "icon.svg", "icon.svg.import", "gai-pi.cmd", "README.md", "ARCHITECTURE.md", "CREDITS.md")
foreach ($file in $files) {
    Copy-Item (Join-Path $root $file) $target
}
$directories = @("app", "zfoo", "docs", ".godot")
foreach ($directory in $directories) {
    $source = Join-Path $root $directory
    if (Test-Path $source) {
        Copy-Item $source $target -Recurse
    }
}

# Keep the repository layout so gai-pi.cmd works unchanged inside the package.
$engineTarget = Join-Path $target ".dependency/godot"
New-Item -ItemType Directory -Path $engineTarget | Out-Null
Copy-Item $engineSource $engineTarget

Write-Host "Portable folder: $target"

if (-not $NoZip) {
    if (Test-Path $archive) { Remove-Item $archive -Force }
    Compress-Archive -Path (Join-Path $target "*") -DestinationPath $archive -CompressionLevel Optimal
    $sizeMb = [math]::Round((Get-Item $archive).Length / 1MB, 1)
    Write-Host "Archive: $archive ($sizeMb MB)"
}
