#!/usr/bin/env python3
"""Compile native alert source and run pure-JVM file-boundary checks.

This does not run an Android provider, notification, reboot or audible test.
"""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--java-home', default=os.environ.get('JAVA_HOME'))
    parser.add_argument('--android-jar')
    parser.add_argument('--flutter-jar')
    args = parser.parse_args()
    if bool(args.android_jar) != bool(args.flutter_jar):
        parser.error('Provide both --android-jar and --flutter-jar, or neither')
    here = Path(__file__).resolve().parent
    app = here.parents[1]
    source = app / 'packages/downloaded_adhan_native/android/src/main/java/org/almomin/app'
    android = '{http://schemas.android.com/apk/res/android}'
    manifest = ET.parse(source.parents[3] / 'AndroidManifest.xml').getroot()
    provider = manifest.find('application/provider')
    receiver = manifest.find('application/receiver')
    if provider is None or receiver is None:
        raise RuntimeError('Native sound components are missing')
    expected = {android + 'name': 'org.almomin.app.DownloadedAdhanProvider',
                android + 'authorities': '${applicationId}.downloaded_adhan_audio',
                android + 'exported': 'false', android + 'grantUriPermissions': 'true'}
    if provider.attrib != expected or receiver.get(android + 'exported') != 'false':
        raise RuntimeError('Native sound component access boundary changed')
    if manifest.findall('uses-permission'):
        raise RuntimeError('This module must not add device permissions')
    print('Private manifest declarations checked, not an Android merge/runtime test.', flush=True)
    command = lambda name: str(Path(args.java_home) / 'bin' / name) if args.java_home else name
    with tempfile.TemporaryDirectory(prefix='downloaded-adhan-checks-') as folder:
        root = Path(folder)
        fixture = root / 'fixture.bin'
        data = bytes(i % 251 for i in range(4096))
        fixture.write_bytes(data)
        reference = subprocess.check_output(['git', 'hash-object', str(fixture)], text=True).strip()
        independent = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if reference != independent:
            raise RuntimeError('Independent Git blob reference did not match')
        digest = root / 'fixture.sha1'
        digest.write_text(reference, encoding='ascii')
        classes = root / 'classes'
        classes.mkdir()
        sources = sorted(source.glob('*.java')) if args.android_jar else [source / 'DownloadedAdhanFile.java']
        compile_command = [command('javac'), '--release', '17', '-encoding', 'UTF-8', '-d', str(classes)]
        if args.android_jar:
            compile_command += ['-classpath', os.pathsep.join([args.android_jar, args.flutter_jar])]
        subprocess.run(compile_command + [str(path) for path in sources] +
                       [str(here / 'DownloadedAdhanFileChecks.java')], check=True)
        subprocess.run([command('java'), '-cp', str(classes),
                        'org.almomin.app.DownloadedAdhanFileChecks', str(fixture), str(digest)], check=True)
        if args.android_jar:
            print('Native plugin API compilation passed. Android runtime behavior was not exercised.')


if __name__ == '__main__':
    main()
