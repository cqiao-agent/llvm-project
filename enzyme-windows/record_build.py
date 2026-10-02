"""Record the Git sources and outputs of a successfully validated native build."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-root', type=Path, default=REPO / 'build-enzyme19')
parser.add_argument('--enzyme-source', type=Path, default=REPO.parent / 'Enzyme')
args = parser.parse_args()
build = args.build_root.resolve()
enzyme = args.enzyme_source.resolve()
output = build / 'validation'
git = shutil.which('git')
if not git:
    raise RuntimeError('Git is required to record source provenance')

def git_output(repo, *arguments):
    return subprocess.check_output([git, '-c', f'safe.directory={repo.as_posix()}',
                                    '-C', str(repo), *arguments], text=True).strip()

results = json.loads((output / 'results.json').read_text(encoding='utf-8-sig'))
checks = sum(results[key]['checks'] for key in ('cpp_O0', 'cpp_O2', 'gameplay'))
if checks != 77 or any(results[key]['failures'] for key in ('cpp_O0', 'cpp_O2', 'gameplay')):
    raise RuntimeError('Expected 77 passing numerical checks')
if not results['ir_has_no_remaining_autodiff_calls']:
    raise RuntimeError('Untransformed autodiff requests remain')

paths = ['llvm/bin/clang.exe', 'llvm/lib/clang.lib', 'enzyme/Enzyme/ClangEnzyme-19.dll',
         'validation/gameplay.dll', 'validation/gameplay.lib', 'validation/validate.exe',
         'validation/cpp-O0.exe', 'validation/cpp-O2.exe']
artifacts = []
for name in paths:
    path = build / name
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    artifacts.append({'path': name, 'bytes': path.stat().st_size, 'sha256': digest})
inspection = subprocess.check_output([str(build / 'llvm/bin/llvm-readobj.exe'),
    '--file-headers', '--coff-imports', str(build / 'enzyme/Enzyme/ClangEnzyme-19.dll')], text=True)
dependencies = [line.strip()[6:] for line in inspection.splitlines() if line.strip().startswith('Name: ')]
if 'Format: COFF-x86-64' not in inspection or 'clang.exe' not in dependencies:
    raise RuntimeError('Unexpected plugin format or host dependency')
(output / 'plugin-pe.txt').write_text(inspection, encoding='utf-8')
manifest = {
    'verified_at_utc': datetime.now(timezone.utc).isoformat(),
    'platform': 'Native Windows x64, MSVC ABI, CPU',
    'llvm_repository': git_output(REPO, 'remote', 'get-url', 'origin'),
    'llvm_source_directory': str(REPO), 'llvm_commit': git_output(REPO, 'rev-parse', 'HEAD'),
    'llvm_branch': git_output(REPO, 'branch', '--show-current'),
    'llvm_base_tag': 'llvmorg-19.1.7',
    'llvm_base_commit': git_output(REPO, 'rev-parse', 'llvmorg-19.1.7^{commit}'),
    'llvm_worktree_dirty': bool(git_output(REPO, 'status', '--porcelain')),
    'enzyme_source_directory': str(enzyme),
    'enzyme_commit': git_output(enzyme, 'rev-parse', 'HEAD'),
    'enzyme_patch': 'enzyme-windows/windows-clang-plugin.patch',
    'enzyme_patch_sha256': hashlib.sha256((ROOT / 'windows-clang-plugin.patch').read_bytes()).hexdigest(),
    'llvm_version': '19.1.7', 'bootstrap_compiler': 'VS Clang-cl 19.1.5',
    'msvc_toolset': '14.29', 'windows_sdk': '10.0.19041.0',
    'build_type': 'Release', 'assertions': True, 'rtti': False, 'runtime': '/MD',
    'target_backends': ['X86'], 'requires_paired_clang_exe': True,
    'plugin_dependencies': dependencies, 'checks_passed': checks, 'validation': results,
    'full_upstream_suite_run': False, 'gpu_tested': False, 'artifacts': artifacts,
}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(f'Recorded {checks} passing checks, Git source revisions and artifact hashes in {output}')
