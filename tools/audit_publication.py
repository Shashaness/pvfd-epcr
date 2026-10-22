#!/usr/bin/env python3
"""Local source-candidate/index audit. No network; never prints matched values.

Heuristic checks are supplementary to human review, not a PHI/secret guarantee.
"""
import argparse
from collections import Counter
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TOP_FILES = {'.gitignore', 'README.md', 'LICENSE', 'CONTRIBUTING.md',
             'SECURITY.md', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md'}
APP_FILES = {'.gitignore', '.metadata', 'README.md', 'analysis_options.yaml',
             'pubspec.yaml', 'pubspec.lock'}
APP_DIRS = {'lib', 'test', 'android', 'ios', 'macos', 'linux', 'windows', 'web'}
BANNED_PARTS = {'build', '.dart_tool', '.gradle', '.idea', '.vscode', 'ephemeral',
                'Pods', '.symlinks', 'Exports', 'exports', 'records',
                'patient_data', 'patient_records', 'backups', 'assets'}
BANNED_SUFFIXES = {'.pdf', '.apk', '.aab', '.ipa', '.jks', '.keystore', '.pem',
                   '.key', '.p12', '.pfx', '.env', '.db', '.sqlite', '.sqlite3',
                   '.bak', '.backup', '.zip', '.log', '.tmp', '.dmp', '.hprof', '.local'}
HISTORICAL = {'main_old.dart', 'main_sha.dart', 'main_last_20260701.dart'}
FIXTURES = {'pvfd_epcr/test/fixtures/milestone_1_pdf_streams.json',
            'pvfd_epcr/test/fixtures/milestone_1_synthetic.xml'}
PATTERNS = {
    'apple-team-assignment': re.compile(r'\bDEVELOPMENT_TEAM\s*=\s*"?[A-Z0-9]{10}"?\s*;'),
    'private-key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    'credential-shape': re.compile(
        r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
        r'|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9_-]{24,})\b'),
    'credential-assignment': re.compile(
        r'''(?i)(?:password|passwd|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*["'][^"'\n]{6,}["']'''),
    'personal-machine-path': re.compile(r'/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|[A-Z]:\\Users\\[A-Za-z0-9._-]+'),
}


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def candidates(staged=False):
    if staged:
        # All tracked index entries, including any accidentally forced ignored file.
        return sorted(set(git('ls-files', '-z').decode().split('\0')) - {''})
    return sorted(set(git('ls-files', '--cached', '--others', '--exclude-standard',
                          '-z').decode().split('\0')) - {''})


def allowed(name):
    p = PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts:
        return False
    if name in TOP_FILES or name == 'third_party/FLUTTER_LICENSE':
        return True
    if p.parts[0] == 'docs' and p.suffix in {'.md', '.txt'}:
        return True
    if name == 'tools/audit_publication.py':
        return True
    if p.parts[0] != 'pvfd_epcr' or len(p.parts) < 2:
        return False
    if len(p.parts) == 2:
        return p.name in APP_FILES
    return p.parts[1] in APP_DIRS


def audit(names, staged=False):
    failures = []
    counts = Counter()
    for name in names:
        p = PurePosixPath(name)
        path = ROOT / name
        if (not allowed(name) or BANNED_PARTS.intersection(p.parts)
                or p.suffix.lower() in BANNED_SUFFIXES
                or p.name in HISTORICAL or '.epcr-tmp-' in p.name
                or p.name.endswith('.reserve')
                or (p.name.startswith('pcr_') and p.suffix == '.json')
                or 'generated_plugin' in p.name.lower()
                or 'generatedpluginregistrant' in p.name.lower()):
            failures.append(('excluded/unreviewed-path', name, 0))
            continue
        if path.is_symlink():
            failures.append(('symlink-needs-review', name, 0))
            continue
        data = git('show', ':' + name) if staged else path.read_bytes()
        if len(data) > 1024 * 1024:
            failures.append(('oversize-source-needs-review', name, 0))
            continue
        counts['files'] += 1
        if p.suffix.lower() in {'.png', '.ico'}:
            counts['reviewed-platform-images'] += 1
            continue  # Asset provenance/visual review is documented separately.
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            failures.append(('unknown-binary-needs-review', name, 0))
            continue
        counts['text-files'] += 1
        for label, pattern in PATTERNS.items():
            for match in pattern.finditer(text):
                failures.append((label, name, text.count('\n', 0, match.start()) + 1))
        if p.suffix == '.json' and name not in FIXTURES:
            if not (name.endswith('/Contents.json') or name == 'pvfd_epcr/web/manifest.json'):
                failures.append(('unreviewed-json', name, 0))
        if name not in FIXTURES and p.suffix == '.xml' and re.search(
                r'<(?:EMSDataSet|PatientCareReport)(?:\s|>)', text):
            failures.append(('unexpected-clinical-export', name, 0))
    return failures, counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true', help='Read actual index blobs')
    parser.add_argument('--write-inventory', action='store_true',
                        help='Write reviewed candidate filenames to docs/PUBLICATION_INVENTORY.txt')
    args = parser.parse_args()
    if args.staged and args.write_inventory:
        parser.error('inventory writing is only supported for working-tree candidates')
    inventory = ROOT / 'docs/PUBLICATION_INVENTORY.txt'
    if args.write_inventory:
        inventory.touch(exist_ok=True)
    names = candidates(args.staged)
    failures, counts = audit(names, args.staged)
    for label, name, line in failures:
        print(f'REVIEW REQUIRED: {label}: {name}' + (f':{line}' if line else ''))
    print('Index' if args.staged else 'Candidates', dict(counts),
          f'findings={len(failures)} (matched values suppressed)')
    if failures:
        return 1
    if args.write_inventory:
        inventory.write_text(''.join(name + '\n' for name in names), encoding='utf-8')
    if args.staged:
        expected = inventory.read_text(encoding='utf-8').splitlines()
        if names != expected:
            print('REVIEW REQUIRED: index differs from reviewed publication inventory')
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
