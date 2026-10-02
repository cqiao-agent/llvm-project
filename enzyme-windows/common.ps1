param([string]$BuildRoot = '', [string]$EnzymeSource = '',
      [string]$VsInstallPath = '', [string]$Python = '')

$llvmSource = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workspace = Split-Path -Parent $llvmSource
if (-not $BuildRoot) { $BuildRoot = Join-Path $llvmSource 'build-enzyme19' }
if (-not $EnzymeSource) { $EnzymeSource = Join-Path $workspace 'Enzyme' }
if (-not $VsInstallPath) { $VsInstallPath = 'C:\Program Files\Microsoft Visual Studio\2022\Community' }
if (-not $Python) {
    $Python = Join-Path $workspace 'warp_newton_env\python.exe'
    if (-not (Test-Path -LiteralPath $Python)) { $Python = (Get-Command python.exe -ErrorAction Stop).Source }
}
$buildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
$enzymeSource = [System.IO.Path]::GetFullPath($EnzymeSource)
$vsRoot = $VsInstallPath
$python = $Python
$git = (Get-Command git.exe -ErrorAction Stop).Source
$llvmBuild = Join-Path $buildRoot 'llvm'
$pluginBuild = Join-Path $buildRoot 'enzyme'
$importHeaders = Join-Path $buildRoot 'llvm-import-include'
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

function Initialize-EnzymeToolchain {
    Import-Module (Join-Path $vsRoot 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vsRoot -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64 -vcvars_ver=14.29 -winsdk=10.0.19041.0'
    $script:cmake = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    $ninjaBin = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
    $script:bootstrapBin = Join-Path $vsRoot 'VC\Tools\Llvm\x64\bin'
    $env:PATH = "$(Split-Path -Parent $cmake);$ninjaBin;$bootstrapBin;$env:PATH"
}
