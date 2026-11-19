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
    self, ComponentTypesEvent, Flow, Hooks, HostSide, RegisterCommandsEvent, Registrar,
    RegistrationContext, RightClickBlockEvent, RunModCommandEvent, ServerHost,
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
