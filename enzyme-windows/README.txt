Enzyme Clang plugin on Windows x64
==================================

This branch is based on LLVM tag llvmorg-19.1.7, commit
cd708029e0b2869e80abe31ddb175f7c35361f90 (also release/19.x at migration time).
The requested branch name is agent_19.1.17_for_enzyme; the LLVM version is 19.1.7.

The Clang driver exports 50 extra LLVM symbols for ClangEnzyme-19.dll, including
48 data symbols. The plugin imports the host's actual analysis keys, pass IDs,
options and optimization levels. LLVM parser/code generation algorithms are
unchanged. Both host and plugin use /MD and assertions.

LAYOUT
  llvm-project/                  This Git repository, next to Enzyme/.
    enzyme-windows/              Tracked integration scripts, examples and patch.
    build-enzyme19/              Ignored generated output.
      llvm/bin/clang.exe         Paired plugin-enabled Clang 19.1.7.
      llvm/lib/clang/19/include/  Compiler resource headers.
      enzyme/Enzyme/ClangEnzyme-19.dll
      llvm-import-include/       Generated plugin-only LLVM header overlay.
      validation/                Executables, gameplay DLL, results and manifest.

BUILD (PowerShell, in llvm-project)
  & .\enzyme-windows\build.ps1
  & .\enzyme-windows\validate.ps1
  & ..\warp_newton_env\python.exe .\enzyme-windows\record_build.py

  Enzyme is a sibling Git checkout from https://github.com/cqiao-agent/Enzyme.git,
  branch agent_windows_clang19, tested commit
  7b72c29b7c28d113c20c216ddb13592ce5c761fc. Its Windows changes are committed there.
  The upstream base cdfaa22a4c3ceee3c19ba7c213ed039a278fe255 is also accepted:
  build.ps1 checks and applies windows-clang-plugin.patch when necessary.
  Conflicting local changes fail the build instead of being overwritten.
  This tracked patch reproduces all changes from the upstream base to the tested
  fork commit, including the scoped .gitattributes LF rules.

  Toolchain used: VS 2022 Community, MSVC 14.29, SDK 10.0.19041.0,
  Clang-cl 19.1.5 bootstrap, bundled CMake/Ninja, Python 3.12.
  Python defaults to the sibling warp_newton_env/python.exe if present, then
  python.exe on PATH. Git must be on PATH.
  Parameters: -Jobs (default 24), -Reconfigure, -PluginOnly, -ConfigureOnly,
  -BuildRoot, -EnzymeSource, -VsInstallPath, -Python.
  Validation accepts the same path/toolchain parameters.

  This is a focused Clang/plugin build with the X86 backend; it does not build
  every LLVM library/tool. Optional DIA support is disabled because the tested
  MSVC toolset lacks ATL. No WSL, MinGW or global installation is required.

USE (after initializing the VS environment, e.g. by running validate.ps1)
  $clang = "$PWD\build-enzyme19\llvm\bin\clang.exe"
  $plugin = "$PWD\build-enzyme19\enzyme\Enzyme\ClangEnzyme-19.dll"
  & $clang -std=c++17 -O2 "-fplugin=$plugin" .\enzyme-windows\plugin_smoke.cpp `
      -o .\build-enzyme19\validation\example.exe
  & .\build-enzyme19\validation\example.exe

  Use this paired clang.exe, keeping that filename and its resource headers.
  The DLL imports clang.exe and cannot use ordinary VS/official prebuilt Clang
  as a substitute. The plugin supplies <enzyme/enzyme> and registers AD passes;
  no separate -I or -fpass-plugin is needed. The resulting gameplay.dll has no
  dependency on Clang or Enzyme at runtime.

WINDOWS COMPATIBILITY
  prepare_windows_imports.py creates an import-header overlay from the tracked
  LLVM headers. It does not rewrite the host LLVM headers or the source tree.
  The Enzyme patch preserves MSVC access-level name mangling, uses Clang's
  -fno-access-control, bundles headers with CMake, fixes Windows virtual header
  paths, gives activity markers C linkage and qualifies llvm::ConstantExpr.
  The affected source/build inputs use text eol=lf in Enzyme's .gitattributes;
  this overrides core.autocrlf for those files without changing global settings.

VALIDATION
  validate.ps1 runs 77 numerical checks and verifies the differentiated IR:
  - C++ forward/reverse differentiation at -O0 and -O2 (8 checks each), including
    virtual headers and frontend version macros.
  - Native C consumer of a plugin-built gameplay DLL (61 checks), including
    mutable state, branches, runtime loops, finite differences and a gradient
    step which lowers the objective.
  - No remaining calls to __enzyme_autodiff / __enzyme_fwddiff in output IR.
  Reference results are in validation-reference.json. Live results and artifact
  hashes are generated under build-enzyme19/validation.
  These checks cover native CPU integration, not the complete upstream suite.
  GPU/CUDA, MLIR and other compiler versions are untested. Hard gameplay event
  boundaries remain nonsmooth; derivatives follow the executed path.

GIT CHECKOUT
  The local checkout was made shallow at the exact tag and uses sparse checkout
  for llvm/, clang/, cmake/, third-party/ and enzyme-windows/. Official source
  archives already on the machine were reused as matching Git blob objects to
  avoid re-downloading them over a slow connection. Git's authoritative trees
  determine the checkout; reused content was checked against those blob hashes.
  Use git sparse-checkout disable to obtain other projects, or git fetch
  --unshallow origin to retrieve older history, when needed.
