#!/usr/bin/env python3
"""Scan all tracked and nonignored files; report paths/rule names, never matched secrets."""
import pathlib, re, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
files = subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=root).split(b'\0')
patterns = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'API credential': rb'sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}',
    'GitHub credential': rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})',
    'JWT': rb'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}',
    'credential assignment': rb'(?i)["\x27](?:access_token|refresh_token|id_token)["\x27]\s*:\s*["\x27][^"\x27]{12,}',
}
forbidden={'.p12','.pfx','.pem','.key','.cer','.mobileprovision','.provisionprofile'}
failures=[]
for raw in sorted(set(files)):
    if not raw: continue
    path=root/raw.decode(); relative=str(path.relative_to(root))
    if not path.is_file(): continue
    if path.suffix.lower() in forbidden or path.name == 'auth.json' or path.name.startswith('.env'):
        failures.append((relative,'forbidden filename'));continue
    data=path.read_bytes()
    for label,pattern in patterns.items():
        if re.search(pattern,data): failures.append((relative,label))
if failures:
    for path,label in failures: print(f'FAIL: {path}: {label}')
    sys.exit(1)
print(f'PASS: {len(set(files))-1} source files scanned; no credential patterns or certificate/key files found.')
print('Heuristic scan only; review the staged diff before pushing.')
