#!/usr/bin/env bash
# Build the game this port's e2e runs: **two** packages, the parent and the add-on.
#
#   tools/build-game.sh            # build (or reuse) the exported game, print the exports
#   eval "$(tools/build-game.sh)"  # the shape tools/e2e.sh reads
#
# Why not `ports/tools/launcher-game.sh build refinedtypes`: that wrapper passes **one**
# port directory, and this port cannot run without its parent (Refined Storage owns the
# network, the controller and the disk drives). The launcher itself accepts "a folder of
# them" (`Checking 2 mods`), so this script bundles two packages and then does what the
# wrapper does after the build: export the built version out of the launcher's managed
# folder, because a direct launch there is refused with exit 78 unless the launcher's Play
# started it (ARCHITECTURE.md §8, ports/_shared/launcher-e2e.md).
#
# The parent half is a **fixture** (`tools/parent-fixture.py`): `ports/refinedstorage` as
# shipped depends on `horizon-core`, which the launcher cannot provide, so its package does
# not build at this pin. The fixture is the parent's own source with that one dependency
# replaced by the API's `Tag::compound`/`Tag::get(&str)`; see
# ports/_shared/evidence/refinedtypes-e2e/launcher-externs.md.
#
# Everything lives under ${HORIZON_E2E_ROOT:-~/.cache/horizon-e2e}; never /tmp.
set -uo pipefail

TOOLS=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TOOLS/../.." && pwd)       # <campaign>/ports
PORT=$ROOT/refinedtypes
CAMPAIGN=$(cd "$ROOT/.." && pwd)

SDK_PIN=0b14f8acfd97fa2c750e42795249dcc981178ca4
MIXINS_PIN=e59da9094f0c2fdda6c627fe9eff22dec6a906f0
PIN=${SDK_PIN:0:7}
RES_VERSION=26.3
E2E_ROOT=${HORIZON_E2E_ROOT:-$HOME/.cache/horizon-e2e}
DATA=$E2E_ROOT/root/data
CONFIG=$E2E_ROOT/root/config
HOME_DIR=$E2E_ROOT/root/home
VERSIONS=$DATA/horizon-launcher/versions
INSTANCE=${HORIZON_E2E_INSTANCE:-e2e}
LAUNCHER=$ROOT/_shared/bin/launcher-0.2.78/horizon-launcher
BUNDLE=$E2E_ROOT/$PIN/bundle-refinedtypes
OUT=$E2E_ROOT/$PIN/refinedtypes
CONTROL=$E2E_ROOT/$PIN/control

say() { printf '%s: %s\n' "${0##*/}" "$*" >&2; }
die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit "${2:-1}"; }

case "$E2E_ROOT" in
    /tmp/*|/tmp) die "HORIZON_E2E_ROOT=$E2E_ROOT is under /tmp (a 7.5 GB tmpfs); use a folder on /home" 2 ;;
esac

launcher() {
    env XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CONFIG" HOME="$HOME_DIR" "$LAUNCHER" "$@"
}

# The Nightly this campaign pins, installed by the campaign wrapper.
nightly_tag() {
    launcher versions --installed --json 2>/dev/null \
        | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
print(next((v for v in d.get("installed",[]) if v.endswith("-'$PIN'")), ""))'
}

# The version `native-build` produced: the newest one carrying this port's manifest.
built_tag() {
    local tag newest="" newest_t=0 t
    for tag in "$VERSIONS"/native-*; do
        [ -d "$tag" ] || continue
        tag=${tag##*/}
        [ -f "$VERSIONS/$tag/horizon-native-mods/refinedtypes/horizon-mod.toml" ] || continue
        cmp -s "$VERSIONS/$tag/horizon-native-mods/refinedtypes/horizon-mod.toml" "$PORT/horizon-mod.toml" \
            || continue
        t=$(stat -c %Y "$VERSIONS/$tag")
        if [ "$t" -gt "$newest_t" ]; then newest=$tag; newest_t=$t; fi
    done
    [ -n "$newest" ] && echo "$newest"
}

# Copy an installed version out of the launcher's managed folder, as the wrapper does.
export_version() { # tag outdir
    local tag=$1 out=$2 f
    rm -rf "$out"
    mkdir -p "$out" || die "cannot create $out" 3
    for f in "$VERSIONS/$tag"/horizon-client "$VERSIONS/$tag"/horizon-ctl \
             "$VERSIONS/$tag"/lib*.so "$VERSIONS/$tag"/horizon-wasm-std.wasm \
             "$VERSIONS/$tag"/native-mods.json; do
        [ -e "$f" ] || continue
        ln -f "$f" "$out/" 2>/dev/null || cp -a "$f" "$out/"
    done
    [ -d "$VERSIONS/$tag/horizon-native-mods" ] && cp -a "$VERSIONS/$tag/horizon-native-mods" "$out/"
    ldd "$out/horizon-client" 2>/dev/null | grep -q 'not found' \
        && die "the exported game in $out misses a library: $(ldd "$out/horizon-client" | grep 'not found' | tr '\n' ' ')" 9
    return 0
}

bundle() {
    rm -rf "$BUNDLE"
    mkdir -p "$BUNDLE"
    python3 "$PORT/tools/parent-fixture.py" >&2 || die "parent fixture failed" 10
    cp -a "$ROOT/_shared/evidence/refinedtypes-e2e/parent/refinedstorage" "$BUNDLE/refinedstorage"
    mkdir -p "$BUNDLE/refinedtypes"
    for entry in horizon-mod.toml Cargo.toml src assets data LICENSE LICENSE-NOTICE.md; do
        [ -e "$PORT/$entry" ] || die "the port is missing $entry" 10
        cp -a "$PORT/$entry" "$BUNDLE/refinedtypes/"
    done
}

env_block() { # game ctl control resources
    printf 'export GAME=%q\n' "$1"
    printf 'export CTL=%q\n' "$2"
    printf 'export CONTROL_GAME=%q\n' "$3"
    printf 'export RES=%q\n' "$4"
    printf 'export HORIZON_RES=%q\n' "$4"
    printf 'export E2E_TMP=%q\n' "$E2E_ROOT/scratch"
    printf 'export SOCK=%q\n' "$E2E_ROOT/scratch/refinedtypes-e2e.sock"
    printf 'export GSOCK=%q\n' "$E2E_ROOT/scratch/refinedtypes-e2e-guest.sock"
}

env_only() {
    local tag
    tag=$(nightly_tag) || die "no Nightly at $PIN installed" 5
    [ -x "$OUT/horizon-client" ] || die "no exported game for refinedtypes; run: ${0##*/}" 2
    [ -x "$CONTROL/horizon-client" ] || die "no exported control game; run: ${0##*/}" 2
    env_block "$OUT/horizon-client" "$OUT/horizon-ctl" "$CONTROL/horizon-client" \
              "$VERSIONS/$tag/.local/horizon-client/$RES_VERSION"
}

build() {
    mkdir -p "$DATA" "$CONFIG" "$HOME_DIR" "$E2E_ROOT/scratch" || die "cannot create $E2E_ROOT" 3
    [ -x "$LAUNCHER" ] || die "no launcher at $LAUNCHER; run: ports/tools/launcher-game.sh ensure" 2
    local tag
    tag=$(nightly_tag) || true
    [ -n "$tag" ] || die "the launcher has no Nightly at $PIN; run: ports/tools/launcher-game.sh build <a port>" 5
    bundle
    say "native-build the two-package bundle against $tag"
    launcher native-build "$BUNDLE" --instance "$INSTANCE" --trust-native-code >&2 \
        || die "horizon-launcher native-build failed" 10
    local built
    built=$(built_tag) || die "native-build reported success but no version carries refinedtypes" 10
    say "built $built; exporting"
    export_version "$built" "$OUT"
    export_version "$tag" "$CONTROL"
    env_only
}

case "${1:-}" in
    "") build ;;
    env) env_only ;;
    *) die "usage: ${0##*/} [env]" 64 ;;
esac
