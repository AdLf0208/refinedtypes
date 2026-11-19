#!/usr/bin/env python3
"""Make the parent's package buildable by the launcher, for the in-game leg only.

`ports/refinedstorage` as shipped declares a second SDK path dependency
(`horizon-core`, for `JavaString`) that the launcher cannot stage — it provides no
`horizon_core` extern, so the build fails with `No such file or directory (os error 2)`
(measured: `ports/_shared/evidence/refinedtypes-e2e/launcher-externs.md`). This script
copies the parent's package and applies the one mechanical, behaviour-preserving change
that removes the dependency: compound keys go through `Tag::compound` and `Tag::get(&str)`,
which the API itself provides.

It writes `ports/_shared/evidence/refinedtypes-e2e/parent/refinedstorage/` — a **fixture**,
never a change to `ports/refinedstorage` (read-only for this job). Every replacement is
exact: a snippet that no longer matches stops the script instead of patching the wrong
thing.

    python3 tools/parent-fixture.py
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
CAMPAIGN = PORT.parents[1]
PARENT = CAMPAIGN / "ports/refinedstorage"
FIXTURE = CAMPAIGN / "ports/_shared/evidence/refinedtypes-e2e/parent/refinedstorage"

# What the copy leaves behind: build products and the port's own tooling.
SKIP = {"target", ".horizon", "refinedstorage.hmod", "tools", "notes.md", "FINDINGS.md",
        "VALIDATION.md", "README.md", "AGENTS.md", "Cargo.lock"}

# (file, old, new) — exact text, applied once each.
PATCHES: list[tuple[str, str, str]] = [
    (
        "Cargo.toml",
        """# The SDK's NBT crate, for the one type the API does not re-export: a compound's
# key (`JavaString`), which `Compound::insert` takes. Same path as the API's own
# dependency, so it is one crate instance, not a second copy.
horizon-core = { path = ".horizon/sdk/api/crates/horizon-core" }
""",
        """# The fixture drops the parent's `horizon-core` dependency: the launcher provides no
# `horizon_core` extern, so a package that depends on it cannot be built (see
# ports/_shared/evidence/refinedtypes-e2e/launcher-externs.md). Compound keys go through
# `Tag::compound` / `Tag::get(&str)` instead — the same change, made for the e2e only.
""",
    ),
    (
        "src/support.rs",
        "use horizon_core::nbt::JavaString;\n",
        "",
    ),
    (
        "src/support.rs",
        "let Some(Tag::List(marks)) = entity.nbt.get(&JavaString::from(VIEW_KEY)) else {",
        "let Some(Tag::List(marks)) = lookup(&entity.nbt, VIEW_KEY) else {",
    ),
    (
        "src/support.rs",
        'state.owned[index] = matches!(mark.get(&JavaString::from("owned")), Some(Tag::Byte(1)));',
        'state.owned[index] = matches!(lookup(mark, "owned"), Some(Tag::Byte(1)));',
    ),
    (
        "src/support.rs",
        'let Some(Tag::Compound(item)) = mark.get(&JavaString::from("item")) else {',
        'let Some(Tag::Compound(item)) = lookup(mark, "item") else {',
    ),
    (
        "src/support.rs",
        """            let mut mark = Compound::new();
            if owned.get(index).copied().unwrap_or(false) {
                mark.insert(JavaString::from("owned"), Tag::Byte(1));
            }
            if let Some(item) = slots
                .get(index)
                .and_then(|slot| slot.as_ref())
                .and_then(|stack| stack.stack().to_nbt(host))
            {
                mark.insert(JavaString::from("item"), Tag::Compound(item));
            }
            Tag::Compound(mark)""",
        """            let mut entries: Vec<(&str, Tag)> = Vec::new();
            if owned.get(index).copied().unwrap_or(false) {
                entries.push(("owned", Tag::Byte(1)));
            }
            if let Some(item) = slots
                .get(index)
                .and_then(|slot| slot.as_ref())
                .and_then(|stack| stack.stack().to_nbt(host))
            {
                entries.push(("item", Tag::Compound(item)));
            }
            Tag::compound(entries)""",
    ),
    (
        "src/support.rs",
        """    entity
        .nbt
        .insert(JavaString::from(VIEW_KEY), Tag::List(marks));""",
        """    // The fixture replaces the payload rather than inserting one key: the grid's saved
    // data holds nothing but this view, so the result is the same.
    entity.nbt = match Tag::compound([(VIEW_KEY, Tag::List(marks))]) {
        Tag::Compound(compound) => compound,
        _ => Compound::new(),
    };""",
    ),
    (
        "src/support.rs",
        "/// A disk cache key: the dimension, the drive's position and its slot.",
        """/// A compound's entry by its text, without naming `JavaString` (which a package built by
/// the launcher cannot reach).
fn lookup<'a>(payload: &'a Compound, key: &str) -> Option<&'a Tag> {
    payload
        .iter()
        .find(|(name, _)| name.to_string_lossy() == key)
        .map(|(_, tag)| tag)
}

/// A disk cache key: the dimension, the drive's position and its slot.""",
    ),
]


def main() -> int:
    if not (PARENT / "horizon-mod.toml").is_file():
        print(f"missing parent: {PARENT}", file=sys.stderr)
        return 2
    if FIXTURE.exists():
        shutil.rmtree(FIXTURE)
    FIXTURE.mkdir(parents=True)
    for entry in sorted(PARENT.iterdir()):
        if entry.name in SKIP:
            continue
        if entry.is_dir():
            shutil.copytree(entry, FIXTURE / entry.name)
        else:
            shutil.copy2(entry, FIXTURE / entry.name)
    for name, old, new in PATCHES:
        target = FIXTURE / name
        text = target.read_text()
        if text.count(old) != 1:
            print(
                f"FAIL: {name}: the snippet occurs {text.count(old)} times, expected once:\n{old}",
                file=sys.stderr,
            )
            return 1
        target.write_text(text.replace(old, new))
    print(f"fixture: {FIXTURE} ({len(PATCHES)} patches applied to the parent's own sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
