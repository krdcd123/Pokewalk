#!/usr/bin/env bash
# Usage: package-ipa.sh <path/to/PokeWalk.app> <bundle-prefix>
# Ad-hoc signs every bundle with its entitlements (HealthKit, App Group) so sideloading tools
# like Sideloadly can read them and request the matching capabilities when they re-sign.
set -euo pipefail
APP="$1"; PREFIX="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/out/tmp"; rm -rf "$ROOT/out"; mkdir -p "$WORK"

ent() { # $1 = entitlements file from the project -> expanded copy
  local dst="$WORK/$(basename "$1")"
  sed "s/\$(BUNDLE_ID_PREFIX)/$PREFIX/g" "$ROOT/$1" > "$dst"
  echo "$dst"
}
sign() { # $1 = bundle, $2 = entitlements (optional)
  if [ -n "${2:-}" ]; then codesign -f -s - --entitlements "$2" --generate-entitlement-der "$1"
  else codesign -f -s - "$1"; fi
}

STAGE="$WORK/Payload"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
A="$STAGE/$(basename "$APP")"

# Inner bundles first
if [ -d "$A/Watch/PokeWalkWatch.app" ]; then
  W="$A/Watch/PokeWalkWatch.app"
  [ -d "$W/PlugIns/PokeWalkComplications.appex" ] && sign "$W/PlugIns/PokeWalkComplications.appex" "$(ent Complications/PokeWalkComplications.entitlements)"
  sign "$W" "$(ent Watch/PokeWalkWatch.entitlements)"
else
  echo "::warning::No Watch app was embedded in the build"
fi
[ -d "$A/PlugIns/PokeWalkLiveActivity.appex" ] && sign "$A/PlugIns/PokeWalkLiveActivity.appex" "$(ent LiveActivity/PokeWalkLiveActivity.entitlements)"
sign "$A" "$(ent iOS/PokeWalk.entitlements)"

(cd "$WORK" && zip -qry "$ROOT/out/PokeWalk.ipa" Payload)

# A phone-only variant, in case your sideloading tool can't handle the embedded Watch app.
rm -rf "$A/Watch"
sign "$A" "$WORK/PokeWalk.entitlements"
(cd "$WORK" && zip -qry "$ROOT/out/PokeWalk-iPhone-only.ipa" Payload)

ls -lh "$ROOT/out"/*.ipa
