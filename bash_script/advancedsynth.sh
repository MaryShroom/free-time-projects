#!/usr/bin/env bash
set -euo pipefail
OK=1

printf "Checking dependencies for MIDI playback...\n"

# Check fluidsynth exists
if command -v fluidsynth >/dev/null 2>&1; then
    ver=$(fluidsynth --version 2>/dev/null | head -n1)
    printf '[OK]   fluidsynth found: %s\n' "${ver:-installed}"
else
    printf "[MISS] fluidsynth not found\n"
    printf "       Install: sudo apt install fluidsynth\n"
    OK=0
fi

# Check xinput
if command -v xinput >/dev/null 2>&1; then
    printf '[OK]   xinput found\n'
else
    printf "[MISS] xinput not found\n"
    printf "       Install: sudo apt install x11-xserver-utils\n"
    OK=0
fi

# Check xdotool
if command -v xdotool >/dev/null 2>&1; then
    printf '[OK]   xdotool found\n'
else
    printf "[MISS] xdotool not found\n"
    printf "       Install: sudo apt install xdotool\n"
    OK=0
fi

# Check soundfont file
shopt -s nullglob
SOUNDFONTS=( /usr/share/sounds/sf2/*.sf2 /usr/share/soundfonts/*.sf2 )
shopt -u nullglob

SOUNDFONT_SELECT="${SOUNDFONTS[0]:-}"

if [[ ${#SOUNDFONTS[@]} -eq 0 ]]; then
    printf "[MISS] no soundfont (.sf2) found in common locations\n"
    printf "       Install: sudo apt install fluid-soundfont-gm\n"
    OK=0
else
    for p in "${SOUNDFONTS[@]}"; do
        if [[ -f "$p" ]]; then
            if [[ "$p" == "/usr/share/sounds/sf2/FluidR3_GM.sf2" ]]; then
                SOUNDFONT_SELECT="$p"
                break
            fi
        fi
    done

    printf "[OK]   soundfont found: $SOUNDFONT_SELECT\n"
fi

# Check audio output backend
AUDIO_BACKEND=""
if command -v aplay >/dev/null 2>&1; then
    AUDIO_BACKEND="alsa (aplay present)"
elif command -v pactl >/dev/null 2>&1; then
    AUDIO_BACKEND="pulseaudio (pactl present)"
elif command -v jackd >/dev/null 2>&1; then
    AUDIO_BACKEND="jack (jackd present)"
fi

if [[ -n "$AUDIO_BACKEND" ]]; then
    printf "[OK]   audio backend detected: $AUDIO_BACKEND\n"
else
    printf "[WARN] no common audio backend (alsa/pulseaudio/jack) detected\n"
    printf "       fluidsynth may fail to produce sound without one\n"
fi

# Check mkfifo
if command -v mkfifo >/dev/null 2>&1; then
    printf "[OK]   mkfifo available (needed for streaming note commands)\n"
else
    printf "[MISS] mkfifo not found (should be part of coreutils)\n"
    OK=0
fi

if [[ "$OK" -eq 1 ]]; then
    printf "\nAll required dependencies are present.\n"
else
    printf "\nSome dependencies are missing — install them before proceeding.\n"
    exit 1
fi

# Start the program
# Top Level Global Variables
declare -A KEYMAP=(
    [38]="F3" [25]="Gb3"
    [39]="G3" [26]="Ab3"
    [40]="A3" [27]="Bb3"
    [41]="B3"
    [42]="C4" [29]="Db4"
    [43]="D4" [30]="Eb4"
    [44]="E4"
    [45]="F4" [32]="Gb4"
    [46]="G4" [33]="Ab4"
    [47]="A4" [34]="Bb4"
    [48]="B4"
)

# Create a FIFO and start fluidsynth reading commands from it, in the background
FIFO="/tmp/fsynth_cmd"
LOGFILE="/tmp/fsynth.log"
FS_PID=""

# Terminal controller
term_clear() {
    printf '\033[2J'     # clear whole screen
    printf '\033[H'      # move cursor to top-left
}

term_goto() {
    # term_goto <row> <col>  (both 1-indexed)
    printf '\033[%d;%dH' "$1" "$2"
}

term_write() {
    # term_write <row> <col> <text>
    term_goto "$1" "$2"
    printf '%s' "$3"
}

term_clear_row() {
    # term_clear_row <row>
    term_goto "$1" 1
    printf '\033[K'
}

term_hide_cursor() { printf '\033[?25l'; }
term_show_cursor() { printf '\033[?25h'; }
term_save_screen()    { printf '\033[?1049h'; }
term_restore_screen() { printf '\033[?1049l'; }

IS_CLEANING=0
cleanup() {
    # Check if cleanup called before
    if [[ "$IS_CLEANING" -eq 1 ]]; then
        return
    fi
    IS_CLEANING=1

    # Show cursor
    term_show_cursor
    term_restore_screen

    printf "\nCleaning up...\n"

    pkill -f "xinput test-xi2 --root" 2>/dev/null || true

    for code in "${!KEYMAP[@]}"; do
        xset r "$code" 2>/dev/null
    done

    # Stop fluidsynth if still running
    if [[ -n "$FS_PID" ]] && kill -0 "$FS_PID" 2>/dev/null; then
        kill "$FS_PID" 2>/dev/null
        wait "$FS_PID" 2>/dev/null
    fi

    # Close file descriptor
    exec 3>&- 2>/dev/null || true

    # Remove FIFO
    if [[ -p "$FIFO" ]]; then
        rm -f "$FIFO"
    fi
    printf "Closed gracefully.\n"
}

trap cleanup EXIT INT TERM HUP PIPE

if [[ -p "$FIFO" ]]; then
    rm -f "$FIFO"
fi
mkfifo "$FIFO"

printf "Starting FluidSynth...\n"
stdbuf -oL fluidsynth -a alsa -g 2.0 "$SOUNDFONT_SELECT" < "$FIFO" > "$LOGFILE" 2>&1 &
FS_PID=$!


sleep 0.3
if ! kill -0 "$FS_PID" 2>/dev/null; then
    printf "FluidSynth exited immediately.\n"
    exit 1
fi

exec 3> "$FIFO"

fsynth_send() {
    printf '%b\n' "$1" >&3
}

printf "FluidSynth running (PID $FS_PID), FIFO at $FIFO\n"

# Variables
declare -A INSTRUMENT=()
declare -A CHANNEL_INSTRUMENT=()
CURRENT_CHANNEL=0

# Functions
wait_log_quiet() {
    local timeout="${1:-3}"
    local waited=0 last_count cur_count quiet_ticks=0

    last_count=$(wc -l < "$LOGFILE")
    while (( waited < timeout * 10 )); do
        sleep 0.1
        ((++waited))
        cur_count=$(wc -l < "$LOGFILE")
        if (( cur_count == last_count )); then
            ((++quiet_ticks))
            if (( quiet_ticks >= 3 )); then
                return 0
            fi
        else
            quiet_ticks=0
            last_count="$cur_count"
        fi
    done
}

query_fsynth() {
    local cmd="$1"
    local timeout="${2:-2}"
    local before after

    wait_log_quiet 1
    before=$(wc -l < "$LOGFILE")

    printf '%s\n' "$cmd" >&3

    local waited=0
    while (( waited < timeout * 10 )); do
        after=$(wc -l < "$LOGFILE")
        if (( after > before )); then
            wait_log_quiet "$timeout"
            break
        fi
        sleep 0.1
        ((++waited))
    done

    after=$(wc -l < "$LOGFILE")
    if (( after > before )); then
        tail -n +"$((before + 1))" "$LOGFILE"
    fi
}

parse_channels_output() {
    # reads lines like: "chan 0, Yamaha Grand Piano" from stdin
    local line chan name
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^chan[[:space:]]+([0-9]+),[[:space:]]*(.+)$ ]]; then
            chan="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            CHANNEL_INSTRUMENT[$chan]="$name"
        fi
    done
}

parse_instruments_output() {
    local line bank program name key
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([0-9]{3})-([0-9]{3})[[:space:]]+(.+)$ ]]; then
            bank=$((10#${BASH_REMATCH[1]}))
            program=$((10#${BASH_REMATCH[2]}))
            name="${BASH_REMATCH[3]}"
            key="${bank}-${program}"
            INSTRUMENT[$key]="$name"
        fi
    done
}

find_instrument() {
    local needle="${1,,}"   # lowercase
    local key name
    for key in "${!INSTRUMENT[@]}"; do
        name="${INSTRUMENT[$key]}"
        if [[ "${name,,}" == *"$needle"* ]]; then
            printf '%s  %s\n' "$key" "$name"
        fi
    done
}

set_instrument() {
    local chan="$1"
    local key="$2"
    local bank program

    if [[ -z "${INSTRUMENT[$key]:-}" ]]; then
        printf 'unknown bank-program: %s (did you call refresh_instruments?)\n' "$key" >&2
        return 1
    fi

    bank="${key%-*}"
    program="${key#*-}"

    printf 'select %d 1 %d %d\n' "$chan" "$bank" "$program" >&3

    refresh_channels
}

set_instrument_by_name() {
    local chan="$1"
    local needle="$2"
    local match key name

    match=$(find_instrument "$needle" | head -n 1)
    if [[ -z "$match" ]]; then
        printf 'no instrument matching "%s"\n' "$needle" >&2
        return 1
    fi

    key="${match%% *}"
    name="${match#* }"

    set_instrument "$chan" "$key"
}

refresh_instruments() {
    parse_instruments_output < <(query_fsynth "inst 1")
}

refresh_channels() {
    parse_channels_output < <(query_fsynth "channels")
}

prompt_for_channel() {
    term_clear_row 20
    term_write 20 1 "Enter channel (0-15): "
    term_show_cursor

    # drain whatever's already sitting in the tty's input buffer — e.g.
    # the "c" keystroke that triggered this prompt in the first place
    while read -r -t 0.01 -n 1 _ < /dev/tty; do :; done

    local input
    read -r input < /dev/tty

    term_hide_cursor
    term_clear_row 20

    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 0 && input <= 15 )); then
        CURRENT_CHANNEL="$input"
        term_write 20 1 "Channel set to $CURRENT_CHANNEL"
    else
        term_write 20 1 "Invalid channel: $input"
    fi
}

prompt_for_instrument() {
    term_clear_row 20
    term_write 20 1 "Enter instrument name: "
    term_show_cursor

    # drain the triggering keystroke (and anything else pending)
    while read -r -t 0.01 -n 1 _ < /dev/tty; do :; done

    local needle
    read -r needle < /dev/tty

    term_hide_cursor
    term_clear_row 20

    local matches match_count key name
    matches=$(find_instrument "$needle")
    match_count=$(printf '%s\n' "$matches" | grep -c .)

    if [[ -z "$matches" ]]; then
        term_write 20 1 "No instrument matching \"$needle\""
        return 1
    fi

    if (( match_count > 1 )); then
        term_write 20 1 "Multiple matches for \"$needle\" — showing first:"
        # (or list them across rows 21+ if you want to show all choices)
    fi

    match=$(printf '%s\n' "$matches" | head -n 1)
    key="${match%% *}"
    name="${match#* }"

    set_instrument "$CURRENT_CHANNEL" "$key"
    term_clear_row 20
    term_write 20 1 "Channel $CURRENT_CHANNEL -> $name ($key)"
}

draw_ui() {
    term_clear_row 1
    term_write 1 1 "Instrument : $CURRENT_CHANNEL"

    term_clear_row 2
    term_write 2 1 "Channel : $CURRENT_CHANNEL"
}

note_to_midi() {
    local input="$1"
    local letter accidental octave offset

    # parse: one letter (A-G), optional # or b, then a signed integer octave
    if [[ "$input" =~ ^([A-Ga-g])(#|b)?(-?[0-9]+)$ ]]; then
        letter="${BASH_REMATCH[1]^^}"
        accidental="${BASH_REMATCH[2]}"
        octave="${BASH_REMATCH[3]}"
    else
        printf "invalid note: $input\n" >&2
        return 1
    fi

    case "$letter" in
        C) offset=0 ;;
        D) offset=2 ;;
        E) offset=4 ;;
        F) offset=5 ;;
        G) offset=7 ;;
        A) offset=9 ;;
        B) offset=11 ;;
    esac

    if [[ "$accidental" == "#" ]]; then
        offset=$((offset + 1))
    elif [[ "$accidental" == "b" ]]; then
        offset=$((offset - 1))
    fi

    local midi=$(( (octave + 1) * 12 + offset ))

    if (( midi < 0 || midi > 127 )); then
        printf "out of MIDI range (0-127): $input -> $midi\n" >&2
        return 1
    fi

    printf "$midi"
}
# End Functions

# Init
sleep 0.3
printf 'Waiting for soundfont to finish loading.'
for i in $(seq 1 60); do
    refresh_instruments
    if (( ${#INSTRUMENT[@]} > 0 )); then
        printf '\n done (%d instruments)\n' "${#INSTRUMENT[@]}"
        break
    fi
    printf '.'
    sleep 0.5
done

if (( ${#INSTRUMENT[@]} == 0 )); then
    printf '\nTimed out waiting for soundfont — check %s\n' "$LOGFILE" >&2
fi

# Clear Terminal
term_save_screen
term_clear
term_hide_cursor

set_instrument_by_name $CURRENT_CHANNEL "${INSTRUMENT['0-0']}"

draw_ui

# Start key listener
TERM_WINID=$(xdotool getactivewindow 2>/dev/null) || TERM_WINID=""
for code in "${!KEYMAP[@]}"; do
    xset -r "$code" 2>/dev/null
done

stdbuf -oL xinput test-xi2 --root 2>/dev/null | stdbuf -oL awk '
    /EVENT type 2/ { state = "press"; next }
    /EVENT type 3/ { state = "release"; next }
    /detail:/ {
        if (state == "press")        { print "PRESS", $2; fflush(); state = "" }
        else if (state == "release") { print "RELEASE", $2; fflush(); state = "" }
    }
' | while read -r action code; do
    active=$(xdotool getactivewindow 2>/dev/null) || active=""
    if [[ "$active" != "$TERM_WINID" ]]; then
        continue
    fi

    # Prompts
    if [[ "$code" == "54" && "$action" == "PRESS" ]]; then # C key
        prompt_for_channel
        draw_ui
        continue
    fi
    if [[ "$code" == "55" && "$action" == "PRESS" ]]; then # C key
        prompt_for_instrument
        draw_ui
        continue
    fi

    # Check note
    mapped="${KEYMAP[$code]:-}"
    if [[ -z "$mapped" ]]; then
        continue
    fi
    note=$(note_to_midi "$mapped") || continue

    case "$action" in
        PRESS)
                fsynth_send "noteon $CURRENT_CHANNEL $note 100"
            ;;
        RELEASE)
            fsynth_send "noteoff $CURRENT_CHANNEL $note"
            ;;
    esac
done
