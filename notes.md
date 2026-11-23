# Refined Types — port notes

Ported from **Refined Types 1.21.1-0.3.2** (`refined-types-1.21.1-0.3.2.jar`, MIT, SHA-1 `ce9421742b454f0dbfc43bb99f315ac05e3d6ec0`, SHA-256 `2373c5b8f1309a43bc25bc0c8f4cfc1f3cb0b725ceafe89311aa74e3e75f7b0d`; upstream `starforcraft/Refined-Types`, branch `1.21.1`, commit
`6a53289a4f7582dfae719c3e8bb2c33c4913373a` = the jar's own version). Minecraft Java 1.21.1
NeoForge; the port targets Horizon **26.3** at the campaign pin
`0a875da91dbb0fdcb7ba8c42c11341aa229af51a` (+ mixins `e59da9094f0c2fdda6c627fe9eff22dec6a906f0`),
`api = "0.2"` (built at `0b14f8a` through 0.1.1, repinned for 0.1.2).

**Licence: MIT — rank 0 (permissive).** Read from the jar's `META-INF/neoforge.mods.toml`
(`license = "MIT"`) and the upstream `LICENSE.txt` (© 2025 Starforcraft). Local-only until the
maintainer approves publishing (ARCHITECTURE.md §8); publishable under MIT with this source.
`LICENSE` and `LICENSE-NOTICE.md` travel inside the package.

**Class + tier: `content` / `machines`, role add-on** (`ports/ledger.csv`; provenance
`ports/_shared/source-map/atm10-sources.csv` — `starforcraft/Refined-Types`). The shape from
`horizon/docs/modpacks.md` §"Tiers" is machines: block entities with saved state, a capability's
worth of typed storage, and a node that does work per tick. No renderer, no dimension, no entity.
It is an **add-on**: its parent `refinedstorage` is `ported-partial` (controller, cable, disk
drive, 1k disk, grid), and this port is written against that port's network, disk-drive slots and
disk-item component conventions.

## What the jar actually ships (the artefact, not the name)

"Refined Types" reads like a type filter. It is **typed storage for three resource types that
Refined Storage does not store itself** — the jar's own description says so: *"addon for Refined
Storage which adds FE, Source and Souls Storage Disks"*. The inventory:

| Family | Tiers | Parts | Disks | Blocks |
|---|---|---:|---:|---:|
| Energy (FE) | 64k, 256k, 1024k, 8192k, 65536k, 262144k, 1048576k, 8388608k, infinite, creative | 9 (no creative part) | 10 | 10 |
| Soul | 1k, 8k, 64k, 512k, 4096k, 32768k, 262144k, 2097152k, infinite, creative | 9 | 10 | 10 |
| Source (Ars Nouveau) | 64b, 256b, 1024b, 8192b, 65536b, 262144b, 1048576b, 8388608b, infinite, creative | 9 | 10 | 10 |
| — | — | — | — | 1 Network Energizer |

88 item models, 31 blockstates, 35 block models, 112 textures, one `en_us.json`, three item tags
(`*_storage_disks`), one `minecraft:mineable/pickaxe` block tag, 32 block loot tables, 111
recipes (28 disk + 28 block + 55 part) and their advancement unlocks. Code: 128 classes in
`storage/`, `type/`, `grid/`, `exporter/`, `importer/`, `externalstorage/`, `autocrafting/`,
`networkenergizer/`, `storagemonitor/`, `compat/{jei,emi}`.

Capacities, read from `storage/{energy,soul,source}/*StorageVariant.java`:

- energy: `k × 1000` (64k = 64,000 FE … 8388608k = 8,388,608,000 FE); `infinite` = unbounded;
  `creative` = unbounded and always full (`CreativeStorageImpl`: stored `Long.MAX_VALUE`, extract
  any amount, never decreases).
- source: `b × Platform.getBucketAmount()`; RS2's NeoForge `PlatformImpl.getBucketAmount()` is
  `FluidType.BUCKET_VOLUME` = **1000**, so 64b = 64,000 and 8388608b = 8,388,608,000.
- soul: `k × 1024` (1k = 1,024 … 2097152k = 2,147,483,648).
- Energy usage per storage block, from `Config.java` defaults: 2, 4, 6, 8, 10, 12, 14, 16, 18 for
  the eight finite tiers and `infinite`; `creative` = 0. The three families use the same ladder.
- Network Energizer: a 1000 FE internal buffer (`EnergyStorageImpl(1000)`, filled at construction),
  an `EnergyProvider` that extracts the network's energy resource (the energy disks' storage) to
  keep the network supplied, `getCapacity()` = `Long.MAX_VALUE`, `getEnergyUsage()` = 0.

## The slice (this version, 0.1.1)

The mod's own purpose is "store FE / Source / Souls on a Refined Storage network". That is what
this slice implements, on the parent port's network:

1. **The three families' storage blocks and disks exist** (all 30 blocks + 30 disks + 27 parts,
   content carried from the jar) and register a block entity that holds a typed amount.
2. **A storage block on the network adds its tier's capacity and its stored amount** to the
   network's total for its family. It costs its configured energy usage per tick.
3. **A storage disk in the parent's disk drive is network storage too.** The add-on accepts its
   own disks where the parent's drive only accepts the parent's: right-clicking a refinedtypes
   disk onto a `refinedstorage:disk_drive` puts it in the first free slot and takes it from the
   hand. The disk's amount lives in its item component (`refinedtypes:stored`), so it travels with
   the item exactly as the parent's 1k disk does.
4. **The Network Energizer** keeps the network supplied: each tick it draws the add-on nodes'
   total energy usage from the network's energy storage (energy disks and blocks), falling back to
   its 1000 FE buffer, and sets its `active` block state from whether the usage was covered.
5. **`/refinedtypes info <pos>`** prints the network: node census, per-family `stored/capacity`,
   the usage, and the energizer's buffer and state. **`/refinedtypes insert <pos> <family>
   <amount>`** deposits into the network's typed storage (the stand-in for the typed grid, see
   deviations).

## Hooks

| Hook (API 0.2) | Method | What it does |
|---|---|---|
| `register` | `Hooks::register(&self, &mut dyn Registrar, &RegistrationContext)` | one block-entity type over the 31 block ids + its Part |
| `component_types` | `Hooks::component_types` | `refinedtypes:stored`, the disk's amount |
| `block_entity` | `BlockEntityPart::block_entity` | a block's saved payload (`{Amount}`) |
| `block_entity_ticks` | `BlockEntityPart::block_entity_ticks` | only the energizer ticks |
| `block_entity_tick` | `BlockEntityPart::block_entity_tick` | the energizer's tick: usage, draw, `active` |
| `block_drops` | `Hooks::block_drops` | a broken storage block's amount onto its own item (slice 3) |
| `on_block_placed_by` | `ItemPart::on_block_placed_by` | the placed item's amount, clamped, into the block (slice 3) |
| `right_click_block` | `Hooks::right_click_block` | a refinedtypes disk onto the parent's drive |
| `screen` | `BlockEntityPart::screen` | the energizer's 176×189 menu layout (slice 4) |
| `screen_draw` | `BlockEntityPart::screen_draw` | the energy bar, from the menu's data slots (slice 4) |
| `screen_tooltip` | `BlockEntityPart::screen_tooltip` | the stored amount under the cursor over the bar (slice 4) |
| `register_commands` | `Hooks::register_commands` | `/refinedtypes info|insert|menu` |
| `run_mod_command` | `Hooks::run_mod_command` | their bodies |
| `server_started` | `Hooks::server_started` | a world opened: drop the per-world cache |
| `world_lifecycle` | `Hooks::world_lifecycle` | a failed/closed world drops it too |

## Deviations (deliberate, each measured or forced by the pin)

1. **No typed grid, exporter, importer, external storage or autocrafting.** Upstream those are
   Refined Storage API integrations (`GridResourceFactory`, `StorageNetworkComponent`,
   `ExternalStorageProvider`, `PatternProviderExternalPatternSink`). A Horizon mod cannot call
   another mod's Rust API, and the parent port's grid is item-only (its own gap 2). The typed
   *storage* is what the mod is for, and it works; the transfer surfaces are the gap.
   `/refinedtypes insert` is the deposit stand-in — the same shape as the parent's
   `/refinedstorage filter` stand-in for the client search box.
2. **The parent has no energy model** (`ports/refinedstorage/notes.md` gap 1: the controller
   consumes nothing). So the add-on charges **its own** nodes' usage: the network's energy need is
   the sum of the refinedtypes storage blocks' configured usage, and the energizer meets it from
   the network's energy storage. The parent's nodes cost 0. Upstream the whole network's usage is
   charged; this port cannot charge what the parent does not model, and says so instead of
   pretending.
3. ~~**A storage block's amount does not survive being broken.**~~ **Done in 0.1.3** (`## Slice 3`):
   the block's own item carries the amount as `minecraft:block_entity_data` and the placement Part
   clamps it back, upstream's `AbstractStorageContainerBlockItem` contract. The Network Energizer's
   buffer is not carried (the gap line names the storage block).
4. ~~**No storage-block or energizer menu/screen.**~~ **Done in 0.1.4** (`## Slice 4`): the
   energizer's menu and screen, which is the mod's only menu (the jar has one
   `NetworkEnergizerContainerMenu`; the storage blocks have none upstream either, so this line's
   earlier "upstream each opens a menu" was wrong and is corrected in the slice's record). A mod
   menu at this pin needs a `Screen` layout and a `ModContainer` — and, as the slice measured,
   a block template whose class opens a menu.
5. **No config file.** The usage ladder and the capacities are constants read from the upstream
   defaults; a Horizon mod's config dir exists (API 26) but a config UI is out of this tier.
6. **Creative/infinite** are modelled as the upstream classes do (creative: always full, extract
   any amount; infinite: unbounded, grows on insert), not as a huge finite number.
7. **The network rule is re-read, not shared.** The add-on walks the same face-adjacent component
   over the parent's four block ids plus its own 31, because the parent's walk is internal to its
   crate. The parent's cable only draws connections to *its* four blocks, so a refinedtypes block
   beside a cable is on the add-on's network but not in the parent's cable state — a cosmetic
   difference, recorded.

## Gaps

1. Typed grid / exporter / importer / external storage / autocrafting / storage monitor insertion
   (see deviation 1).
2. ~~Recipes: **not carried**.~~ **Done in 0.1.2** (`## Slice 2` below). The parent's chain landed
   (`machine_casing`, the processors, `storage_housing`, `1k_storage_part`, plus the `c:` tags), so
   107 of the jar's 109 recipes are carried and crafted in game. Two still cannot load at this pin
   and stay blocked: `network_energizer` (needs `refinedstorage:interface`, the parent's gap 2) and
   the source chain's root `64b_source_storage_part` (needs `ars_nouveau:magebloom_fiber`; Ars
   Nouveau is not ported, so the source branch is reachable only with a creative-given part).
3. ~~The block item does not carry the block's amount (deviation 3).~~ **Done in 0.1.3**.
4. ~~Menus and screens (deviation 4).~~ **Done in 0.1.4** (`## Slice 4`): the energizer's menu
   and screen; the storage blocks have no menu upstream either.
5. The energizer does not refill its buffer from the network once drained (upstream does not
   either: the buffer is a load-time kick-start), and the network is not shut down when unpowered
   (the parent has no such state) — the storage stays readable, `active` says whether the usage
   was covered.
6. Source and Soul have no consumer at this pin (no exporters, and Ars Nouveau / the soul mod are
   not ported), so their role is capacity, totals and usage.
7. A storage block beside a cable does not appear in the parent's cable connection state
   (deviation 7).
8. The disks and blocks are not `fireResistant` as upstream declares them (`Item.Properties
   .fireResistant()`): the declaration template does not name a component for it, and an
   unverified component would be worse than the omission.

## Upstream source analysis

Repository `https://github.com/starforcraft/Refined-Types`, branch `1.21.1`, commit
`6a53289a4f7582dfae719c3e8bb2c33c4913373a` (2026-05-21, `modVersion=1.21.1-0.3.2` — the jar's
version). Clone: `ports/_shared/upstream/refinedtypes/` (gitignored). Files read:

- `storage/{energy,soul,source}/{*StorageVariant,*StorageDiskItem,*StorageBlockProvider,
  *StorageBlockBlockItem}.java` — the tier tables, capacities, the disassembly byproducts, the
  block item's place/break contract;
- `storage/CreativeStorageImpl.java`, `storage/ImprovedSameTypeStorageType.java` — creative and
  same-type storage semantics;
- `networkenergizer/*` — the node's buffer, `getStored`/`extract`, the `active` block state, the
  menu data;
- `type/Type.java`, `type/TypeStack.java`, `type/*/{*Resource,*ResourceType,*CapabilityCache,
  *ExtractableStorage,*InsertableStorage}` — the resource keys and the storage adapters;
- `Config.java` — the usage defaults per tier and family;
- `registry/{Blocks,Items,BlockEntities,Menus,Tags,Types}.java`, `ModInitializer.java` — what is
  registered and how;
- `grid/*`, `exporter/*`, `importer/*`, `externalstorage/*`, `autocrafting/*`,
  `storagemonitor/*`, `compat/{jei,emi}/*` — the integration half, read to bound the gap.

Where the rewrite differs: the storage is a block entity payload and an item component (the
parent port's convention) instead of RS's world-level `StorageRepository` keyed by UUID; the
energy accounting is the add-on's own (deviation 2); the network walk is the parent's rule
re-read (deviation 7). No Java was translated: the numbers and the contract come from the files
above, the code is new.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## Verification

Pin **`0b14f8acfd97fa2c750e42795249dcc981178ca4`**, mixins
**`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, game 26.3, launcher 0.2.78, Nightly
`nightly-2026-11-18-0b14f8a`. Every Rust step ran through `ports/tools/build-slot.sh`
(`BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0`, no `--target-dir`); the in-game leg ran in one
`build-slot.sh run --step e2e` lease.

| Step | Command | Result |
|---|---|---|
| runtime tests, red first | `cargo test --offline` before the model existed | **163 errors** (`cargo_exit: 101`) — the API was missing, not the tests (`evidence/refinedtypes/runtime-red.log`) |
| runtime + glue tests | `cargo test --offline` | **21 passed**, 0 failed (`evidence/refinedtypes/ladder-final.log`) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings |
| format | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean (not `cargo fmt --all`: it reaches into `.horizon/sdk`) |
| SDK gate | `cargo horizon-mod check` | exit 0 — *"Refined Types uses 257 items of the API (4 Part kinds, 1 associated item, 1 capability, 50 fields or variants, 9 hooks, 13 hook arguments, 2 macros, 87 methods, 18 traits, 72 types). Made for 0b14f8a."* |
| package | `rm -f Cargo.lock` before each; `cargo horizon-mod build` twice, `cmp` | **245,100 B**, SHA-256 `9dcbbd3af28e7578e383858352d6f3ce3b8762470132857bd95cf2b15b264606`, **474 entries**, second build byte-identical |
| package check | `cargo horizon-mod check refinedtypes.hmod` | exit 0 — *"refinedtypes 0.1.1 (native-mod, format native-1/0b14f8a…/e59da90…, for 26.3) 245100 bytes, SHA-256 9dcbbd3a…, unsigned"* |
| fits | `cargo horizon-mod fits refinedtypes.hmod --build 0b14f8a` | exit 0 — *"0b14f8a made for"* |
| content carry | `python3 tools/carry.py --check` | **468 files** re-derived and compared byte for byte; 221 jar files (the recipes and their advancements) deliberately left out; nothing unexplained |
| in-game (modded) | `build-slot.sh run --step e2e -- tools/e2e.sh` — the game carries the **real** `refinedstorage` 0.2.1 beside this port | **PASS** + `EXIT:0` (`evidence/refinedtypes-e2e/e2e.log`) |
| in-game (control) | `GAME=$CONTROL_GAME tools/e2e.sh` | **FAIL** + `EXIT:1` — *"the block at 44,64,0 is minecraft:air"*, the first assertion (`…/e2e-control.log`) |
| fail proof | `SELFTEST=1 tools/e2e.sh` | **FAIL** + `EXIT:1` — *"SELFTEST: the disk was drained to 2998, so the assertion is alive"* (`…/e2e-selftest.log`) |
| e2e artefact gate | `python3 ports/tools/check-e2e-logs.py refinedtypes-e2e --strict` | `logs=3 ok=3 missing-exit=0 bad-exit=0`, exit 0 |
| package gate | `python3 ports/tools/verify-sdk-package.py refinedtypes` | **1/1** — package, runtime byte-identical, `no packed Cargo.lock  474 entries`, tests 21, clippy 0, check, fits, skills gate |

The `check` prints one compatibility note — *"`Block`: built field by field (src/support.rs:221)"*
— about the port's own `Found`/`Site::Block` literal, not an SDK type; `check` and `fits` both
exit 0.

**No `Cargo.lock` in the package (packaging fix, 2026-11-19).** The first artifact carried the
8,833-byte lock that `cargo test` had generated in the port (247,437 B, `ae50e446…`, 475
entries) and failed the orchestrator's `verify-sdk-package.py` gate on that one point. The lock
is build output: `rm -f Cargo.lock` before the build, `cargo horizon-mod build` (which does not
regenerate it — the SDK crates are path dependencies), and the package is 245,100 B / `b94fd6bf…`
/ 474 entries with `no packed Cargo.lock` ok. Only the lock left: the launcher compiles the
port's `src/`, so its build was reused unchanged (`native-0b14f8a-26375509d48a`, the same
`librefinedtypes.so`) and the three in-game legs were re-run against it — `PASS`/`EXIT:0`,
control `EXIT:1`, selftest `EXIT:1`, `--strict` 3/3.

**0.1.1 (2026-11-19): the parent, not the fixture.** The same package, rebuilt with
`ports/refinedstorage` 0.2.1 as the leg's other half and the fixture deleted: **245,100 B**,
SHA-256 `9dcbbd3a…`, 474 entries, `rm -f Cargo.lock` before each of two builds, byte-identical,
`check`/`fits` exit 0, `verify-sdk-package.py` **1/1**.

### In-game scenario (`tools/e2e.sh`)

The game carries **two** packages, both the shipped ones: `ports/refinedstorage` 0.2.1 and this
port. The End arena at y=63; the network at y=64:

```
controller 40 - cable 41 - disk drive 42 - network energizer 43 - 64k energy block 44 -
64k soul block 45
```

Quoted from `e2e.log`:

```
block(44,64,0): refinedtypes:64k_energy_storage_block
block(45,64,0): refinedtypes:64k_soul_storage_block
block(43,64,0): refinedtypes:network_energizer[active=true]
info(43,64,0): Refined Types network at 43,64,0: online (2 storage, 1 energizer, 1 controller, 1 drive, 0 grid); energy 0/64000; soul 0/65536; source 0/0; usage 8 FE/t; energizer 830/1000 active
info(43,64,0): … energizer 0/1000 inactive                       (after 200 ticks on the buffer)
block(43,64,0): refinedtypes:network_energizer[active=false]
deposit: Deposited 5000 energy; the network now holds 5000/64000.
energy just after the deposit: 4968
block(43,64,0): refinedtypes:network_energizer[active=true]
energy after 100 ticks: 4136                                     (8 FE/t: the two storage blocks)
info(43,64,0): … (1 storage, …); energy 4080/64000; soul 0/0; usage 2 FE/t; …   (the soul block broken)
deposit with no storage: The network took 0 of 4000 energy; it now holds 0/0.
drive: [{"count":1,"item":"refinedtypes:64k_energy_storage_disk"}]
deposit into the disk: Deposited 4000 energy; the network now holds 4000/64000.
info(43,64,0): … (1 storage, …); energy 3928/64000; soul 0/65536; usage 6 FE/t; …
energy after 150 ticks: 3004                                     (the disk drained and written back)
info(43,64,0): … offline (1 storage, 1 energizer, 0 controller, 1 drive, 0 grid); energy 0/0; …   (controller broken)
deposit while offline: The network is offline: it has no controller.
info(43,64,0): … online (…); energy 2692/64000; …                (controller back: the disk kept it)
energy after the controller came back: 2668 (was 3004 offline)
PASS: … EXIT:0
```

The controls are inside the scenario: the **buffer** (a network with nothing stored is powered
only by the energizer's 1000 FE and goes inactive when it is gone), the **nodes** (breaking the
soul block drops the usage from 8 to 2 FE/t), the **empty network** (a deposit with no energy
storage is refused), the **offline network** (a broken controller: totals 0, deposits refused,
the disk keeps its amount), and the **parent's drive** (the disk only becomes storage once it is
in a slot the parent owns).

### The parent: found broken, now fixed, and the fixture is gone (2026-11-19)

When this port was built, `ports/refinedstorage` declared a second SDK path dependency
(`horizon-core`, added for `JavaString`) and the launcher provides **no `horizon_core` extern**,
so `native-build` failed on it with `error: No such file or directory (os error 2)` — measured,
and reproduced on a working port by adding that one line
(`ports/_shared/evidence/refinedtypes-e2e/launcher-externs.md`). The leg therefore ran a patched
copy of the parent, produced by `tools/parent-fixture.py` (8 exact replacements).

The parent is now **0.2.1** with that dependency gone, and it installs and has its own green
in-game leg. So:

- `tools/parent-fixture.py` is **deleted**, and so is the copy it wrote
  (`ports/_shared/evidence/refinedtypes-e2e/parent/`). `tools/build-game.sh` bundles
  `ports/refinedstorage` **unchanged** beside this port; it still refuses a parent whose
  `Cargo.toml` names `horizon-core`, so a regression fails with a sentence instead of a launcher
  error.
- The scenario was re-run against the real pair with **no change to the scenario or to any
  assertion**, and every assertion passed for the same reason and with the same numbers: the disk
  goes into the parent's drive (`drive: [{"count":1,"item":"refinedtypes:64k_energy_storage_disk"}]`),
  the network reports it (`energy 0/64000` from the disk alone), the energizer drains it
  (`4000 → 3004` in 150 ticks) and the offline/online pair reads `energy 0/0` then `2692`. **No
  assertion needed the fixture.**
- `launcher-externs.md` stays as the measurement that led to the parent's fix (its consequence-1
  paragraph is history, kept because it names the exact failure a regression would show).

### Deviations from the brief's command shape

- The in-game leg builds through `tools/build-game.sh`, not `ports/tools/launcher-game.sh build
  refinedtypes`: that wrapper passes one port directory, and this port cannot run without the
  parent. The launcher accepts a folder of packages, so the script bundles the two shipped
  packages (`ports/refinedstorage` and this port), then does what the wrapper does after a build
  (export the version out of the managed folder).
- The e2e runs as `build-slot.sh run --job … --step e2e`, not `build-slot.sh e2e`: the `e2e`
  subcommand wraps the retired `tools/horizon.py build` ladder, which an SDK port has no
  `horizon.py` for (measured: `python3: can't open file …/tools/horizon.py`).

## Slice 2 — the recipe family, every carried recipe crafted in game (2026-11-21) — version 0.1.2

Gap line this slice answers — §Gaps item 2: *"Recipes: **not carried**. Every recipe needs
`refinedstorage:machine_casing` … The 111 recipes and their advancement unlocks would be dead
data."* The parent's slice 2 (2026-11-21, 0.2.2) landed the chain and the `c:` tags, so the first
blocker is gone. This is the parity rule's sharpest case: a carried recipe that is never crafted
is dead data, and until this slice the 30 blocks and 30 disks were creative-only.

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`**, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, launcher 0.2.92, game 26.3. Class `content`, tier
**machines**, unchanged: recipes are data-tier *content*, so this slice adds a family below the
tier and cannot exceed it. No new pin API and no third-party mod (`refinedstorage` is the
required parent).

`src/` changes in one place only: the local `Site::Block` variant is renamed `Site::Storage`
(`src/support.rs`) because `fits --build 0b14f8a` matched the name `Block` to a surface type and
reported *"the type `Block` can no longer be built with a literal"* — the false positive HANDOVER
§9d item 14 records. The runtime is otherwise untouched (`runtime.rs` byte-identical in the
package). This is a mechanical carry, so the red proofs are the carry check, the dialect check
and the in-game leg against the previous package, not a new Rust unit test.

### What was carried (from `refined-types-1.21.1-0.3.2.jar`, MIT)

| family | carried |
|---|---|
| recipes | **107** of the jar's **109** (the inventory's earlier "111" was an estimate; the jar has 27 block + 27 disk + 54 part-dir + 1 energizer): 27 block recipes, 27 shaped disk recipes, 27 shapeless `storage_housing` disk recipes, 26 part recipes |
| shape | 26.3 dialect: one bare id or one `#tag` per ingredient, no `neoforge:conditions`, no `category`, `count` only when != 1 — derived by `tools/carry.py`, not hand-written |
| tags | the three the recipes name (`c:glass_blocks`, `c:dusts/redstone`, `c:silicon`) are declared by the **parent** (a required dependency); `carry.py --check` fails if it stops declaring them |
| loot tables | the 31 carried tables normalized to 26.3's own shape (`no bonus_rolls`, integral `rolls`), proven by the in-game drop differential below |
| not carried | `network_energizer` (`refinedstorage:interface` absent from the parent) and `part/64b_source_storage_part` (`ars_nouveau:magebloom_fiber`; namespace not ported) — both printed with the reason by `tools/carry.py`; the 112 advancement unlocks (recipe-book listing only, no gameplay) |

The soul recipes carry upstream's `neoforge:mod_loaded: industrialforegoingsouls` condition
**dropped**: 26.3 has no loader conditions (an unknown one drops the file) and the recipe's own
ingredient is `minecraft:sculk`, which exists. The gate only told upstream's datagen "the same pack
also has the soul mod"; this port ships soul storage without it, so the recipe is carried ungated.

### Red proofs (before the fix)

1. **The dialect the jar ships** — `ports/tools/check_261_dialect.py` on the jar's raw recipes:
   `data shape: 109 offender(s) in 109 recipe/loot file(s)`, every one
   `minecraft:crafting_shaped ingredient(s) in the 1.21.1 object form:
   {"item": "minecraft:redstone_block"}, …` (`red-dialect-jar-recipes.log`, exit 1).
2. **The family absent from the package** — `python3 tools/carry.py --check` before the conversion
   wrote anything: **107** × `FAIL: missing: data/refinedtypes/recipe/…`
   (`red-carry-check-0.1.1.log`, exit 1).
3. **The previous package in game** — the new driver (reading the 107 new recipes) against the
   delivered 0.1.1 + refinedstorage 0.2.1 at `0b14f8a`:
   ```
   FAIL: no refinedstorage:machine_casing in the inventory to place
     1024b_source_storage_block -> None x0
   FAIL: 1024b_source_storage_block: expected refinedtypes:1024b_source_storage_block x1, got None x0
   ```
   `EXIT:1` (`evidence/refinedtypes-e2e/e2e-red-recipes-0b14f8a.log`).

A static shadow check compared all 80 shaped and 27 shapeless carried recipes against the 827
shaped / 375 shapeless vanilla 26.3 recipes by resolved ingredient set: **0 candidate collisions**,
so no carried grid is shadowed by a vanilla one (the in-game craft asserts the result id anyway).

### Green — the in-game leg (one slot lease, `tools/build-game.sh` at `0a875da`)

The game carries the two shipped packages (`ports/refinedstorage` 0.2.2 and this port);
`build-game.sh` printed `Compiling refinedstorage (1 of 2)` / `Compiling refinedtypes (2 of 2)`
(the manifest bump to 0.1.2 is what forced the second line).

```
== the crafting chain: every carried recipe crafts in game ==
recipe PASS: 107 of 107 carried recipes craft in game with their declared output and count,
             their ingredients are consumed, 107 wrong-ingredient controls leave the result
             empty, the carried table is 107, and an unknown id is refused
== a storage block drops itself with the tool its tag declares, and not without ==
  bare hand: {"drops":{},"items_left_on_ground":0}
  pickaxe: {"drops":{"refinedtypes:256k_energy_storage_block":1},"items_left_on_ground":1}
…
PASS: … all 107 carried recipes craft in game with their declared output and count (each with a
      wrong-ingredient control), and a storage block drops itself for a pickaxe and not for a
      bare hand
EXIT:0
```

The driver (`tools/recipe_check.py`) reads **this package's** `data/refinedtypes/recipe/**`: a
recipe the conversion dropped makes the count assertion fail, and a recipe the game rejected
fails its craft. Per recipe: the result slot's **id and count**, a shift-click leaving the 3×3
grid empty (ingredients consumed) and the crafted stack in the inventory, and a counterfactual
with one ingredient cell replaced by a non-ingredient. The block-drop leg is the loot table's
differential: `requires_tool` + `#minecraft:mineable/pickaxe` drops for a pickaxe and nothing for
a bare hand.

| Step | Command | Result |
|---|---|---|
| runtime + glue tests | `cargo test --offline` | **21 passed**, 0 failed (`evidence/refinedtypes/sdk-test.log`, sha in the header) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** (`sdk-clippy.log`) |
| formatting | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean |
| SDK check | `cargo horizon-mod check` | *"…257 items of the API (… 9 hooks …). Made for 0a875da."* |
| package | `rm -f Cargo.lock && cargo horizon-mod build` ×2 | **byte-identical** (`cmp`), **283,949 B**, SHA-256 `5360468e99254658545ba986e0ec12fde04b4ab738a997121d66d5726cfbca34`, **581 entries**, no `Cargo.lock` |
| package check | `cargo horizon-mod check refinedtypes.hmod` | `0.1.2 (native-mod, format native-1/0a875da…/e59da90…, for 26.3) 283949 bytes` (`sdk-check.log`) |
| fits (pin) | `… fits refinedtypes.hmod --build 0a875da` | *"0a875da made for"* (`sdk-fits.log`) |
| fits (other build) | `… fits refinedtypes.hmod --build 0b14f8a` | *"0b14f8a fits"* (`sdk-fits-other.log`) — the one that proves something |
| dialect gate | `python3 ports/tools/check_261_dialect.py refinedtypes.hmod` | exit 0 — `138 recipe/loot file(s), every one in the 26.3 dialect` |
| content carry | `python3 tools/carry.py --check` | **575 files** re-derived byte for byte; 107 recipes; 2 skipped with the reason; 112 advancements left out |
| launcher build | `tools/build-game.sh` | exit 0, `Compiling refinedtypes (2 of 2)`, `native-0a875da-15b9b9794d13` |
| in-game leg | `build-slot.sh run --step e2e -- … tools/e2e.sh` | **PASS** + **`EXIT:0`** (`evidence/refinedtypes-e2e/e2e.log`) |
| in-game red | the same driver against 0.1.1/0.2.1 at `0b14f8a` | **FAIL** + **`EXIT:1`** (`e2e-red-recipes-0b14f8a.log`) |
| control (same Nightly, no packages) | `GAME=$CONTROL_GAME tools/e2e.sh` | **FAIL** + **`EXIT:1`** — *"the block at 44,64,0 is minecraft:air"* (`e2e-control.log`) |
| selftest (flipped drain assertion) | `SELFTEST=1 tools/e2e.sh` | **FAIL** + **`EXIT:1`** — *"SELFTEST: the disk was drained to 2998"* (`e2e-selftest.log`) |
| log gate | `check-e2e-logs.py refinedtypes-e2e --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` |
| package gate | `verify-sdk-package.py refinedtypes` | **1/1** |

### Coverage (parity rule) — every family this port ships

| family | state |
|---|---|
| 27 block recipes | **tested** — crafted, output id + count, ingredients consumed, counterfactual (`recipe_check.py`) |
| 27 shaped disk recipes | **tested** — same driver |
| 27 shapeless `storage_housing` disk recipes | **tested** — same driver (shapeless path) |
| 26 part recipes | **tested** — same driver |
| `network_energizer` recipe | **blocked(`refinedstorage:interface`)** — the parent does not ship the interface (its gap 2); the block itself is given in game and asserted in the network legs |
| `64b_source_storage_part` recipe | **blocked(`ars_nouveau:magebloom_fiber`)** — Ars Nouveau is not ported; the source branch's 35 other recipes are carried and crafted from a creative-given part |
| the three `c:` tags | **tested** — `#c:glass_blocks`, `#c:dusts/redstone`, `#c:silicon` each resolve in a crafted recipe, and a non-member in the cell yields no result |
| 31 block loot tables | **tested** — differential: `256k_energy_storage_block` drops itself for a pickaxe (`drops: {…:1}`) and not for a bare hand (`drops: {}`) |
| 112 advancement unlocks | **not ported** — recipe-book listing only, no gameplay at this pin (the parent skipped its own) |
| unknown ids | **tested** — `give refinedtypes:no_such_item` refused, `setblock … refinedtypes:no_such_block` leaves air |
| typed grid / exporters / importers / external storage / autocrafting / storage monitor | **not ported** — §Gaps item 1, unchanged (parent-API integrations a Horizon mod cannot call) |
| block item carries the block's amount (slice 3) | **tested** — 5,000 in → break → the drop's `data get entity @s SelectedItem` carries `block_entity_data` with `Amount: 5000L` → place → `5000/256000`; a fresh item places `0/256000`; a doctored `999999999` clamps to `256000`; the inverted assertion is red under `NEGATIVE=1` |
| menus/screens; fire resistance; cable state | **not ported** — §Gaps items 4–8, unchanged |

### Deviations and traps (this slice)

1. **The jar ships 109 recipes, not 111.** Counted from the jar (`recipe/blocks` 27, `recipe/disk`
   27, `recipe/part` 54, one energizer). The earlier inventory was an estimate; the artefact wins.
2. **Two recipes are dropped, not faked.** A recipe naming an id no package declares cannot load
   at 26.3; carrying it would ship a file the game rejects and a player would see an uncraftable
   item with no error. `tools/carry.py` derives the skip from the data (not from a filename list)
   and prints the reason; the driver's count assertion makes a silent drop impossible.
3. **The soul recipes' loader condition is dropped, not the recipe.** The condition's ingredient
   (`minecraft:sculk`) exists at 26.3; only the `neoforge:conditions` block is unsupported.
4. **The `Site::Block` → `Site::Storage` rename** is a false-positive fix for `fits` (HANDOVER §9d
   item 14), not a behaviour change: 21 unit tests and every e2e assertion are unchanged.
5. **A stop-and-go:** the first in-game attempt ran the driver with buffered stdout, so the
   e2e-guard saw no output for 900 s and killed the leg (`EXIT:124`); the fix is `python3 -u`.
   The second attempt lost the pickaxe to the give-then-select tick boundary (HANDOVER §9c: `ctl
   give` lands on the next tick) — `ctl wait 4` between them, and the drop is asserted from the
   `ctl break` reply's `drops` field rather than from the inventory, because the item can land
   1.8 blocks away outside pickup range.

## Slice 3 — the storage block's item carries its amount (2026-11-22) — version 0.1.3

Gap line this slice answers — §Gaps item 3 / deviation 3: *"A storage block's amount does not
survive being broken. … `block_drops` + an `ItemPart` placement hook are the missing halves."*
Class `content`, tier **machines**, unchanged: a block entity's saved amount riding on its own
item is machines-tier state, and this adds no menu, renderer, third party or pin API. Pin
**`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`**, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`.

### The shape (HANDOVER §9m, and the three proven ports)

- `block_drops` runs **before** the removal, so `level.block_entity_data(entity)` is the pre-break
  snapshot with `Amount` still in it. The payload is built **fresh** from the amount
  (`{id: "refinedtypes:node", Amount}`) instead of copied from the snapshot — this block declares
  no container, so nothing spills, but a snapshot copy could carry keys this slice never named.
- Carrier: vanilla's `minecraft:block_entity_data`, the same component powah 0.2.7 carries a
  machine buffer in. The payload carries no `Items` (the rule rftoolsstorage 0.2.4 and
  functionalstorage 0.2.1 paid for).
- `block_drops` runs with a read-only `LevelHost`, which cannot name a drop's item, so the 31
  block→item keys are resolved once in `register` (powah's `remember_item` table).
- Placement is `ItemPart::on_block_placed_by`: read the item's payload, clamp to the placed
  tier and merge `{Amount}` into the block entity. This is also **the clamp**: the engine's own
  `block_entity_item::place` merges `block_entity_data` only through `canonical()`, which answers
  `None` for a mod type id, so the Part is the only path a mod block entity's amount comes back by.
- The rule is pure in `runtime.rs`: `carried(capacity, stored) -> Option<u64>` (what the drop
  names: `None` for an empty finite/infinite store, `CREATIVE_STORED` for creative) and
  `restored(capacity, asked) -> u64` (the placement clamp).

### Red → green

The tests came first (verbatim from `evidence/refinedtypes/red-slice3-blockitem.log`):

```
error[E0425]: cannot find function `carried` in this scope
   --> src/runtime.rs:919:20
error[E0425]: cannot find function `restored` in this scope
   --> src/runtime.rs:940:20
error[E0425]: cannot find function `carried_patch` in this scope
   --> src/support.rs:676:21
error: could not compile `refinedtypes` (lib test) due to 12 previous errors
```

Then the glue; **25 tests pass** (21 + 4): `a_broken_block_carries_what_it_held_and_an_empty_one_carries_nothing`,
`a_carried_amount_is_clamped_to_the_tier_it_is_placed_as`,
`a_carried_payload_names_the_block_entity_type_and_the_amount_only`,
`a_payloads_amount_is_read_from_any_integer_tag_a_player_may_write`.

### In-game (one `build-slot.sh run --step e2e` lease per leg)

Two one-block-deep networks with **no energizer** (nothing draws, so the read-back is exact):
controller 50 / cable 51 / 256k block 52, and controller 54 / cable 55 / block 56. Quoted from
`e2e.log`:

```
== slice 3: a storage block's own item carries the amount it held ==
  block(52,64,0): refinedtypes:256k_energy_storage_block
  info(50,64,0): … online (1 storage, 0 energizer, 1 controller, 0 drive, 0 grid); energy 0/256000; …
  deposit: Deposited 5000 energy; the network now holds 5000/256000.
  block saved data: {"chat":["52, 64, 0 has the following block data: 5000L"],"ok":true}
  break: {"block":"minecraft:air","drops":{"refinedtypes:256k_energy_storage_block":1},"picked_up":{"refinedtypes:256k_energy_storage_block":1}}
  dropped item: {"chat":["… {components: {\"minecraft:block_entity_data\": {Amount: 5000L, id: \"refinedtypes:node\"}}, count: 1, id: \"refinedtypes:256k_energy_storage_block\"}"],"ok":true}
  placed refinedtypes:256k_energy_storage_block at 52,64,0
  info(50,64,0): … energy 5000/256000; …
  placed block saved data: {"chat":["52, 64, 0 has the following block data: 5000L"],"ok":true}
  placed refinedtypes:256k_energy_storage_block at 56,64,0
  info(54,64,0): … energy 0/256000; …                       (the differential: a fresh item)
  doctored give: {"chat":["Gave 1 [256K Energy Storage Block] to Player21496"],"ok":true}
  doctored item: {"chat":["… {components: {\"minecraft:block_entity_data\": {Amount: 999999999L, id: \"refinedtypes:node\"}}, count: 1, id: \"refinedtypes:256k_energy_storage_block\"}"],"ok":true}
  placed refinedtypes:256k_energy_storage_block at 56,64,0
  info(54,64,0): … energy 256000/256000; …                  (clamped)
  doctored block saved data: {"chat":["56, 64, 0 has the following block data: 256000L"],"ok":true}
```

`NEGATIVE=1` inverts the restore assertion and must fail; it does —
`FAIL: NEGATIVE: the replaced block reads 5000/256000, so the assertion is alive`
(`e2e-negative.log`, `EXIT:1`). The whole-run counterfactuals: the control game (no packages)
dies at the first block assertion (`e2e-control.log`, `EXIT:1`), and `SELFTEST=1` still flips the
drain assertion (`e2e-selftest.log`, `EXIT:1`).

### Traps this slice met (measured)

1. **A creative placement keeps the stack.** After the differential's freshly given block was
   placed, a plain 256k block stayed in hand; `ctl select` then found *that* one and the doctored
   stack read as plain (first attempt failed exactly here, `EXIT:1`). `clear @s` before the
   doctored give is what makes the leg honest.
2. **A bare-hand break is close to `ctl`'s 30 s default** (hardness 4.5 ≈ 23 s), and on a loaded
   box it timed out once. Both breaks now pass `--timeout 90` and report a `FAIL:` line instead of
   dying silently under `set -e`.
3. **The End has endermen, and a survival death loses the inventory mid-scenario** (one negative
   run died during the bare-hand break). The survival legs now run under `resistance 4` +
   `regeneration 4` (`undying`), which changes no drop rule the assertions read.
4. **The recipe driver is flaky under load**, not broken: one run lost the crafting screen mid-file
   (`no menu is open: {screen: playing}`); the same driver passed before and after, and the recipe
   family is slice 2's, untouched here.

### Ladder (0.1.3)

| Step | Command | Result |
|---|---|---|
| runtime + glue tests | `cargo test --offline` | **25 passed**, 0 failed (`sdk-test.log`) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings (`sdk-clippy.log`) |
| format | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean |
| SDK check | `cargo horizon-mod check` | *"Refined Types uses 325 items of the API (4 Part kinds, 1 associated item, 2 capabilitys, 66 fields or variants, 12 hooks, 23 hook arguments, 2 macros, 109 methods, 22 traits, 84 types). Made for 0a875da."* (`sdk-check.log`) |
| package | `rm -f Cargo.lock` before each of two `cargo horizon-mod build` runs | **288,647 B**, SHA-256 `9432dc8761476a9e266877631a02e3a55e94215259aad104ca7ddaaa4a7bd678`, **581 entries**, `cmp` byte-identical, no packed `Cargo.lock` |
| package check | `cargo horizon-mod check refinedtypes.hmod` | `0.1.3 (native-mod, format native-1/0a875da…/e59da90…, for 26.3) 288647 bytes` (`sdk-package-check.log`) |
| fits (pin) | `… fits refinedtypes.hmod --build 0a875da` | *"0a875da  made for"* (`sdk-fits.log`) |
| fits (other build) | `… fits refinedtypes.hmod --build 0b14f8a` | *"0b14f8a  fits"* (`sdk-fits-other.log`) — the one that proves something |
| content carry | `python3 tools/carry.py --check` | 575 files re-derived, 107 recipes, 2 skipped with the reason, nothing unexplained |
| launcher build | `tools/build-game.sh` | exit 0, `Compiling refinedstorage (1 of 2)` / `Compiling refinedtypes (2 of 2)`, `native-0a875da-a0dca869a3ba` (`refinedtypes-e2e/launcher-build-0a875da.log`) |
| in-game leg | `build-slot.sh run --step e2e -- … tools/e2e.sh` | **PASS** + **`EXIT:0`** (`refinedtypes-e2e/e2e.log`) |
| control (same Nightly, no packages) | `GAME=$CONTROL_GAME tools/e2e.sh` | **FAIL** + `EXIT:1` — *the block at 44,64,0 is minecraft:air* (`e2e-control.log`) |
| negative (inverted restore) | `NEGATIVE=1 tools/e2e.sh` | **FAIL** + `EXIT:1` — *the replaced block reads 5000/256000* (`e2e-negative.log`) |
| selftest (flipped drain) | `SELFTEST=1 tools/e2e.sh` | **FAIL** + `EXIT:1` — *the disk was drained to 3004* (`e2e-selftest.log`) |
| log gate | `check-e2e-logs.py refinedtypes-e2e --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` |
| package gate | `verify-sdk-package.py refinedtypes` | **1/1** |

### Deviations (this slice)

1. **The payload is the amount alone.** This block is not a container, so no stash and no
   `on_destroyed_by_player` half is needed (rftoolsstorage 0.2.4's shape); HANDOVER §9m still
   applies as "the payload carries no `Items`", which the unit test asserts.
2. **An empty store carries nothing** — a zero amount and no payload are the same state, so an
   empty block drops the plain item; a creative block always carries `CREATIVE_STORED`.
3. **The energizer's buffer is still not carried** (out of this gap line); breaking it drops a
   plain item, unchanged.
4. **A doctored payload is clamped at placement, not refused** — vanilla's own posture for
   `block_entity_data`; the block reads the tier's capacity.

## Slice 4 — the Network Energizer's menu and screen (2026-11-23) — version 0.1.4

Gap line this slice answers — §Gaps item 4 / deviation 4: *"No storage-block or energizer
menu/screen. Upstream each opens a menu (the energizer shows an energy bar via a
`NetworkEnergizerData` packet)."* Class `content`, tier **machines**, unchanged: menus and screens
are the tier's own shape (`horizon/docs/modpacks.md`, "Tiers"), and no renderer, entity, dimension
or third-party mod is added.

### The artefact corrected the brief: the mod has one menu, and it is the energizer's

The brief for this slice named the *storage block's* menu. The 0.3.2 jar has exactly **one** menu,
one screen and one data packet — `networkenergizer/NetworkEnergizerContainerMenu`,
`NetworkEnergizerScreen`, `EnergyProgressWidget`, `NetworkEnergizerEnergyInfo` and
`packet/s2c/NetworkEnergizerEnergyInfoPacket`, registered by `registry/Menus` — and no
`MenuProvider` under `storage/` (the class listing has no `*ContainerMenu` there, and the storage
blocks are `EnergyStorageBlockBlockItem`/`...Provider` only). So a storage-block menu would be
invented content, which `AGENTS.md` forbids; this slice ports the mod's only menu. The gap line's
"upstream each opens a menu" was this port's own error and is corrected here.

### The `u64` in `i32` question, settled before the code

Measured first, then designed:

- a mod menu's data slots are `ModBlockEntity.data: Vec<i32>` (`horizon-mod-vocab/src/item/containers.rs`),
  as many as the menu type declares (`data_slots`, `data/<id>/horizon/menu/<name>.json`);
- the menu's sync sends them as `i16` — `lan/containers.rs::sync_container_data` maps `v as i16`,
  and the `screen_draw` doc says "16-bit on the wire … a bigger value wraps";
- the energizer's readout is the network's stored energy and capacity: `u64`, up to 8,388,608,000
  on the 8388608k tier (33 bits) and `i64::MAX` on a creative store.

**Decision: split the amount across slots in base 2¹⁶, four limbs per value** — stored then
capacity, 8 data slots. *Capped* would show 34,464 for a 1024k block holding 100,000; *two slots*
cover only 32 bits, short of the biggest tier; *reading the block entity's own NBT on the client*
needs a `block_entity_update_tag` sync on every change, which the pin's own guidance rejects for a
menu's progress ("menus have their own data slots"). The limbs are exact for every `u64`, each fits
the 16 bits the wire carries, and the screen reassembles them — so the menu carries the amount, and
the leg reads it out of the same storage the sync reads (`block_entity_data_slots`).

### Two platform facts this slice measured (neither was in the pin's docs)

1. **A mod container's menu opens only when its block's *template* opens one.** The engine's use
   path opens a container for a block whose class emits `PlayerEffect::OpenMenu`; our blocks are
   templated on `minecraft:iron_block`, which does not. With the container and menu type declared
   and nothing else, `ctl interact` on the energizer left `screen: playing` (red leg,
   `e2e-red-menu.log`). `PlayerRef::open_menu` *does* open the menu — but then the client has no
   block position for it ("`screen_pos` is the block as the server named it when the block opened
   its menu type"), so no mod screen is built, no `screen_draw`, and the data slots never reach a
   screen: measured, the menu opened with the right title and 36 slots and drew nothing
   (`mod_screen` stayed `None`). The working route is a template whose class opens a menu:
   `minecraft:smithing_table` opens one and has **no state properties of its own**, so the block's
   state stays the jar's `active` alone. (`minecraft:barrel`, what the parent's four container
   blocks use, would have added `facing`/`open` and changed the blockstate the jar ships.)
2. **`screen_draw`'s coordinates are screen-relative.** `event.origin` is the screen's top-left;
   the mod draws from there. Drawing at the upstream numbers without adding the origin put the bar
   outside the panel — the screenshot caught it (a 192-pixel green sliver at the window's
   `(80, y)`, the un-offset rectangle) before the e2e's bar measurement did.

### The readout and the screen

- `data/refinedtypes/horizon/menu/energizer.json` — `{"slots": 1, "data_slots": 8}`. Upstream's
  menu holds no container slots (the player's inventory only), and a menu type at this pin declares
  at least one, so the type declares one and the port's `screen` leaves it out (`Screen::slots:
  [None]`), which keeps it out of the server's menu too (`native_hidden_slots`) — the leg asserts
  36 slots and no `300+`.
- `Registrar::block_container(network_energizer, ModContainer { slots: 1, no faces, no inputs,
  menu: "refinedtypes:energizer" })`.
- `BlockEntityPart::screen` — 176 × 189, the inventory's first row at y = 107 and its left column at
  8, upstream's own numbers (`NetworkEnergizerScreen`: `imageWidth 176`, `imageHeight 189`,
  `addPlayerInventory(playerInventory, 8, 107)`).
- `BlockEntityPart::screen_draw` — the 16 × 70 bar at (80, 20) from the screen's top left, a
  `#1B1B1B` trough and a `#5AD35A` fill grown from the bottom, `progress * height` as upstream's
  `EnergyProgressWidget` slices its sprite. The jar's own `textures/gui/sprites/widget/energy_progress_bar.png`
  is carried, but the sprite route is not used: the pin's `sprite` names atlas entries and the
  carried sprite's key is not worth guessing when two `fill`s draw the same gauge and a screenshot
  can measure it.
- `BlockEntityPart::screen_tooltip` — `Available: 5,000` (upstream's
  `NetworkEnergizerEnergyInfo.createTooltip`, `∞` for a creative store) when the cursor is over the
  bar. The text is a literal: the key upstream uses (`gui.autocrafting_preview.available`) belongs
  to the parent mod, not to this one.
- The energizer's tick writes `event.entity.data = menu_slots(stored, capacity)`, only when it
  changed (a write marks the block entity changed).
- `/refinedtypes menu <pos>` — the readout the leg asserts: the eight data slots and the amount they
  hold. The pin has no `ctl` command for a menu's data slots (`ctl screen` reports the screen, its
  title and its slots), so the command reads them through the same accessor the menu's sync uses.

### Upstream defect fixed: the bar is a gauge, not a full bar

`NetworkEnergizerBlockEntity.getCapacity()` returns `getStored()` — its own comment says *"it's
currently not possible to find out the capacity of all energy disks in the network, that's why we
just pass stored as the capacity instead"*. The bar is therefore `stored / stored` = always full,
and `NetworkEnergizerData` carries the same value twice. This port's network walk already computes
the family's real capacity (`/refinedtypes info` prints `energy 5000/256000`), so the menu's second
quantity is that capacity, and the bar shows 5,000 of 256,000 as 1.3 of 70 pixels — measured in the
screenshot. What a user notices: the gauge moves, and a nearly empty network looks nearly empty.
The buffer fallback upstream has (`stored <= 0` reads the node's own 1,000 FE buffer) is kept, and
the capacity never drops below the amount shown, so a network powered by the buffer alone draws a
full bar (1,000/1,000, also measured).

### Red → green

Red, verbatim from `e2e-red-menu.log` (the 0.1.4 tree with the container declaration and the menu
type removed — 0.1.3's state — built by the launcher and driven by the new leg):

```
  screen: {"screen":"playing","container":null,"title":"","slots":0}
FAIL: using the energizer did not open a menu: {"screen":"playing","container":null}
EXIT:1
```

The runtime came first too (`red-slice4-menu.log`): `error[E0425]: cannot find function
bar_fraction`/`formatted`/`menu_slots`/`menu_amounts`/`menu_capacity`/`limbs`/`unlimbs`, 21 errors,
`CARGO_EXIT:101`.

Green, from `e2e.log` (the delivered pair):

```
  screen: {"screen":"container","container":[-2147483648,0,0],"title":"Network Energizer","slots":36}
  menu: Menu at 39,64,2: 8 data slots [4848, 0, 0, 0, 59392, 3, 0, 0]; stored 4,848/256,000
  readout: stored=4848 capacity=256000 limbs=(4848 0 0 0 | 59392 3 0 0)
  info just after the readout: 4808
  bar at 4848/256000: 1.3 of 70 GUI px filled, 68.7 dark (the trough)
  menu (buffer only): Menu at 49,64,2: 8 data slots [1000, 0, 0, 0, 1000, 0, 0, 0]; stored 1,000/1,000
  bar at 1000/1000: 70.1 of 70 GUI px filled (the 5000/256000 one was 1.3)
PASS: …
EXIT:0
```

`256,000` is `0x3E800`: the low limb is 59,392 and the next 3 — a single 16-bit slot could not have
carried it, which is the split's point. The readout trails the deposit because the network pays its
4 FE/t while the menu is open, so the leg compares it with `/refinedtypes info` (a different reading
of the same amount) to within 100 FE rather than pinning 5,000 exactly.

`MENU_NEGATIVE=1` inverts the readout assertion and must fail; it does —
`FAIL: MENU_NEGATIVE: the menu reads 4924 for a 5000 network, so the assertion is alive`
(`e2e-menu-negative.log`, `EXIT:1`).

### Ladder (0.1.4)

| Step | Command | Result |
|---|---|---|
| runtime tests, red first | `cargo test --offline` before the model existed | **21 errors** (`E0425` ×7 functions), `CARGO_EXIT:101` (`evidence/refinedtypes/red-slice4-menu.log`) |
| runtime + glue tests | `cargo test --offline` | **29 passed**, 0 failed (`evidence/refinedtypes/sdk-test.log`) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** (`sdk-clippy.log`) |
| format | `rustfmt --edition 2024 --check src/{lib,support,runtime}.rs` | clean |
| SDK check | `cargo horizon-mod check` | *"Refined Types uses 405 items of the API (5 Part kinds, …, 15 hooks, …). Made for 0a875da."* (`sdk-check.log`) |
| package | `rm -f Cargo.lock` before each of two `cargo horizon-mod build` runs | **295,355 B**, SHA-256 `1c2b80ea37a1e52b7681f34e6dc5e180b738e66ef42e077d4cc867f52bd189df`, **582 entries**, `cmp` byte-identical, no packed `Cargo.lock` |
| package check | `cargo horizon-mod check refinedtypes.hmod` | `0.1.4 (native-mod, format native-1/0a875da…/e59da90…) 295355 bytes` (`sdk-package-check.log`) |
| fits (pin) | `… fits refinedtypes.hmod --build 0a875da` | *"0a875da  made for"* (`sdk-fits.log`) |
| fits (other build) | `… fits refinedtypes.hmod --build 0b14f8a` | *"0b14f8a  fits"* (`sdk-fits-other.log`) — the one that proves something |
| content carry | `python3 tools/carry.py --check` | 576 files re-derived (575 + the menu declaration), 107 recipes, 2 skipped with the reason |
| recipe types | `python3 ports/tools/check-recipe-types.py refinedtypes` | `refinedtypes: ok` |
| launcher build | `tools/build-game.sh` | exit 0, `Compiling refinedstorage (1 of 2)` / `Compiling refinedtypes (2 of 2)`, `native-0a875da-7d560bff795f` |
| in-game leg | `build-slot.sh run --step e2e -- … tools/e2e.sh` | **PASS** + **`EXIT:0`** (`refinedtypes-e2e/e2e.log`) |
| red (no container declaration) | the same leg against a build of the 0.1.3 state | **FAIL** + **`EXIT:1`** — *"using the energizer did not open a menu: {"screen":"playing"}*" (`e2e-red-menu.log`) |
| control (same Nightly, no packages) | `GAME=$CONTROL_GAME tools/e2e.sh` | **FAIL** + `EXIT:1` — *"the block at 44,64,0 is minecraft:air"* (`e2e-control.log`) |
| negative (inverted restore) | `NEGATIVE=1 tools/e2e.sh` | **FAIL** + `EXIT:1` — *"the replaced block reads 5000/256000"* (`e2e-negative.log`) |
| menu negative (inverted readout) | `MENU_ONLY=1 MENU_NEGATIVE=1 tools/e2e.sh` | **FAIL** + `EXIT:1` — *"the menu reads 4924 for a 5000 network"* (`e2e-menu-negative.log`) |
| selftest (flipped drain) | `SELFTEST=1 tools/e2e.sh` | **FAIL** + `EXIT:1` — *"the disk was drained to 3004"* (`e2e-selftest.log`) |
| menu leg alone | `MENU_ONLY=1 tools/e2e.sh` | **PASS** + `EXIT:0` (`e2e-menu-only.log`) |
| log gate | `check-e2e-logs.py refinedtypes-e2e --strict` | `logs=7 ok=7 missing-exit=0 bad-exit=0` |
| package gate | `verify-sdk-package.py refinedtypes` | **1/1** |

### Coverage (parity rule) — the families this slice touches

| family | state |
|---|---|
| the energizer's menu (its only menu) | **tested** — `ctl interact` opens it; `ctl screen` reports `container`, the title `Network Energizer` and the player's 36 slots with no container slot; `ctl close` returns to `playing` (`e2e.log`, `e2e-red-menu.log` for the red) |
| the menu's data slots (stored + capacity) | **tested** — 8 slots, the stored amount in the low limb and the capacity split as `[59392, 3, 0, 0]` for 256,000; cross-checked against `/refinedtypes info`; inverted under `MENU_NEGATIVE=1` |
| the bar | **tested** — measured from a screenshot (`tools/bar_check.py`): 1.3 of 70 GUI px filled for 4,848/256,000 and 70.1 for 1,000/1,000 (differential), with the 68.7-pixel trough proving the bar is drawn |
| the tooltip | **drawn, not machine-measured** — `screen_tooltip` returns `Available: <amount>` over the bar; the pin's `ctl` has no hover-a-tooltip command, and the amount it formats is the data slot asserted above (`formatted` is unit-tested) |
| storage-block menus | **not ported** — the jar has none (one `*ContainerMenu` class, the energizer's): a storage-block menu would be invented content |
| the redstone-mode side button | **not ported** — upstream's `RedstoneModeSideButtonWidget` needs the parent's redstone-mode property, which the parent port does not model (its own gap) |

### Deviations and traps (this slice)

1. **The template is `minecraft:smithing_table`, not the jar's plain block.** For a menu, a content
   block's template must be a class that opens one; a workstation is the cheapest such class and
   this one has no state properties, so the block's state stays the jar's `active` alone. Recorded
   because a template is a mechanism choice the jar does not make.
2. **One declared container slot, hidden by the screen.** A menu type at this pin declares 1 to 256
   slots; upstream's menu has none. The screen leaves the one out, and the server's menu drops it
   too, so a player sees the player inventory only.
3. **The capacity shown is the real one** (upstream's always-full bar is the defect above), and the
   buffer fallback stands in for a network that holds nothing.
4. **The tooltip text is a literal**, because its translation key belongs to the parent mod.
5. **A screenshot assertion needs both counts.** The first measurement counted only bright pixels
   and "passed" on the plain 198-grey panel; the trough count is what distinguishes a drawn bar from
   a light panel behind it. The first drawing attempt was also outside the panel (the origin bug
   above) and only the screenshot showed it.
6. **`| tail` in a leg's pipeline blinds the e2e guard.** The guard watches the leg's own output for
   900 s of silence; `tools/e2e.sh | tee LOG | tail -N` buffers everything until EOF, so a healthy
   8-minute run was killed twice as a "hang". The leg now runs `… | tee LOG` with nothing after it.
   `tools/recipe_check.py`'s ctl calls gained a 180 s timeout for the same reason: a call the game
   never answers now names itself instead of idling the leg out.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices
