#!/usr/bin/env bash
set -euo pipefail
# Der gepinnte Flutter-SDK liefert Gradle Wrapper, Ressourcen und Builddateien.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
flutter create --platforms=android --no-pub --org ch.stromheftli --project-name app "$tmpdir/app"
mkdir -p android
cp -an "$tmpdir/app/android/." android/
