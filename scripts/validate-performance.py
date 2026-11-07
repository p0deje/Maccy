#!/usr/bin/env python3
"""Run native tests/benchmarks in an isolated copy; requires Xcode and Python 3."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--case', choices=['preview', 'insertion'], required=True)
parser.add_argument('--output', type=Path, required=True, help='New directory for source, build, logs and results')
parser.add_argument('--baseline', help='Git revision to compare (same benchmark, original implementation)')
parser.add_argument('--packages', type=Path, help='Optional existing Xcode SourcePackages cache')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
src = out / 'source'
src.mkdir()
env = dict(os.environ)

def run(command, log, timeout=900):
    with (out / log).open('w') as stream:
        result = subprocess.run(command, cwd=src, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{command[0]} failed; see {out / log}')

# Archive the selected revision, then overlay only tracked working files for the candidate.
revision = args.baseline or 'HEAD'
archive = out / 'source.tar'
subprocess.run(['git', 'archive', '-o', str(archive), revision], cwd=repo, check=True)
with tarfile.open(archive) as tar:
    tar.extractall(src, filter='data')
if not args.baseline:
    for name in subprocess.check_output(['git', 'ls-files'], cwd=repo, text=True).splitlines():
        if (repo / name).is_file():
            shutil.copy2(repo / name, src / name)

kind = args.case
testfile = 'MaccyTests/HistoryDecoratorTests.swift' if kind == 'preview' else 'MaccyTests/SorterTests.swift'
if args.baseline:
    current = (repo / testfile).read_text()
    marker = '\nimport Darwin' if kind == 'preview' else '\n// Opt-in, synthetic component benchmark.'
    bench = current[current.index(marker):]
    if kind == 'insertion':
        bench = bench.replace('let index = sorter.insertionIndex(of: candidate, in: copy, by: .lastCopiedAt)',
                              'let index = sorter.sort(copy.map(\\.item) + [incoming], by: .lastCopiedAt).firstIndex(of: incoming)!')
    p = src / testfile
    p.write_text(p.read_text() + '\n' + bench)

# Runtime isolation is confined to this disposable copy and used identically on both sides.
identity = 'org.maccy.performance.validation.' + uuid.uuid4().hex
p = src / 'Maccy.xcodeproj/project.pbxproj'
p.write_text(p.read_text().replace('org.p0deje.Maccy', identity))
for folder in ['Maccy', 'MaccyTests']:
    for p in (src / folder).rglob('*.swift'):
        text = p.read_text().replace('NSPasteboard.general', 'NSPasteboard(name: NSPasteboard.Name("' + identity + '"))')
        p.write_text(text)
# Existing DEBUG test hooks supply in-memory storage, isolated defaults and no History observers.
derived = out / 'build'
command = ['xcodebuild', 'build-for-testing', '-project', 'Maccy.xcodeproj', '-scheme', 'Maccy',
           '-configuration', 'Release', '-destination', 'platform=macOS,arch=arm64',
           '-derivedDataPath', str(derived), 'CODE_SIGN_IDENTITY=-', 'DEVELOPMENT_TEAM=',
           'CODE_SIGN_STYLE=Manual', 'ENABLE_HARDENED_RUNTIME=NO', 'ENABLE_TESTABILITY=YES',
           'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG']
if args.packages:
    command += ['-clonedSourcePackagesDirPath', str(args.packages.resolve()), '-skipPackageUpdates']
run(command, 'build.log')
runner = next((derived / 'Build/Products').glob('*.xctestrun'))
config = plistlib.loads(runner.read_bytes())

def normalize(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in ('DYLD_FRAMEWORK_PATH', '__XPC_DYLD_FRAMEWORK_PATH') and isinstance(child, str):
                value[key] = ':'.join(p for p in child.split(':') if not p.startswith('__TESTROOT__'))
            elif key == 'CommandLineArguments':
                value[key] = ['enable-testing']
            else:
                normalize(child)
    elif isinstance(value, list):
        for child in value:
            normalize(child)
normalize(config)
runner.write_bytes(plistlib.dumps(config))
suite = 'HistoryItemDecoratorTests' if kind == 'preview' else 'SorterTests'
common = ['xcodebuild', 'test-without-building', '-xctestrun', str(runner), '-destination',
          'platform=macOS,arch=arm64', '-parallel-testing-enabled', 'NO', '-enablePerformanceTestsDiagnostics', 'NO']
unit_selection = ['-only-testing:MaccyTests/SharedStateTests/' + suite]
if kind == 'insertion':
    unit_selection.append('-only-testing:MaccyTests/SharedStateTests/HistoryTests')
run(common + unit_selection + ['-resultBundlePath', str(out / 'unit.xcresult')], 'unit.log', 180)
if not re.search(r'Test run with [1-9][0-9]* tests.*passed', (out / 'unit.log').read_text()):
    raise RuntimeError('No successful nonempty Swift Testing run was recorded')

def enable_bench(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in ('EnvironmentVariables', 'TestingEnvironmentVariables'):
                child['MACCY_RUN_BENCHMARKS'] = '1'
            enable_bench(child)
    elif isinstance(value, list):
        for child in value:
            enable_bench(child)
enable_bench(config)
runner.write_bytes(plistlib.dumps(config))
bench_suite = 'TextPreviewBenchmarks' if kind == 'preview' else 'InsertionBenchmarks'
records = []
for trial in range(1, 4):
    log = f'benchmark-{trial}.log'
    run(common + ['-only-testing:MaccyTests/SharedStateTests/' + bench_suite,
                  '-resultBundlePath', str(out / f'benchmark-{trial}.xcresult')], log, 180)
    for line in (out / log).read_text().splitlines():
        if 'MACCY_BENCHMARK ' in line:
            records.append(dict(trial=trial, **json.loads(line.split('MACCY_BENCHMARK ', 1)[1])))
if not records:
    raise RuntimeError('No benchmark records were emitted')
(out / 'results.json').write_text(json.dumps({'kind': kind, 'baseline': args.baseline,
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'records': records}, indent=2) + '\n')
print(out / 'results.json')
