#!/usr/bin/env python3
"""Carry Refined Types' content out of its jar, and prove the carried tree.

    python3 tools/carry.py            # write assets/, data/, LICENSE, LICENSE-NOTICE.md
    python3 tools/carry.py --check    # re-derive every file and compare, byte for byte

What is carried, and from where:

  * `assets/refinedtypes/**` — every entry the jar ships (blockstates, models, textures,
    lang), byte-identical. `assets/refinedtypes/items/*.json` is **generated**: 1.21.4+
    item-model definitions the 1.21.1 jar does not have, one per item the jar models.
  * `data/refinedtypes/tags/item/*.json` and `data/minecraft/tags/block/mineable/pickaxe.json`
    — byte-identical.
  * `data/refinedtypes/loot_table/blocks/*.json` — the jar's table, upgraded to the 26.3
    shape (one `condition` instead of a list, the entry's `functions` hoisted to the table's
    `modifier`, `copy_name` becoming `copy_components` of the custom name) exactly as the
    pipeline upgrades `ports/refinedstorage`'s.
  * `data/refinedtypes/horizon/{block,item}/*.json` — the template mapping the content root
    reads: one declaration per block and per item, generated from the jar's own ids. A storage
    disk and a storage block also declare `fireResistant()` as 26.3 spells it
    (`minecraft:damage_resistant` over `#minecraft:is_fire`, upstream's six
    `*StorageDiskItem`/`*StorageBlockBlockItem` constructors); a part and the energizer do not,
    because upstream's `SimpleItem` and `NetworkNodeBlockItem` do not.
  * `data/refinedtypes/recipe/**` — the jar's 109 recipes, converted to the 26.3 dialect: one
    bare id or one `#tag` per ingredient (the 1.21.1 `{"item": …}` / `{"tag": …}` object form is
    rejected at load), no `neoforge:conditions` (an unknown load condition drops the file) and
    no `category`. Two recipes cannot load at this pin and are skipped with the reason printed:
    `part/64b_source_storage_part.json` names `ars_nouveau:magebloom_fiber` (Ars Nouveau is not
    ported) and `network_energizer.json` names `refinedstorage:interface` (the parent does not
    ship it). Every other ingredient is `minecraft:`, `refinedtypes:` or an id the parent port
    itself declares; `--check` cross-checks that against `../refinedstorage/data/`, so a parent
    rename fails here instead of silently dropping recipes in game.
  * `LICENSE` (the upstream MIT text) and `LICENSE-NOTICE.md` (provenance).

Deliberately **not** carried, and printed by `--check` so the omission is explicit: the
jar's `data/refinedtypes/advancement/**` — they only unlock recipes in the recipe book, which
is a client-list feature with no gameplay at this pin.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
CAMPAIGN = PORT.parents[1]
JAR = CAMPAIGN / "ports/_shared/licence-cache/refined-types-1.21.1-0.3.2.jar"
UPSTREAM_LICENSE = PORT / "tools/upstream-license.txt"

NAMESPACE = "refinedtypes"
ASSETS = f"assets/{NAMESPACE}/"
DATA = f"data/{NAMESPACE}/"
RECIPE = DATA + "recipe/"
VANILLA_TAG = "data/minecraft/tags/block/mineable/pickaxe.json"
PARENT = PORT.parent / "refinedstorage"

# The parent is a required dependency and the authority for its own ids and `c:` tags: a
# refinedtypes recipe that names a parent item the parent does not declare cannot load, so
# `parent_ids()` / `declared_tags()` read the parent port's data instead of a copied list.
TAGS_USED = ("c:glass_blocks", "c:dusts/redstone", "c:silicon")

# The jar's own tier spellings, in the order its enums declare them.
TIERS = {
    "energy": ["64k", "256k", "1024k", "8192k", "65536k", "262144k", "1048576k", "8388608k"],
    "soul": ["1k", "8k", "64k", "512k", "4096k", "32768k", "262144k", "2097152k"],
    "source": ["64b", "256b", "1024b", "8192b", "65536b", "262144b", "1048576b", "8388608b"],
}
UNBOUNDED = ["infinite", "creative"]
ENERGIZER = "network_energizer"


def tier_names() -> list[str]:
    return [f"{tier}_{family}" for family, tiers in TIERS.items() for tier in tiers + UNBOUNDED]


def block_names() -> list[str]:
    return [f"{name}_storage_block" for name in tier_names()] + [ENERGIZER]


def item_names() -> list[str]:
    """The items that are not block items: disks and parts."""
    names = []
    for name in tier_names():
        names.append(f"{name}_storage_disk")
        # The creative tier ships no part (there is nothing to craft it from).
        if not name.startswith("creative_"):
            names.append(f"{name}_storage_part")
    return names


def json_bytes(value: object, newline: bool) -> bytes:
    text = json.dumps(value, indent=2, sort_keys=True)
    return (text + "\n" if newline else text).encode()


def item_model(name: str) -> bytes:
    return json_bytes(
        {"model": {"model": f"{NAMESPACE}:item/{name}", "type": "minecraft:model"}}, False
    )


# `Item.Properties.fireResistant()` at 26.3, in the component table's own spelling. A
# fire-resistant item declares the `minecraft:damage_resistant` component naming the
# `#minecraft:is_fire` damage tag — exactly what vanilla's `minecraft:netherite_ingot` entry in
# `items.json` carries — and the engine reads it as `ItemInfo.fire_resistant`
# (`horizon-items/src/items.rs`) and as `Items::resists_fire` for a stack, which is what keeps
# a dropped item alive in lava. One rule, applied where upstream applies it:
#   * `EnergyStorageDiskItem` / `SoulStorageDiskItem` / `SourceStorageDiskItem`:
#     `new Item.Properties().stacksTo(1).fireResistant()`  -> fire resistant;
#   * `*StorageBlockBlockItem`:                                `...stacksTo(1).fireResistant()` -> fire resistant;
#   * `SimpleItem` (the parts) and `NetworkEnergizerBlock.createBlockItem()`
#     (`NetworkNodeBlockItem` over `BlockConstants.PROPERTIES`): no `fireResistant()` -> plain.
FIREPROOF = {"minecraft:damage_resistant": {"types": "#minecraft:is_fire"}}


def block_declaration(name: str) -> bytes:
    declaration = {
        "template": "minecraft:iron_block",
        "properties": {
            "hardness": 4.5,
            "explosion_resistance": 6.0,
            "requires_tool": True,
            "light": 0,
            "map_color": 11,
            "sounds": "minecraft:stone",
        },
        "item": True,
    }
    if name == ENERGIZER:
        # The jar's blockstate has `active=false|true` (NetworkEnergizerBlock).
        declaration["state_properties"] = {"active": {"type": "boolean"}}
        declaration["default_state"] = {"active": "false"}
        # The one block of the jar that opens a menu (upstream `NetworkEnergizerBlock.useWithoutItem`
        # -> `openMenu`). A content block opens its menu through its template's class, and a
        # template that opens one is a workstation: `minecraft:smithing_table` is a menu-opening
        # class with no state properties of its own, so the block's state stays the jar's
        # `active` alone (`minecraft:barrel`, what the parent's container blocks use, would add
        # `facing` and `open` and change the blockstate the jar ships).
        declaration["template"] = "minecraft:smithing_table"
    else:
        # `*StorageBlockBlockItem` is the fire-resistant item of a storage block; the
        # energizer's block item is not.
        declaration["components"] = FIREPROOF
    return json_bytes(declaration, True)


def item_declaration(name: str) -> bytes:
    disk = name.endswith("_storage_disk")
    declaration = {
        "template": "minecraft:paper",
        # A storage disk is one item (`stacksTo(1)`); a part stacks.
        "max_stack_size": 1 if disk else 64,
        "rarity": "common",
    }
    if disk:
        # `*StorageDiskItem`: `new Item.Properties().stacksTo(1).fireResistant()`.
        declaration["components"] = FIREPROOF
    return json_bytes(declaration, True)


def menu_declaration() -> bytes:
    """The energizer's menu type, the mod's only menu (`registry/Menus`).

    Upstream's `NetworkEnergizerContainerMenu` holds no container slots of its own (only
    the player's inventory; the energy readout travels in `NetworkEnergizerEnergyInfoPacket`).
    A menu type at this pin declares at least one slot, so it declares one and the port's
    `screen` hides it — which also keeps it out of the server's menu.

    The eight data slots are the readout: the stored amount and the capacity it is measured
    against, four 16-bit limbs each (a data slot is a `short` on the wire, so a `u64` cannot
    ride in one).
    """
    return json_bytes({"slots": 1, "data_slots": 8}, True)


def upgrade_loot(raw: bytes) -> bytes:
    """The jar's loot table in the 26.3 shape (see the module doc)."""
    table = json.loads(raw)
    modifier: list[dict] = []
    pools = []
    for pool in table["pools"]:
        upgraded = {key: value for key, value in pool.items() if key != "conditions"}
        # 26.3's own block tables (all 1139 of them) carry no `bonus_rolls` and write an
        # integral roll as `1`; the game accepts the 1.21.1 spellings, but normalising keeps
        # the package green under `ports/tools/check_261_dialect.py` at no behaviour cost
        # (the e2e breaks a block and asserts the drop).
        if upgraded.pop("bonus_rolls", None) not in (None, 0, 0.0):
            raise SystemExit(f"loot pool with a non-zero bonus_rolls: {pool}")
        rolls = upgraded.get("rolls")
        if isinstance(rolls, float) and rolls.is_integer():
            upgraded["rolls"] = int(rolls)
        conditions = pool.get("conditions")
        if conditions:
            if len(conditions) != 1:
                raise SystemExit(f"loot pool with {len(conditions)} conditions: {conditions}")
            # 1.21.1 spells a predicate's discriminator `condition`; 26.3 wants `type`.
            predicate = dict(conditions[0])
            if "condition" in predicate:
                predicate["type"] = predicate.pop("condition")
            upgraded["condition"] = predicate
        entries = []
        for entry in pool["entries"]:
            entry = dict(entry)
            for function in entry.pop("functions", []):
                if function["function"] != "minecraft:copy_name":
                    raise SystemExit(f"unhandled loot function {function}")
                modifier.append(
                    {
                        "include": ["minecraft:custom_name"],
                        "source": "block_entity",
                        "type": "minecraft:copy_components",
                    }
                )
            entries.append(entry)
        upgraded["entries"] = entries
        pools.append(upgraded)
    out: dict[str, object] = {"type": table["type"], "pools": pools}
    if "random_sequence" in table:
        out["random_sequence"] = table["random_sequence"]
    if modifier:
        out["modifier"] = modifier
    return json_bytes(out, False)


def notice(sha256: str, entries: int) -> bytes:
    return f"""# Refined Types — provenance of the carried content

`assets/refinedtypes/**` and the tag and loot-table files under `data/` are carried from the
upstream mod's own jar, byte for byte (loot tables upgraded to the 26.3 shape by
`tools/carry.py`); the block and item declarations under `data/refinedtypes/horizon/` are
generated from the jar's ids, and `data/refinedtypes/recipe/**` is the jar's recipe family
converted to the 26.3 dialect (bare ingredient ids, no loader conditions). `tools/carry.py
--check` re-derives every file and compares it.

| | |
|---|---|
| Mod | Refined Types 1.21.1-0.3.2 |
| Jar | `refined-types-1.21.1-0.3.2.jar` ({entries} entries) |
| Jar SHA-256 | `{sha256}` |
| Upstream | <https://github.com/starforcraft/Refined-Types>, branch `1.21.1`, commit `6a53289a4f7582dfae719c3e8bb2c33c4913373a` |
| Author | Starforcraft (Ultramega) |
| Licence | MIT — see `LICENSE`, the upstream `LICENSE.txt` |
| Mod id / namespace | `refinedtypes` |

The mod's code is **not** carried: this port is a clean-room Rust rewrite of the behaviour
(`notes.md` §"Upstream source analysis"). What travels is the mod's own art, models, lang and
data, under the MIT licence above.
""".encode()


def parent_ids() -> set[str]:
    """Every id the parent port declares (block items and plain items)."""
    ids: set[str] = set()
    for kind in ("block", "item"):
        for path in sorted((PARENT / f"data/refinedstorage/horizon/{kind}").glob("*.json")):
            ids.add(f"refinedstorage:{path.stem}")
    return ids


def declared_tags() -> set[str]:
    """Every `c:` tag the parent (or this package) declares, as `c:path/to/tag`."""
    tags: set[str] = set()
    for root in (PARENT / "data/c/tags/item", PORT / "data/c/tags/item"):
        for path in sorted(root.rglob("*.json")):
            tags.add("c:" + path.relative_to(root).with_suffix("").as_posix())
    return tags


def own_ids() -> set[str]:
    """Every item id this package declares (block items included)."""
    return {f"{NAMESPACE}:{name}" for name in block_names() + item_names()}


def ingredient(spec: object, where: str) -> str:
    """One ingredient in the 26.3 shape: a bare id or `#tag`."""
    if isinstance(spec, str):
        return spec
    if isinstance(spec, dict) and len(spec) == 1:
        if "item" in spec:
            return str(spec["item"])
        if "tag" in spec:
            return "#" + str(spec["tag"])
    raise SystemExit(f"{where}: unhandled ingredient {spec!r} (only item/tag objects exist)")


def skip_reason(spec: str, parent: set[str], tags: set[str], own: set[str]) -> str | None:
    """Why a recipe naming SPEC cannot load at this pin, or None when it can."""
    if spec.startswith("#"):
        tag = spec[1:]
        return None if tag in tags else f"tag #{tag} is declared by neither package"
    namespace = spec.partition(":")[0]
    if namespace in ("minecraft", NAMESPACE):
        return None if namespace == "minecraft" or spec in own else f"{spec} is not declared here"
    if namespace == "refinedstorage":
        return None if spec in parent else f"{spec} is not declared by the parent port"
    return f"{spec} is in a namespace this game does not have"


def convert_recipe(raw: dict, name: str, parent: set[str], tags: set[str],
                   own: set[str]) -> tuple[bytes, None] | tuple[None, str]:
    """One jar recipe in the 26.3 dialect, or the reason it cannot be carried."""
    kind = raw.get("type")
    if kind not in ("minecraft:crafting_shaped", "minecraft:crafting_shapeless"):
        raise SystemExit(f"{name}: unexpected recipe type {kind!r}")
    if kind == "minecraft:crafting_shaped":
        ingredients = [ingredient(value, name) for value in raw["key"].values()]
    else:
        ingredients = [ingredient(value, name) for value in raw["ingredients"]]
    for spec in ingredients:
        reason = skip_reason(spec, parent, tags, own)
        if reason is not None:
            return None, reason
    result = {"id": raw["result"]["id"]}
    if raw["result"].get("count", 1) != 1:
        result["count"] = raw["result"]["count"]
    out: dict[str, object] = {"type": kind, "result": result}
    if kind == "minecraft:crafting_shaped":
        out["pattern"] = raw["pattern"]
        out["key"] = {key: ingredient(value, name) for key, value in raw["key"].items()}
    else:
        out["ingredients"] = ingredients
    return json_bytes(out, True), None


def recipe_files(jar: zipfile.ZipFile) -> tuple[dict[str, bytes], list[str]]:
    """The carried recipes, and one printed line per recipe that cannot load here."""
    parent, tags, own = parent_ids(), declared_tags(), own_ids()
    missing = [tag for tag in TAGS_USED if tag not in tags]
    if missing:
        raise SystemExit(
            f"the recipes need {missing}, which neither package declares "
            f"(read: {PARENT}/data/c/tags/item)"
        )
    files: dict[str, bytes] = {}
    skipped: list[str] = []
    for name in sorted(jar.namelist()):
        if not name.startswith(RECIPE) or not name.endswith(".json"):
            continue
        raw = json.loads(jar.read(name))
        converted, reason = convert_recipe(raw, name, parent, tags, own)
        if converted is None:
            skipped.append(f"{name[len(RECIPE):]}: {reason}")
        else:
            files[name] = converted
    return files, skipped


def expected(jar: zipfile.ZipFile) -> dict[str, bytes]:
    """Every file the port's content tree must hold, by path, with its bytes."""
    files: dict[str, bytes] = {}
    for name in jar.namelist():
        if name.endswith("/"):
            continue
        if name.startswith(ASSETS):
            files[name] = jar.read(name)
        elif name.startswith(DATA):
            if name.startswith(DATA + "loot_table/blocks/"):
                files[name] = upgrade_loot(jar.read(name))
            elif name.startswith(DATA + "tags/item/"):
                files[name] = jar.read(name)
        elif name == VANILLA_TAG:
            files[name] = jar.read(name)
    # The 1.21.4+ item-model definitions, one per item the jar models.
    for name in item_model_names(jar):
        files[f"{ASSETS}items/{name}.json"] = item_model(name)
    # The template mapping.
    for name in block_names():
        files[f"{DATA}horizon/block/{name}.json"] = block_declaration(name)
    for name in item_names():
        files[f"{DATA}horizon/item/{name}.json"] = item_declaration(name)
    # The energizer's menu type: the mod's only menu (upstream declares it in code).
    files[f"{DATA}horizon/menu/energizer.json"] = menu_declaration()
    # The recipe family, converted to the 26.3 dialect.
    recipes, _ = recipe_files(jar)
    files.update(recipes)
    # The licence and its notice.
    files["LICENSE"] = UPSTREAM_LICENSE.read_bytes()
    sha256 = hashlib.sha256(JAR.read_bytes()).hexdigest()
    files["LICENSE-NOTICE.md"] = notice(sha256, len(jar.namelist()))
    return files


def item_model_names(jar: zipfile.ZipFile) -> list[str]:
    prefix = f"{ASSETS}models/item/"
    return sorted(
        name[len(prefix) : -len(".json")]
        for name in jar.namelist()
        if name.startswith(prefix) and name.endswith(".json") and not name.endswith("/")
    )


def left_out(jar: zipfile.ZipFile) -> list[str]:
    """Jar entries the port deliberately does not carry (the module doc says why)."""
    return sorted(
        name
        for name in jar.namelist()
        if not name.endswith("/")
        and name.startswith(DATA)
        and name.startswith(DATA + "advancement/")
    )


def check() -> int:
    jar = zipfile.ZipFile(JAR)
    files = expected(jar)
    problems: list[str] = []
    for path, want in files.items():
        target = PORT / path
        if not target.is_file():
            problems.append(f"missing: {path}")
        elif target.read_bytes() != want:
            problems.append(f"differs from the jar's or the rule's bytes: {path}")
    # Nothing unexplained under the two carried trees.
    for root in ("assets", "data"):
        for target in sorted((PORT / root).rglob("*")):
            if target.is_dir():
                continue
            rel = str(target.relative_to(PORT))
            if rel not in files:
                problems.append(f"unexplained file: {rel}")
    omitted = left_out(jar)
    recipes, skipped = recipe_files(jar)
    print(f"carry: {len(files)} files checked against {JAR.name}")
    print(f"carry: {len(recipes)} recipes carried in the 26.3 dialect")
    for line in skipped:
        print(f"carry: skipped recipe {line}")
    print(f"carry: {len(omitted)} jar files deliberately left out (advancement unlocks only)")
    if problems:
        for problem in problems:
            print(f"FAIL: {problem}", file=sys.stderr)
        return 1
    print("carry: every carried file matches; nothing unexplained")
    return 0


def carry() -> int:
    jar = zipfile.ZipFile(JAR)
    files = expected(jar)
    for path, data in files.items():
        target = PORT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    omitted = left_out(jar)
    recipes, skipped = recipe_files(jar)
    print(f"carry: wrote {len(files)} files")
    print(f"carry: {len(recipes)} recipes in the 26.3 dialect")
    for line in skipped:
        print(f"carry: skipped recipe {line}")
    print(f"carry: left out {len(omitted)} jar files (advancement unlocks only; see the module doc)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="re-derive and compare instead of writing")
    args = parser.parse_args()
    for needed in (JAR, UPSTREAM_LICENSE):
        if not needed.is_file():
            print(f"missing: {needed}", file=sys.stderr)
            return 2
    return check() if args.check else carry()


if __name__ == "__main__":
    raise SystemExit(main())
