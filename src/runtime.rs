//! Refined Types' pure model: the three resource families, their storage tiers and
//! capacities, the stores, the network component the storage lives on, and the
//! Network Energizer's accounting.
//!
//! No `mod_api` types here: this file builds and tests with `cargo test` alone, which
//! is what keeps the numbers honest. The game glue is [`crate::support`].

use std::collections::HashSet;

/// NeoForge's `FluidType.BUCKET_VOLUME`, which is what RS2's `Platform.getBucketAmount()`
/// answers — the unit the Source tiers are declared in (`SourceStorageVariant`).
pub const BUCKET: u64 = 1_000;

/// The Network Energizer's internal buffer (`EnergyStorageImpl(1000)` in
/// `NetworkEnergizerBlockEntity`), filled once at construction as the load-time kick-start.
pub const ENERGIZER_BUFFER: u64 = 1_000;

/// What a creative store answers for `getStored()` (`CreativeStorageImpl`: `Long.MAX_VALUE`).
pub const CREATIVE_STORED: u64 = i64::MAX as u64;

/// The component walk's cap, the same one the parent's network uses.
pub const NETWORK_LIMIT: usize = 512;

/// The three resource types Refined Storage does not store itself.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Family {
    /// Forge Energy, the `energy` family.
    Energy,
    /// Malum-style souls, the `soul` family.
    Soul,
    /// Ars Nouveau source, the `source` family.
    Source,
}

impl Family {
    /// Every family, in the order the jar declares them (energy, source, soul in the lang
    /// file; energy, soul, source here, matching the tier spellings' sort).
    pub const ALL: [Family; 3] = [Family::Energy, Family::Soul, Family::Source];

    /// The name the ids and the command use.
    pub fn name(self) -> &'static str {
        match self {
            Family::Energy => "energy",
            Family::Soul => "soul",
            Family::Source => "source",
        }
    }

    /// The index into [`totals`]' array.
    pub fn index(self) -> usize {
        match self {
            Family::Energy => 0,
            Family::Soul => 1,
            Family::Source => 2,
        }
    }

    /// The family a name names, if it is one of the three.
    pub fn from_name(name: &str) -> Option<Family> {
        Family::ALL.into_iter().find(|family| family.name() == name)
    }
}

/// What a storage tier holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Capacity {
    /// A fixed amount, the finite tiers.
    Bounded(u64),
    /// No limit, and it grows on insert: the `infinite` tier.
    Infinite,
    /// Always full and never emptied: the `creative` tier (`CreativeStorageImpl`).
    Creative,
}

/// One tier of one family: the pair an id names.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Variant {
    family: Family,
    tier: usize,
}

/// The three things a variant's id can be: a crafting part, a disk, a block.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum IdKind {
    /// `refinedtypes:<name>_storage_part`.
    Part,
    /// `refinedtypes:<name>_storage_disk`.
    Disk,
    /// `refinedtypes:<name>_storage_block`.
    Block,
}

impl IdKind {
    /// The id suffix of this kind.
    fn suffix(self) -> &'static str {
        match self {
            IdKind::Part => "storage_part",
            IdKind::Disk => "storage_disk",
            IdKind::Block => "storage_block",
        }
    }

    /// The kind an id suffix names.
    fn from_suffix(suffix: &str) -> Option<IdKind> {
        [IdKind::Part, IdKind::Disk, IdKind::Block]
            .into_iter()
            .find(|kind| kind.suffix() == suffix)
    }
}

/// The tier names, in tier order, for the finite tiers: energy and source count in
/// thousands of the unit, souls in 1024s (`EnergyStorageVariant`/`SourceStorageVariant`/
/// `SoulStorageVariant`).
const ENERGY_NAMES: [&str; 8] = [
    "64k", "256k", "1024k", "8192k", "65536k", "262144k", "1048576k", "8388608k",
];
const SOUL_NAMES: [&str; 8] = [
    "1k", "8k", "64k", "512k", "4096k", "32768k", "262144k", "2097152k",
];
const SOURCE_NAMES: [&str; 8] = [
    "64b", "256b", "1024b", "8192b", "65536b", "262144b", "1048576b", "8388608b",
];
/// The two unbounded tiers, after the eight finite ones.
const INFINITE_TIER: usize = 8;
const CREATIVE_TIER: usize = 9;
/// The configured energy usage of each finite tier (`Config.java`: 2, 4, 6, 8, 10, 12, 14, 16),
/// then `infinite` (18); `creative` costs nothing.
const USAGE_LADDER: [u64; 8] = [2, 4, 6, 8, 10, 12, 14, 16];
const INFINITE_USAGE: u64 = 18;

impl Variant {
    /// The number of tiers a family has: eight finite, infinite, creative.
    pub const TIERS: usize = 10;

    /// The variant of a family and a tier index, if both are in range.
    pub fn new(family: Family, tier: usize) -> Option<Variant> {
        (tier < Variant::TIERS).then_some(Variant { family, tier })
    }

    /// The family.
    pub fn family(self) -> Family {
        self.family
    }

    /// The tier's name as the jar spells it in its ids.
    pub fn name(self) -> &'static str {
        match self.tier {
            INFINITE_TIER => "infinite",
            CREATIVE_TIER => "creative",
            tier => {
                let names = match self.family {
                    Family::Energy => ENERGY_NAMES,
                    Family::Soul => SOUL_NAMES,
                    Family::Source => SOURCE_NAMES,
                };
                names[tier]
            }
        }
    }

    /// What this tier holds.
    pub fn capacity(self) -> Capacity {
        match self.tier {
            INFINITE_TIER => Capacity::Infinite,
            CREATIVE_TIER => Capacity::Creative,
            tier => Capacity::Bounded(match self.family {
                // `k x 1000` FE.
                Family::Energy => finite_name_value(ENERGY_NAMES[tier]) * 1_000,
                // `k x 1024` souls.
                Family::Soul => finite_name_value(SOUL_NAMES[tier]) * 1_024,
                // `b x BUCKET`.
                Family::Source => finite_name_value(SOURCE_NAMES[tier]) * BUCKET,
            }),
        }
    }

    /// The energy a block of this tier costs the network each tick.
    pub fn usage(self) -> u64 {
        match self.tier {
            CREATIVE_TIER => 0,
            INFINITE_TIER => INFINITE_USAGE,
            tier => USAGE_LADDER[tier],
        }
    }

    /// The variant a tier name names, in a family.
    pub fn from_name(family: Family, name: &str) -> Option<Variant> {
        let names = match family {
            Family::Energy => ENERGY_NAMES,
            Family::Soul => SOUL_NAMES,
            Family::Source => SOURCE_NAMES,
        };
        if name == "infinite" {
            return Variant::new(family, INFINITE_TIER);
        }
        if name == "creative" {
            return Variant::new(family, CREATIVE_TIER);
        }
        names
            .iter()
            .position(|known| *known == name)
            .and_then(|tier| Variant::new(family, tier))
    }

    /// This variant's id as one of the three kinds.
    pub fn id(self, kind: IdKind) -> String {
        format!(
            "refinedtypes:{}_{}_{}",
            self.name(),
            self.family.name(),
            kind.suffix()
        )
    }

    /// The variant and kind an id names, or `None` for any other id (the energizer's
    /// included).
    pub fn from_id(id: &str) -> Option<(Variant, IdKind)> {
        let rest = id.strip_prefix("refinedtypes:")?;
        let (name, tail) = rest.split_once('_')?;
        let (family, suffix) = tail.split_once('_')?;
        let family = Family::from_name(family)?;
        let kind = IdKind::from_suffix(suffix)?;
        Some((Variant::from_name(family, name)?, kind))
    }
}

/// The number in a finite tier's name (`"64k"` -> 64, `"8192b"` -> 8192).
fn finite_name_value(name: &str) -> u64 {
    name.trim_end_matches(['k', 'b'])
        .parse()
        .expect("the tier names are constants")
}

/// One typed storage: a capacity and what it holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Store {
    capacity: Capacity,
    amount: u64,
}

impl Store {
    /// An empty store of a capacity.
    pub fn new(capacity: Capacity) -> Store {
        Store {
            capacity,
            amount: match capacity {
                Capacity::Creative => CREATIVE_STORED,
                _ => 0,
            },
        }
    }

    /// A store loaded with an amount, clamped to what its capacity can hold.
    pub fn with_stored(capacity: Capacity, amount: u64) -> Store {
        let mut store = Store::new(capacity);
        store.set_stored(amount);
        store
    }

    /// What the store is.
    pub fn capacity(&self) -> Capacity {
        self.capacity
    }

    /// What it holds; a creative store is always full.
    pub fn stored(&self) -> u64 {
        match self.capacity {
            Capacity::Creative => CREATIVE_STORED,
            _ => self.amount,
        }
    }

    /// How much of `amount` it took.
    pub fn insert(&mut self, amount: u64) -> u64 {
        match self.capacity {
            Capacity::Creative => amount,
            Capacity::Infinite => {
                self.amount = self.amount.saturating_add(amount);
                amount
            }
            Capacity::Bounded(limit) => {
                let room = limit.saturating_sub(self.amount);
                let taken = amount.min(room);
                self.amount += taken;
                taken
            }
        }
    }

    /// How much it gave.
    pub fn extract(&mut self, amount: u64) -> u64 {
        match self.capacity {
            Capacity::Creative => amount,
            _ => {
                let taken = amount.min(self.amount);
                self.amount -= taken;
                taken
            }
        }
    }

    /// Replace what it holds, clamped to the capacity (the load path).
    pub fn set_stored(&mut self, amount: u64) {
        self.amount = match self.capacity {
            Capacity::Creative => CREATIVE_STORED,
            Capacity::Infinite => amount,
            Capacity::Bounded(limit) => amount.min(limit),
        };
    }
}

/// A block that is on a Refined Storage network, or the add-on's own.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Node {
    /// The parent's controller: a component with one is online.
    Controller,
    /// The parent's cable.
    Cable,
    /// The parent's disk drive, whose slots hold storage disks.
    DiskDrive,
    /// The parent's grid.
    Grid,
    /// One of the add-on's 30 storage blocks.
    Storage(Variant),
    /// The add-on's Network Energizer.
    Energizer,
}

impl Node {
    /// The node a block id is, or `None` when the block is not a network node.
    pub fn from_block(id: &str) -> Option<Node> {
        match id {
            "refinedstorage:controller" => Some(Node::Controller),
            "refinedstorage:cable" => Some(Node::Cable),
            "refinedstorage:disk_drive" => Some(Node::DiskDrive),
            "refinedstorage:grid" => Some(Node::Grid),
            "refinedtypes:network_energizer" => Some(Node::Energizer),
            other => Variant::from_id(other)
                .filter(|(_, kind)| *kind == IdKind::Block)
                .map(|(variant, _)| Node::Storage(variant)),
        }
    }
}

/// The six face neighbours of a position, in the order north, east, south, west, up, down.
pub fn neighbours(pos: [i32; 3]) -> [[i32; 3]; 6] {
    [
        [pos[0], pos[1], pos[2] - 1],
        [pos[0] + 1, pos[1], pos[2]],
        [pos[0], pos[1], pos[2] + 1],
        [pos[0] - 1, pos[1], pos[2]],
        [pos[0], pos[1] + 1, pos[2]],
        [pos[0], pos[1] - 1, pos[2]],
    ]
}

/// The connected component of nodes a position belongs to.
#[derive(Clone, Debug, Default)]
pub struct Network {
    nodes: Vec<([i32; 3], Node)>,
}

impl Network {
    /// How many nodes the component has.
    #[cfg_attr(
        not(test),
        expect(dead_code, reason = "the walk's size is what the tests assert on")
    )]
    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    /// A component is online when it holds a controller: the parent's rule.
    pub fn online(&self) -> bool {
        self.nodes.iter().any(|(_, node)| *node == Node::Controller)
    }

    /// How many nodes answer `predicate`.
    pub fn count(&self, predicate: impl Fn(&Node) -> bool) -> usize {
        self.nodes
            .iter()
            .filter(|(_, node)| predicate(node))
            .count()
    }

    /// The parent's disk drives.
    pub fn drives(&self) -> Vec<[i32; 3]> {
        self.nodes
            .iter()
            .filter(|(_, node)| *node == Node::DiskDrive)
            .map(|(pos, _)| *pos)
            .collect()
    }

    /// The add-on's storage blocks, with their variants.
    pub fn storages(&self) -> Vec<([i32; 3], Variant)> {
        self.nodes
            .iter()
            .filter_map(|(pos, node)| match node {
                Node::Storage(variant) => Some((*pos, *variant)),
                _ => None,
            })
            .collect()
    }

    /// The add-on's energizers.
    pub fn energizers(&self) -> Vec<[i32; 3]> {
        self.nodes
            .iter()
            .filter(|(_, node)| *node == Node::Energizer)
            .map(|(pos, _)| *pos)
            .collect()
    }

    /// The energy the add-on's nodes cost the network each tick.
    pub fn usage(&self) -> u64 {
        self.nodes
            .iter()
            .map(|(_, node)| match node {
                Node::Storage(variant) => variant.usage(),
                // The energizer's own `getEnergyUsage()` is 0.
                _ => 0,
            })
            .sum()
    }
}

/// The component a position belongs to, read through `at`, capped at [`NETWORK_LIMIT`].
pub fn network(start: [i32; 3], at: impl Fn([i32; 3]) -> Option<Node>) -> Network {
    let mut network = Network::default();
    let Some(first) = at(start) else {
        return network;
    };
    let mut seen = HashSet::new();
    seen.insert(start);
    network.nodes.push((start, first));
    let mut next = 0;
    while next < network.nodes.len() && network.nodes.len() < NETWORK_LIMIT {
        let (pos, _) = network.nodes[next];
        next += 1;
        for neighbour in neighbours(pos) {
            if network.nodes.len() >= NETWORK_LIMIT {
                break;
            }
            if !seen.insert(neighbour) {
                continue;
            }
            if let Some(node) = at(neighbour) {
                network.nodes.push((neighbour, node));
            }
        }
    }
    network
}

/// One typed storage on the network: a block's or a disk's.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Holding {
    /// The tier it is.
    pub variant: Variant,
    /// What it holds and how much it can.
    pub store: Store,
}

impl Holding {
    /// A holding of a variant loaded with an amount, clamped to its tier.
    pub fn new(variant: Variant, amount: u64) -> Holding {
        Holding {
            variant,
            store: Store::with_stored(variant.capacity(), amount),
        }
    }
}

/// One family's total across the network's holdings.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Totals {
    /// Everything the family's storages hold.
    pub stored: u64,
    /// What they could hold together: creative beats infinite beats the sum.
    pub capacity: Capacity,
}

/// The three families' totals, indexed by [`Family::index`].
pub fn totals(holdings: &[Holding]) -> [Totals; 3] {
    let mut totals = [Totals {
        stored: 0,
        capacity: Capacity::Bounded(0),
    }; 3];
    for family in Family::ALL {
        let of_family = holdings
            .iter()
            .filter(|holding| holding.variant.family() == family);
        let mut sum = 0u64;
        let mut bounded = 0u64;
        let mut capacity = Capacity::Bounded(0);
        for holding in of_family {
            sum = sum.saturating_add(holding.store.stored());
            match (capacity, holding.store.capacity()) {
                (_, Capacity::Creative) => capacity = Capacity::Creative,
                (Capacity::Creative, _) => {}
                (_, Capacity::Infinite) => capacity = Capacity::Infinite,
                (Capacity::Infinite, _) => {}
                (Capacity::Bounded(_), Capacity::Bounded(limit)) => {
                    bounded = bounded.saturating_add(limit);
                    capacity = Capacity::Bounded(bounded);
                }
            }
        }
        let stored = match capacity {
            Capacity::Creative => CREATIVE_STORED,
            _ => sum,
        };
        totals[family.index()] = Totals { stored, capacity };
    }
    totals
}

/// What one tick of the Network Energizer took from where.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Draw {
    /// What the network's energy storage gave.
    pub from_storage: u64,
    /// What the energizer's own buffer gave.
    pub from_buffer: u64,
}

/// The Network Energizer: a buffer, and whether the network's usage is covered.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Energizer {
    buffer: u64,
    active: bool,
}

impl Default for Energizer {
    fn default() -> Self {
        Energizer::new()
    }
}

impl Energizer {
    /// A freshly placed energizer: its buffer full, inactive until it has run a tick.
    pub fn new() -> Energizer {
        Energizer {
            buffer: ENERGIZER_BUFFER,
            active: false,
        }
    }

    /// An energizer loaded from a saved payload.
    pub fn with_state(buffer: u64, active: bool) -> Energizer {
        Energizer {
            buffer: buffer.min(ENERGIZER_BUFFER),
            active,
        }
    }

    /// What is left in the buffer.
    pub fn buffer(&self) -> u64 {
        self.buffer
    }

    /// Whether the last tick covered the network's usage.
    pub fn active(&self) -> bool {
        self.active
    }

    /// One tick: `usage` FE is needed and the network's energy storage holds `available`
    /// (a creative storage reports [`CREATIVE_STORED`], so it always covers). The storage is
    /// drawn first, the buffer only for what is left.
    pub fn tick(&mut self, usage: u64, available: u64) -> Draw {
        let from_storage = usage.min(available);
        let shortfall = usage - from_storage;
        let from_buffer = shortfall.min(self.buffer);
        self.buffer -= from_buffer;
        self.active = from_storage + from_buffer == usage;
        Draw {
            from_storage,
            from_buffer,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    #[test]
    fn the_tier_table_is_the_jars_capacities() {
        // Energy: `k x 1000` (`EnergyStorageVariant`: K_64(64_000L) ... K_8388608(8_388_608_000L)).
        assert_eq!(
            Variant::new(Family::Energy, 0).unwrap().capacity(),
            Capacity::Bounded(64_000)
        );
        assert_eq!(
            Variant::new(Family::Energy, 7).unwrap().capacity(),
            Capacity::Bounded(8_388_608_000)
        );
        // Soul: `k x 1024` (`SoulStorageVariant`: K_1(1L) ... K_2097152(2097152L)).
        assert_eq!(
            Variant::new(Family::Soul, 0).unwrap().capacity(),
            Capacity::Bounded(1_024)
        );
        assert_eq!(
            Variant::new(Family::Soul, 7).unwrap().capacity(),
            Capacity::Bounded(2_147_483_648)
        );
        // Source: `b x Platform.getBucketAmount()` = 1000 on NeoForge (`B_64(64L) ...`).
        assert_eq!(
            Variant::new(Family::Source, 0).unwrap().capacity(),
            Capacity::Bounded(64_000)
        );
        assert_eq!(
            Variant::new(Family::Source, 7).unwrap().capacity(),
            Capacity::Bounded(8_388_608_000)
        );
        for family in Family::ALL {
            assert_eq!(
                Variant::new(family, 8).unwrap().capacity(),
                Capacity::Infinite
            );
            assert_eq!(
                Variant::new(family, 9).unwrap().capacity(),
                Capacity::Creative
            );
            assert!(Variant::new(family, Variant::TIERS).is_none());
        }
    }

    #[test]
    fn the_names_are_the_jars_own_spellings() {
        assert_eq!(Variant::new(Family::Energy, 0).unwrap().name(), "64k");
        assert_eq!(Variant::new(Family::Energy, 7).unwrap().name(), "8388608k");
        assert_eq!(Variant::new(Family::Soul, 0).unwrap().name(), "1k");
        assert_eq!(Variant::new(Family::Soul, 7).unwrap().name(), "2097152k");
        assert_eq!(Variant::new(Family::Source, 3).unwrap().name(), "8192b");
        assert_eq!(Variant::new(Family::Energy, 8).unwrap().name(), "infinite");
        assert_eq!(Variant::new(Family::Source, 9).unwrap().name(), "creative");
        assert_eq!(
            Variant::new(Family::Energy, 0).unwrap().id(IdKind::Disk),
            "refinedtypes:64k_energy_storage_disk"
        );
        assert_eq!(
            Variant::new(Family::Soul, 0).unwrap().id(IdKind::Block),
            "refinedtypes:1k_soul_storage_block"
        );
        assert_eq!(
            Variant::new(Family::Source, 7).unwrap().id(IdKind::Part),
            "refinedtypes:8388608b_source_storage_part"
        );
    }

    #[test]
    fn every_id_the_jar_ships_parses_back_to_its_variant() {
        for family in Family::ALL {
            for tier in 0..Variant::TIERS {
                let variant = Variant::new(family, tier).unwrap();
                for kind in [IdKind::Part, IdKind::Disk, IdKind::Block] {
                    let id = variant.id(kind);
                    assert_eq!(Variant::from_id(&id), Some((variant, kind)), "{id}");
                }
            }
        }
        assert_eq!(Variant::from_id("refinedtypes:network_energizer"), None);
        assert_eq!(Variant::from_id("refinedstorage:1k_storage_disk"), None);
        assert_eq!(
            Variant::from_id("refinedtypes:64k_energy_storage_widget"),
            None
        );
    }

    #[test]
    fn the_usage_ladder_is_the_configs_defaults() {
        // Config.java: 2, 4, 6, 8, 10, 12, 14, 16, infinite 18, creative 0 — for all three
        // families.
        let ladder = [2, 4, 6, 8, 10, 12, 14, 16];
        for family in Family::ALL {
            for (tier, want) in ladder.iter().enumerate() {
                assert_eq!(
                    Variant::new(family, tier).unwrap().usage(),
                    *want,
                    "{family:?} tier {tier}"
                );
            }
            assert_eq!(Variant::new(family, 8).unwrap().usage(), 18);
            assert_eq!(Variant::new(family, 9).unwrap().usage(), 0);
        }
    }

    #[test]
    fn a_bounded_store_takes_only_what_fits_and_gives_only_what_it_has() {
        let mut store = Store::new(Capacity::Bounded(64_000));
        assert_eq!(store.stored(), 0);
        assert_eq!(store.insert(5_000), 5_000);
        assert_eq!(store.stored(), 5_000);
        assert_eq!(store.insert(70_000), 59_000, "the rest does not fit");
        assert_eq!(store.stored(), 64_000);
        assert_eq!(store.insert(1), 0, "a full store takes nothing");
        assert_eq!(store.extract(64_001), 64_000, "it gives what it has");
        assert_eq!(store.stored(), 0);
        assert_eq!(store.extract(1), 0);
    }

    #[test]
    fn an_infinite_store_never_refuses_and_keeps_growing() {
        let mut store = Store::new(Capacity::Infinite);
        assert_eq!(store.insert(1_000_000), 1_000_000);
        assert_eq!(store.stored(), 1_000_000);
        assert_eq!(
            store.insert(u64::MAX),
            u64::MAX,
            "no limit to what it takes"
        );
        assert_eq!(store.stored(), u64::MAX, "it saturates rather than wraps");
        assert_eq!(store.extract(400_000), 400_000);
        assert_eq!(store.stored(), u64::MAX - 400_000);
        assert_eq!(store.capacity(), Capacity::Infinite);
    }

    #[test]
    fn a_creative_store_is_always_full_and_never_empties() {
        // `CreativeStorageImpl`: stored `Long.MAX_VALUE`, extract returns the amount asked
        // and never decreases, insert returns the amount asked.
        let mut store = Store::new(Capacity::Creative);
        assert_eq!(store.stored(), CREATIVE_STORED);
        assert_eq!(store.extract(5_000), 5_000);
        assert_eq!(store.stored(), CREATIVE_STORED);
        assert_eq!(store.insert(5_000), 5_000);
        assert_eq!(store.stored(), CREATIVE_STORED);
    }

    #[test]
    fn a_loaded_amount_is_clamped_to_the_capacity() {
        let store = Store::with_stored(Capacity::Bounded(1_024), 9_999);
        assert_eq!(store.stored(), 1_024);
        let store = Store::with_stored(Capacity::Creative, 0);
        assert_eq!(store.stored(), CREATIVE_STORED);
    }

    #[test]
    fn the_network_is_the_face_adjacent_component_of_nodes() {
        let mut world: HashMap<[i32; 3], Node> = HashMap::new();
        world.insert([0, 64, 0], Node::Controller);
        world.insert([1, 64, 0], Node::Cable);
        world.insert([2, 64, 0], Node::DiskDrive);
        world.insert(
            [3, 64, 0],
            Node::Storage(Variant::new(Family::Soul, 2).unwrap()),
        );
        // A diagonal neighbour is not face-adjacent.
        world.insert(
            [4, 65, 0],
            Node::Storage(Variant::new(Family::Energy, 0).unwrap()),
        );
        let net = network([1, 64, 0], |pos| world.get(&pos).copied());
        assert_eq!(net.len(), 4);
        assert!(net.online());
        assert_eq!(net.count(|node| *node == Node::Controller), 1);
        assert_eq!(net.drives().len(), 1);
        assert_eq!(net.storages().len(), 1);
        assert_eq!(net.energizers().len(), 0);
        // From the diagonal block the component is that block alone.
        let alone = network([4, 65, 0], |pos| world.get(&pos).copied());
        assert_eq!(alone.len(), 1);
        assert!(!alone.online());
    }

    #[test]
    fn a_network_without_a_controller_is_offline() {
        let mut world: HashMap<[i32; 3], Node> = HashMap::new();
        world.insert([0, 64, 0], Node::Cable);
        world.insert([1, 64, 0], Node::Energizer);
        let net = network([0, 64, 0], |pos| world.get(&pos).copied());
        assert_eq!(net.len(), 2);
        assert!(!net.online());
    }

    #[test]
    fn the_walk_does_not_pass_through_a_block_that_is_not_a_node() {
        let mut world: HashMap<[i32; 3], Node> = HashMap::new();
        world.insert([0, 64, 0], Node::Controller);
        // (1,64,0) is a vanilla block: the walk stops there.
        world.insert([2, 64, 0], Node::Grid);
        let net = network([0, 64, 0], |pos| world.get(&pos).copied());
        assert_eq!(net.len(), 1);
    }

    #[test]
    fn the_walk_is_capped() {
        // A line of nodes longer than the cap stops at the cap, as the parent's does.
        let net = network([0, 0, 0], |pos| {
            (pos[0] >= 0 && pos[1] == 0 && pos[2] == 0 && pos[0] < 10_000).then_some(Node::Cable)
        });
        assert_eq!(net.len(), NETWORK_LIMIT);
    }

    #[test]
    fn totals_add_one_family_and_keep_its_strongest_capacity() {
        let holdings = [
            Holding::new(Variant::new(Family::Energy, 0).unwrap(), 5_000),
            Holding::new(Variant::new(Family::Energy, 0).unwrap(), 1_000),
            Holding::new(Variant::new(Family::Soul, 1).unwrap(), 8),
        ];
        let sums = totals(&holdings);
        let energy = sums[Family::Energy.index()];
        assert_eq!(energy.stored, 6_000);
        assert_eq!(energy.capacity, Capacity::Bounded(128_000));
        let soul = sums[Family::Soul.index()];
        assert_eq!(soul.stored, 8);
        assert_eq!(soul.capacity, Capacity::Bounded(8_192));
        let source = sums[Family::Source.index()];
        assert_eq!(source.stored, 0);
        assert_eq!(source.capacity, Capacity::Bounded(0));

        // One creative or infinite storage makes the family's capacity that.
        let mixed = [
            Holding::new(Variant::new(Family::Source, 0).unwrap(), 0),
            Holding::new(Variant::new(Family::Source, 8).unwrap(), 7),
        ];
        assert_eq!(
            totals(&mixed)[Family::Source.index()].capacity,
            Capacity::Infinite
        );
        assert_eq!(totals(&mixed)[Family::Source.index()].stored, 7);
        let creative = [Holding::new(Variant::new(Family::Source, 9).unwrap(), 0)];
        assert_eq!(
            totals(&creative)[Family::Source.index()].capacity,
            Capacity::Creative
        );
        assert_eq!(
            totals(&creative)[Family::Source.index()].stored,
            CREATIVE_STORED
        );
    }

    #[test]
    fn the_energizer_draws_the_usage_from_storage_first_and_then_its_buffer() {
        let mut energizer = Energizer::new();
        assert_eq!(energizer.buffer(), ENERGIZER_BUFFER);
        assert!(!energizer.active());
        // Storage covers it: the buffer is untouched.
        let draw = energizer.tick(8, 5_000);
        assert_eq!(draw.from_storage, 8);
        assert_eq!(draw.from_buffer, 0);
        assert_eq!(energizer.buffer(), ENERGIZER_BUFFER);
        assert!(energizer.active());
        // Storage is short by 5: the buffer covers the rest.
        let draw = energizer.tick(8, 3);
        assert_eq!(draw.from_storage, 3);
        assert_eq!(draw.from_buffer, 5);
        assert_eq!(energizer.buffer(), ENERGIZER_BUFFER - 5);
        assert!(energizer.active());
    }

    #[test]
    fn an_energizer_that_cannot_cover_the_usage_goes_inactive() {
        let mut energizer = Energizer::new();
        // 1000 FE buffer, 8 FE a tick: 125 ticks, then nothing left.
        for _ in 0..(ENERGIZER_BUFFER / 8) {
            let draw = energizer.tick(8, 0);
            assert_eq!(draw.from_storage, 0);
            assert!(energizer.active(), "the buffer still covers the usage");
        }
        assert_eq!(energizer.buffer(), 0);
        let draw = energizer.tick(8, 0);
        assert_eq!(draw.from_buffer, 0);
        assert!(!energizer.active(), "nothing covers the usage");
    }

    #[test]
    fn an_energizer_with_nothing_to_power_is_active() {
        let mut energizer = Energizer::new();
        let draw = energizer.tick(0, 0);
        assert_eq!(draw.from_storage, 0);
        assert_eq!(draw.from_buffer, 0);
        assert!(energizer.active());
        assert_eq!(energizer.buffer(), ENERGIZER_BUFFER);
    }

    #[test]
    fn a_node_is_recognised_from_the_block_id() {
        assert_eq!(
            Node::from_block("refinedstorage:controller"),
            Some(Node::Controller)
        );
        assert_eq!(Node::from_block("refinedstorage:cable"), Some(Node::Cable));
        assert_eq!(
            Node::from_block("refinedstorage:disk_drive"),
            Some(Node::DiskDrive)
        );
        assert_eq!(Node::from_block("refinedstorage:grid"), Some(Node::Grid));
        assert_eq!(
            Node::from_block("refinedtypes:network_energizer"),
            Some(Node::Energizer)
        );
        assert_eq!(
            Node::from_block("refinedtypes:64k_energy_storage_block"),
            Some(Node::Storage(Variant::new(Family::Energy, 0).unwrap()))
        );
        assert_eq!(Node::from_block("minecraft:stone"), None);
    }

    #[test]
    fn the_six_neighbours_are_the_faces_in_a_fixed_order() {
        assert_eq!(
            neighbours([0, 0, 0]),
            [
                [0, 0, -1],
                [1, 0, 0],
                [0, 0, 1],
                [-1, 0, 0],
                [0, 1, 0],
                [0, -1, 0]
            ]
        );
    }
}
