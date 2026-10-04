#!/usr/bin/env bash
set -euo pipefail

print() {
    printf '%b\n' "$1" >&2
}

SOUNDFONT=$(find /usr/share/sounds/sf2/ -name "*.sf2" 2>/dev/null | head -n 1)

if [[ -z "$SOUNDFONT" ]]; then
    print "Error: No SoundFont (.sf2) file found under /usr/share/sounds/sf2/"
    exit 1
else
    for sf in "/usr/share/sounds/sf2/FluidR3_GM.sf2" \
              "/usr/share/sounds/sf2/default-GM.sf2" \
              "/usr/share/sounds/sf2/TimGM6mb.sf2"; do
        if [[ -f "$sf" ]]; then
            SOUNDFONT="$sf"
            break
        fi
    done
fi

PORT=9800
FS_PID=""

if ! command -v nc >/dev/null 2>&1; then
    print "Error: 'nc' (netcat) is required. [netcat-openbsd]"
    exit 1
fi

fluidsynth_ready() {
    print "Initializing FluidSynth Server..."
    if pgrep -f "fluidsynth.*$PORT" >/dev/null 2>&1 || fuser "$PORT/tcp" >/dev/null 2>&1; then
        print "Cleaning up lingering FluidSynth instances..."
        pkill -9 -f "fluidsynth" || true
        fuser -k -9 "$PORT/tcp" >/dev/null 2>&1 || true
        sleep 0.5
    fi

    # Start FluidSynth server in background, localhost
    print "Starting FluidSynth Server..."
    fluidsynth -a alsa -s -i "$SOUNDFONT" -o shell.port=$PORT >/dev/null 2>&1 &
    FS_PID=$!

    print "Waiting for FluidSynth Server on port $PORT..."
    local RETRIES=50
    while ! nc -z 127.0.0.1 $PORT >/dev/null 2>&1; do
        sleep 0.1
        RETRIES=$((RETRIES - 1))
        if [[ $RETRIES -le 0 ]]; then
            print "Error: FluidSynth failed to bind port $PORT within 5 seconds."
            kill -9 "$FS_PID" 2>/dev/null || true
            exit 1
        fi
    done

    print "Connected."

    (
        echo "cc 0 123 0"
        echo "cc 0 120 0"
    ) | nc -w 1 127.0.0.1 $PORT >/dev/null 2>&1

    print "FluidSynth is fully operational."
}


# Save terminal configuration
OLD_STTY=$(stty -g)
cleanup() {
    echo -e "\nServer shut down. Exited cleanly."
    stty "$OLD_STTY"
    if kill -0 "$FS_PID" 2>/dev/null; then
        kill "$FS_PID" 2>/dev/null || true
        wait "$FS_PID" 2>/dev/null || true
    fi
    echo -e "\nServer shut down. Exited cleanly."
}

trap cleanup EXIT INT TERM

sleep 1

set_instrument() {
    local prog_num="$1"
    local inst_name="$2"
    echo "prog 0 $prog_num" | nc -w 1 127.0.0.1 $PORT >/dev/null 2>&1 &
    printf "\e[1A\e[2K"
    print " Active Instrument: [$prog_num] $inst_name"
}
get_pitch_hex() {
    local note_input="$1"
    local velocity="${2:-96}"
    local channel="${3:-0}"

    # Validate note
    if [[ ! "$note_input" =~ ^([A-Ga-g])([#b]?)(-?[0-9]+)$ ]]; then
        print "Error: Invalid note format '$note_input'. Use format like C4, Eb4, F#5."
        return 1
    fi

    local base_note="${BASH_REMATCH[1]^}"
    local accidental="${BASH_REMATCH[2]}"
    local octave="${BASH_REMATCH[3]}"

    # Map base note to chromatic index
    local base_val
    case "$base_note" in
        C) base_val=0 ;;
        D) base_val=2 ;;
        E) base_val=4 ;;
        F) base_val=5 ;;
        G) base_val=7 ;;
        A) base_val=9 ;;
        B) base_val=11 ;;
    esac

    # Apply accidental modifiers
    if [[ "$accidental" == "#" ]]; then
        ((base_val++))
    elif [[ "$accidental" == "b" ]]; then
        ((base_val--))
    fi

    # Calculate MIDI pitch
    local pitch=$(( (octave + 1) * 12 + base_val ))

    # Validate MIDI range limits
    if (( pitch < 0 || pitch > 127 )); then
        print "Error: Pitch $pitch out of valid MIDI range (0-127)."
        return 1
    fi

    printf "0x%02X" "$pitch"
}

LAST_KEY=""
LAST_TIME=0
play_note() {
    local note_name="$1"
    local pitch_hex="0x3C"
    pitch_hex=$(get_pitch_hex "$note_name")

    pitch_dec=$(( pitch_hex ))
    (
        echo "noteoff 0 $pitch_dec"
        echo "noteon 0 $pitch_dec 100"
    ) | nc -w 1 127.0.0.1 $PORT >/dev/null 2>&1 &
}

stty -echo -icanon min 1 time 0

fluidsynth_ready

declare -g -A INSTRUMENTS=(
    [0]="Yamaha Grand Piano"    [1]="Bright Yamaha Grand"
    [2]="Electric Piano"        [3]="Honky Tonk"
    [4]="Rhodes EP"             [5]="Legend EP 2"
    [6]="Harpsichord"           [7]="Clavinet"
    [8]="Celesta"               [9]="Glockenspiel"
    [10]="Music Box"            [11]="Vibraphone"
    [12]="Marimba"              [13]="Xylophone"
    [14]="Tubular Bells"        [15]="Dulcimer"
    [16]="DrawbarOrgan"         [17]="Percussive Organ"
    [18]="Rock Organ"           [19]="Church Organ"
    [20]="Reed Organ"           [21]="Accordian"
    [22]="Harmonica"            [23]="Bandoneon"
    [24]="Nylon String Guitar"  [25]="Steel String Guitar"
    [26]="Jazz Guitar"          [27]="Clean Guitar"
    [28]="Palm Muted Guitar"    [29]="Overdrive Guitar"
    [30]="Distortion Guitar"    [31]="Guitar Harmonics"
    [32]="Acoustic Bass"        [33]="Fingered Bass"
    [34]="Picked Bass"          [35]="Fretless Bass"
    [36]="Slap Bass"            [37]="Pop Bass"
    [38]="Synth Bass 1"         [39]="Synth Bass 2"
[40]="Violin"
[41]="Viola"
[42]="Cello"
[43]="Contrabass"
[44]="Tremolo"
[45]="Pizzicato Section"
[46]="Harp"
[47]="Timpani"
[48]="Strings"
[49]="Slow Strings"
[50]="Synth Strings 1"
[51]="Synth Strings 2"
[52]="Ahh Choir"
[53]="Ohh Voices"
[54]="Synth Voice"
[55]="Orchestra Hit"
[56]="Trumpet"
[57]="Trombone"
[58]="Tuba"
[59]="Muted Trumpet"
[60]="French Horns"
[61]="Brass Section"
[62]="Synth Brass 1"
[63]="Synth Brass 2"
[64]="Soprano Sax"
[65]="Alto Sax"
[66]="Tenor Sax"
[67]="Baritone Sax"
[68]="Oboe"
[69]="English Horn"
[70]="Bassoon"
[71]="Clarinet"
[72]="Piccolo"
[73]="Flute"
[74]="Recorder"
[75]="Pan Flute"
[76]="Bottle Chiff"
[77]="Shakuhachi"
[78]="Whistle"
[79]="Ocarina"
[80]="Square Lead"
[81]="Saw Wave"
[82]="Calliope Lead"
[83]="Chiffer Lead"
[84]="Charang"
[85]="Solo Vox"
[86]="Fifth Sawtooth Wave"
[87]="Bass & Lead"
[88]="Fantasia"
[89]="Warm Pad"
[90]="Polysynth"
[91]="Space Voice"
[92]="Bowed Glass"
[93]="Metal Pad"
[94]="Halo Pad"
[95]="Sweep Pad"
[96]="Ice Rain"
[97]="Soundtrack"
[98]="Crystal"
[99]="Atmosphere"
[100]="Brightness"
[101]="Goblin"
[102]="Echo Drops"
[103]="Star Theme"
[104]="Sitar"
[105]="Banjo"
[106]="Shamisen"
[107]="Koto"
[108]="Kalimba"
[109]="BagPipe"
[110]="Fiddle"
[111]="Shenai"
[112]="Tinker Bell"
[113]="Agogo"
[114]="Steel Drums"
[115]="Woodblock"
[116]="Taiko Drum"
[117]="Melodic Tom"
[118]="Synth Drum"
[119]="Reverse Cymbal"
[120]="Fret Noise"
[121]="Breath Noise"
[122]="Sea Shore"
[123]="Bird Tweet"
[124]="Telephone"
[125]="Helicopter"
[126]="Applause"
[127]="Gun Shot"
)

print ""
print " ┌──┬─┬─┬─┬─┬─┬──┬──┬─┬─┬─┬──┬──┬─┬─┬─┬─┬─┬──┐"
print " │  │ │ │ │ │ │  │  │ │ │ │  │  │ │ │ │ │ │  │"
print " │  │W│ │E│ │R│  │  │Y│ │U│  │  │O│ │P│ │[│  │"
print " │  └┬┘ └┬┘ └┬┘  │  └┬┘ └┬┘  │  └┬┘ └┬┘ └┬┘  │"
print " │ A │ S │ D │ F │ G │ H │ J │ K │ L │ ; │ ' │"
print " └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘"
print "                   C\n"

print " C - Stop"
print " Q - Quit\n"
set_instrument 0 "${INSTRUMENTS['0']}"

IS_TYPE=false
COUNTING=1
NUMBERS=""
while true; do
    if read -r -N 1 -t 0.001 key; then
        case "$key" in
            1)
                NUMBERS+="1"
                COUNTING=100
                IS_TYPE=true
                ;;
            2)
                NUMBERS+="2"
                COUNTING=100
                IS_TYPE=true
                ;;
            3)
                NUMBERS+="3"
                COUNTING=100
                IS_TYPE=true
                ;;
            4)
                NUMBERS+="4"
                COUNTING=100
                IS_TYPE=true
                ;;
            5)
                NUMBERS+="5"
                COUNTING=100
                IS_TYPE=true
                ;;
            6)
                NUMBERS+="6"
                COUNTING=100
                IS_TYPE=true
                ;;
            7)
                NUMBERS+="7"
                COUNTING=100
                IS_TYPE=true
                ;;
            8)
                NUMBERS+="8"
                COUNTING=100
                IS_TYPE=true
                ;;
            9)
                NUMBERS+="9"
                COUNTING=100
                IS_TYPE=true
                ;;
            0)
                NUMBERS+="0"
                COUNTING=100
                IS_TYPE=true
                ;;

            a|A) play_note "F3" ;;
            s|S) play_note "G3" ;;
            d|D) play_note "A3" ;;
            f|F) play_note "B3" ;;
            g|G) play_note "C4" ;;
            h|H) play_note "D4" ;;
            j|J) play_note "E4" ;;
            k|K) play_note "F4" ;;
            l|L) play_note "G4" ;;
            \;|\:) play_note "A4" ;;
            \'|\") play_note "B4" ;;

            w|W) play_note "Gb3" ;;
            e|E) play_note "Ab3" ;;
            r|R) play_note "Bb3" ;;

            y|Y) play_note "Db4" ;;
            u|U) play_note "Eb4" ;;

            o|O) play_note "Gb4" ;;
            p|P) play_note "Ab4" ;;
            \[|\{) play_note "Bb4" ;;

            c|C|" ")
                (
                    echo "cc 0 123 0"
                    echo "cc 0 120 0"
                ) | nc -w 1 127.0.0.1 $PORT >/dev/null 2>&1 &
                ;;
            q|Q) break ;;

            *) ;;
        esac
    fi

    if $IS_TYPE; then
        ((COUNTING++))

        if (( COUNTING >= 200 )); then
            if [[ "$NUMBERS" -le 127 ]]; then
                set_instrument $NUMBERS "${INSTRUMENTS[$NUMBERS]:-0}"
            fi
            NUMBERS=""
            COUNTING=1
            IS_TYPE=false
        fi
    fi

    sleep 0.01
done
