#!/usr/bin/env python3
"""Back up a closed iStickies2 profile, verify it, or restore into a NEW directory.
Never quits an App, migrates data, replaces an existing profile, or bypasses locks.
The complete profile is included except the live notes.lock file. Restore a compatible
App separately; downgrading an executable alone cannot downgrade schema 10 data.
"""
import argparse
import ctypes
import sys
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import zipfile

MAX_BYTES = 512 * 1024 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(ok, message):
    if not ok:
        raise ValueError(message)


@contextmanager
def locked(profile):
    require(profile.is_dir() and not profile.is_symlink(), 'Profile must be a real directory')
    fd = os.open(profile / 'notes.lock', os.O_RDONLY | os.O_NOFOLLOW)
    try:
        require(stat.S_ISREG(os.fstat(fd).st_mode), 'Existing regular notes.lock required')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(fd)


def inventory(profile):
    entries = {}
    def walk(directory):
        # Unlike glob/rglob, iterdir propagates unreadable-directory errors.
        # A partial traversal must never become a verified complete backup.
        for path in sorted(directory.iterdir()):
            yield path
            if stat.S_ISDIR(path.lstat().st_mode):
                yield from walk(path)
    for path in walk(profile):
        rel = path.relative_to(profile).as_posix()
        if rel == 'notes.lock':
            continue
        mode = path.lstat().st_mode
        require(stat.S_ISREG(mode) or stat.S_ISDIR(mode), 'Symlinks and special files are unsupported')
        entry = dict(mode=stat.S_IMODE(mode) & 0o777, directory=stat.S_ISDIR(mode))
        if not entry['directory']:
            data = path.read_bytes()
            entry.update(size=len(data), sha256=digest(data))
        entries[rel] = entry
    return entries


def verify(archive):
    with zipfile.ZipFile(archive) as z:
        infos = z.infolist()
        require(len(infos) <= 10001 and sum(i.file_size for i in infos) <= MAX_BYTES,
                'Backup exceeds supported size')
        require(len(z.namelist()) == len(set(z.namelist())), 'Duplicate ZIP entries')
        require(z.getinfo('manifest.json').file_size <= 1024 * 1024, 'Manifest too large')
        manifest = json.loads(z.read('manifest.json'))
        require(manifest.get('format') == 1, 'Unsupported backup format')
        entries = manifest['entries']
        require(isinstance(entries, dict), 'Invalid entry manifest')
        expected = {'manifest.json'}
        for name, entry in entries.items():
            require(isinstance(entry, dict), 'Invalid entry metadata')
            path = PurePosixPath(name)
            require(name and path.parts and str(path) == name and not path.is_absolute() and '..' not in path.parts
                    and path.parts[0] != 'notes.lock', 'Unsafe profile path')
            require(type(entry.get('directory')) is bool and type(entry.get('mode')) is int
                    and 0 <= entry['mode'] <= 0o777, 'Invalid file metadata')
            for parent in path.parents:
                if str(parent) != '.':
                    require(entries.get(str(parent), {}).get('directory') is True,
                            'Missing parent directory')
            if not entry['directory']:
                member = 'profile/' + name
                expected.add(member)
                info = z.getinfo(member)
                require(stat.S_ISREG(info.external_attr >> 16), 'Backup member must be a regular file')
                require(info.file_size == entry['size'] and digest(z.read(member)) == entry['sha256'],
                        'Backup content checksum mismatch')
        require(set(z.namelist()) == expected, 'Unexpected ZIP entries')
        return manifest


def backup(profile, destination):
    profile, destination = Path(profile).absolute(), Path(destination).absolute()
    require(not destination.resolve().is_relative_to(profile.resolve()), 'Backup must be outside the profile')
    require(not destination.exists() and not destination.is_symlink(), 'Backup destination already exists')
    with locked(profile):
        entries = inventory(profile)
        require(sum(e.get('size', 0) for e in entries.values()) <= MAX_BYTES - 1024 * 1024,
                'Profile exceeds supported size')
        manifest = dict(format=1, entries=entries)
        fd, temporary = tempfile.mkstemp(prefix='.istk-backup-', suffix='.partial', dir=destination.parent)
        temporary = Path(temporary)
        try:
            with os.fdopen(fd, 'w+b') as stream:
                with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED) as z:
                    z.writestr('manifest.json', json.dumps(manifest, sort_keys=True))
                    for name, entry in entries.items():
                        if not entry['directory']:
                            info = zipfile.ZipInfo('profile/' + name)
                            info.external_attr = (stat.S_IFREG | entry['mode']) << 16
                            info.compress_type = zipfile.ZIP_DEFLATED
                            z.writestr(info, (profile / name).read_bytes())
                stream.flush()
                os.fsync(stream.fileno())
            require(verify(temporary) == manifest, 'Backup verification failed')
            require(inventory(profile) == entries, 'Profile changed while backing up')
            # Atomic, no-clobber publication; incomplete files retain .partial names.
            os.link(temporary, destination)
            parent = os.open(destination.parent, os.O_RDONLY)
            try:
                os.fsync(parent)
            finally:
                os.close(parent)
        finally:
            temporary.unlink(missing_ok=True)
    return len(entries)


def restore(archive, destination):
    require(sys.platform == 'darwin', 'Atomic profile restore currently requires macOS')
    destination = Path(destination).absolute()
    require(not destination.exists() and not destination.is_symlink(), 'Restore destination already exists')
    # Keep one archive handle throughout verification and extraction.
    with Path(archive).open('rb') as stream:
        manifest = verify(stream)
        staged = Path(tempfile.mkdtemp(prefix='.istk-restore-', suffix='.partial', dir=destination.parent))
        try:
            with (staged / 'notes.lock').open('xb') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with zipfile.ZipFile(stream) as z:
                    for name, entry in sorted(manifest['entries'].items()):
                        path = staged / name
                        if entry['directory']:
                            path.mkdir(mode=0o700)
                        else:
                            data = z.read('profile/' + name)
                            require(digest(data) == entry['sha256'], 'Archive changed during restore')
                            with path.open('xb') as out:
                                out.write(data)
                                out.flush()
                                os.fsync(out.fileno())
                            path.chmod(entry['mode'])
                for name, entry in sorted(manifest['entries'].items(), reverse=True):
                    if entry['directory']:
                        (staged / name).chmod(entry['mode'])
                require(inventory(staged) == manifest['entries'], 'Restored profile differs')
                # macOS RENAME_EXCL prevents replacement even if another process
                # creates the destination after the initial absence check.
                libc = ctypes.CDLL(None, use_errno=True)
                rename = libc.renamex_np
                rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
                rename.restype = ctypes.c_int
                if rename(os.fsencode(staged), os.fsencode(destination), 4) != 0:
                    raise OSError(ctypes.get_errno(), 'Cannot publish restored profile')
                parent = os.open(destination.parent, os.O_RDONLY)
                try:
                    os.fsync(parent)
                finally:
                    os.close(parent)
        finally:
            if staged.exists():
                shutil.rmtree(staged)
    return len(manifest['entries'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for command in ('backup', 'restore'):
        cmd = sub.add_parser(command)
        cmd.add_argument('source', type=Path)
        cmd.add_argument('destination', type=Path)
    sub.add_parser('verify').add_argument('source', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'verify':
            count = len(verify(args.source)['entries'])
        else:
            count = globals()[args.command](args.source, args.destination)
        print(json.dumps({'status': 'verified', 'entries': count, 'operation': args.command}))
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Profile operation stopped: {error}\n')
