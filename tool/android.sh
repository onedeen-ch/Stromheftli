#!/usr/bin/env bash
set -euo pipefail
# Der gepinnte Flutter-SDK liefert Gradle Wrapper, Ressourcen und Builddateien.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
flutter create --platforms=android --no-pub --org ch.stromheftli --project-name app "$tmpdir/app"
mkdir -p android
cp -an "$tmpdir/app/android/." android/

if ! grep -q 'pdfbox-android' android/app/build.gradle.kts; then
  printf '\n dependencies { implementation("com.tom-roush:pdfbox-android:2.0.27.0") }\n' >> android/app/build.gradle.kts
fi
