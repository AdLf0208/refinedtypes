# Refined Types — validation record

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`**, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, game 26.3, launcher 0.2.92, `api = "0.2"`.
Version **0.1.3** (slice 3: the storage block's item carries its amount). Every Rust step ran
through `ports/tools/build-slot.sh` (`BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0`, no `--target-dir`);
the in-game legs ran in one `build-slot.sh run --step e2e` lease each.

## The deliverable

| | |
|---|---|
| package | `ports/refinedtypes/refinedtypes.hmod` |
| size | **288,647 B** |
| SHA-256 | `9432dc8761476a9e266877631a02e3a55e94215259aad104ca7ddaaa4a7bd678` |
| version | **0.1.3** (manifest + `Cargo.toml`) |
| entries | **581** (unchanged from 0.1.2; the slice adds code, not files) |
| packed `Cargo.lock` | none |
| runtime | `src/runtime.rs` byte-identical in the tree and in the package (`9731b2de6b25…`) |
| two builds | `cmp`-identical, `rm -f Cargo.lock` before each |

## Gates (all fresh, against the delivered bytes)

| gate | command | result | log |
|---|---|---|---|
| tests | `cargo test --offline` | **25 passed**, 0 failed | `evidence/refinedtypes/sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings | `sdk-clippy.log` |
| format | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean | — |
| SDK check (source) | `cargo horizon-mod check` | *…325 items of the API (12 hooks…); Made for 0a875da* | `sdk-check.log` |
| package check | `cargo horizon-mod check refinedtypes.hmod` | *0.1.3, native-1/0a875da…/e59da90…, 288647 bytes* | `sdk-package-check.log` |
| fits (pin) | `… fits refinedtypes.hmod --build 0a875da` | *0a875da made for* | `sdk-fits.log` |
| fits (other build) | `… fits refinedtypes.hmod --build 0b14f8a` | *0b14f8a fits* | `sdk-fits-other.log` |
| content carry | `python3 tools/carry.py --check` | 575 files re-derived, 107 recipes, 2 skipped (reasons) | — |
| package gate | `verify-sdk-package.py refinedtypes` | **1/1** | — |

## In-game legs (`ports/_shared/evidence/refinedtypes-e2e/`)

| leg | result | log |
|---|---|---|
| modded pair (refinedstorage 0.2.2 + refinedtypes 0.1.3) | **PASS** + `EXIT:0` | `e2e.log` |
| control (same Nightly, no packages) | **FAIL** + `EXIT:1` — *the block at 44,64,0 is minecraft:air* | `e2e-control.log` |
| negative (inverted restore: the block must read 0, it reads 5000) | **FAIL** + `EXIT:1` — *NEGATIVE: the replaced block reads 5000/256000* | `e2e-negative.log` |
| selftest (flipped drain assertion) | **FAIL** + `EXIT:1` — *the disk was drained to 3004* | `e2e-selftest.log` |
| log gate | `check-e2e-logs.py refinedtypes-e2e --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` | — |

The 0.1.1/0.1.2 logs are kept under `retired-0.1.1/` and `retired-0.1.2/`.

## Re-run

```sh
# the ladder (each a separate lease)
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step test  -- bash -lc 'cd ports/refinedtypes && cargo test --offline'
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step lint  -- bash -lc 'cd ports/refinedtypes && cargo clippy --all-targets --offline -- -D warnings'
ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step build -- bash -lc 'cd ports/refinedtypes && rm -f Cargo.lock && cargo horizon-mod build'
# the game (two packages) and the leg
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step build -- bash -lc 'cd ports/refinedtypes && tools/build-game.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e   -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && tools/e2e.sh'
# the fail-capable legs
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && NEGATIVE=1 tools/e2e.sh'
BUILD_LOCAL=1 ports/tools/build-slot.sh run --job RT --port ports/refinedtypes --step e2e -- bash -lc 'cd ports/refinedtypes && eval "$(tools/build-game.sh env)" && GAME=$CONTROL_GAME tools/e2e.sh'
```

The recipe phase alone, against any running socket (a smoke run of the first N recipes):

```sh
python3 -u ports/refinedtypes/tools/recipe_check.py SOCK CTL 36 64 8 [N]
```
