# Refined Types — validation record

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`**, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, game 26.3 (Nightly `nightly-2026-11-20-0a875da`),
launcher 0.2.92, `api = "0.2"`. Version **0.1.4** (slice 4: the Network Energizer's menu and
screen — the mod's only menu). Every Rust step ran through `ports/tools/build-slot.sh`
(`BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0`, no `--target-dir`); the in-game legs ran in
`build-slot.sh run --step e2e` leases, one per leg.

## The deliverable

| | |
|---|---|
| package | `ports/refinedtypes/refinedtypes.hmod` |
| size | **295,355 B** |
| SHA-256 | `1c2b80ea37a1e52b7681f34e6dc5e180b738e66ef42e077d4cc867f52bd189df` |
| version | **0.1.4** (manifest + `Cargo.toml`) |
| entries | **582** (581 + the menu declaration) |
| packed `Cargo.lock` | none |
| runtime | `src/runtime.rs` byte-identical in the tree and in the package (`eece9ae798cc`) |
| two builds | `cmp`-identical, `rm -f Cargo.lock` before each |
| launcher build | `native-0a875da-7d560bff795f` (`Compiling refinedstorage (1 of 2)` / `Compiling refinedtypes (2 of 2)`), the parent at 0.2.13 |

## Gates (all fresh, against the delivered bytes)

| gate | command | result | log |
|---|---|---|---|
| tests | `cargo test --offline` | **29 passed**, 0 failed | `evidence/refinedtypes/sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings | `sdk-clippy.log` |
| format | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean | — |
| SDK check (source) | `cargo horizon-mod check` | *405 items of the API (15 hooks…); Made for 0a875da* | `sdk-check.log` |
| package check | `cargo horizon-mod check refinedtypes.hmod` | *0.1.4, native-1/0a875da…/e59da90…, 295355 bytes* | `sdk-package-check.log` |
| fits (pin) | `… fits refinedtypes.hmod --build 0a875da` | *0a875da made for* | `sdk-fits.log` |
| fits (other build) | `… fits refinedtypes.hmod --build 0b14f8a` | *0b14f8a fits* | `sdk-fits-other.log` |
| content carry | `python3 tools/carry.py --check` | 576 files re-derived, 107 recipes, 2 skipped (reasons) | — |
| recipe types | `python3 ports/tools/check-recipe-types.py refinedtypes` | `refinedtypes: ok` | — |
| package gate | `verify-sdk-package.py refinedtypes` | **1/1** | — |

## In-game legs (`ports/_shared/evidence/refinedtypes-e2e/`)

| leg | result | log |
|---|---|---|
| modded pair (refinedstorage 0.2.13 + refinedtypes 0.1.4) | **PASS** + `EXIT:0` | `e2e.log` |
| red: the 0.1.3 state (no container declaration, no menu type) | **FAIL** + `EXIT:1` — *the energizer opens no menu: `screen: playing`* | `e2e-red-menu.log` |
| control (same Nightly, no packages) | **FAIL** + `EXIT:1` — *the block at 44,64,0 is minecraft:air* | `e2e-control.log` |
| negative (inverted slice-3 restore: the block must read 0, it reads 5000) | **FAIL** + `EXIT:1` — *NEGATIVE: the replaced block reads 5000/256000* | `e2e-negative.log` |
| menu negative (inverted readout: the menu must read 0, it reads 4924) | **FAIL** + `EXIT:1` — *MENU_NEGATIVE: the menu reads 4924 for a 5000 network* | `e2e-menu-negative.log` |
| selftest (flipped drain assertion) | **FAIL** + `EXIT:1` — *the disk was drained to 3004* | `e2e-selftest.log` |
| the slice-4 leg alone | **PASS** + `EXIT:0` | `e2e-menu-only.log` |
| log gate | `check-e2e-logs.py refinedtypes-e2e --strict` | `logs=7 ok=7 missing-exit=0 bad-exit=0` | — |

The 0.1.1/0.1.2 logs are kept under `retired-0.1.1/` and `retired-0.1.2/`; 0.1.3's four logs were
replaced by 0.1.4's run (the same scenario plus slice 4) and remain in the port's history.

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
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && MENU_ONLY=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && MENU_ONLY=1 MENU_NEGATIVE=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && NEGATIVE=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && SELFTEST=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && GAME=$CONTROL_GAME tools/e2e.sh'
```
