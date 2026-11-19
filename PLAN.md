# Refined Types — slice 1 implementation plan

**Goal:** a flat SDK `.hmod` in which Refined Types' typed storage (FE, Source, Souls) exists on a
Refined Storage network: storage blocks add capacity to the component, storage disks live in the
parent's disk drives, the Network Energizer sustains the network from the energy storage, and
`/refinedtypes info` reports it.

**Architecture:** `src/runtime.rs` is the pure model (families, tiers, capacities, stores, the
network component, the energizer's accounting) with unit tests and no `mod_api` types.
`src/support.rs` is the glue: registration, block-entity payloads, the item component, the drive
interaction and the commands. `src/lib.rs` is the one `impl Hooks`.

**Tech stack:** Horizon mod API `0.2` at pin `0b14f8a` (mixins `e59da90`), Rust 2024, no
dependency but `horizon-mod-api`. **No `horizon-core`**: the launcher provides no `horizon_core`
extern (measured — `ports/_shared/evidence/refinedtypes-e2e/launcher-externs.md`), so compound
keys go through `Tag::compound([("key", Tag::Long(..))])` and `Tag::get(&str)`.

**Spec:** `notes.md` (jar inventory, slice boundary, gaps) — the plan argues from it.

## Global constraints

- Campaign pin `0b14f8acfd97fa2c750e42795249dcc981178ca4`, mixins
  `e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, game `26.3`, `api = "0.2"`.
- Class `content`, tier `machines`, role **add-on** (`ports/ledger.csv`). Do not exceed it: no
  renderers, no dimensions, no new vanilla hooks.
- Licence MIT (rank 0) read from the jar's `neoforge.mods.toml`; `LICENSE` and
  `LICENSE-NOTICE.md` travel inside the package.
- Every build/test step goes through `ports/tools/build-slot.sh`; never a bare `cargo` outside a
  lease, never `--target-dir`, `CARGO_INCREMENTAL=0`.
- No `//!`/`#![…]` in `support.rs` (`E_MODULE` at the retired planner is gone, but the campaign
  keeps the rule for its own modules' shape).
- Content: only what the jar ships. Recipes are **not** carried (they need
  `refinedstorage:machine_casing`, `c:dusts/redstone` and `neoforge:conditions`, none of which
  exist at 26.3) — recorded as a gap.

## Review focus

- **A network that is not connected to a controller must report nothing.** The walk is the
  parent's rule; an add-on node two blocks away from a cable is not on the network.
- **A store never reports more than its capacity and never goes below zero** — including the load
  path (`set_stored`) and the creative/infinite special cases.
- **The energizer never invents energy**: it draws from the network's energy storage, then its own
  1000 FE buffer, and reports `inactive` when neither covers the usage.
- **The drive's slots are the parent's**: an add-on disk goes into the first free slot in one
  transaction, leaves the hand, and the parent's own disk still behaves as before.
- **A disk's amount survives being read back**: the item component is written whenever the
  network takes or gives energy from a disk.

---

## Task 1 — the pure model (`src/runtime.rs`), tests first

**Files:** create `src/runtime.rs`; `src/lib.rs` gets `mod runtime;`.

**Interfaces (produces):** `Family`, `Capacity`, `Variant`, `IdKind`, `Store`, `Node`,
`Network`, `network`, `neighbours`, `Holding`, `Totals`, `totals`, `Energizer`, `Draw`,
`lookup`, `saved_amount`, `save_amount`.

- [ ] Write the failing tests (tier table, store clamping, creative/infinite, usage ladder,
      network walk, totals, energizer drain/cover, id round trip).
- [ ] Run them; confirm they fail for the missing items.
- [ ] Implement the minimum each test needs.
- [ ] Run; all green; then `cargo clippy --all-targets -- -D warnings`.

## Task 2 — the glue (`src/support.rs`)

**Files:** create `src/support.rs`; `src/lib.rs` wires `register`, `component_types`,
`block_entity_ticks`, `block_entity_tick`, `right_click_block`, `register_commands`,
`run_mod_command`, `server_started`, `world_lifecycle`.

- [ ] `register`: one block-entity type over the 31 block ids, its Part, nothing else.
- [ ] The Part: `block_entity` returns the saved payload; `block_entity_ticks` is true only for
      the energizer; `block_entity_tick` runs the energizer's tick.
- [ ] `component_types`: `refinedtypes:stored`.
- [ ] `right_click_block`: a refinedtypes disk onto a `refinedstorage:disk_drive` goes into the
      first free slot; the parent's own disk and every other click are left alone.
- [ ] `run_mod_command`: `info <pos>` and `insert <pos> <family> <amount>`.
- [ ] A world open resets the per-world cache; a close drops it.

## Task 3 — content (`assets/`, `data/`)

**Files:** `tools/carry.py` (carry + `--check`), generated `assets/refinedtypes/items/*.json`,
`data/refinedtypes/horizon/{block,item}/*.json`, carried `assets/refinedtypes/{blockstates,models,
textures,lang}`, `data/refinedtypes/{loot_table,tags}`, `data/minecraft/tags/block/mineable/…`.

- [ ] `tools/carry.py` reads the jar and writes each file, recording its origin.
- [ ] `tools/carry.py --check` re-derives every file and compares byte for byte; exit 1 on any
      difference, missing file or unexplained extra file.
- [ ] `LICENSE` + `LICENSE-NOTICE.md` inside the package.

## Task 4 — ladder

- [ ] `rm -f Cargo.lock`; `cargo test --offline`; `cargo clippy --all-targets --offline -- -D
      warnings`; `rustfmt --edition 2024 --check src/*.rs`.
- [ ] `cargo horizon-mod check`; `cargo horizon-mod build` twice → `cmp` identical;
      `cargo horizon-mod check refinedtypes.hmod`; `cargo horizon-mod fits refinedtypes.hmod
      --build 0b14f8a`.
- [ ] Copy the package to the port root.

## Task 5 — in-game leg

**Files:** `tools/build-game.sh` (the bundle: the parent fixture + this port), `tools/e2e.sh`,
`tools/parent-fixture.py`.

- [ ] `parent-fixture.py` copies `ports/refinedstorage` and applies the one documented patch (its
      `horizon-core` dependency cannot be built by the launcher; the rewrite is mechanical).
- [ ] `build-game.sh` builds the two-package game and exports it.
- [ ] `tools/e2e.sh`: the scenario, `PASS` + `EXIT:0`; `GAME=$CONTROL_GAME` → `EXIT:1`;
      `SELFTEST=1` → `FAIL` + `EXIT:1`.
- [ ] `python3 ports/tools/check-e2e-logs.py refinedtypes-e2e --strict` → 0.

## Task 6 — record

- [ ] `notes.md`: class+tier, jar inventory, the slice, gaps, deviations, the `Skills:` line and
      the verification table with the evidence paths.
- [ ] Evidence under `ports/_shared/evidence/refinedtypes/` and `…/refinedtypes-e2e/`.
