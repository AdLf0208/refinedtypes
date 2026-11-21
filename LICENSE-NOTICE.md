# Refined Types — provenance of the carried content

`assets/refinedtypes/**` and the tag and loot-table files under `data/` are carried from the
upstream mod's own jar, byte for byte (loot tables upgraded to the 26.3 shape by
`tools/carry.py`); the block and item declarations under `data/refinedtypes/horizon/` are
generated from the jar's ids, and `data/refinedtypes/recipe/**` is the jar's recipe family
converted to the 26.3 dialect (bare ingredient ids, no loader conditions). `tools/carry.py
--check` re-derives every file and compares it.

| | |
|---|---|
| Mod | Refined Types 1.21.1-0.3.2 |
| Jar | `refined-types-1.21.1-0.3.2.jar` (761 entries) |
| Jar SHA-256 | `2373c5b8f1309a43bc25bc0c8f4cfc1f3cb0b725ceafe89311aa74e3e75f7b0d` |
| Upstream | <https://github.com/starforcraft/Refined-Types>, branch `1.21.1`, commit `6a53289a4f7582dfae719c3e8bb2c33c4913373a` |
| Author | Starforcraft (Ultramega) |
| Licence | MIT — see `LICENSE`, the upstream `LICENSE.txt` |
| Mod id / namespace | `refinedtypes` |

The mod's code is **not** carried: this port is a clean-room Rust rewrite of the behaviour
(`notes.md` §"Upstream source analysis"). What travels is the mod's own art, models, lang and
data, under the MIT licence above.
