"""Compile the shipping extractor on macOS; exercise real archives and path guards."""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import zipfile

project = Path(__file__).resolve().parent.parent
source = (project / 'NativeMedia.mm').read_text()
api = source[source.index('struct archive;'):source.index('// Preview ADX')]
with tempfile.TemporaryDirectory(prefix='miku-archive-tests-') as directory:
    base = Path(directory)
    helper = base / 'extract.mm'
    helper.write_text('#import <Foundation/Foundation.h>\n#include <sys/stat.h>\nextern "C" {\n' + api + r'''
int main(int argc, char **argv) {
 @autoreleasepool {
  NSError *error=nil;
  BOOL ok=MFExtractArchive(@(argv[1]),@(argv[2]),&error);
  if(!ok)fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
  return ok?0:1;
 }
}
''')
    subprocess.run(['clang++', '-fobjc-arc', '-framework', 'Foundation', '-larchive', str(helper), '-o', str(base / 'extract')], check=True)
    def archive(name, entries):
        path = base / (name + '.zip')
        with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            for entry, content in entries:
                z.writestr(entry, content)
        return path
    valid = archive('valid', [('Mov_1/', ''), ('Mov_1/song.usm', b'media-fixture'), ('InstallData/Thum_1/a.png', b'image')])
    root = base / 'real'; root.mkdir()
    alias = base / 'alias'; alias.symlink_to(root, target_is_directory=True)
    for destination in [str(alias), str(alias) + '/', str(root) + '/']:
        subprocess.run([str(base / 'extract'), str(valid), destination], check=True)
        assert (root / 'Mov_1/song.usm').read_bytes() == b'media-fixture'
    assert not (base / 'escaped').exists()
    for name, entry in [('traversal', '../escaped'), ('absolute', str(base / 'escaped')), ('backslash', r'..\escaped')]:
        result = subprocess.run([str(base / 'extract'), str(archive(name, [(entry, 'bad')])), str(alias)], capture_output=True)
        assert result.returncode != 0, name
        assert not (base / 'escaped').exists(), name
    outside = base / 'outside'; outside.mkdir()
    (root / 'redirect').symlink_to(outside, target_is_directory=True)
    redirected = archive('redirect', [('redirect/escaped', 'bad')])
    result = subprocess.run([str(base / 'extract'), str(redirected), str(alias)], capture_output=True)
    assert result.returncode != 0 and not (outside / 'escaped').exists()
    symlink = base / 'symlink.zip'
    with zipfile.ZipFile(symlink, 'w') as z:
        info = zipfile.ZipInfo('Mov_1/link'); info.create_system = 3
        info.external_attr = (0o120777 << 16)
        z.writestr(info, '../../outside')
    result = subprocess.run([str(base / 'extract'), str(symlink), str(alias)], capture_output=True)
    assert result.returncode != 0
    print('PASS: shipping ZIP extractor, aliased/trailing-slash roots, nested packs, traversal/absolute/backslash paths, archived and existing symlinks')
