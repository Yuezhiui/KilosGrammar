# Convenience name for the same audited, offline-only Windows build pipeline.
[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$PythonExe = '',
    [switch]$PreflightOnly
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build-OfflineRelease.ps1') -GodotExe $GodotExe -PythonExe $PythonExe -PreflightOnly:$PreflightOnly
