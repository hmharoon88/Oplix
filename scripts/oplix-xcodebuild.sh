#!/usr/bin/env bash
# Run xcodebuild with an isolated DerivedData tree under the repo (./.oplix-dd/).
# Use when the default ~/Library/Developer/Xcode/DerivedData/Oplix-* tree is
# corrupted (missing Privacy manifests, broken grpc zips, stale swift-protobuf).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DDP="${OPLIX_DERIVED_DATA:-$ROOT/.oplix-dd}"
exec xcodebuild -project "$ROOT/Oplix.xcodeproj" -scheme Oplix -derivedDataPath "$DDP" "$@"
