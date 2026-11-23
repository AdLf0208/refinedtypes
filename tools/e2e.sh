
#!/usr/bin/env bash
# In-game check for Refined Types (slice 1): FE / Soul / Source storage on a Refined
# Storage network.
#
# The game is built from **two** packages — the parent (Refined Storage) and this add-on —
# by `tools/build-game.sh`; the exports it prints are what this script reads.
#
# The End arena (stone floor at y=63, the network at y=64):
#   controller 40 - cable 41 - disk drive 42 - network energizer 43 -
#   64k energy block 44 - 64k soul block 45
# The energizer sits between the drive and the storage blocks so that breaking the storage
# blocks leaves it on the network (its component still reaches the controller through the
# drive), which is what the drain legs need.
# Every mod command is typed with `ctl chat "/cmd"` because `ctl command` runs the console
# path and bypasses the native command hook.
#
# Default run (the modded game):
#  - the three families' blocks exist and the energizer's network is online with 2 storage
#    blocks, 1 energizer, 1 controller and 1 drive; `energy 0/64000`, `soul 0/65536`
#    (the jar's tiers), `usage 8 FE/t` (2 for the 64k energy block + 6 for the 64k soul one);
#  - with nothing in the energy storage the energizer runs on its 1000 FE buffer and goes
#    inactive when that is gone (`energizer 0/1000 inactive`, block state `active=false`);
#  - `/refinedtypes insert ... energy 5000` fills the 64k block (`energy 5000/64000`), the
#    energizer is active again, and the storage drains by the usage over the next ticks;
#  - breaking the soul block drops the usage to 2 FE/t: the usage is the nodes';
#  - with no energy storage at all a deposit is refused (the network took 0);
#  - a refinedtypes disk right-clicked onto the parent's drive goes into it and leaves the
#    hand, and is then the network's only energy storage: a deposit lands in it
#    (`energy 4000/64000`) and the energizer drains it (the amount is written back into the
#    disk's item component each tick);
#  - a broken controller takes the network offline (totals 0, deposits refused), and the
#    disk still holds what it held when the controller comes back.
#
# Slice 3 (0.1.3): a broken storage block's own item carries the amount it held. A 256k
# block on its own network (controller + cable, no energizer, so nothing draws) takes 5,000,
# is broken with a pickaxe, the drop's `data get entity @s SelectedItem` carries
# `minecraft:block_entity_data` with `Amount:5000`, and placing that item back reads
# `energy 5000/256000` again. The differentials: a freshly given block places `0/256000`, and
# a payload doctored to 999,999,999 places `256000/256000` (clamped).
#
# Slice 4 (0.1.4): the Network Energizer's menu — the mod's only menu. A 256k network takes
# 5,000, the energizer is used, and the port's menu opens with the readout in its eight data
# slots (the stored amount and the capacity, four 16-bit limbs each). `/refinedtypes menu`
# reads them back, a screenshot measures the 16×70 bar, and a network with nothing but the
# energizer's own 1,000 FE buffer is the full-bar differential.
#
# Slice 5 (0.1.5): a storage disk and a storage block are fire resistant, as upstream declares
# them (`*StorageDiskItem`/`*StorageBlockBlockItem`: `...fireResistant()`). At 26.3 that is the
# `minecraft:damage_resistant` component over `#minecraft:is_fire`, so a dropped disk or block
# in lava survives while a part (`SimpleItem`) and a vanilla diamond are destroyed. Six items
# are summoned above one contained lava pool and counted through `ctl entities 12 item` after
# sixty ticks: the three families' disks and a storage block stay (`1` each), the part and the
# diamond are gone (`0` each), and the surviving disk's own `.pos` is inside the pool.
#
# `GAME=$CONTROL_GAME tools/e2e.sh` runs the same scenario on the same Nightly without the
# packages: the first assertion fails, so the leg ends `EXIT:1`.
# `SELFTEST=1` flips the fire assertion (it must FAIL), which proves the scenario can fail.
# `FIRE_ONLY=1` runs just the slice-5 leg (a launch plus a lava pool): the red proof against a
# package without the declarations, and `FIRE_ONLY=1 SELFTEST=1` for its inverted assertion.
# `DRAIN_SELFTEST=1` flips the slice-1 drain assertion (it must FAIL), which proves that one can.
# `NEGATIVE=1` inverts the slice-3 restore assertion (it must FAIL), which proves that one can.
# `MENU_ONLY=1` runs just the slice-4 menu leg (a launch plus a handful of blocks): the red
# proof against a build without the container declaration, and `MENU_ONLY=1 MENU_NEGATIVE=1`
# for its inverted assertion. `MENU_NEGATIVE=1` alone inverts the menu's readout assertion and
# must FAIL. The bar is measured from a screenshot by `tools/bar_check.py` (filled and trough
# pixels of the 16×70 gauge), so the run proves the screen is drawn, not only that it opened.
set -euo pipefail
export LC_ALL=C

CAMPAIGN=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CAMPAIGN/ports/refinedtypes
CTL=${CTL:-$PORT/target/horizon-cargo/fast/horizon-ctl}
GAME=${GAME:-$PORT/target/horizon-cargo/fast/horizon-client}
CONTROL_GAME=${CONTROL_GAME:-$CTL}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/refinedtypes-e2e.sock}
SELFTEST=${SELFTEST:-0}
DRAIN_SELFTEST=${DRAIN_SELFTEST:-0}
NEGATIVE=${NEGATIVE:-0}
MENU_NEGATIVE=${MENU_NEGATIVE:-0}
MENU_ONLY=${MENU_ONLY:-0}
FIRE_ONLY=${FIRE_ONLY:-0}
KEEP=${KEEP:-0}
WORLD=RefinedTypesE2E
ENERGIZER=43
DISK_DRIVE=42

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL (eval \"\$(tools/build-game.sh)\")" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME (eval \"\$(tools/build-game.sh)\")" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d "${E2E_TMP:-/tmp/opencode}"/refinedtypes-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME"
rm -f "$SOCK"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
say() { ctl chat "/$1" >/dev/null; }
fail() { echo "FAIL: $*" >&2; ctl logs --lines 40 >&2 || true; exit 1; }

# The non-null slots of the container at a position, as JSON.
slots() { ctl container "$1" "$2" "$3" | jq -c '[.slots[] | select(. != null)]'; }
# How many of ITEM the player carries.
count_of() {
    ctl inventory | jq -r --arg item "$1" \
        '[((.hotbar // [])[] | select(.item == $item) | .count), ((.main // [])[] | select(.item == $item) | .count)] | add // 0'
}
block() { ctl block "$1" "$2" "$3" | jq -r '.state'; }
expect_state() { # expect_state X Y Z TEXT
    local got
    got=$(block "$1" "$2" "$3")
    case "$got" in
        *"$4"*) ;;
        *) fail "the block at $1,$2,$3 is $got, expected $4" ;;
    esac
    echo "  block($1,$2,$3): $got"
}
# The /refinedtypes info line for a position.
info() { # info X Y Z
    say "refinedtypes info $1 $2 $3"
    ctl wait 4 >/dev/null
    ctl messages 6 | jq -r '.chat[]' | grep -m1 -E 'Refined Types network|No Refined Storage' || true
}
# The /refinedtypes menu line for a position (the menu's data slots, read back).
menu() { # menu X Y Z
    say "refinedtypes menu $1 $2 $3"
    ctl wait 4 >/dev/null
    ctl messages 6 | jq -r '.chat[]' | grep -m1 -E 'Menu at|No Refined Storage' || true
}
expect_info() { # expect_info X Y Z TEXT
    local line
    line=$(info "$1" "$2" "$3")
    echo "  info($1,$2,$3): $line"
    case "$line" in
        *"$4"*) ;;
        *) fail "expected /refinedtypes info to say '$4', got '$line'" ;;
    esac
}
# A family's stored amount out of the info line ("energy 5000/64000" -> 5000).
stored() { # stored X Y Z FAMILY
    info "$1" "$2" "$3" | sed -n "s/.* $4 \([0-9]*\)\/.*/\1/p" | head -1
}
# The last /refinedtypes feedback line in chat.
last_reply() { ctl messages 6 | jq -r '.chat[]' | grep -m1 -E 'Deposited|The network took|network is offline|No Refined Storage' || true; }
# A deposit, with its reply.
deposit() { # deposit X Y Z FAMILY AMOUNT
    say "refinedtypes insert $1 $2 $3 $4 $5"
    ctl wait 4 >/dev/null
    last_reply
}
# How many of ITEM the player carries.
inv_count() { ctl inventory | jq -r --arg item "$1" '.counts[$item] // 0'; }
# The End has endermen, and a death in a survival leg loses the inventory mid-scenario.
undying() {
    ctl command "effect give @s minecraft:resistance 900 4 true" >/dev/null
    ctl command "effect give @s minecraft:regeneration 900 4 true" >/dev/null
}
# survival, an empty inventory and a pickaxe in hand (the block needs one to drop).
tool_up() {
    ctl command "gamemode survival @s" >/dev/null
    undying
    ctl command "clear @s" >/dev/null
    ctl command "item replace entity @s hotbar.0 with minecraft:diamond_pickaxe" >/dev/null
    ctl select 1 >/dev/null
    ctl wait 4
}
# pickup ITEM X Y Z: pick up the item a break just dropped and hold it. `ctl tp` onto the
# item entity's own reported position (never `ctl collect`: it *walks*, and a walk off the
# arena is a 35-block fall — HANDOVER §9c). An item that lands in the main inventory is moved
# into the hotbar with vanilla's own `/item replace … from entity`, the same stack and
# payload, never a copy.
pickup() { # pickup ITEM X Y Z
    local tries=0 drop slot main k dx dy dz
    ctl wait 10
    while [ "$tries" -lt 4 ] && [ "$(inv_count "$1")" -lt 1 ]; do
        drop=$(ctl entities 12 item |
            jq -r --arg id "$1" '[.entities[] | select(.item.item == $id) | .pos] | first // empty | @csv')
        if [ -n "$drop" ]; then
            IFS=, read -r dx dy dz <<<"$drop"
            echo "  the drop lies at $drop"
            ctl tp "$dx" "$dy" "$dz" >/dev/null
        else
            ctl tp "$2.5" "$2" "$(($3 + 1)).5" >/dev/null
        fi
        ctl wait 20
        tries=$((tries + 1))
    done
    [ "$(inv_count "$1")" -ge 1 ] \
        || fail "$1 did not reach the inventory after the break: $(ctl inventory | jq -c '{counts, hotbar}' | head -c 400)"
    slot=$(ctl inventory | jq -r --arg i "$1" '[.hotbar[] | select(.item == $i) | .slot] | .[0] // ""')
    if [ -z "$slot" ]; then
        main=$(ctl inventory | jq -r --arg i "$1" '[.main[] | select(.item == $i) | .slot] | .[0] // ""')
        [ -n "$main" ] \
            || fail "$1 is in the inventory but in neither the hotbar nor the main slots: $(ctl inventory | jq -c '{counts, hotbar, main}' | head -c 500)"
        for k in "$((main - 9))" "$main"; do
            ctl command "item replace entity @s hotbar.1 from entity @s inventory.$k" >/dev/null
            ctl wait 6
            slot=$(ctl inventory | jq -r --arg i "$1" '[.hotbar[] | select(.item == $i) | .slot] | .[0] // ""')
            [ -n "$slot" ] && break
        done
    fi
    [ -n "$slot" ] || fail "could not move $1 into the hotbar: $(ctl inventory | jq -c '{counts, hotbar}' | head -c 400)"
    tries=0
    while [ "$tries" -lt 3 ]; do
        slot=$(ctl inventory | jq -r --arg i "$1" '[.hotbar[] | select(.item == $i) | .slot] | .[0] // ""')
        [ -z "$slot" ] && break
        ctl select $((slot + 1)) >/dev/null
        ctl wait 6
        [ "$(ctl inventory | jq -r '.held.item // ""')" = "$1" ] && break
        tries=$((tries + 1))
    done
    [ "$(ctl inventory | jq -r '.held.item // ""')" = "$1" ] \
        || fail "$1 is not in hand after selecting slot $slot: $(ctl inventory | jq -c '{counts, hotbar, held}' | head -c 500)"
    ctl tp "$2.5" "$2" "$(($3 + 1)).5" >/dev/null
    ctl wait 4
}
# place_item X Y Z ITEM: place ITEM from the hotbar at an empty position, two blocks away,
# and assert the block is there. A refused click keeps the stack, so the attempt is retried.
place_item() { # place_item X Y Z ITEM
    local i name
    for i in 1 2 3; do
        ctl tp "$1.5" "$2" "$(($3 + 2)).5" >/dev/null
        ctl wait 6
        ctl place "$1" "$2" "$3" --item "$4" >/dev/null 2>&1 || true
        ctl wait 8
        name=$(ctl block "$1" "$2" "$3" | jq -r '.block // empty')
        if [ "$name" = "$4" ]; then
            echo "  placed $4 at $1,$2,$3"
            return 0
        fi
        echo "  place attempt $i at $1,$2,$3 left '$name' ($(ctl inventory | jq -c '.counts'))"
        ctl wait 10
    done
    fail "the item $4 did not place at $1,$2,$3: $(ctl state | jq -c '.player.position')"
}

cleanup() {
    local status=$?
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    if [ "$KEEP" = 1 ]; then
        echo "kept scratch: $SCRATCH" >&2
    else
        rm -rf "$SCRATCH" 2>/dev/null || true
    fi
    echo "EXIT:$status"
}
trap cleanup EXIT

launch() {
    rm -f "$SOCK"
    cd "$SCRATCH"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$WORLD" --seed 20261105 --creative --offscreen --wait \
        --resources "$RES" >/dev/null
    ctl wait-ready 200
    ctl wait 40
}

# The first launch only: a stone floor and a clear volume in The End.
arena() {
    ctl command "execute in minecraft:the_end run tp @s 40.5 64 3.5"
    local loaded=false
    for _ in $(seq 1 120); do
        ctl wait 5
        if [ "$(ctl block 40 63 0 | jq -r '.loaded // false')" = true ]; then
            loaded=true
            break
        fi
    done
    [ "$loaded" = true ] || fail "the End arena chunk never loaded"
    ctl command "execute in minecraft:the_end run fill 32 63 -8 56 63 24 minecraft:stone"
    ctl command "execute in minecraft:the_end run fill 32 64 -8 56 74 24 minecraft:air"
    ctl command "execute in minecraft:the_end run kill @e[type=item]"
    ctl wait 20
}

menu_section() {
    echo "== slice 4: the Network Energizer's menu, and the readout it carries =="
    # Gap 4 / deviation 4. Upstream's only menu is the energizer's (`NetworkEnergizerContainerMenu`,
    # `NetworkEnergizerScreen`, an energy bar drawn from `NetworkEnergizerEnergyInfo`); storage
    # blocks have none. A 256k network takes 5,000, the block is used, and the port's menu opens with
    # the readout in its data slots: the stored amount and the capacity, four 16-bit limbs each (a
    # data slot is a `short` on the wire, so a `u64` cannot ride in one).
    ctl command "execute in minecraft:the_end run setblock 36 64 2 refinedstorage:controller"
    ctl command "execute in minecraft:the_end run setblock 37 64 2 refinedstorage:cable"
    ctl command "execute in minecraft:the_end run setblock 38 64 2 refinedtypes:256k_energy_storage_block"
    ctl command "execute in minecraft:the_end run setblock 39 64 2 refinedtypes:network_energizer"
    ctl wait 16
    expect_state 39 64 2 'refinedtypes:network_energizer'
    expect_info 39 64 2 "online (1 storage, 1 energizer, 1 controller, 0 drive, 0 grid)"
    REPLY=$(deposit 39 64 2 energy 5000)
    echo "  deposit: $REPLY"
    case "$REPLY" in
        *"Deposited 5000 energy"*) ;;
        *) fail "the 256k block on the menu network did not take the 5000: $REPLY" ;;
    esac
    ctl command "execute in minecraft:the_end run tp @s 39.5 64 4.5" >/dev/null
    ctl wait 4
    ctl interact 39 64 2
    ctl wait 8
    SCREEN=$(ctl screen)
    echo "  screen: $(echo "$SCREEN" | jq -c '{screen, container, title: (.title // [] | map(.text) | join("")), slots: (.slots | length)}')"
    [ "$(echo "$SCREEN" | jq -r '.screen')" = container ] \
        || fail "using the energizer did not open a menu: $(echo "$SCREEN" | jq -c '{screen, container}')"
    # The menu a mod opens itself (`PlayerRef::open_menu`) names no block position to the
    # client, so `container` there is a sentinel: the menu type's title and the slot count are
    # the assertion (the port's menu, the player's 36 slots and no container slot).
    [ "$(echo "$SCREEN" | jq -r '.title // [] | map(.text) | join("")')" = "Network Energizer" ] \
        || fail "the menu's title is not the block's: $(echo "$SCREEN" | jq -c '.title')"
    # The one declared container slot is hidden by the port's screen, so the server's menu does not
    # have it either: every slot the screen lists is the player's.
    [ "$(echo "$SCREEN" | jq -r '[.slots[].slot | select(. >= 300)] | length')" = 0 ] \
        || fail "the menu has a container slot the screen hides: $(echo "$SCREEN" | jq -c '[.slots[].slot]')"

    MENU=$(menu 39 64 2)
    echo "  menu: $MENU"
    SLOTS=$(sed -n 's/.*data slots \[\([^]]*\)\].*/\1/p' <<<"$MENU")
    [ -n "$SLOTS" ] || fail "/refinedtypes menu printed no data slots: $MENU"
    read -r S0 S1 S2 S3 C0 C1 C2 C3 <<<"$(tr ',' ' ' <<<"$SLOTS")"
    STORED_READ=$(sed -n 's/.*stored \([0-9,]*\)\/.*/\1/p' <<<"$MENU" | tr -d ,)
    CAP_READ=$(sed -n 's/.*stored [0-9,]*\/\([0-9,]*\).*/\1/p' <<<"$MENU" | tr -d ,)
    echo "  readout: stored=$STORED_READ capacity=$CAP_READ limbs=($S0 $S1 $S2 $S3 | $C0 $C1 $C2 $C3)"
    # 5,000 deposited, then the network pays its usage while the menu is open (the 256k
    # tier's 4 FE/t, `Config`'s ladder) for the ticks the reads take: the readout is the last
    # tick's, so it trails the deposit. Two checks: it never exceeds what was deposited, and
    # it agrees with `/refinedtypes info` — a different reading of the same amount (the
    # block's payload against the menu's data slots) — to within a few ticks' usage.
    [ "$STORED_READ" -le 5000 ] && [ "$STORED_READ" -ge 4000 ] \
        || fail "the menu does not hold the deposited 5000: $STORED_READ ($MENU)"
    LIVE=$(stored 39 64 2 energy)
    echo "  info just after the readout: $LIVE"
    [ -n "$LIVE" ] || fail "the info line has no energy amount: $(info 39 64 2)"
    # The two readings are a few ticks apart by construction (two chat round-trips) while the
    # network pays 4 FE/t, so they agree to within 100 FE (25 ticks). A slot that held the
    # capacity instead, or a limb in the wrong place, is off by thousands.
    [ $((LIVE - STORED_READ)) -le 100 ] && [ $((STORED_READ - LIVE)) -le 100 ] \
        || fail "the menu reads $STORED_READ while the network reads $LIVE: the slots are not the amount"
    [ "$S0" = "$STORED_READ" ] && [ "$S1$S2$S3" = "000" ] \
        || fail "the stored amount is not the slots' low limb: ($S0 $S1 $S2 $S3) for $STORED_READ"
    [ "$CAP_READ" = 256000 ] || fail "the menu's capacity is not the network's: $CAP_READ"
    # 256,000 = 0x3E800: the low limb is 59,392 and the next one 3, exactly what the 16-bit split
    # leaves — which a single slot could not have carried.
    [ "$C0" = 59392 ] && [ "$C1" = 3 ] && [ "$C2" = 0 ] && [ "$C3" = 0 ] \
        || fail "the capacity is not split into 16-bit limbs: ($C0 $C1 $C2 $C3) for $CAP_READ"
    if [ "$MENU_NEGATIVE" = 1 ]; then
        echo "(menu-negative: asserting the menu reads 0, which must fail)"
        [ "$STORED_READ" = 0 ] \
            || fail "MENU_NEGATIVE: the menu reads $STORED_READ for a 5000 network, so the assertion is alive"
        echo "MENU_NEGATIVE unexpectedly saw an empty menu"
        exit 0
    fi
    GUI=$(ctl ui | jq -r '"\(.gui_size[0]) \(.gui_size[1])"')
    SHOT=$SCRATCH/bar-5000.png
    ctl screenshot "$SHOT" >/dev/null || fail "no screenshot of the open menu"
    read -r SMALL SMALL_TROUGH <<<"$(python3 "$PORT/tools/bar_check.py" "$SHOT" $GUI)" \
        || fail "the screenshot could not be read"
    echo "  bar at $STORED_READ/$CAP_READ: $SMALL of 70 GUI px filled, $SMALL_TROUGH dark (the trough)"
    awk -v f="$SMALL" 'BEGIN { exit !(f <= 4) }' \
        || fail "the bar is not nearly empty for $STORED_READ/$CAP_READ: $SMALL px"
    # The trough is drawn even where the fill is not, so this proves the bar is on the screen
    # at all, not that a light panel was measured.
    awk -v d="$SMALL_TROUGH" 'BEGIN { exit !(d >= 60) }' \
        || fail "the bar is not drawn for $STORED_READ/$CAP_READ: $SMALL_TROUGH dark px"
    ctl close
    ctl wait 6
    [ "$(ctl screen | jq -r '.screen')" = playing ] \
        || fail "closing the menu did not return to the game: $(ctl screen | jq -c '.screen')"

    # The differential, in the same slot engine: a network with nothing but the energizer (its own
    # 1000 FE buffer, no storage) reads 1000 of 1000 — a full bar. If the fraction never crossed the
    # data slots, both networks would draw the same bar.
    ctl command "execute in minecraft:the_end run setblock 47 64 2 refinedstorage:controller"
    ctl command "execute in minecraft:the_end run setblock 48 64 2 refinedstorage:cable"
    ctl command "execute in minecraft:the_end run setblock 49 64 2 refinedtypes:network_energizer"
    ctl wait 16
    expect_info 49 64 2 "online (0 storage, 1 energizer, 1 controller, 0 drive, 0 grid)"
    ctl command "execute in minecraft:the_end run tp @s 49.5 64 4.5" >/dev/null
    ctl wait 4
    ctl interact 49 64 2
    ctl wait 8
    [ "$(ctl screen | jq -r '.screen')" = container ] \
        || fail "the buffer-only energizer did not open its menu: $(ctl screen | jq -c '{screen, container}')"
    MENU=$(menu 49 64 2)
    echo "  menu (buffer only): $MENU"
    case "$MENU" in
        *"stored 1,000/1,000"*) ;;
        *) fail "the buffer-only energizer's readout is not 1000/1000: $MENU" ;;
    esac
    SHOT=$SCRATCH/bar-buffer.png
    ctl screenshot "$SHOT" >/dev/null || fail "no screenshot of the buffer-only menu"
    read -r FULL FULL_TROUGH <<<"$(python3 "$PORT/tools/bar_check.py" "$SHOT" $GUI)" \
        || fail "the screenshot could not be read"
    echo "  bar at 1000/1000: $FULL of 70 GUI px filled (the 5000/256000 one was $SMALL)"
    awk -v f="$FULL" 'BEGIN { exit !(f >= 60) }' \
        || fail "the bar is not full for 1000/1000: $FULL px"
    ctl close
    ctl wait 6

}

echo "== launch (The End arena, both packages) =="
launch
arena

# How many dropped items of ITEM are near the player (the lava pool is a few blocks away).
dropped() { # dropped ITEM
    ctl entities 12 item | jq -r --arg id "$1" '[.entities[] | select(.item.item == $id)] | length'
}
# Summon one item entity well above the pool, so it falls into the lava as a player's drop would.
# Each summon is proved by its own reply: `/summon` answers "Summoned new <name>" when it worked,
# and `ctl command` answers ok:true even for a command the game refuses (the gamerule trap), so
# the chat line — not `ok` — is the setup's assertion. (Summoned *inside* the lava an item dies
# before anything can be asserted; from this height it falls in over a few seconds.)
summon_item() { # summon_item ITEM X Y Z
    local reply
    reply=$(ctl command "summon minecraft:item $2 72.5 $3 {Item:{id:\"$1\",count:1}}")
    case "$reply" in
        *"Summoned new"*) ;;
        *) fail "the setup could not summon $1: $reply" ;;
    esac
}

fire_section() {
    echo "== slice 5: a dropped disk and storage block survive lava, as upstream declares them =="
    # Gap 8 (an omission the jar does not have). Upstream gives a disk and a storage block
    # `fireResistant()` (`*StorageDiskItem`, `*StorageBlockBlockItem`) and leaves a part
    # (`SimpleItem`) and the
    # energizer (`NetworkNodeBlockItem` over `BlockConstants.PROPERTIES`) alone. At 26.3 the
    # declaration is the `minecraft:damage_resistant` component naming `#minecraft:is_fire` — the
    # spelling vanilla's own `minecraft:netherite_ingot` uses, which the engine reads as
    # `ItemInfo.fire_resistant` — so a dropped item entity in lava takes no damage. The
    # differential is inside the run: the same pool destroys a part and a vanilla diamond.
    ctl command "gamemode creative @s" >/dev/null
    ctl command "clear @s" >/dev/null
    ctl command "execute in minecraft:the_end run kill @e[type=item]" >/dev/null
    ctl command "execute in minecraft:the_end run tp @s 46.5 64 21.5" >/dev/null
    ctl wait 8
    # A contained pool: the arena floor is stone at y=63, so a 5×5 stone plate at y=64 with its
    # middle 3×3 replaced by lava source blocks cannot flow down or sideways.
    ctl command "execute in minecraft:the_end run fill 44 64 15 48 64 19 minecraft:stone"
    ctl command "execute in minecraft:the_end run fill 45 64 16 47 64 18 minecraft:lava"
    ctl wait 8
    expect_state 46 64 17 'minecraft:lava'
    expect_state 44 64 15 'minecraft:stone'
    # Three families' disks, a storage block, a part and a vanilla control, each above its own
    # cell of the pool.
    summon_item refinedtypes:64k_energy_storage_disk 45.5 16.5
    summon_item refinedtypes:1k_soul_storage_disk 46.5 16.5
    summon_item refinedtypes:1024b_source_storage_disk 47.5 16.5
    summon_item refinedtypes:64k_energy_storage_block 45.5 17.5
    summon_item refinedtypes:64k_energy_storage_part 46.5 17.5
    summon_item minecraft:diamond 47.5 17.5
    ctl wait 4
    echo "  in the world above the pool: $(ctl entities 12 item | jq -c '[.entities[] | .item.item]')"
    # The four that are fire resistant cannot die in the air, so they are the setup's proof that
    # the summon path worked and they are in the world; the two the pool will destroy are proved
    # by their own summon replies above (they may already be gone by now, which is the point).
    for item in refinedtypes:64k_energy_storage_disk refinedtypes:1k_soul_storage_disk \
                refinedtypes:1024b_source_storage_disk refinedtypes:64k_energy_storage_block; do
        [ "$(dropped "$item")" = 1 ] \
            || fail "the setup did not keep $item in the world before the drop: $(ctl entities 12 item | jq -c '[.entities[] | .item.item]')"
    done
    # They fall the seven blocks into the lava over a couple of seconds; the two that are not
    # fire resistant are gone a tick or two after they touch it, the four that are stay.
    ctl wait 60
    ENERGY_DISK=$(dropped refinedtypes:64k_energy_storage_disk)
    SOUL_DISK=$(dropped refinedtypes:1k_soul_storage_disk)
    SOURCE_DISK=$(dropped refinedtypes:1024b_source_storage_disk)
    STORAGE_BLOCK=$(dropped refinedtypes:64k_energy_storage_block)
    PART=$(dropped refinedtypes:64k_energy_storage_part)
    DIAMOND=$(dropped minecraft:diamond)
    echo "  after 60 ticks in lava: energy-disk=$ENERGY_DISK soul-disk=$SOUL_DISK source-disk=$SOURCE_DISK block=$STORAGE_BLOCK part=$PART diamond=$DIAMOND"
    if [ "$SELFTEST" = 1 ]; then
        echo "(selftest: asserting the disk was destroyed, which must fail)"
        [ "$ENERGY_DISK" = 0 ] \
            || fail "SELFTEST: the disk is still in the lava, so the assertion is alive"
        echo "SELFTEST unexpectedly saw the disk destroyed"
        exit 0
    fi
    [ "$ENERGY_DISK" = 1 ] || fail "a dropped 64k energy disk did not survive lava ($ENERGY_DISK alive)"
    [ "$SOUL_DISK" = 1 ] || fail "a dropped 1k soul disk did not survive lava ($SOUL_DISK alive)"
    [ "$SOURCE_DISK" = 1 ] || fail "a dropped 1024b source disk did not survive lava ($SOURCE_DISK alive)"
    [ "$STORAGE_BLOCK" = 1 ] || fail "a dropped 64k storage block did not survive lava ($STORAGE_BLOCK alive)"
    # `ctl entities` answers `.pos` (not `.position`); each survivor must lie inside the pool
    # (x 44..48, z 15..19), or it survived somewhere that is not lava and the leg proves nothing.
    POS=$(ctl entities 12 item |
        jq -c '[.entities[] | select(.item.item | startswith("refinedtypes:")) | {item: .item.item, pos}]')
    echo "  the survivors lie at $POS"
    OUTSIDE=$(jq -r '[.[] | select(.pos[0] < 44 or .pos[0] > 48 or .pos[2] < 15 or .pos[2] > 19) | .item] | join(",")' <<<"$POS")
    [ -z "$OUTSIDE" ] || fail "a survivor lies outside the lava pool: $OUTSIDE ($POS)"
    # The in-mod differential: a part is the same mod's item without the declaration upstream
    # does not give it, and it is destroyed exactly as the vanilla control is.
    [ "$PART" = 0 ] || fail "a dropped storage part survived lava ($PART alive): upstream's SimpleItem is not fire resistant"
    [ "$DIAMOND" = 0 ] || fail "a dropped diamond survived lava ($DIAMOND alive): the control is not a control"
    ctl command "execute in minecraft:the_end run kill @e[type=item]" >/dev/null
    ctl wait 4
}

# `FIRE_ONLY=1` runs just the slice-5 leg: the red proof against a package without the
# fire-resistance declarations, and the inverted assertion (`SELFTEST=1`). It is a launch plus
# a lava pool and six summons, so a red leg costs a minute rather than the whole scenario.
if [ "$FIRE_ONLY" = 1 ]; then
    fire_section
    echo "PASS: a dropped storage disk (all three families) and a storage block survive sixty ticks in lava while a part and a vanilla diamond are destroyed"
    exit 0
fi

# `MENU_ONLY=1` runs just the menu leg: the red proof against a build without the menu, and the
# inverted assertion. It is a launch plus fourteen block placements, so a red leg costs a minute
# rather than the whole scenario.
if [ "$MENU_ONLY" = 1 ]; then
    menu_section
    echo "PASS: the Network Energizer opens the port's own menu whose data slots carry the network's stored energy and capacity, with the bar drawn from them"
    exit 0
fi

echo "== the three families' blocks exist and the network is online =="
ctl command "execute in minecraft:the_end run setblock 40 64 0 refinedstorage:controller"
ctl command "execute in minecraft:the_end run setblock 41 64 0 refinedstorage:cable"
ctl command "execute in minecraft:the_end run setblock 42 64 0 refinedstorage:disk_drive"
ctl command "execute in minecraft:the_end run setblock 43 64 0 refinedtypes:network_energizer"
ctl command "execute in minecraft:the_end run setblock 44 64 0 refinedtypes:64k_energy_storage_block"
ctl command "execute in minecraft:the_end run setblock 45 64 0 refinedtypes:64k_soul_storage_block"
ctl wait 20
# The first assertion of the run: the add-on's blocks are in the game (the control leg dies
# here, because without the packages the ids are unknown and the block is air).
expect_state 44 64 0 'refinedtypes:64k_energy_storage_block'
expect_state 45 64 0 'refinedtypes:64k_soul_storage_block'
expect_state 43 64 0 'refinedtypes:network_energizer'
expect_info $ENERGIZER 64 0 "online (2 storage, 1 energizer, 1 controller, 1 drive, 0 grid)"
expect_info $ENERGIZER 64 0 "energy 0/64000; soul 0/65536; source 0/0"
expect_info $ENERGIZER 64 0 "usage 8 FE/t"
expect_state $ENERGIZER 64 0 'active=true'

echo "== with nothing stored the energizer runs on its buffer, then goes inactive =="
ctl wait 200
expect_info $ENERGIZER 64 0 "energizer 0/1000 inactive"
expect_state $ENERGIZER 64 0 'active=false'

echo "== a deposit fills the 64k block, and the usage drains it =="
REPLY=$(deposit $ENERGIZER 64 0 energy 5000)
echo "  deposit: $REPLY"
case "$REPLY" in
    *"Deposited 5000 energy"*) ;;
    *) fail "the deposit was not accepted: $REPLY" ;;
esac
case "$REPLY" in
    *"holds 5000/64000"*) ;;
    *) fail "the network does not report the deposit in its 64k block: $REPLY" ;;
esac
# The ticks between the deposit and the read are the energizer's usage, so the amount read
# back is a little under 5000.
AFTER=$(stored $ENERGIZER 64 0 energy)
echo "  energy just after the deposit: $AFTER"
[ -n "$AFTER" ] || fail "the info line has no energy amount: $(info $ENERGIZER 64 0)"
[ "$AFTER" -le 5000 ] && [ "$AFTER" -ge 4900 ] \
    || fail "the deposit did not land in the 64k block: $AFTER of 5000"
expect_state $ENERGIZER 64 0 'active=true'
ctl wait 100
BEFORE=$(stored $ENERGIZER 64 0 energy)
echo "  energy after 100 ticks: $BEFORE"
[ -n "$BEFORE" ] || fail "the info line has no energy amount: $(info $ENERGIZER 64 0)"
[ "$BEFORE" -lt "$AFTER" ] || fail "the energizer did not drain the storage: $BEFORE, was $AFTER"
[ "$BEFORE" -gt 3000 ] || fail "the storage drained far faster than 8 FE/t: $BEFORE left"

echo "== the usage is the nodes': breaking the soul block drops it to 2 FE/t =="
ctl command "execute in minecraft:the_end run setblock 45 64 0 minecraft:air"
ctl wait 12
expect_info $ENERGIZER 64 0 "usage 2 FE/t"
expect_info $ENERGIZER 64 0 "soul 0/0"

echo "== with no energy storage a deposit is refused =="
ctl command "execute in minecraft:the_end run setblock 44 64 0 minecraft:air"
ctl wait 12
expect_info $ENERGIZER 64 0 "energy 0/0"
REPLY=$(deposit $ENERGIZER 64 0 energy 4000)
echo "  deposit with no storage: $REPLY"
case "$REPLY" in
    *"took 0 of 4000 energy"*) ;;
    *) fail "a deposit with no energy storage was not refused: $REPLY" ;;
esac

echo "== a refinedtypes disk goes into the parent's drive and is the network's storage =="
ctl give refinedtypes:64k_energy_storage_disk 1
ctl wait 4
ctl select refinedtypes:64k_energy_storage_disk
ctl wait 4
ctl command "execute in minecraft:the_end run tp @s 42.5 64 2.5"
ctl wait 4
ctl interact $DISK_DRIVE 64 0
ctl wait 8
[ "$(count_of refinedtypes:64k_energy_storage_disk)" = 0 ] \
    || fail "the disk stayed in the hand: $(ctl inventory | jq -c '[.hotbar[] | select(.item != null)]')"
slots $DISK_DRIVE 64 0 | jq -e '[.[] | select(.item == "refinedtypes:64k_energy_storage_disk")] | length == 1' >/dev/null \
    || fail "the parent's drive does not hold the disk: $(slots $DISK_DRIVE 64 0)"
echo "  drive: $(slots $DISK_DRIVE 64 0)"
expect_info $ENERGIZER 64 0 "energy 0/64000"
REPLY=$(deposit $ENERGIZER 64 0 energy 4000)
echo "  deposit into the disk: $REPLY"
case "$REPLY" in
    *"Deposited 4000 energy"*) ;;
    *) fail "the disk did not take the deposit: $REPLY" ;;
esac
case "$REPLY" in
    *"holds 4000/64000"*) ;;
    *) fail "the disk is not the network's energy storage: $REPLY" ;;
esac

echo "== the energizer drains the disk, writing the amount back into the item =="
# A storage block again, so the network has a usage to pay: the disk is the only energy
# storage, so what the energizer takes comes out of the disk's item component. It goes at 44,
# beside the energizer, because 45 was cut off from the component when 44 was broken.
ctl command "execute in minecraft:the_end run setblock 44 64 0 refinedtypes:64k_soul_storage_block"
ctl wait 12
expect_info $ENERGIZER 64 0 "usage 6 FE/t"
ctl wait 150
LEFT=$(stored $ENERGIZER 64 0 energy)
echo "  energy after 150 ticks: $LEFT"
[ -n "$LEFT" ] || fail "the info line has no energy amount: $(info $ENERGIZER 64 0)"
if [ "$DRAIN_SELFTEST" = 1 ]; then
    echo "(drain-selftest: asserting the disk kept all 4000, which must fail)"
    [ "$LEFT" -eq 4000 ] || fail "DRAIN_SELFTEST: the disk was drained to $LEFT, so the assertion is alive"
    echo "DRAIN_SELFTEST unexpectedly saw the disk undrained"
    exit 0
fi
[ "$LEFT" -lt 4000 ] || fail "the energizer did not drain the disk: $LEFT of 4000 left"
[ "$LEFT" -gt 1000 ] || fail "the disk drained far faster than 6 FE/t: $LEFT left"

echo "== a broken controller takes the network offline; the disk keeps its amount =="
ctl command "gamemode survival"
undying
ctl give minecraft:diamond_pickaxe 1
ctl wait 4
ctl select minecraft:diamond_pickaxe
ctl command "execute in minecraft:the_end run tp @s 40.5 64 2.5"
ctl wait 6
ctl break 40 64 0
ctl wait 12
ctl command "clear @s refinedstorage:controller"
ctl command "execute in minecraft:the_end run kill @e[type=item]"
ctl command "gamemode creative"
ctl wait 4
expect_info $ENERGIZER 64 0 "offline"
expect_info $ENERGIZER 64 0 "energy 0/0"
REPLY=$(deposit $ENERGIZER 64 0 energy 100)
echo "  deposit while offline: $REPLY"
case "$REPLY" in
    *"network is offline"*) ;;
    *) fail "a deposit on an offline network was not refused: $REPLY" ;;
esac
ctl command "execute in minecraft:the_end run setblock 40 64 0 refinedstorage:controller"
ctl wait 20
expect_info $ENERGIZER 64 0 "online"
KEPT=$(stored $ENERGIZER 64 0 energy)
echo "  energy after the controller came back: $KEPT (was $LEFT offline)"
[ -n "$KEPT" ] || fail "the info line has no energy amount: $(info $ENERGIZER 64 0)"
[ "$KEPT" -le "$LEFT" ] || fail "the disk gained energy while offline: $KEPT, was $LEFT"
# The offline leg itself takes a few dozen ticks (breaking the controller with a pickaxe,
# the restore, the reads), and the network pays its usage for each of them once it is back;
# 500 FE is well under what a reset would show and well over those ticks.
[ "$KEPT" -ge "$((LEFT - 500))" ] \
    || fail "the disk lost far more than the usage while the controller was away: $KEPT, was $LEFT"

echo "== the crafting chain: every carried recipe crafts in game =="
# Slice 2. The driver reads this package's own data/refinedtypes/recipe/** and crafts
# every file it finds (107: the jar's 109 minus the two the pin cannot load), asserting
# each output id and count, that the ingredients were consumed, and a wrong-ingredient
# counterfactual per recipe. A dropped recipe fails the run, not the bookkeeping.
python3 -u "$PORT/tools/recipe_check.py" "$SOCK" "$CTL" 36 64 8 || fail "the recipe check failed"

echo "== a storage block drops itself with the tool its tag declares, and not without =="
# The loot-table differential: requires_tool + #minecraft:mineable/pickaxe must drop the
# block for a pickaxe and nothing for a bare hand. It also proves the carried table parses
# (a 26.3 shape defect leaves the block empty).
ctl command "execute in minecraft:the_end run setblock 46 64 0 refinedtypes:256k_energy_storage_block"
ctl wait 6
expect_state 46 64 0 'refinedtypes:256k_energy_storage_block'
ctl command "execute in minecraft:the_end run tp @s 46.5 64 1.5"
ctl command "gamemode survival"
undying
ctl command "clear @s"
ctl wait 4
# A bare hand takes ~23 s on hardness 4.5, close to ctl's 30 s default on a loaded box.
BARE=$(ctl break 46 64 0 --timeout 90) || fail "the bare-hand break failed: $BARE"
echo "  bare hand: $(echo "$BARE" | jq -c '{drops, items_left_on_ground}')"
[ "$(echo "$BARE" | jq -r '.drops["refinedtypes:256k_energy_storage_block"] // 0')" = 0 ] \
    || fail "a bare hand harvested the storage block: $(echo "$BARE" | jq -c '.drops')"
ctl command "execute in minecraft:the_end run setblock 46 64 0 refinedtypes:256k_energy_storage_block"
ctl wait 6
ctl give minecraft:diamond_pickaxe 1
ctl wait 4
ctl select minecraft:diamond_pickaxe
ctl wait 4
WITH=$(ctl break 46 64 0 --timeout 90) || fail "the pickaxe break failed: $WITH"
echo "  pickaxe: $(echo "$WITH" | jq -c '{drops, items_left_on_ground}')"
[ "$(echo "$WITH" | jq -r '.drops["refinedtypes:256k_energy_storage_block"] // 0')" = 1 ] \
    || fail "the storage block did not drop itself with a pickaxe: $(echo "$WITH" | jq -c '.drops')"
ctl command "gamemode creative"
ctl command "clear @s"
ctl command "execute in minecraft:the_end run kill @e[type=item]"
ctl wait 4


echo "== slice 3: a storage block's own item carries the amount it held =="
# Gap 3 / deviation 3: until 0.1.2 a broken storage block dropped a full-capacity, empty
# block. `block_drops` writes the amount onto the block's own item as
# `minecraft:block_entity_data`, and the item's Part clamps it back on placement. Two
# one-block-deep networks with no energizer, so nothing draws the amount while it is read.
ctl command "execute in minecraft:the_end run setblock 50 64 0 refinedstorage:controller"
ctl command "execute in minecraft:the_end run setblock 51 64 0 refinedstorage:cable"
ctl command "execute in minecraft:the_end run setblock 52 64 0 refinedtypes:256k_energy_storage_block"
ctl wait 16
expect_state 52 64 0 'refinedtypes:256k_energy_storage_block'
expect_info 50 64 0 "online (1 storage, 0 energizer, 1 controller, 0 drive, 0 grid)"
expect_info 50 64 0 "energy 0/256000"
REPLY=$(deposit 52 64 0 energy 5000)
echo "  deposit: $REPLY"
case "$REPLY" in
    *"Deposited 5000 energy"*) ;;
    *) fail "the 256k block did not take the 5000 energy: $REPLY" ;;
esac
case "$REPLY" in
    *"holds 5000/256000"*) ;;
    *) fail "the network does not report the 5000 in its 256k block: $REPLY" ;;
esac
SAVED=$(ctl command "data get block 52 64 0 Amount")
echo "  block saved data: $(head -c 200 <<<"$SAVED")"
case "$SAVED" in
    *5000*) ;;
    *) fail "the block's own saved data does not hold 5000: $SAVED" ;;
esac

# Broken with the tool its tag declares, in survival (a creative break drops nothing).
tool_up
ctl command "execute in minecraft:the_end run tp @s 52.5 64 1.5" >/dev/null
ctl wait 6
BROKEN=$(ctl break 52 64 0 --timeout 60) || fail "the storage block break failed: $BROKEN"
echo "  break: $(echo "$BROKEN" | jq -c '{block, drops, picked_up}')"
[ "$(echo "$BROKEN" | jq -r '.block')" = "minecraft:air" ] || fail "the 256k block did not break: $BROKEN"
[ "$(echo "$BROKEN" | jq -r '.drops["refinedtypes:256k_energy_storage_block"] // 0')" = 1 ] \
    || fail "the 256k block did not drop itself: $(echo "$BROKEN" | jq -c '.drops')"
pickup refinedtypes:256k_energy_storage_block 52 64 0
HELD=$(ctl command "data get entity @s SelectedItem")
echo "  dropped item: $(head -c 400 <<<"$HELD")"
case "$HELD" in
    *block_entity_data*) ;;
    *) fail "the dropped block item carries no block entity data: $HELD" ;;
esac
case "$HELD" in
    *"Amount: 5000L"*) ;;
    *) fail "the dropped block item does not carry the 5000 it held: $HELD" ;;
esac

# That very item back: the block must read 5000 again, not the tier's empty default.
place_item 52 64 0 refinedtypes:256k_energy_storage_block
expect_info 50 64 0 "energy 5000/256000"
RESTORED=$(ctl command "data get block 52 64 0 Amount")
echo "  placed block saved data: $(head -c 200 <<<"$RESTORED")"
case "$RESTORED" in
    *5000*) ;;
    *) fail "the replaced block's saved data does not hold 5000: $RESTORED" ;;
esac
if [ "$NEGATIVE" = 1 ]; then
    echo "(negative: asserting the replaced block is still empty, which must fail)"
    [ "$(stored 50 64 0 energy)" = 0 ] \
        || fail "NEGATIVE: the replaced block reads $(stored 50 64 0 energy)/256000, so the assertion is alive"
    echo "NEGATIVE unexpectedly saw the replaced block empty"
    exit 0
fi

# The differential: a freshly given block carries nothing, so it places empty.
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl command "execute in minecraft:the_end run setblock 54 64 0 refinedstorage:controller"
ctl command "execute in minecraft:the_end run setblock 55 64 0 refinedstorage:cable"
ctl wait 12
ctl give refinedtypes:256k_energy_storage_block 1
ctl wait 4
place_item 56 64 0 refinedtypes:256k_energy_storage_block
expect_info 54 64 0 "online (1 storage, 0 energizer, 1 controller, 0 drive, 0 grid)"
expect_info 54 64 0 "energy 0/256000"

# A doctored payload naming more than the tier holds must clamp: 999,999,999 on a 256k
# block places 256,000. The item's Part is the clamp (the engine's own placement path
# cannot merge a mod block entity's `block_entity_data`).
ctl command "execute in minecraft:the_end run setblock 56 64 0 minecraft:air"
# A creative placement keeps the stack, so the plain block is still in hand: clear it, or
# `ctl select` would pick that one and the doctored stack would never be read.
ctl command "clear @s" >/dev/null
ctl wait 4
GIVEN=$(ctl command "give @s refinedtypes:256k_energy_storage_block[minecraft:block_entity_data={id:\"refinedtypes:node\",Amount:999999999L}]")
echo "  doctored give: $(head -c 240 <<<"$GIVEN")"
ctl wait 4
[ "$(inv_count refinedtypes:256k_energy_storage_block)" -ge 1 ] \
    || fail "the doctored block item did not reach the inventory: $GIVEN"
ctl select refinedtypes:256k_energy_storage_block >/dev/null
ctl wait 2
DOCTORED=$(ctl command "data get entity @s SelectedItem")
echo "  doctored item: $(head -c 300 <<<"$DOCTORED")"
case "$DOCTORED" in
    *999999999*) ;;
    *) fail "the doctored item does not carry 999999999: $DOCTORED" ;;
esac
place_item 56 64 0 refinedtypes:256k_energy_storage_block
expect_info 54 64 0 "energy 256000/256000"
CLAMPED=$(ctl command "data get block 56 64 0 Amount")
echo "  doctored block saved data: $(head -c 200 <<<"$CLAMPED")"
case "$CLAMPED" in
    *256000*) ;;
    *) fail "the doctored 999999999 was not clamped to 256000: $CLAMPED" ;;
esac

ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl command "execute in minecraft:the_end run kill @e[type=item]" >/dev/null
ctl wait 4

menu_section

fire_section

echo "PASS: the three families' blocks are on the network (energy 0/64000, soul 0/65536, usage 8 FE/t), the energizer drains its 1000 FE buffer to inactive and then runs off the network's energy storage (5000 deposited into the 64k block and drained by the usage; 4000 deposited into a disk in the parent's drive, drained and written back into the item), breaking the soul block drops the usage to 2 FE/t, a deposit with no energy storage is refused, an offline network reports nothing while the disk keeps its amount, all 107 carried recipes craft in game with their declared output and count (each with a wrong-ingredient control), a storage block drops itself for a pickaxe and not for a bare hand, a broken 256k block's own item carries its 5000 energy so placing it back reads 5000/256000 (a fresh item places 0/256000 and a payload doctored to 999999999 clamps to 256000), and the Network Energizer opens the port's own menu (title 'Network Energizer', no container slot) whose eight data slots carry the network's 5000 stored energy and 256000 capacity as 16-bit limbs, with the bar drawn nearly empty for 5000/256000 and full for a buffer-only network, and a dropped storage disk (all three families) and storage block survive sixty ticks in lava while a storage part and a vanilla diamond are destroyed"
