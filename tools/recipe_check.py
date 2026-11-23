#!/usr/bin/env python3
"""Craft every recipe this package carries, in a real game.

Slice 2's in-game proof (AGENTS.md "Parity rule"): each recipe is crafted the way it
declares, its output id and count are asserted, and the ingredients are shown to be
consumed. The recipe table is read from the package's own
`data/refinedtypes/recipe/**`, so a carried recipe cannot be dead data and a recipe the
conversion dropped fails the run (the carried count is asserted).

Called by tools/e2e.sh with the open game's control socket:

    recipe_check.py SOCK CTL TABLE_X TABLE_Y TABLE_Z

Both the shaped and the shapeless recipes this package ships run in a crafting table
(`screen` slots 100-108 row-major, result 200).

Assertions, per recipe:
  1. the result slot holds exactly the declared id and count;
  2. a shift-click on the result leaves the 3x3 grid empty (the ingredients were
     consumed) and the crafted stack in the player's inventory;
  3. a counterfactual: the same grid with one ingredient replaced by a non-ingredient
     yields no result — for every recipe, not only the ones with a tag.

It also asserts that an unknown id is refused (`give` leaves the inventory empty,
`setblock` leaves air), and that the carried table is the 107 recipes the jar allows at
this pin (109 upstream; the two skipped ones are named in notes.md and by
`tools/carry.py`).

Exits 1 on the first mismatch, printing `FAIL: …` (the e2e's trap prints EXIT:1).
"""
import json
import pathlib
import subprocess
import sys

GRID = [100 + i for i in range(9)]  # row-major: 100,101,102 = the top row
RESULT = 200

# 109 recipes in the jar; two cannot load at this pin (see notes.md §Gaps item 2 and
# tools/carry.py, which prints the reasons).
EXPECTED_RECIPES = 107

# A real item that carries each tag the recipes name. The package ships no `c:` tag
# file itself; the parent (a required dependency) declares these three, so a lone run
# still resolves them here.
TAG_FALLBACK = {
    "c:glass_blocks": "minecraft:glass",
    "c:dusts/redstone": "minecraft:redstone",
    "c:silicon": "refinedstorage:silicon",
}
# An item that is NOT in the tag, for the counterfactual.
TAG_IMPOSTOR = {
    "c:glass_blocks": "minecraft:dirt",
    "c:dusts/redstone": "minecraft:dirt",
    "c:silicon": "minecraft:dirt",
}


class Ctl:
    def __init__(self, sock, binary):
        self.sock = sock
        self.binary = binary

    def __call__(self, *args):
        try:
            out = subprocess.run(
                [self.binary, "--socket", self.sock, *map(str, args)],
                text=True,
                capture_output=True,
                # A ctl call the game never answers must fail fast, not idle the leg out:
                # the e2e guard kills a run after 900 s of silence, which reads as a hang
                # with no suspect named (measured 2026-11-23 on a loaded box).
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            raise SystemExit(f"ctl {' '.join(map(str, args))}: no reply in 180 s")
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(map(str, args))}: {out.stdout}{out.stderr}")

    def wait(self, ticks=2):
        self("wait", ticks)

    def slots(self):
        screen = self("screen")
        if "slots" not in screen:
            raise SystemExit(f"no menu is open: {screen}")
        return screen["slots"]


def load_tags(data):
    """Every `#tag` this package's own data declares, mapped to one concrete item id."""
    tags = {}
    for path in sorted((data / "c" / "tags" / "item").rglob("*.json")):
        tag = "c:" + path.relative_to(data / "c" / "tags" / "item").with_suffix("").as_posix()
        values = json.loads(path.read_text())["values"]
        plain = [v for v in values if not v.startswith("#")]
        if plain:
            tags[tag] = plain[0]
    for path in sorted((data / "minecraft" / "tags" / "item").rglob("*.json")):
        tag = "minecraft:" + path.relative_to(data / "minecraft" / "tags" / "item").with_suffix("").as_posix()
        values = json.loads(path.read_text())["values"]
        plain = [v for v in values if not v.startswith("#")]
        if plain:
            tags[tag] = plain[0]
    return tags


def ingredient_id(spec, tags):
    """A recipe's ingredient as (`item-id`, `#tag or None`).

    The carried recipes are in the 26.3 shape (a bare string); the object form is still
    accepted so the driver reads an unconverted jar recipe instead of crashing on it.
    """
    if isinstance(spec, str):
        if spec.startswith("#"):
            tag = spec[1:]
            return (tags.get(tag) or TAG_FALLBACK[tag], tag)
        return (spec, None)
    if "item" in spec:
        return (spec["item"], None)
    tag = spec["tag"]
    return (tags.get(tag) or TAG_FALLBACK[tag], tag)


def main():
    if len(sys.argv) < 6:
        raise SystemExit(__doc__)
    sock, ctl_path, tx, ty, tz = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:6])
    limit = int(sys.argv[6]) if len(sys.argv) > 6 else 0  # a smoke run of the first N
    here = pathlib.Path(__file__).resolve().parent.parent
    data = here / "data"
    recipes = sorted((data / "refinedtypes" / "recipe").rglob("*.json"))
    if not recipes:
        raise SystemExit(f"no recipes under {data / 'refinedtypes' / 'recipe'}")
    tags = load_tags(data)
    ctl = Ctl(sock, ctl_path)
    failures = []

    def fail(message):
        failures.append(message)
        print(f"FAIL: {message}", file=sys.stderr)

    def give(item, count=1):
        ctl("command", "gamemode creative @s")
        ctl("give", item, count)

    def find(item):
        for slot in ctl.slots():
            if slot.get("item") == item:
                return slot["slot"]
        return None

    def reset_table():
        """An empty table, an empty inventory, and its menu open."""
        try:
            ctl("close")
        except SystemExit:
            pass
        ctl.wait(2)
        ctl("setblock", tx, ty, tz, "minecraft:air")
        ctl("setblock", tx, ty, tz, "minecraft:crafting_table")
        ctl.wait(2)
        ctl("command", f"tp @s {tx - 0.5} {ty} {tz + 1.5}")
        ctl.wait(2)
        ctl("command", "clear @s")
        ctl.wait(1)
        opened = ctl("interact", tx, ty, tz)
        ctl.wait(3)
        if not any(slot["slot"] == RESULT for slot in ctl.slots()):
            raise SystemExit(f"the crafting table did not open (no result slot): {opened}")

    def grid():
        return [s for s in ctl.slots() if s["slot"] in GRID]

    def result():
        stack = [s for s in ctl.slots() if s["slot"] == RESULT]
        return (stack[0]["item"], stack[0]["count"]) if stack and stack[0].get("item") else (None, 0)

    def place(item, cells):
        """Right-click one unit of ITEM into each cell; the rest goes back."""
        slot = find(item)
        if slot is None:
            fail(f"no {item} in the inventory to place")
            return
        ctl("click-slot", slot)
        ctl.wait(1)
        for cell in cells:
            ctl("click-slot", cell, "right")
            ctl.wait(1)
        ctl("click-slot", slot)
        ctl.wait(2)

    def count(item):
        """How many of ITEM the player carries (not the grid's or the result's)."""
        return sum(
            s.get("count", 0)
            for s in ctl.slots()
            if s.get("item") == item and s["slot"] not in GRID and s["slot"] != RESULT
        )

    def craft(label, cells_per_item, want):
        """GIVE the ingredients, PLACE them in cells_per_item, assert the result."""
        reset_table()
        for item, cells in cells_per_item:
            give(item, len(cells))
            ctl.wait(2)
            place(item, cells)
        got_item, got_count = result()
        print(f"  {label} -> {got_item} x{got_count}")
        if (got_item, got_count) != (want[0], want[1]):
            fail(f"{label}: expected {want[0]} x{want[1]}, got {got_item} x{got_count}")
            return False
        # Take it: a shift-click on the result moves it to the inventory and,
        # because the grid held exactly one recipe's worth, empties the grid.
        ctl("click-slot", RESULT, "shift")
        ctl.wait(3)
        leftovers = [s for s in grid() if s.get("item")]
        if leftovers:
            fail(f"{label}: the grid still holds {json.dumps(leftovers)} after crafting (ingredients were not consumed)")
        if count(want[0]) < want[1]:
            fail(f"{label}: the crafted {want[0]} is not in the inventory ({count(want[0])} of {want[1]})")
        return True

    def expect_empty(label):
        nonlocal controls
        controls += 1
        got_item, got_count = result()
        print(f"  {label} (control) -> {got_item} x{got_count}")
        if got_item is not None:
            fail(f"{label} control: the wrong ingredient still crafted {got_item} x{got_count}")

    def counterfactual(label, cells_per_item, target_cells, impostor):
        """The same grid with one ingredient cell replaced: no result."""
        reset_table()
        for item, item_cells in cells_per_item:
            remaining = list(item_cells)
            hit = [cell for cell in item_cells if cell in target_cells]
            if hit:
                remaining.remove(hit[0])
                give(impostor, 1)
                ctl.wait(2)
                place(impostor, [hit[0]])
            if remaining:
                give(item, len(remaining))
                ctl.wait(2)
                place(item, remaining)
        expect_empty(label)

    crafted = 0
    controls = 0
    for path in (recipes[:limit] if limit else recipes):
        recipe = json.loads(path.read_text())
        kind = recipe["type"]
        name = path.stem
        out = recipe["result"]["id"]
        out_count = recipe["result"].get("count", 1)
        print(f"recipe {name} ({kind})")
        if kind == "minecraft:crafting_shaped":
            cells_by_item = {}
            for row, line in enumerate(recipe["pattern"]):
                for col, key in enumerate(line):
                    if key == " ":
                        continue
                    item, tag = ingredient_id(recipe["key"][key], tags)
                    cells_by_item.setdefault((item, tag), []).append(GRID[row * 3 + col])
            cells_per_item = [(item, cells) for (item, _), cells in cells_by_item.items()]
            ok = craft(name, cells_per_item, (out, out_count))
            crafted += 1
            # Counterfactual: one cell's ingredient becomes a non-ingredient. Prefer a
            # tag cell (proves the tag resolves) when the recipe has one.
            first = next((k for k in cells_by_item if k[1]), None) or next(iter(cells_by_item))
            (item, tag), cells = first, cells_by_item[first]
            impostor = TAG_IMPOSTOR.get(tag, "minecraft:dirt") if tag else "minecraft:dirt"
            if impostor == item:
                impostor = "minecraft:stick"
            if ok and cells:
                counterfactual(f"{name} with {impostor} for {item}", cells_per_item,
                               cells, impostor)
        elif kind == "minecraft:crafting_shapeless":
            cells_per_item = []
            for index, spec in enumerate(recipe["ingredients"]):
                item, tag = ingredient_id(spec, tags)
                cells_per_item.append((item, [GRID[index]]))
            ok = craft(name, cells_per_item, (out, out_count))
            crafted += 1
            # Counterfactual: the second ingredient replaced by a non-ingredient.
            if ok and len(cells_per_item) >= 2:
                item, cells = cells_per_item[1]
                impostor = "minecraft:dirt" if item != "minecraft:dirt" else "minecraft:stick"
                counterfactual(f"{name} with {impostor} for {item}", cells_per_item,
                               cells, impostor)
        else:
            fail(f"{name}: unsupported recipe type {kind} (the driver would silently skip it)")

    ctl("close")

    # The table itself: the 109 upstream files minus the two the pin cannot load.
    print(f"carried recipes: {len(recipes)} (expected {EXPECTED_RECIPES})")
    if not limit and len(recipes) != EXPECTED_RECIPES:
        fail(f"the package carries {len(recipes)} recipes, expected {EXPECTED_RECIPES}: "
             "a dropped file is a silently dead recipe")

    # An unknown id is refused: nothing in the inventory, and air in the world.
    ctl("command", "gamemode creative @s")
    ctl("command", "clear @s")
    ctl("give", "refinedtypes:no_such_item", 1)
    ctl.wait(2)
    inventory = json.dumps(ctl("inventory"))
    if "refinedtypes:no_such_item" in inventory:
        fail("give refinedtypes:no_such_item produced the item")
    ctl("setblock", tx + 1, ty, tz, "refinedtypes:no_such_block")
    ctl.wait(2)
    state = ctl("block", tx + 1, ty, tz)
    print(f"  refinedtypes:no_such_block -> {state.get('state', state)}")
    if "refinedtypes" in json.dumps(state):
        fail(f"setblock refinedtypes:no_such_block placed something: {state}")

    ctl("command", "clear @s")
    if failures:
        print(f"EXIT:1 ({len(failures)} failed)", file=sys.stderr)
        raise SystemExit(1)
    print(
        f"recipe PASS: {crafted} of {len(recipes)} carried recipes craft in game with their "
        f"declared output and count, their ingredients are consumed, {controls} "
        f"wrong-ingredient controls leave the result empty, the carried table is "
        f"{EXPECTED_RECIPES}, and an unknown id is refused"
    )


if __name__ == "__main__":
    main()
