"""Deterministic CLI archive encoding; caller verifies the compiled executable."""
import io
import zipfile


def archive_bytes(files):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (0o100755 if name == 'istk' else 0o100644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data, compresslevel=9)
    return buffer.getvalue()
