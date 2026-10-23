#!/usr/bin/env python3
"""Authenticate portable backups offline; never prints paths or clinical content."""
import argparse
import os
import stat
from pathlib import Path

from pvfd_generate_recovery_keys import prompt
from pvfd_recovery_format import RecoveryError, MAX_ENVELOPE, decrypt, load_private
from pvfd_recovery_io import atomic_new, directory, read_regular, parts


def inputs(source, recursive):
    # fd-relative traversal rejects symlinks even if swapped after discovery.
    source = Path(source)
    parts(source)
    info = source.lstat()
    if stat.S_ISLNK(info.st_mode):
        raise RecoveryError('unsafe_input_path')
    if stat.S_ISREG(info.st_mode):
        yield source, Path(source.name + '.recovered')
        return
    if not stat.S_ISDIR(info.st_mode):
        raise RecoveryError('unsafe_input_path')
    def walk(path, relative):
        with directory(path) as fd:
            for name in sorted(os.listdir(fd)):
                if name in ('.', '..') or '/' in name:
                    raise RecoveryError('unsafe_input_path')
                entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISLNK(entry.st_mode):
                    raise RecoveryError('unsafe_input_path')
                if stat.S_ISDIR(entry.st_mode):
                    if recursive:
                        yield from walk(path / name, relative / name)
                elif name.endswith('.pvfdbak'):
                    if not stat.S_ISREG(entry.st_mode):
                        raise RecoveryError('unsafe_input_path')
                    yield path / name, relative / (name + '.recovered')
    yield from walk(source, Path())


def recover(source, output, private_key, recursive=False, verify_only=False):
    source = Path(source).absolute()
    parts(source)
    if not verify_only:
        if output is None:
            raise RecoveryError('output_required')
        output = Path(output).absolute()
        parts(output)
        # Avoid recursively consuming plaintext/output trees or modifying inputs.
        if source == output or source in output.parents or output in source.parents:
            raise RecoveryError('overlapping_paths')
        with directory(output, create=True, private=True):
            pass
    successes, failures = 0, 0
    try:
        for path, relative in inputs(source, recursive):
            try:
                payload = read_regular(path, MAX_ENVELOPE)
                plaintext = decrypt(payload, private_key) # Authenticated in memory before any write.
                if not verify_only:
                    atomic_new(output / relative, plaintext)
                successes += 1
            except RecoveryError as error:
                failures += 1
                print('File failed: ' + error.code)
    except (RecoveryError, OSError):
        failures += 1
        print('Input traversal failed: unsafe_or_unavailable_path')
    if successes == 0 and failures == 0:
        failures = 1
        print('No backup files selected')
    return successes, failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-key', required=True)
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', help='Secured output directory; new files only')
    parser.add_argument('--recursive', action='store_true')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args(argv)
    if not args.verify_only and not args.output:
        parser.error('--output is required unless --verify-only is used')
    try:
        data = read_regular(args.private_key, 32768)
        private_key = load_private(data, prompt('Recovery private-key passphrase: ').encode('utf-8'))
        successes, failures = recover(args.input, args.output, private_key, args.recursive, args.verify_only)
        print(f'Processed: {successes}; failed: {failures}; mode: ' + ('verify-only' if args.verify_only else 'recover'))
        return 1 if failures else 0
    except RecoveryError as error:
        print('Recovery failed: ' + error.code)
    except (OSError, ValueError, EOFError, KeyboardInterrupt):
        print('Recovery failed: operation_failed')
    # Includes secure prompt refusal on a non-TTY; no traceback or echo fallback.
    except Warning:
        print('Recovery failed: secure_prompt_unavailable')
    except Exception:
        print('Recovery failed: operation_failed')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
