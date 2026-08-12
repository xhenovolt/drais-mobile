#!/usr/bin/env bash
#
# Builds a DRAIS Mobile artefact and leaves it under a name that identifies it.
#
#   tool/build.sh apk debug          → build/drais-1.7.2-debug.apk
#   tool/build.sh apk release        → build/drais-1.7.2-release.apk
#   tool/build.sh appbundle release  → build/drais-1.7.2-release.aab
#
# ## Why this wrapper exists
#
# `android/app/build.gradle.kts` already names the artefact correctly, and
# Gradle honours it — the file lands at
# `build/app/outputs/apk/<channel>/drais-<version>-<channel>.apk`.
#
# But the Flutter Gradle plugin then *copies* that into
# `build/app/outputs/flutter-apk/app-<channel>.apk` using a filename it
# hardcodes, and that copy is the path `flutter build` prints. There is no
# hook in `build.gradle.kts` to change it. So the vague name is the one people
# see and share, which is the whole problem.
#
# This script takes the correctly named file Gradle produced, puts it at the
# top of `build/` where it is easy to find, and deletes the ambiguous copy so
# there is exactly one artefact and no chance of grabbing the wrong one.
#
# It reads the version from pubspec.yaml — the authoritative source, which
# `test/core/app_version_test.dart` keeps in step with everything else.

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-apk}"
CHANNEL="${2:-release}"

case "$TARGET" in
  apk|appbundle) ;;
  *) echo "Usage: tool/build.sh <apk|appbundle> [debug|profile|release]" >&2
     exit 64 ;;
esac

case "$CHANNEL" in
  debug|profile|release) ;;
  *) echo "Channel must be debug, profile or release (got '$CHANNEL')." >&2
     exit 64 ;;
esac

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d+ -f1)"
BUILD="$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d+ -f2)"

if [ -z "$VERSION" ]; then
  echo "Could not read version from pubspec.yaml." >&2
  exit 65
fi

echo "Building DRAIS $VERSION+$BUILD — $TARGET/$CHANNEL"
echo

flutter build "$TARGET" "--$CHANNEL"

if [ "$TARGET" = "apk" ]; then
  EXT="apk"
  # Gradle already named this one. Prefer it over the flutter-apk copy.
  SOURCE="build/app/outputs/apk/$CHANNEL/drais-$VERSION-$CHANNEL.apk"
  FALLBACK="build/app/outputs/flutter-apk/app-$CHANNEL.apk"
else
  EXT="aab"
  SOURCE="build/app/outputs/bundle/${CHANNEL}/app-$CHANNEL.aab"
  FALLBACK="$SOURCE"
fi

if [ ! -f "$SOURCE" ]; then
  if [ ! -f "$FALLBACK" ]; then
    echo "Build reported success but no artefact was found at:" >&2
    echo "  $SOURCE" >&2
    echo "  $FALLBACK" >&2
    exit 70
  fi
  SOURCE="$FALLBACK"
fi

DEST="build/drais-$VERSION-$CHANNEL.$EXT"
cp "$SOURCE" "$DEST"

# Remove the ambiguously named copy so only one artefact remains and nobody
# ships `app-debug.apk` by reaching for the first file they see.
if [ "$TARGET" = "apk" ] && [ -f "build/app/outputs/flutter-apk/app-$CHANNEL.apk" ]; then
  rm -f "build/app/outputs/flutter-apk/app-$CHANNEL.apk" \
        "build/app/outputs/flutter-apk/app-$CHANNEL.apk.sha1"
fi

echo
echo "  $DEST"
ls -lh "$DEST" | awk '{print "  " $5}'
