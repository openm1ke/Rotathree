"""Package an already-built VK draft; index.html is at the ZIP root."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT / 'build/releases/vk/Rotathree-vk-draft.zip')
args = parser.parse_args()
source = ROOT / 'webapp/dist-vk'
manifest = json.loads((source / 'vk-release.json').read_text())
if manifest.get('platform') != 'vk' or manifest.get('appId') != '54815388':
    raise SystemExit('Build the VK target for app 54815388 first.')
for required in ['index.html', 'credits.html', 'licenses/Exo2-OFL.txt', 'licenses/VK-Bridge-MIT.txt']:
    if not (source / required).is_file():
        raise SystemExit(f'Missing release file: {required}')
if len(list((source / 'music').glob('*.m4a'))) != 5:
    raise SystemExit('Expected exactly five licensed music tracks.')
if any((source / 'music' / name).exists() for name in ['deep-focus.m4a', 'deep-focus-1.m4a']):
    raise SystemExit('Unverified Deep Focus tracks must not ship in this VK draft.')
files = sorted(path for path in source.rglob('*') if path.is_file())
if any(path.suffix in ['.ts', '.tsx', '.map'] or 'vk-host' in path.name or path.is_symlink() for path in files):
    raise SystemExit('Source files, test hosts or symlinks found in release.')
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, path.relative_to(source).as_posix())
    if archive.testzip() is not None:
        raise SystemExit('ZIP integrity check failed.')
digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
args.output.with_suffix('.zip.sha256').write_text(f'{digest}  {args.output.name}\n')
print(json.dumps({'zip': str(args.output), 'bytes': args.output.stat().st_size, 'files': len(files), 'sha256': digest}))
