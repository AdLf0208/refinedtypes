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
    reads: one declaration per block and per item, generated from the jar's own ids.
  * `LICENSE` (the upstream MIT text) and `LICENSE-NOTICE.md` (provenance).

Deliberately **not** carried, and printed by `--check` so the omission is explicit: the
jar's `data/refinedtypes/recipe/**` and `data/refinedtypes/advancement/**`. Every recipe
needs `refinedstorage:machine_casing` (the parent has no crafting chain), `c:dusts/redstone`
(a NeoForge tag absent at 26.3) and `neoforge:conditions` (no such condition at 26.3); the
advancements only unlock those recipes. Shipping them would be dead data that cannot parse.
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
VANILLA_TAG = "data/minecraft/tags/block/mineable/pickaxe.json"

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
    return json_bytes(declaration, True)


def item_declaration(name: str) -> bytes:
    disk = name.endswith("_storage_disk")
    return json_bytes(
        {
            "template": "minecraft:paper",
            # A storage disk is one item (`stacksTo(1)`); a part stacks.
            "max_stack_size": 1 if disk else 64,
            "rarity": "common",
        },
        True,
    )


def upgrade_loot(raw: bytes) -> bytes:
    """The jar's loot table in the 26.3 shape (see the module doc)."""
    table = json.loads(raw)
    modifier: list[dict] = []
    pools = []
    for pool in table["pools"]:
        upgraded = {key: value for key, value in pool.items() if key != "conditions"}
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
generated from the jar's ids. `tools/carry.py --check` re-derives every file and compares it.

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
        and (
            name.startswith(DATA + "recipe/")
            or name.startswith(DATA + "advancement/")
        )
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
    print(f"carry: {len(files)} files checked against {JAR.name}")
    print(f"carry: {len(omitted)} jar files deliberately left out (recipes and their advancements)")
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
    print(f"carry: wrote {len(files)} files")
    print(f"carry: left out {len(omitted)} jar files (recipes and their advancements; see the module doc)")
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
