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
# `GAME=$CONTROL_GAME tools/e2e.sh` runs the same scenario on the same Nightly without the
# packages: the first assertion fails, so the leg ends `EXIT:1`.
# `SELFTEST=1` flips the drain assertion (it must FAIL), which proves the scenario can fail.
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

echo "== launch (The End arena, both packages) =="
launch
arena

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
if [ "$SELFTEST" = 1 ]; then
    echo "(selftest: asserting the disk kept all 4000, which must fail)"
    [ "$LEFT" -eq 4000 ] || fail "SELFTEST: the disk was drained to $LEFT, so the assertion is alive"
    echo "SELFTEST unexpectedly saw the disk undrained"
    exit 0
fi
[ "$LEFT" -lt 4000 ] || fail "the energizer did not drain the disk: $LEFT of 4000 left"
[ "$LEFT" -gt 1000 ] || fail "the disk drained far faster than 6 FE/t: $LEFT left"

echo "== a broken controller takes the network offline; the disk keeps its amount =="
ctl command "gamemode survival"
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

echo "PASS: the three families' blocks are on the network (energy 0/64000, soul 0/65536, usage 8 FE/t), the energizer drains its 1000 FE buffer to inactive and then runs off the network's energy storage (5000 deposited into the 64k block and drained by the usage; 4000 deposited into a disk in the parent's drive, drained and written back into the item), breaking the soul block drops the usage to 2 FE/t, a deposit with no energy storage is refused, and an offline network reports nothing while the disk keeps its amount"
