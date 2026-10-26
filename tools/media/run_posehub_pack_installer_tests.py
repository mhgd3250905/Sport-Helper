#!/usr/bin/env python3
"""Compile the actual internal Kotlin installer and run small JVM fixtures.

Uses the installed Android SDK's Apache-2.0 org.json sources at test runtime;
there is no new App dependency, copied third-party source, or network access.
The bridge compiles against the real Android/Flutter JARs, but is not executed.

python tools/media/run_posehub_pack_installer_tests.py --sdk E:/Android/SDK \
  --java-home "E:/Android/Android Studio/jbr" --gradle-cache E:/DevCaches/gradle
Optional --descriptor and --manifest check released metadata without unpacking
or reading the large archive. All compilation output lives in a temporary dir.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--java-home', type=Path, required=True)
    parser.add_argument('--gradle-cache', type=Path, required=True)
    parser.add_argument('--descriptor', type=Path)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    if bool(args.descriptor) != bool(args.manifest):
        parser.error('--descriptor and --manifest must be supplied together')
    root = Path(__file__).resolve().parents[2]
    cache = args.gradle_cache / 'caches/modules-2/files-2.1'

    def jar(group: str, artifact: str) -> Path:
        matches = sorted((cache / group / artifact).glob('*/*/*.jar'))
        if not matches:
            parser.error(f'Missing cached test tool: {group}/{artifact}; no download attempted')
        return matches[-1]

    compiler = jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable')
    stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib')
    compiler_jars = [compiler, stdlib]
    for group, name in [
        ('org.jetbrains.kotlin', 'kotlin-script-runtime'),
        ('org.jetbrains.kotlin', 'kotlin-reflect'),
        ('org.jetbrains.intellij.deps', 'trove4j'),
        ('org.jetbrains', 'annotations'),
        ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm'),
    ]:
        compiler_jars.append(jar(group, name))
    android = sorted((args.sdk / 'platforms').glob('*/android.jar'))[-1]
    embedding = jar('io.flutter', 'flutter_embedding_release')
    json_dirs = sorted((args.sdk / 'sources').glob('*/org/json'))
    if not json_dirs:
        parser.error('Android SDK org.json sources are required; no download attempted')
    java_suffix = '.exe' if os.name == 'nt' else ''
    java = args.java_home / 'bin' / f'java{java_suffix}'
    javac = args.java_home / 'bin' / f'javac{java_suffix}'

    def run(command: list[str | Path]) -> None:
        subprocess.run([str(part) for part in command], check=True, cwd=root)

    with tempfile.TemporaryDirectory(prefix='smartfit-pack-jvm-') as temporary:
        work = Path(temporary)
        json_classes = work / 'json-classes'
        json_classes.mkdir()
        annotations = {
            'android/annotation/SystemApi.java': 'package android.annotation; public @interface SystemApi { enum Client { PRIVILEGED_APPS, MODULE_LIBRARIES } Client client() default Client.PRIVILEGED_APPS; }',
            'android/compat/annotation/UnsupportedAppUsage.java': 'package android.compat.annotation; public @interface UnsupportedAppUsage {}',
            'libcore/util/NonNull.java': 'package libcore.util; @java.lang.annotation.Target(java.lang.annotation.ElementType.TYPE_USE) public @interface NonNull {}',
            'libcore/util/Nullable.java': 'package libcore.util; @java.lang.annotation.Target(java.lang.annotation.ElementType.TYPE_USE) public @interface Nullable {}',
        }
        sources = []
        for name, contents in annotations.items():
            source = work / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(contents, encoding='utf-8')
            sources.append(source)
        run([javac, '-encoding', 'UTF-8', '-d', json_classes, *sources, *json_dirs[-1].glob('*.java')])
        classes = work / 'classes'
        classes.mkdir()
        classpath = os.pathsep.join(map(str, [json_classes, stdlib, android, embedding]))
        run([
            java, '-cp', os.pathsep.join(map(str, compiler_jars)),
            'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect',
            '-jvm-target', '17', '-classpath', classpath, '-d', classes,
            root / 'android/app/src/internal/kotlin/com/ugk/smartfit/PoseHubPackInstaller.kt',
            root / 'tools/media/test_posehub_pack_installer.kt',
        ])
        command = [java, '-cp', os.pathsep.join(map(str, [classes, json_classes, stdlib])),
                   'com.ugk.smartfit.Test_posehub_pack_installerKt']
        if args.descriptor:
            command.extend([args.descriptor.resolve(), args.manifest.resolve()])
        run(command)


if __name__ == '__main__':
    main()
