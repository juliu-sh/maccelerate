#!/usr/bin/env python3
"""Archive a local app, verify its restoration, and optionally retire a build."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def contents(root):
    result = {'.': {'mode': stat.S_IMODE(root.stat().st_mode), 'kind': 'directory'}}
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(base) / name
            details = path.lstat()
            entry = {'mode': stat.S_IMODE(details.st_mode)}
            if path.is_symlink():
                entry.update(kind='link', target=os.readlink(path))
            elif path.is_file():
                entry.update(kind='file', sha256=digest(path))
                try:
                    fork = Path(str(path) + '/..namedfork/rsrc').read_bytes()
                except FileNotFoundError:
                    fork = b''
                if fork:
                    entry['resource_fork'] = hashlib.sha256(fork).hexdigest()
            elif path.is_dir():
                entry.update(kind='directory')
            else:
                raise ValueError(f'Unsupported file type: {path}')
            result[str(path.relative_to(root))] = entry
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--retire', action='store_true', help='Remove only a verified app in this checkout\'s build directory')
    args = parser.parse_args()
    app = args.app.absolute()
    archive = args.archive.absolute()
    build = Path(__file__).resolve().parents[1] / 'build'
    if args.retire and (app.parent.resolve() != build or app.name not in ('Maccelerate.app', 'Maccelerate Source.app') or app.is_symlink()):
        raise ValueError('Retirement is limited to this checkout\'s own build app bundles')
    if not app.is_dir() or not app.name.endswith('.app'):
        raise ValueError('Expected an existing app bundle')
    if archive.suffix != '.zip' or archive.exists() or app in archive.parents:
        raise ValueError('Use a new ZIP path outside the app bundle')
    before = contents(app)
    archive.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    original_signed = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    with tempfile.TemporaryDirectory(prefix='maccelerate-archive-verify-') as scratch:
        subprocess.run(['ditto', '-x', '-k', str(archive), scratch], check=True)
        restored = Path(scratch) / app.name
        if contents(restored) != before:
            raise ValueError('Restored file contents, permissions, links or resource forks differ')
        if original_signed:
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(restored)], check=True)
    if contents(app) != before:
        raise ValueError('Original app changed during verification; it has not been retired')
    if args.retire:
        register = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
        result = subprocess.run([register, '-u', str(app)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode not in (0, 1):
            raise ValueError('Could not unregister the build; it has not been retired')
        shutil.rmtree(app)
    print(f'Archive verified: {archive}')


if __name__ == '__main__':
    main()
