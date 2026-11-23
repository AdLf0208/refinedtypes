//! Refined Types for Horizon: FE, Source and Soul storage on a Refined Storage network.
//!
//! The mod is an add-on: its parent is Refined Storage, and its storage lives on the parent's
//! network — storage blocks add capacity to the component, storage disks sit in the parent's disk
//! drives, and the Network Energizer keeps the network supplied from the energy storage.
//!
//! [`runtime`] is the pure model (the families and their tiers, the stores, the network component,
//! the energizer's accounting); [`support`] is the game glue. See `notes.md` for the jar inventory,
//! the slice boundary, the deviations and the gaps.
mod runtime;
mod support;

use mod_api::{
    self, BlockDropsEvent, ComponentTypesEvent, Flow, Hooks, HostSide, LevelHost,
    RegisterCommandsEvent, Registrar, RegistrationContext, RightClickBlockEvent,
    RunModCommandEvent, ServerHost,
};

/// The mod holds no state of its own: a block's amount is its block-entity payload, a disk's is
/// its item component, and the energizer's is its payload, so everything survives a save.
#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Declare the one block-entity type over the 31 blocks, and its Part.
    fn register(&self, registrar: &mut dyn Registrar, cx: &RegistrationContext) {
        support::register(registrar, cx);
    }

    /// The component a storage disk's amount travels in, before content loads.
    fn component_types(&self, _cx: &RegistrationContext, event: &mut ComponentTypesEvent<'_>) {
        support::register_component_types(event);
    }

    /// A storage disk right-clicked onto the parent's disk drive goes into its first free
    /// slot; every other click is the block's own.
    fn right_click_block(&self, host: HostSide<'_>, event: &mut RightClickBlockEvent<'_>) -> Flow {
        support::on_right_click_block(host, event)
    }

    /// A broken storage block's own item carries the amount the block held.
    fn block_drops(&self, level: &dyn LevelHost, event: &mut BlockDropsEvent<'_>) -> Flow {
        support::on_block_drops(level, event)
    }

    /// `/refinedtypes info|insert`.
    fn register_commands(&self, _host: &mut dyn ServerHost, event: &mut RegisterCommandsEvent<'_>) {
        support::on_register_commands(event);
    }

    /// The bodies of `/refinedtypes info|insert`.
    fn run_mod_command(
        &self,
        host: &mut dyn ServerHost,
        event: &mut RunModCommandEvent<'_>,
    ) -> Flow {
        support::on_run_mod_command(host, event)
    }
}

/// The declarations this package ships, and the one rule upstream states for them.
///
/// Upstream makes a **disk** and a **storage block** fire resistant
/// (`*StorageDiskItem`/`*StorageBlockBlockItem`: `new Item.Properties().stacksTo(1).fireResistant()`)
/// and leaves a **part** (`SimpleItem`) and the **Network Energizer**
/// (`NetworkNodeBlockItem` with `BlockConstants.PROPERTIES`) alone. At 26.3 that declaration is
/// the `minecraft:damage_resistant` component naming the `#minecraft:is_fire` damage tag — the
/// spelling vanilla's own `minecraft:netherite_ingot` uses in `items.json`, which the engine
/// reads as `ItemInfo.fire_resistant` and as `Items::resists_fire` for a stack. A test, not a
/// comment, because the declarations are generated (`tools/carry.py`) and a regenerated tree
/// that lost the component would otherwise ship silently.
#[cfg(test)]
mod declarations {
    use std::fs;
    use std::path::Path;

    /// What a fire-resistant declaration carries. Whitespace is stripped before comparing, so
    /// the assertion is about the component and its value, not about the file's indentation.
    const FIREPROOF: &str = r##""minecraft:damage_resistant":{"types":"#minecraft:is_fire"}"##;

    /// The declaration files under `data/refinedtypes/horizon/<dir>/`, name → whitespace-free text.
    fn declarations(dir: &str) -> Vec<(String, String)> {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("data/refinedtypes/horizon")
            .join(dir);
        let mut files: Vec<(String, String)> = fs::read_dir(&root)
            .unwrap_or_else(|e| panic!("cannot read {}: {e}", root.display()))
            .map(|entry| entry.expect("a declaration entry").path())
            .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
            .map(|path| {
                let name = path
                    .file_stem()
                    .expect("a declaration has a file stem")
                    .to_string_lossy()
                    .into_owned();
                let text = fs::read_to_string(&path)
                    .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
                let flat: String = text.chars().filter(|c| !c.is_whitespace()).collect();
                (name, flat)
            })
            .collect();
        files.sort();
        files
    }

    #[test]
    fn the_disks_and_storage_blocks_declare_fire_resistance_and_nothing_else_does() {
        let items = declarations("item");
        let blocks = declarations("block");

        // The jar's families: 10 tiers × 3 families of disks and blocks, 9 parts per family (the
        // creative tier ships no part), and the one energizer.
        let (disks, parts): (Vec<_>, Vec<_>) = items
            .iter()
            .partition(|(name, _)| name.ends_with("_storage_disk"));
        let (storage_blocks, others): (Vec<_>, Vec<_>) = blocks
            .iter()
            .partition(|(name, _)| name.ends_with("_storage_block"));
        assert_eq!(disks.len(), 30, "storage disks in the tree");
        assert_eq!(parts.len(), 27, "storage parts in the tree");
        assert_eq!(storage_blocks.len(), 30, "storage blocks in the tree");
        assert_eq!(
            others.len(),
            1,
            "the one block that is not a storage block: {:?}",
            others
                .iter()
                .map(|(name, _)| name.as_str())
                .collect::<Vec<_>>()
        );
        assert_eq!(others[0].0, "network_energizer");

        for (name, text) in disks.iter().chain(storage_blocks.iter()) {
            assert!(
                text.contains(FIREPROOF),
                "{name} does not declare {FIREPROOF} (upstream: `Item.Properties::fireResistant`)"
            );
        }
        for (name, text) in parts.iter().chain(others.iter()) {
            assert!(
                !text.contains("damage_resistant"),
                "{name} declares fire resistance, which upstream gives neither a part \
                 (`SimpleItem`) nor the Network Energizer (`NetworkNodeBlockItem`)"
            );
        }
    }
}
