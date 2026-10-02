param([string]$BuildRoot = '', [string]$EnzymeSource = '',
      [string]$VsInstallPath = '', [string]$Python = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1') -BuildRoot $BuildRoot -EnzymeSource $EnzymeSource -VsInstallPath $VsInstallPath -Python $Python
Initialize-EnzymeToolchain
$clang = Join-Path $llvmBuild 'bin\clang.exe'
$plugin = Join-Path $pluginBuild 'Enzyme\ClangEnzyme-19.dll'
$outputRoot = Join-Path $buildRoot 'validation'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$results = [ordered]@{}

foreach ($level in @('O0', 'O2')) {
    $executable = Join-Path $outputRoot "cpp-$level.exe"
    & $clang '-std=c++17' "-$level" "-fplugin=$plugin" (Join-Path $PSScriptRoot 'plugin_smoke.cpp') -o $executable
    if ($LASTEXITCODE -ne 0) { throw "C++ plugin compilation failed at $level." }
    $result = & $executable
    if ($LASTEXITCODE -ne 0) { throw "C++ gradient check failed at $level." }
    $results["cpp_$level"] = $result | ConvertFrom-Json
}

$dll = Join-Path $outputRoot 'gameplay.dll'
$importLib = Join-Path $outputRoot 'gameplay.lib'
$validator = Join-Path $outputRoot 'validate.exe'
& $clang -O2 "-fplugin=$plugin" -shared (Join-Path $PSScriptRoot 'gameplay.c') -o $dll "-Wl,/implib:$importLib"
if ($LASTEXITCODE -ne 0) { throw 'Building gameplay DLL through the Clang plugin failed.' }
& $clang -O2 (Join-Path $PSScriptRoot 'validate.c') $importLib -o $validator
if ($LASTEXITCODE -ne 0) { throw 'Building gameplay DLL consumer failed.' }
$result = & $validator
if ($LASTEXITCODE -ne 0) { throw 'Gameplay DLL validation failed.' }
$results.gameplay = $result | ConvertFrom-Json

$outputIR = Join-Path $outputRoot 'gameplay.grad.ll'
& $clang -O2 "-fplugin=$plugin" -S -emit-llvm (Join-Path $PSScriptRoot 'gameplay.c') -o $outputIR
if ($LASTEXITCODE -ne 0) { throw 'Generating differentiated IR through the Clang plugin failed.' }
if (Select-String -LiteralPath $outputIR -Pattern '(call|invoke).*@__enzyme_(auto|fwd)diff' -Quiet) {
    throw 'Untransformed Enzyme differentiation calls remain in the output IR.'
}
$results.ir_has_no_remaining_autodiff_calls = $true
$results | ConvertTo-Json -Depth 5 | Tee-Object -FilePath (Join-Path $outputRoot 'results.json')
