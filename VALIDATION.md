# Refined Types — validation record

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`**, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, game 26.3, launcher 0.2.92, `api = "0.2"`.
Version **0.1.2** (slice 2: the recipe family). Every Rust step ran through
`ports/tools/build-slot.sh` (`BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0`, no `--target-dir`); the
in-game legs ran in one `build-slot.sh run --step e2e` lease each.

## The deliverable

| | |
|---|---|
| package | `ports/refinedtypes/refinedtypes.hmod` |
| size | **283,949 B** |
| SHA-256 | `5360468e99254658545ba986e0ec12fde04b4ab738a997121d66d5726cfbca34` |
| version | **0.1.2** (manifest + `Cargo.toml`) |
| entries | **581** (474 from 0.1.1 + the 107 carried recipes) |
| packed `Cargo.lock` | none |
| runtime | `src/runtime.rs` byte-identical in the tree and in the package (`2757785cdf9c…`) |
| two builds | `cmp`-identical, `rm -f Cargo.lock` before each |

## Gates (all fresh, against the delivered bytes)

| gate | command | result | log |
|---|---|---|---|
| tests | `cargo test --offline` | 21 passed, 0 failed | `evidence/refinedtypes/sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings | `sdk-clippy.log` |
| format | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean | `sdk-clippy.log` |
| SDK check | `cargo horizon-mod check refinedtypes.hmod` | *0.1.2, native-1/0a875da…/e59da90…, 283949 bytes* | `sdk-check.log` |
| fits (pin) | `… fits refinedtypes.hmod --build 0a875da` | *0a875da made for* | `sdk-fits.log` |
| fits (other build) | `… fits refinedtypes.hmod --build 0b14f8a` | *0b14f8a fits* | `sdk-fits-other.log` |
| dialect gate | `check_261_dialect.py refinedtypes.hmod` | 138 recipe/loot files, all 26.3 | — |
| content carry | `python3 tools/carry.py --check` | 575 files re-derived, 107 recipes, 2 skipped (reasons) | — |
| package gate | `verify-sdk-package.py refinedtypes` | **1/1** | — |

Each of `sdk-test.log`, `sdk-check.log`, `sdk-fits.log`, `sdk-fits-other.log` starts with
`package: refinedtypes.hmod 283949 B sha256 5360468e…`, so a log cannot be mistaken for another
package's run.

## In-game legs (`ports/_shared/evidence/refinedtypes-e2e/`)

| leg | result | log |
|---|---|---|
| modded pair (refinedstorage 0.2.2 + refinedtypes 0.1.2) | **PASS** + `EXIT:0` | `e2e.log` |
| red: the same driver against 0.1.1/0.2.1 at `0b14f8a` | **FAIL** + `EXIT:1` — *no refinedstorage:machine_casing* | `e2e-red-recipes-0b14f8a.log` |
| control (same Nightly, no packages) | **FAIL** + `EXIT:1` — *the block at 44,64,0 is minecraft:air* | `e2e-control.log` |
| selftest (flipped drain assertion) | **FAIL** + `EXIT:1` — *the disk was drained to 2998* | `e2e-selftest.log` |
| log gate | `check-e2e-logs.py refinedtypes-e2e --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` | — |

## Re-run

```sh
# the ladder (each a separate lease)
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step test  -- bash -lc 'cd ports/refinedtypes && cargo test --offline'
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step lint  -- bash -lc 'cd ports/refinedtypes && cargo clippy --all-targets --offline -- -D warnings'
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step build -- bash -lc 'cd ports/refinedtypes && rm -f Cargo.lock && cargo horizon-mod build'
# the game (two packages) and the leg
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step build -- bash -lc 'cd ports/refinedtypes && tools/build-game.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e   -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && tools/e2e.sh'
```

The recipe phase alone, against any running socket (a smoke run of the first N recipes):

```sh
python3 -u ports/refinedtypes/tools/recipe_check.py SOCK CTL 36 64 8 [N]
```
