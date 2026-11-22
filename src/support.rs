//! The game glue: registration, the block-entity payloads, the storage-disk component,
//! the parent's disk drive, the energizer's tick and the commands.
//!
//! The rules live in [`crate::runtime`], which has no `mod_api` types; this module only
//! reads the game, calls the runtime and writes the result back. The one thing it owns is
//! the shape of the saved payloads, because that shape is the game's (`Tag`/`Compound`).

use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};

use mod_api::{
    self, BlockDropsEvent, BlockEntityEvent, BlockEntityPart, BlockEntityTickEvent,
    BlockEntityTicksEvent, BlockPart, Command, CommandArgumentValue, Component, Compound, Flow,
    Host, HostSide, HostTransaction, ItemKey, ItemPart, ItemStack, LevelHost, LevelSide,
    OnBlockPlacedByEvent, RegisterCommandsEvent, Registrar, RegistrationContext,
    RightClickBlockEvent, RunModCommandEvent, ServerHost, Tag, Text,
};

use crate::runtime::{
    self, Capacity, Energizer, Family, Holding, IdKind, Node, Store, Totals, Variant, network,
};

/// The block-entity type this mod declares, over its 31 blocks.
const BE_TYPE: &str = "refinedtypes:node";
/// The item component that carries a storage disk's amount.
const COMPONENT: &str = "refinedtypes:stored";
/// The vanilla component that moves a block entity's saved data on its own item
/// (`BlockItem.updateCustomBlockEntityTag` / `applyComponentsFromItemStack`), tagged with
/// the block entity type's id.
const BLOCK_ENTITY_DATA: &str = "minecraft:block_entity_data";
/// The saved key of a storage block's amount.
const AMOUNT_KEY: &str = "Amount";
/// The saved keys of the energizer's state.
const BUFFER_KEY: &str = "Buffer";
const ACTIVE_KEY: &str = "Active";
/// The parent's disk drive, and the slot count it declares (`ports/refinedstorage`).
const DRIVE: &str = "refinedstorage:disk_drive";
const DRIVE_SLOTS: u32 = 9;

// --- registration ----------------------------------------------------------

/// Every block id the one block-entity type covers: the 30 storage blocks and the
/// energizer, exactly as the content declares them.
fn block_ids() -> Vec<String> {
    let mut ids: Vec<String> = Family::ALL
        .into_iter()
        .flat_map(|family| {
            (0..Variant::TIERS)
                .filter_map(move |tier| Variant::new(family, tier))
                .map(|variant| variant.id(IdKind::Block))
        })
        .collect();
    ids.push(ENERGIZER_BLOCK.to_owned());
    ids
}

/// The energizer's block id (it is not a storage tier).
const ENERGIZER_BLOCK: &str = "refinedtypes:network_energizer";

/// Declare the block-entity type and attach the Part to it.
pub(crate) fn register(registrar: &mut dyn Registrar, _cx: &RegistrationContext) {
    let ids = block_ids();
    let borrowed: Vec<&str> = ids.iter().map(String::as_str).collect();
    let kind = registrar
        .block_entity_type(BE_TYPE)
        .blocks(&borrowed)
        .build();
    registrar
        .block_entity_part(&kind, NodePart)
        .expect("one Part per block-entity type");
    // Every block's own item, for the drop hook, and — for the 30 storage blocks — the Part
    // that gives a placed block the amount its item carried. (The energizer's buffer is not
    // carried; its only state is its own tick's.)
    for id in &ids {
        let item = registrar.item_key(id);
        remember_item(id, item);
        if matches!(Node::from_block(id), Some(Node::Storage(_))) {
            registrar.item_part(item, StorageItem);
        }
    }
}

/// The disk's component: the amount it carries.
pub(crate) fn register_component_types(event: &mut mod_api::ComponentTypesEvent<'_>) {
    event.types.push(COMPONENT.to_owned());
}

// --- the saved payloads ----------------------------------------------------

/// The payload of a storage block: the amount it holds.
fn save_amount(amount: u64) -> Compound {
    compound([(AMOUNT_KEY, Tag::Long(amount as i64))])
}

/// The amount a saved payload holds, 0 when it holds none or the wrong type.
///
/// Any integer tag counts, as vanilla's `NbtUtils.getLong` accepts every numeric type: a
/// payload written by hand in SNBT may name an `Int` or a `Byte`, not only our own `Long`.
fn saved_amount(payload: &Compound) -> u64 {
    match lookup(payload, AMOUNT_KEY) {
        Some(Tag::Long(value)) => u64::try_from(*value).unwrap_or(0),
        Some(Tag::Int(value)) => u64::try_from(*value).unwrap_or(0),
        Some(Tag::Byte(value)) => u64::try_from(*value).unwrap_or(0),
        _ => 0,
    }
}

/// A compound from string keys: the API's `Tag::compound` is the only route to one without
/// naming `JavaString`, which the launcher provides no crate for.
fn compound<const N: usize>(entries: [(&'static str, Tag); N]) -> Compound {
    match Tag::compound(entries) {
        Tag::Compound(compound) => compound,
        _ => Compound::new(),
    }
}

/// A key of a compound, found by its text.
fn lookup<'a>(payload: &'a Compound, key: &str) -> Option<&'a Tag> {
    payload
        .iter()
        .find(|(name, _)| name.to_string_lossy() == key)
        .map(|(_, tag)| tag)
}

/// The energizer's payload: its buffer and whether it covered the last tick's usage.
fn save_energizer(energizer: &Energizer) -> Compound {
    compound([
        (BUFFER_KEY, Tag::Long(energizer.buffer() as i64)),
        (
            ACTIVE_KEY,
            Tag::Byte(if energizer.active() { 1 } else { 0 }),
        ),
    ])
}

/// The energizer an entity's payload describes; a fresh one when it has none.
fn load_energizer(payload: &Compound) -> Energizer {
    let Some(Tag::Long(buffer)) = lookup(payload, BUFFER_KEY) else {
        return Energizer::new();
    };
    let active = matches!(lookup(payload, ACTIVE_KEY), Some(Tag::Byte(1)));
    Energizer::with_state(u64::try_from(*buffer).unwrap_or(0), active)
}

// --- the storage disk's component -----------------------------------------

/// A storage disk's amount, in the disk item's own component.
struct StoredAmount;

impl Component for StoredAmount {
    type Value = u64;

    fn id(&self) -> &str {
        COMPONENT
    }

    fn decode(&self, value: &Tag) -> Option<Self::Value> {
        match value {
            Tag::Long(amount) => u64::try_from(*amount).ok(),
            _ => None,
        }
    }

    fn encode(&self, value: Self::Value) -> Tag {
        Tag::Long(value as i64)
    }
}

/// What a disk item holds, 0 when it has no component yet.
fn disk_amount(stack: &ItemStack) -> u64 {
    stack.get(&StoredAmount).unwrap_or(0)
}

/// Write a disk item's amount (a zero amount drops the component).
fn set_disk_amount(stack: &mut ItemStack, amount: u64) {
    if amount == 0 {
        stack.remove(&StoredAmount);
        return;
    }
    let _ = stack.set(&StoredAmount, amount);
}

/// The variant and kind an item id names, when it is a storage disk.
fn disk_of(id: &str) -> Option<Variant> {
    Variant::from_id(id)
        .filter(|(_, kind)| *kind == IdKind::Disk)
        .map(|(variant, _)| variant)
}

// --- the storage block's own item -----------------------------------------

/// `minecraft:block_entity_data`, as a component a stack's payload is read from.
struct BlockEntityData;

impl Component for BlockEntityData {
    type Value = Compound;

    fn id(&self) -> &str {
        BLOCK_ENTITY_DATA
    }

    fn decode(&self, value: &Tag) -> Option<Self::Value> {
        match value {
            Tag::Compound(data) => Some(data.clone()),
            _ => None,
        }
    }

    fn encode(&self, value: Self::Value) -> Tag {
        Tag::Compound(value)
    }
}

/// The `minecraft:block_entity_data` payload a stack carries, if it carries one.
fn payload_of(stack: &ItemStack) -> Option<Compound> {
    stack.get(&BlockEntityData)
}

/// The `minecraft:block_entity_data` patch a broken storage block's own item carries: the
/// amount it held, tagged with the block entity type's id (the engine loads a payload only
/// when its `id` names the block entity it is placed as).
///
/// **Only the amount.** The engine spills a container's stacks as their own item entities
/// when the block is removed, so a payload that also carried `Items` would put every stack in
/// the world twice (HANDOVER §9m). These blocks declare no container, and the payload is built
/// fresh from the amount, so nothing else rides on the drop.
fn carried_patch(amount: u64) -> Compound {
    let payload = compound([
        ("id", Tag::String(BE_TYPE.into())),
        (
            AMOUNT_KEY,
            Tag::Long(i64::try_from(amount).unwrap_or(i64::MAX)),
        ),
    ]);
    compound([(BLOCK_ENTITY_DATA, Tag::Compound(payload))])
}

/// The block items, resolved once at registration: `block_drops` runs with a read-only level
/// host, which cannot name an item, so the drop is matched by the key remembered here.
static ITEMS: OnceLock<RwLock<HashMap<String, ItemKey>>> = OnceLock::new();

/// The block-to-item table, a poisoned lock treated as a table (a panic elsewhere must not
/// turn every later break into a no-op).
fn items() -> &'static RwLock<HashMap<String, ItemKey>> {
    ITEMS.get_or_init(|| RwLock::new(HashMap::new()))
}

/// Remember the item a block's own drop resolves to (registration time).
fn remember_item(block: &str, item: ItemKey) {
    items()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(block.to_owned(), item);
}

/// The item key of the block `block` names, once [`remember_item`] ran.
fn item_of(block: &str) -> Option<ItemKey> {
    items()
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .get(block)
        .copied()
}

/// The item half of a storage block: a placed block takes the amount its item carried,
/// clamped into its tier (a payload a player doctored past the tier gives the tier's
/// capacity). The engine's own placement path cannot do this for a mod block entity —
/// `block_entity_item::place` merges `minecraft:block_entity_data` through `canonical()`,
/// which answers `None` for a type it does not know — so this Part is what restores it.
pub(crate) struct StorageItem;

#[mod_api::horizon_part]
impl ItemPart for StorageItem {
    fn on_block_placed_by(&self, host: &mut dyn ServerHost, event: &mut OnBlockPlacedByEvent<'_>) {
        let Some(payload) = payload_of(event.stack) else {
            return;
        };
        let asked = saved_amount(&payload);
        let Some(Node::Storage(variant)) = node_at(host, event.pos) else {
            return;
        };
        let wanted = runtime::restored(variant.capacity(), asked);
        let Some(level) = host.level(host.dimension()) else {
            return;
        };
        let Some(entity) = host.block_entity(level, event.pos) else {
            return;
        };
        let current = entity
            .data(host)
            .map(|saved| saved_amount(&saved))
            .unwrap_or(0);
        if current == wanted {
            return;
        }
        let _ = entity.merge_data(host, save_amount(wanted));
    }
}

/// `block_drops`: a broken storage block's own item carries the amount the block held, so
/// placing the item gives the block that amount back (upstream's
/// `AbstractStorageContainerBlockItem`).
///
/// The event is built before the removal, so `level.block_entity_data` is the block entity's
/// snapshot with the amount still in it (HANDOVER §9m), and the payload is rebuilt from the
/// amount alone rather than copied from the snapshot.
pub(crate) fn on_block_drops(level: &dyn LevelHost, event: &mut BlockDropsEvent<'_>) -> Flow {
    let Some(block) = level.state_block(event.state) else {
        return Flow::Continue;
    };
    let Some((variant, IdKind::Block)) = Variant::from_id(block) else {
        return Flow::Continue;
    };
    let Some(entity) = event.block_entity else {
        return Flow::Continue;
    };
    let amount = level
        .block_entity_data(entity)
        .map(|payload| saved_amount(&payload))
        .unwrap_or(0);
    let Some(amount) = runtime::carried(variant.capacity(), amount) else {
        return Flow::Continue;
    };
    let Some(item) = item_of(block) else {
        return Flow::Continue;
    };
    let patch = carried_patch(amount);
    for drop in event.drops.iter_mut() {
        if drop.stack.item() == item {
            let _ = drop.stack.apply_components(&patch);
        }
    }
    Flow::Continue
}

// --- reading the world -----------------------------------------------------

/// The id of the loaded block at `pos`, none when the chunk is not loaded.
fn block_id_at(host: &dyn Host, pos: [i32; 3]) -> Option<String> {
    let level = host.level(host.dimension())?;
    if !level.is_loaded(host, pos) {
        return None;
    }
    level.block(host, pos).map(|block| block.id(host))
}

/// The node the loaded block at `pos` is.
fn node_at(host: &dyn Host, pos: [i32; 3]) -> Option<Node> {
    block_id_at(host, pos).and_then(|id| Node::from_block(&id))
}

/// The network the block at `start` belongs to, read from the loaded level.
fn network_at(host: &dyn Host, start: [i32; 3]) -> runtime::Network {
    network(start, |pos| node_at(host, pos))
}

/// Where one typed storage lives, so a change can be written back to it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Site {
    /// One of the add-on's storage blocks.
    Storage([i32; 3]),
    /// A disk in one slot of the parent's disk drive.
    Drive { drive: [i32; 3], slot: u32 },
}

/// One typed storage on the network, with the place it lives.
#[derive(Clone, Copy, Debug)]
struct Found {
    variant: Variant,
    store: Store,
    at: Site,
}

impl Found {
    fn holding(self) -> Holding {
        Holding::new(self.variant, self.store.stored())
    }
}

/// Every typed storage the network has: its storage blocks, then the disks in its drives.
fn holdings(host: &dyn Host, net: &runtime::Network) -> Vec<Found> {
    let mut found: Vec<Found> = net
        .storages()
        .into_iter()
        .map(|(pos, variant)| Found {
            variant,
            store: Store::with_stored(variant.capacity(), block_amount(host, pos)),
            at: Site::Storage(pos),
        })
        .collect();
    for drive in net.drives() {
        found.extend(drive_disks(host, drive));
    }
    found
}

/// A storage block's amount from its saved payload.
fn block_amount(host: &dyn Host, pos: [i32; 3]) -> u64 {
    let Some(level) = host.level(host.dimension()) else {
        return 0;
    };
    let Some(entity) = host.block_entity(level, pos) else {
        return 0;
    };
    entity
        .data(host)
        .map(|payload| saved_amount(&payload))
        .unwrap_or(0)
}

/// The add-on's storage disks in one of the parent's drives.
fn drive_disks(host: &dyn Host, drive: [i32; 3]) -> Vec<Found> {
    let Some(level) = host.level(host.dimension()) else {
        return Vec::new();
    };
    let Some(entity) = host.block_entity(level, drive) else {
        return Vec::new();
    };
    let mut found = Vec::new();
    for slot in 0..DRIVE_SLOTS {
        let Ok(Some(stack)) = entity.item_slot(host, slot) else {
            continue;
        };
        let Some(variant) = disk_of(&stack.item().id(host)) else {
            continue;
        };
        found.push(Found {
            variant,
            store: Store::with_stored(variant.capacity(), disk_amount(&stack)),
            at: Site::Drive { drive, slot },
        });
    }
    found
}

/// Write one storage's amount back where it lives. A disk the network changed goes back
/// into its slot, so the item carries the amount; a block's payload is merged.
fn write_back(host: &mut dyn ServerHost, found: &Found) {
    let amount = found.store.stored();
    match found.at {
        Site::Storage(pos) => {
            let Some(level) = host.level(host.dimension()) else {
                return;
            };
            let Some(entity) = host.block_entity(level, pos) else {
                return;
            };
            let _ = entity.merge_data(host, save_amount(amount));
        }
        Site::Drive { drive, slot } => {
            let Some(level) = host.level(host.dimension()) else {
                return;
            };
            let Some(entity) = host.block_entity(level, drive) else {
                return;
            };
            let Ok(Some(mut stack)) = entity.item_slot(host, slot) else {
                return;
            };
            set_disk_amount(&mut stack, amount);
            let _ = host.transaction(|host, tx| entity.set_item_slot(host, tx, slot, Some(stack)));
        }
    }
}

// --- the Part: the 31 blocks ----------------------------------------------

/// The Part of the mod's one block-entity type. It distinguishes the blocks by their id.
struct NodePart;

#[mod_api::horizon_part]
impl BlockPart for NodePart {}

#[mod_api::horizon_part]
impl BlockEntityPart for NodePart {
    /// Every node block gets a block entity with empty saved data.
    fn block_entity(
        &self,
        _level: LevelSide<'_>,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// Only the energizer works per tick; a storage block changes when something writes it.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = Node::from_block(event.block) == Some(Node::Energizer);
    }

    /// One server tick of the energizer: draw the network's usage, then say whether it was
    /// covered.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        if node_at(host, event.pos) != Some(Node::Energizer) {
            return;
        }
        let pos = event.pos;
        let mut energizer = load_energizer(&event.entity.nbt);
        // The state the block showed before this tick, so the property is written when it
        // changes (a write every tick would be noise).
        let was_active = energizer.active();
        let net = network_at(host, pos);
        let online = net.online();
        let usage = if online { net.usage() } else { 0 };
        let mut found = if online {
            holdings(host, &net)
        } else {
            Vec::new()
        };
        let available = energy_available(&found);
        let draw = energizer.tick(usage, available);
        if draw.from_storage > 0 {
            draw_from(host, &mut found, draw.from_storage);
        }
        // The state is the payload's, so it survives a save and a reload.
        event.entity.nbt = save_energizer(&energizer);
        if was_active != energizer.active() || !online {
            host.set_block_property(
                pos,
                "active",
                if energizer.active() && online {
                    "true"
                } else {
                    "false"
                },
            );
        }
    }
}

/// What the network's energy storage holds together (a creative storage is always full).
fn energy_available(found: &[Found]) -> u64 {
    found
        .iter()
        .filter(|entry| entry.variant.family() == Family::Energy)
        .fold(0u64, |sum, entry| sum.saturating_add(entry.store.stored()))
}

/// Take `amount` from the network's energy storages, in order, writing each one back.
fn draw_from(host: &mut dyn ServerHost, found: &mut [Found], amount: u64) {
    let mut left = amount;
    for entry in found.iter_mut() {
        if left == 0 {
            break;
        }
        if entry.variant.family() != Family::Energy {
            continue;
        }
        let taken = entry.store.extract(left);
        if taken > 0 {
            left -= taken;
            write_back(host, entry);
        }
    }
}

// --- player interaction ----------------------------------------------------

/// A refinedtypes storage disk right-clicked onto the parent's disk drive goes into its
/// first free slot; every other click is left to the game and the parent.
pub(crate) fn on_right_click_block(
    host: HostSide<'_>,
    event: &mut RightClickBlockEvent<'_>,
) -> Flow {
    let HostSide::Server(host) = host else {
        return Flow::Continue;
    };
    let pos = event.click.pos;
    if block_id_at(host, pos).as_deref() != Some(DRIVE) {
        return Flow::Continue;
    }
    let Some(held) = event.click.stack else {
        return Flow::Continue;
    };
    if disk_of(&held.item().id(host)).is_none() {
        return Flow::Continue;
    }
    let mut one = held.clone();
    let _ = one.set_count(1);
    if insert_into_drive(host, pos, one) {
        consume_held(host, event.click.player, held);
        tell(host, event.click.player, "Storage disk inserted.");
    } else {
        tell(host, event.click.player, "The disk drive is full.");
    }
    // Either way the click is the drive's: no menu opens behind a disk that was placed.
    Flow::Cancel
}

/// Put `one` in the drive's first free slot, in one transaction.
fn insert_into_drive(host: &mut dyn ServerHost, drive: [i32; 3], one: ItemStack) -> bool {
    let Some(level) = host.level(host.dimension()) else {
        return false;
    };
    let Some(entity) = host.block_entity(level, drive) else {
        return false;
    };
    let slot = (0..DRIVE_SLOTS).find(|slot| matches!(entity.item_slot(host, *slot), Ok(None)));
    let Some(slot) = slot else {
        return false;
    };
    host.transaction(|host, tx| entity.set_item_slot(host, tx, slot, Some(one)))
        .unwrap_or(false)
}

/// Take one item from the acting player's held stack (a disk moves into the drive, it is
/// not used, so creative mode keeps no free copy).
fn consume_held(host: &mut dyn ServerHost, uuid: u128, held: &ItemStack) {
    let Some(player) = host.player(uuid) else {
        return;
    };
    let Some(slot) = player.selected_slot(host) else {
        return;
    };
    let remaining = held.clone().split(1).remainder;
    let _ = player.set_inventory_slot(host, slot as u32, remaining);
}

fn tell(host: &mut dyn ServerHost, uuid: u128, line: &str) {
    if let Some(player) = host.player(uuid) {
        let _ = player.tell(host, Text::literal(line));
    }
}

// --- commands --------------------------------------------------------------

/// `/refinedtypes info|insert` (`register_commands`).
pub(crate) fn on_register_commands(event: &mut RegisterCommandsEvent<'_>) {
    event
        .commands
        .push(Command::new("refinedtypes info <pos:block_pos>"));
    event.commands.push(Command::new(
        "refinedtypes insert <pos:block_pos> <family:word> <amount:integer>",
    ));
}

/// The `/refinedtypes` commands' bodies (`run_mod_command`).
pub(crate) fn on_run_mod_command(
    host: &mut dyn ServerHost,
    event: &mut RunModCommandEvent<'_>,
) -> Flow {
    let [root, sub] = event.command.literals.as_slice() else {
        return Flow::Continue;
    };
    if root != "refinedtypes" {
        return Flow::Continue;
    }
    let Some(CommandArgumentValue::BlockPos(pos)) = event.command.argument("pos") else {
        feedback(
            host,
            "Usage: /refinedtypes <info|insert> <x> <y> <z> [family] [amount]",
        );
        return Flow::Cancel;
    };
    let pos = *pos;
    match sub.as_str() {
        "info" => {
            info(host, pos);
            Flow::Cancel
        }
        "insert" => {
            let family = match event.command.argument("family") {
                Some(CommandArgumentValue::String(name)) => Family::from_name(name),
                _ => None,
            };
            let amount = match event.command.argument("amount") {
                Some(CommandArgumentValue::Integer(amount)) => u64::try_from(*amount).ok(),
                _ => None,
            };
            match (family, amount) {
                (Some(family), Some(amount)) => insert(host, pos, family, amount),
                _ => feedback(
                    host,
                    "Usage: /refinedtypes insert <x> <y> <z> <energy|soul|source> <amount>",
                ),
            }
            Flow::Cancel
        }
        _ => Flow::Continue,
    }
}

fn feedback(host: &mut dyn ServerHost, line: &str) {
    let _ = host.commands().feedback(Text::literal(line));
}

/// `stored/capacity`, with `infinite` where a tier has no limit.
fn describe(totals: Totals) -> String {
    let stored = match totals.capacity {
        Capacity::Creative => "infinite".to_owned(),
        _ => totals.stored.to_string(),
    };
    let capacity = match totals.capacity {
        Capacity::Bounded(limit) => limit.to_string(),
        Capacity::Infinite | Capacity::Creative => "infinite".to_owned(),
    };
    format!("{stored}/{capacity}")
}

fn info(host: &mut dyn ServerHost, pos: [i32; 3]) {
    if node_at(host, pos).is_none() {
        feedback(host, "No Refined Storage network block there.");
        return;
    }
    let net = network_at(host, pos);
    let online = net.online();
    let found = holdings(host, &net);
    let sums = if online {
        runtime::totals(
            &found
                .iter()
                .map(|entry| entry.holding())
                .collect::<Vec<_>>(),
        )
    } else {
        runtime::totals(&[])
    };
    let usage = if online { net.usage() } else { 0 };
    let energizer = net
        .energizers()
        .first()
        .map(|at| {
            let Some(level) = host.level(host.dimension()) else {
                return Energizer::new();
            };
            let Some(entity) = host.block_entity(level, *at) else {
                return Energizer::new();
            };
            entity
                .data(host)
                .map(|payload| load_energizer(&payload))
                .unwrap_or_else(Energizer::new)
        })
        .unwrap_or_default();
    feedback(
        host,
        &format!(
            "Refined Types network at {},{},{}: {state} ({} storage, {} energizer, {} controller, {} drive, {} grid); energy {}; soul {}; source {}; usage {usage} FE/t; energizer {}/{} {activity}",
            pos[0],
            pos[1],
            pos[2],
            net.count(|node| matches!(node, Node::Storage(_))),
            net.energizers().len(),
            net.count(|node| *node == Node::Controller),
            net.drives().len(),
            net.count(|node| *node == Node::Grid),
            describe(sums[Family::Energy.index()]),
            describe(sums[Family::Soul.index()]),
            describe(sums[Family::Source.index()]),
            energizer.buffer(),
            runtime::ENERGIZER_BUFFER,
            activity = if energizer.active() {
                "active"
            } else {
                "inactive"
            },
            state = if online { "online" } else { "offline" },
        ),
    );
}

/// Deposit into the network's typed storage, in the order `holdings` returns: its storage
/// blocks, then the disks in its drives.
fn insert(host: &mut dyn ServerHost, pos: [i32; 3], family: Family, amount: u64) {
    if node_at(host, pos).is_none() {
        feedback(host, "No Refined Storage network block there.");
        return;
    }
    let net = network_at(host, pos);
    if !net.online() {
        feedback(host, "The network is offline: it has no controller.");
        return;
    }
    let mut found = holdings(host, &net);
    let mut left = amount;
    for entry in found.iter_mut() {
        if left == 0 {
            break;
        }
        if entry.variant.family() != family {
            continue;
        }
        let taken = entry.store.insert(left);
        if taken > 0 {
            left -= taken;
            write_back(host, entry);
        }
    }
    let accepted = amount - left;
    let totals = runtime::totals(
        &found
            .iter()
            .map(|entry| entry.holding())
            .collect::<Vec<_>>(),
    );
    if left == 0 {
        feedback(
            host,
            &format!(
                "Deposited {accepted} {}; the network now holds {}.",
                family.name(),
                describe(totals[family.index()])
            ),
        );
    } else {
        feedback(
            host,
            &format!(
                "The network took {accepted} of {amount} {}; it now holds {}.",
                family.name(),
                describe(totals[family.index()])
            ),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_block_amount_round_trips_through_its_payload() {
        assert_eq!(saved_amount(&save_amount(5_000)), 5_000);
        assert_eq!(saved_amount(&save_amount(0)), 0);
        assert_eq!(saved_amount(&Compound::new()), 0);
    }

    #[test]
    fn an_energizer_state_round_trips_through_its_payload() {
        let mut energizer = Energizer::new();
        energizer.tick(8, 0);
        let payload = save_energizer(&energizer);
        let loaded = load_energizer(&payload);
        assert_eq!(loaded.buffer(), energizer.buffer());
        assert_eq!(loaded.active(), energizer.active());
        // A payload with no buffer key is a fresh energizer.
        let fresh = load_energizer(&Compound::new());
        assert_eq!(fresh.buffer(), runtime::ENERGIZER_BUFFER);
        assert!(!fresh.active());
    }

    #[test]
    fn a_carried_payload_names_the_block_entity_type_and_the_amount_only() {
        let patch = carried_patch(5_000);
        // The drop carries vanilla's `minecraft:block_entity_data`, tagged with our type id.
        let Some(Tag::Compound(payload)) = lookup(&patch, BLOCK_ENTITY_DATA) else {
            panic!("the patch is the block entity data component: {patch:?}");
        };
        assert_eq!(saved_amount(payload), 5_000);
        assert_eq!(
            lookup(payload, "id"),
            Some(&Tag::String(BE_TYPE.into())),
            "the engine loads a payload only for the type its id names"
        );
        // The engine spills a container's stacks itself, so a payload must carry no `Items`
        // (HANDOVER §9m): this block has none, and the fresh payload proves it.
        assert!(lookup(payload, "Items").is_none());
    }

    #[test]
    fn a_payloads_amount_is_read_from_any_integer_tag_a_player_may_write() {
        assert_eq!(
            saved_amount(&compound([("Amount", Tag::Long(5_000))])),
            5_000
        );
        // A payload written by hand in SNBT may name an int or a byte; both are that amount.
        assert_eq!(
            saved_amount(&compound([("Amount", Tag::Int(5_000))])),
            5_000
        );
        assert_eq!(saved_amount(&compound([("Amount", Tag::Byte(64))])), 64);
        // A negative amount, a wrong type and an absent key are no amount at all.
        assert_eq!(saved_amount(&compound([("Amount", Tag::Long(-5))])), 0);
        assert_eq!(
            saved_amount(&compound([("Amount", Tag::String("5".into()))])),
            0
        );
        assert_eq!(saved_amount(&Compound::new()), 0);
    }

    #[test]
    fn the_block_entity_type_covers_every_block_the_content_declares() {
        let ids = block_ids();
        assert_eq!(ids.len(), 31);
        assert!(
            ids.iter()
                .any(|id| id == "refinedtypes:64k_energy_storage_block")
        );
        assert!(
            ids.iter()
                .any(|id| id == "refinedtypes:2097152k_soul_storage_block")
        );
        assert!(
            ids.iter()
                .any(|id| id == "refinedtypes:8388608b_source_storage_block")
        );
        assert!(ids.iter().any(|id| id == ENERGIZER_BLOCK));
        // Every one is a node, and no node is missing from the list.
        for id in &ids {
            assert!(Node::from_block(id).is_some(), "{id}");
        }
    }
}
