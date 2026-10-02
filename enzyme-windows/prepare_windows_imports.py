"""LLVM 19.1.7 header overlay for data imported from the paired clang.exe.

Only the Enzyme build uses these headers. Host LLVM headers and libraries keep
their original ABI. The corresponding data exports are in clang-extra-exports.txt.
"""
from pathlib import Path
import re

import argparse
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'llvm/include/llvm'
OUTPUT = (args.output or ROOT.parent / 'build-enzyme19/llvm-import-include') / 'llvm'
IMPORT = '__declspec(dllimport) '

analysis_headers = [
    "Analysis/AliasAnalysis.h", "Analysis/AssumptionCache.h",
    "Analysis/BasicAliasAnalysis.h", "Analysis/CallGraph.h",
    "Analysis/GlobalsModRef.h", "Analysis/LoopInfo.h",
    "Analysis/PhiValues.h", "Analysis/PostDominators.h",
    "Analysis/ScalarEvolution.h", "Analysis/ScopedNoAliasAA.h",
    "Analysis/TargetLibraryInfo.h", "Analysis/TypeBasedAliasAnalysis.h",
    "IR/Dominators.h", "IR/PassManager.h",
]
rules = {name: [(r"static AnalysisKey Key;", "static " + IMPORT + "AnalysisKey Key;")]
         for name in analysis_headers}
rules["IR/PassManager.h"].append((
    r"template <typename AnalysisManagerT, typename IRUnitT, typename\.\.\. ExtraArgTs>\nAnalysisKey\n    (?:Inner|Outer)AnalysisManagerProxy<AnalysisManagerT, IRUnitT, ExtraArgTs\.\.\.>::Key;",
    "// Analysis keys are imported from the paired clang.exe."))
for name in ["Analysis/AliasAnalysis.h", "Analysis/LoopInfo.h",
             "Analysis/TargetLibraryInfo.h", "IR/Dominators.h"]:
    rules[name].append((r"static char ID;", "static " + IMPORT + "char ID;"))
rules["Analysis/TargetLibraryInfo.h"].append((
    r"static StringLiteral const StandardNames\[NumLibFuncs\];",
    "static " + IMPORT + "StringLiteral const StandardNames[NumLibFuncs];"))
rules["IR/Analysis.h"] = [
    (r"static AnalysisSetKey AllAnalysesKey;", "static " + IMPORT + "AnalysisSetKey AllAnalysesKey;"),
    (r"(class CFGAnalyses \{[\s\S]*?)static AnalysisSetKey SetKey;",
     r"\1static " + IMPORT + "AnalysisSetKey SetKey;"),
]
rules["Passes/OptimizationLevel.h"] = [
    (r"static const OptimizationLevel (O[0123sz]);", "static " + IMPORT + r"const OptimizationLevel \1;")]
rules["Transforms/IPO/Attributor.h"] = [
    (r"static const char ID;", "static " + IMPORT + "const char ID;")]
rules["Transforms/Scalar/LICM.h"] = [
    (r"extern cl::opt<unsigned> (SetLicmMssa\w+);", "extern " + IMPORT + r"cl::opt<unsigned> \1;")]
rules["Support/Debug.h"] = [(r"extern bool DebugFlag;", "extern " + IMPORT + "bool DebugFlag;")]
# Enzyme's CMake also reads this header from the first LLVM include directory.
rules["Transforms/Utils/ScalarEvolutionExpander.h"] = []

for name, replacements in rules.items():
    contents = (SOURCE / name).read_text(encoding="utf-8")
    for pattern, replacement in replacements:
        contents, count = re.subn(pattern, replacement, contents)
        if not count:
            raise RuntimeError(f"LLVM header pattern changed: {name}: {pattern}")
    target = OUTPUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.read_text(encoding="utf-8") != contents:
        target.write_text(contents, encoding="utf-8")
print(f"Prepared {len(rules)} LLVM import headers in {OUTPUT.parent}")
