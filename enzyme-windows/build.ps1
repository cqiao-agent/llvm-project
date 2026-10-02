param([int]$Jobs = 24, [switch]$Reconfigure, [switch]$ConfigureOnly,
      [switch]$PluginOnly, [string]$BuildRoot = '', [string]$EnzymeSource = '',
      [string]$VsInstallPath = '', [string]$Python = '')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1') -BuildRoot $BuildRoot -EnzymeSource $EnzymeSource -VsInstallPath $VsInstallPath -Python $Python
Initialize-EnzymeToolchain
$baseCommit = & $git -c "safe.directory=$($llvmSource.Replace('\','/'))" -C $llvmSource rev-parse 'llvmorg-19.1.7^{commit}'
if ($LASTEXITCODE -ne 0 -or $baseCommit -ne 'cd708029e0b2869e80abe31ddb175f7c35361f90') {
    throw 'The official llvmorg-19.1.7 tag is required in this checkout.'
}
$enzymeCommit = & $git -c "safe.directory=$($enzymeSource.Replace('\','/'))" -C $enzymeSource rev-parse HEAD
$enzymeBaseCommit = 'cdfaa22a4c3ceee3c19ba7c213ed039a278fe255'
$enzymeForkCommit = '7b72c29b7c28d113c20c216ddb13592ce5c761fc'
if ($LASTEXITCODE -ne 0 -or $enzymeCommit -notin @($enzymeBaseCommit, $enzymeForkCommit)) {
    throw "Enzyme must use the tested fork commit $enzymeForkCommit or upstream base $enzymeBaseCommit with the compatibility patch."
}
$patch = Join-Path $PSScriptRoot 'windows-clang-plugin.patch'
& $git -c "safe.directory=$($enzymeSource.Replace('\','/'))" -c core.autocrlf=true -c core.safecrlf=false -C $enzymeSource apply --reverse --check $patch 2>$null
if ($LASTEXITCODE -ne 0) {
    & $git -c "safe.directory=$($enzymeSource.Replace('\','/'))" -c core.autocrlf=true -c core.safecrlf=false -C $enzymeSource apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Enzyme changes conflict with the required compatibility patch.' }
    & $git -c "safe.directory=$($enzymeSource.Replace('\','/'))" -c core.autocrlf=true -c core.safecrlf=false -C $enzymeSource apply $patch
    if ($LASTEXITCODE -ne 0) { throw 'Applying the Enzyme compatibility patch failed.' }
}
& $python (Join-Path $PSScriptRoot 'prepare_windows_imports.py') --output $importHeaders
if ($LASTEXITCODE -ne 0) { throw 'Preparing LLVM DLL import headers failed.' }

if (-not $PluginOnly) {
    if ($Reconfigure -or -not (Test-Path -LiteralPath (Join-Path $llvmBuild 'CMakeCache.txt'))) {
        $llvmArgs = @(
            '-S', (Join-Path $llvmSource 'llvm'), '-B', $llvmBuild, '-G', 'Ninja',
            "-DCMAKE_C_COMPILER=$($bootstrapBin.Replace('\','/'))/clang-cl.exe",
            "-DCMAKE_CXX_COMPILER=$($bootstrapBin.Replace('\','/'))/clang-cl.exe",
            '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL',
            '-DLLVM_USE_LINKER=lld',
            '-DLLVM_ENABLE_PROJECTS=clang', '-DLLVM_TARGETS_TO_BUILD=X86',
            '-DLLVM_ENABLE_PLUGINS=ON', '-DLLVM_EXPORT_SYMBOLS_FOR_PLUGINS=ON',
            '-DCLANG_PLUGIN_SUPPORT=ON', '-DLLVM_ENABLE_ASSERTIONS=ON',
            '-DLLVM_ENABLE_RTTI=OFF', '-DLLVM_ENABLE_EH=OFF',
            '-DLLVM_INCLUDE_TESTS=OFF', '-DLLVM_INCLUDE_EXAMPLES=OFF',
            '-DLLVM_INCLUDE_BENCHMARKS=OFF', '-DLLVM_ENABLE_ZLIB=OFF',
            '-DLLVM_ENABLE_ZSTD=OFF', '-DLLVM_ENABLE_LIBXML2=OFF',
            '-DLLVM_ENABLE_LIBEDIT=OFF',
            '-DLLVM_ENABLE_DIA_SDK=OFF',
            "-DCLANG_ENZYME_EXTRA_EXPORTS=$($PSScriptRoot.Replace('\','/'))/clang-extra-exports.txt",
            '-DCLANG_ENABLE_STATIC_ANALYZER=OFF', '-DCLANG_ENABLE_ARCMT=OFF',
            '-DLLVM_PARALLEL_LINK_JOBS=2', '-DLLVM_BUILD_LLVM_DYLIB=OFF',
            '-DLLVM_LINK_LLVM_DYLIB=OFF',
            "-DPython3_EXECUTABLE=$($python.Replace('\','/'))"
        )
        & $cmake @llvmArgs 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot 'llvm19-configure.log')
        if ($LASTEXITCODE -ne 0) { throw "LLVM configuration failed: $LASTEXITCODE" }
    }
    if ($ConfigureOnly) { return }
    & $cmake --build $llvmBuild --target clang opt llvm-config llvm-nm llvm-readobj FileCheck clang-resource-headers --parallel $Jobs 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot 'llvm19-build.log')
    if ($LASTEXITCODE -ne 0) { throw "LLVM build failed: $LASTEXITCODE" }
}

if ($Reconfigure -or -not (Test-Path -LiteralPath (Join-Path $pluginBuild 'CMakeCache.txt'))) {
    $enzymeArgs = @(
        '-S', (Join-Path $enzymeSource 'enzyme'), '-B', $pluginBuild, '-G', 'Ninja',
        "-DLLVM_DIR=$($llvmBuild.Replace('\','/'))/lib/cmake/llvm",
        "-DClang_DIR=$($llvmBuild.Replace('\','/'))/lib/cmake/clang",
        "-DENZYME_WINDOWS_LLVM_INCLUDE_DIR=$($importHeaders.Replace('\','/'))",
        "-DCMAKE_C_COMPILER=$($bootstrapBin.Replace('\','/'))/clang-cl.exe",
        "-DCMAKE_CXX_COMPILER=$($bootstrapBin.Replace('\','/'))/clang-cl.exe",
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL',
        '-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2', '-DCMAKE_C_FLAGS_RELEASE=/O2 /Ob2',
        '-DENZYME_CONFIGURED_WITH_PRESETS=ON', '-DCMAKE_POLICY_DEFAULT_CMP0116=NEW',
        '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW',
        '-DENZYME_ENABLE_PLUGINS=ON',
        '-DENZYME_CLANG=ON', '-DENZYME_BC_LOADER=OFF', '-DENZYME_MLIR=OFF',
        '-DENZYME_EXTERNAL_SHARED_LIB=OFF', '-DENZYME_STATIC_LIB=OFF',
        "-DLLVM_EXTERNAL_LIT=$($llvmSource.Replace('\','/'))/llvm/utils/lit/lit.py",
        "-DPython3_EXECUTABLE=$($python.Replace('\','/'))"
    )
    & $cmake @enzymeArgs 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot 'clang-plugin-configure.log')
    if ($LASTEXITCODE -ne 0) { throw "Clang plugin configuration failed: $LASTEXITCODE" }
}
if ($ConfigureOnly) { return }
& $cmake --build $pluginBuild --target ClangEnzyme-19 --parallel $Jobs 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot 'clang-plugin-build.log')
if ($LASTEXITCODE -ne 0) { throw "Clang plugin build failed: $LASTEXITCODE" }
