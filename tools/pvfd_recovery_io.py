"""POSIX, no-symlink, no-overwrite file operations for recovery tools."""
import os
import secrets
import stat
from pathlib import Path
from contextlib import contextmanager

from pvfd_recovery_format import RecoveryError


def parts(path):
    path = Path(path)
    if '..' in path.parts:
        raise RecoveryError('unsafe_path')
    return Path(os.path.abspath(path)).parts[1:]


@contextmanager
def directory(path, create=False, private=False):
    if os.name != 'posix' or not hasattr(os, 'O_NOFOLLOW'):
        raise RecoveryError('unsupported_filesystem')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in parts(path):
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = nxt
        if private:
            info = os.fstat(fd)
            if info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise RecoveryError('insecure_output_directory')
        yield fd
    except OSError:
        raise RecoveryError('unsafe_or_unavailable_path') from None
    finally:
        os.close(fd)


def read_regular(path, limit):
    path = Path(path)
    with directory(path.parent) as parent:
        try:
            fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            with os.fdopen(fd, 'rb') as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                    raise RecoveryError('unsafe_input_file')
                data = stream.read(limit + 1)
        except OSError:
            raise RecoveryError('input_read_failed') from None
    if len(data) > limit:
        raise RecoveryError('oversized_input')
    return data


def atomic_new(path, data):
    """Authenticate first, then publish a fully fsynced 0600 file via link(2)."""
    path = Path(path)
    if not path.name or path.name in ('.', '..'):
        raise RecoveryError('unsafe_path')
    with directory(path.parent, create=True, private=True) as parent:
        tmp = '.pvfd-recovery-' + secrets.token_hex(16)
        created = False
        try:
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent)
            created = True
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.link(tmp, path.name, src_dir_fd=parent, dst_dir_fd=parent, follow_symlinks=False)
            os.fsync(parent)
        except FileExistsError:
            raise RecoveryError('output_exists') from None
        except OSError:
            raise RecoveryError('output_write_failed') from None
        finally:
            if created:
                os.unlink(tmp, dir_fd=parent)


def ensure_absent(path):
    path = Path(path)
    with directory(path.parent, private=True) as parent:
        try:
            os.stat(path.name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            return
        raise RecoveryError('output_exists')
