# Refined Types — validation record

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`**, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, game 26.3 (Nightly `nightly-2026-11-20-0a875da`),
launcher 0.2.92, `api = "0.2"`. Version **0.1.5** (slice 5: a storage disk and a storage block are
fire resistant, as upstream's `Item.Properties.fireResistant()` declares them — 60 of the 88 items;
a part and the Network Energizer are not, as upstream leaves them). Every Rust step ran through
`ports/tools/build-slot.sh` (`BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0`, no `--target-dir`); the
in-game legs ran in `build-slot.sh run --step e2e` leases, one per leg.

## The deliverable

| | |
|---|---|
| package | `ports/refinedtypes/refinedtypes.hmod` |
| size | **299,863 B** |
| SHA-256 | `8058cf2166ea2c9e5eef07ea90c9614830da26a68c8c698f6581a13acbf29ad3` |
| version | **0.1.5** (manifest + `Cargo.toml`) |
| entries | **582** |
| packed `Cargo.lock` | none |
| runtime | `src/runtime.rs` byte-identical in the tree and in the package (`eece9ae798cc`) |
| two builds | `cmp`-identical, `rm -f Cargo.lock` before each |
| launcher build | `native-0a875da-2ee25a89c4b2` (`Compiling refinedstorage (1 of 2)` / `Compiling refinedtypes (2 of 2)`), the parent at 0.2.13; the two `native-*` folders that carried 0.1.4 were deleted first, so the bytes are this tree's |

## Gates (all fresh, against the delivered bytes)

| gate | command | result | log |
|---|---|---|---|
| tests | `cargo test --offline` | **30 passed**, 0 failed (red first: 29 passed, 1 failed) | `evidence/refinedtypes/sdk-test.log`, `red-slice5-fireproof.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings | `sdk-clippy.log` |
| format | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean | — |
| content carry | `python3 tools/carry.py --check` | 576 files re-derived, 107 recipes, 2 skipped (reasons) | — |
| SDK check (source) | `cargo horizon-mod check` | *421 items of the API (15 hooks…); Made for 0a875da* | `sdk-check.log` |
| package check | `cargo horizon-mod check refinedtypes.hmod` | *0.1.5, native-1/0a875da…/e59da90…, 299863 bytes* | `sdk-package-check.log` |
| fits (pin) | `… fits refinedtypes.hmod --build 0a875da` | *0a875da made for* | `sdk-fits.log` |
| fits (other build) | `… fits refinedtypes.hmod --build 0b14f8a` | *0b14f8a fits* | `sdk-fits-other.log` |
| recipe types | `python3 ports/tools/check-recipe-types.py refinedtypes` | `refinedtypes: ok` | — |
| package gate | `verify-sdk-package.py refinedtypes` | **1/1** | — |

## In-game legs (`ports/_shared/evidence/refinedtypes-e2e/`)

| leg | result | log |
|---|---|---|
| modded pair (refinedstorage 0.2.13 + refinedtypes 0.1.5) | **PASS** + `EXIT:0` | `e2e.log` |
| red: the delivered 0.1.4 pair, slice-5 assertions | **FAIL** + `EXIT:1` — *a dropped 64k energy disk did not survive lava (0 alive)* | `e2e-red-fire-0.1.4.log` |
| the slice-5 leg alone | **PASS** + `EXIT:0` | `e2e-fire-only.log` |
| selftest (flipped fire assertion: the disk must be destroyed, it is not) | **FAIL** + `EXIT:1` — *the disk is still in the lava* | `e2e-selftest.log` |
| drain selftest (flipped slice-1 drain: the disk must keep 4,000, it was drained) | **FAIL** + `EXIT:1` — *the disk was drained to 2998* | `e2e-drain-selftest.log` |
| control (same Nightly, no packages) | **FAIL** + `EXIT:1` — *the block at 44,64,0 is minecraft:air* | `e2e-control.log` |
| negative (inverted slice-3 restore: the block must read 0, it reads 5000) | **FAIL** + `EXIT:1` — *NEGATIVE: the replaced block reads 5000/256000* | `e2e-negative.log` |
| the slice-4 menu leg alone | **PASS** + `EXIT:0` | `e2e-menu-only.log` |
| menu negative (inverted readout: the menu must read 0, it reads 4924) | **FAIL** + `EXIT:1` — *MENU_NEGATIVE: the menu reads 4924 for a 5000 network* | `e2e-menu-negative.log` |
| red: the 0.1.3 state (no container declaration, no menu type) | **FAIL** + `EXIT:1` — *the energizer opens no menu: `screen: playing`* | `e2e-red-menu.log` |
| log gate | `check-e2e-logs.py refinedtypes-e2e --strict` | `logs=10 ok=10 missing-exit=0 bad-exit=0` | — |

The 0.1.1/0.1.2 logs are kept under `retired-0.1.1/` and `retired-0.1.2/`; 0.1.3's and 0.1.4's own
runs were replaced by 0.1.5's (the same scenario plus slice 5) and remain in the port's history.
`e2e-red-menu.log` is slice 4's red proof against the 0.1.3 state; it is kept as that slice's
evidence and was not re-cut for 0.1.5.

## Re-run

```sh
# the ladder (each a separate lease)
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step test  -- bash -lc 'cd ports/refinedtypes && cargo test --offline'
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step lint  -- bash -lc 'cd ports/refinedtypes && cargo clippy --all-targets --offline -- -D warnings'
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step build -- bash -lc 'cd ports/refinedtypes && rm -f Cargo.lock && cargo horizon-mod build && cp target/horizon-mod/refinedtypes.hmod refinedtypes.hmod'
# the game (two packages) and the leg
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step build -- bash -lc 'cd ports/refinedtypes && tools/build-game.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e   -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && tools/e2e.sh'
# the fail-capable legs (keep `tee LOG` last in the pipeline: the guard watches the leg's output)
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && FIRE_ONLY=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && FIRE_ONLY=1 SELFTEST=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && DRAIN_SELFTEST=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && MENU_ONLY=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && MENU_ONLY=1 MENU_NEGATIVE=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && NEGATIVE=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && GAME=$CONTROL_GAME tools/e2e.sh'
```
