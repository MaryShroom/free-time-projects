#!/usr/bin/env bash

set -euo pipefail

HAS_W=0
HAS_H=0

MSG="Done."

PAINT_ROW=10
PAINT_COL=10
NAME="Untitled"
PAINT_BG=2
EDIT=1
FILE_PATH=""
COLOR_PALETTE_TYPE=1
FORCE_RUN=0
TRUECOLOR=0

while getopts "w:l:t:b:f:c:xh" opt; do
    case "$opt" in
        w)
			# Width/Column
			PAINT_COL="$OPTARG"
			HAS_W=1
			;;
        l)
			# Length/Height/Row
			PAINT_ROW="$OPTARG"
			HAS_H=1
			;;
        t) NAME="$OPTARG" ;; # Name
        b)
			# Set canvas background, white default
			if [[ "$OPTARG" -ge 0 && "$OPTARG" -le 8 ]]; then
				PAINT_BG="$OPTARG"
			fi
			;;
		f)
			# Check is file
			if [[ ! -f "$OPTARG" || ! -r "$OPTARG" ]]; then
				printf 'Error: State file "%s" is unreadable or missing.\n' "$OPTARG" >&2
				exit 1
			fi

			exec 3< "$OPTARG"

			# Read magic
			IFS= read -r -d '' magic <&3 || {
				printf 'Error: Failed to read magic header from file.\n' >&2
				exec 3<&-
				exit 1;
			}

			# Check metadata
			if [[ "$magic" != "TUI_STATE_V1" ]]; then
				printf 'Error: Invalid file format (Magic: "%s").\n' "$magic" >&2
				exec 3<&-
				exit 1
			fi

			FILE_PATH="$OPTARG"
			EDIT=0
			;;
		c)
			if [[ "$OPTARG" -ge 1 && "$OPTARG" -le 9 ]]; then
				COLOR_PALETTE_TYPE="$OPTARG"
			fi
			;;
		x)  FORCE_RUN=1;	;;
		h)
			printf "# Usage: $0 [-w width -l length -t title -b bg_color -f file -c palette -x force_run -h help]\n"
			printf "#   -w  Set Width\n#   -l  Set Length/Height\n#   -t  Set Title\n#   -b  Set Background Color (Refer below)\n#   -f  Open .bin File\n#   -c  Set Color Palette (Refer Below)\n#       [If terminal support truecolor. Does not affect on save]\n#   -x  Force run [NOT RECOMMENDED]\n#   -h  Show Help\n#\n"
			printf "# Default backgound color (White)\n#   0 - Transparent\n#   1 - Black\n#   2 - White\n#   3 - Red\n#   4 - Green\n#   5 - Yellow\n#   6 - Blue\n#   7 - Magenta\n#   8 - Cyan\n#\n"
			printf "# Color Palette [If terminal support truecolor. Does not affect on save]\n"
			printf "#   1 - Adwaita Dark (GNOME Terminal) "
			printf "\e[48;2;23;20;33m  \e[48;2;192;28;40m  \e[48;2;38;162;105m  \e[48;2;162;115;0m  "
			printf "\e[48;2;18;72;139m  \e[48;2;163;71;186m  \e[48;2;42;161;152m  \e[48;2;208;207;204m  \e[0m"
			printf " # Default\n"
			printf "#   2 - Catppuccin Mocha  (Alacritty) "
			printf "\e[48;2;69;71;90m  \e[48;2;243;139;168m  \e[48;2;166;227;161m  \e[48;2;249;226;175m  "
			printf "\e[48;2;137;180;250m  \e[48;2;245;194;231m  \e[48;2;148;226;213m  \e[48;2;186;194;222m  \e[0m\n"
			printf "#   3 - Breeze              (Konsole) "
			printf "\e[48;2;35;38;41m  \e[48;2;237;21;21m  \e[48;2;17;209;22m  \e[48;2;246;116;0m  "
			printf "\e[48;2;29;153;243m  \e[48;2;155;89;182m  \e[48;2;26;188;156m  \e[48;2;252;252;252m  \e[0m\n"
			printf "#   4 - Pencil Dark         (WezTerm) "
			printf "\e[48;2;0;0;0m  \e[48;2;204;0;0m  \e[48;2;78;154;6m  \e[48;2;196;160;0m  "
			printf "\e[48;2;52;101;164m  \e[48;2;117;80;123m  \e[48;2;6;152;154m  \e[48;2;211;215;207m  \e[0m\n"
			printf "#   5 - Tango Dark   (Xfce4 Terminal) "
			printf "\e[48;2;0;0;0m  \e[48;2;170;0;0m  \e[48;2;0;170;0m  \e[48;2;170;85;0m  "
			printf "\e[48;2;0;0;170m  \e[48;2;170;0;170m  \e[48;2;0;170;170m  \e[48;2;170;170;170m  \e[0m\n"
			printf "#   6 - Kitty Dark            (Kitty) "
			printf "\e[48;2;0;0;0m  \e[48;2;204;4;3m  \e[48;2;25;203;0m  \e[48;2;206;203;0m  "
			printf "\e[48;2;13;115;204m  \e[48;2;203;30;209m  \e[48;2;13;205;205m  \e[48;2;221;221;221m  \e[0m\n"
			printf "#   7 - Solarized Dark       (iTerm2) "
			printf "\e[48;2;7;54;66m  \e[48;2;220;50;47m  \e[48;2;133;153;0m  \e[48;2;181;137;0m  "
			printf "\e[48;2;38;139;210m  \e[48;2;211;54;130m  \e[48;2;42;161;152m  \e[48;2;238;232;213m  \e[0m\n"
			printf "#   8 - Nord              (Alacritty) "
			printf "\e[48;2;59;66;82m  \e[48;2;191;97;106m  \e[48;2;163;190;140m  \e[48;2;235;203;139m  "
			printf "\e[48;2;129;161;193m  \e[48;2;180;142;173m  \e[48;2;136;192;208m  \e[48;2;229;233;240m  \e[0m\n"
			printf "#   9 - Classic VT100         (XTerm) "
			printf "\e[48;2;0;0;0m  \e[48;2;205;0;0m  \e[48;2;0;205;0m  \e[48;2;205;205;0m  "
			printf "\e[48;2;0;0;205m  \e[48;2;205;0;205m  \e[48;2;0;205;205m  \e[48;2;229;229;229m  \e[0m\n"
			printf "#\n"
			printf "# Key Input\n#   #  Foreground - Left Click on color palette\n#   \e[41m \e[0m  Background - Right Click on color palette\n#   [] Shade - Left Click on color shade\n"
			printf "#   Q - Quit program\n#   P - Choose color palette [number]. Press again to cancel\n"
			printf "#   Ctrl + A - Save as .pam\n#   Ctrl + S - Save as .bin (Recommended)\n#   Ctrl + E - Save as .bmp (Half-width size 1:2)\n#   Ctrl + R - Save as .bmp (Full-width size 1:1)\n#   Ctrl + D - Save as .png (Half-width size 1:2) [Perl Required]\n#   Ctrl + F - Save as .png (Full-width size 1:1) [Perl Required]\n"
			exit 0
			;;
        ?)
			printf "# Usage: $0 [-w width -l length -t title -b bg_color -f file -c palette -x force_run -h help]\n"
			exit 1
			;;
    esac
done

shift $(( OPTIND - 1 ))

# Get terminal settings
TTY_DEV="$(tty 2>/dev/null || echo "/dev/tty")"

# Save terminal settings
SAVED_STTY=""
if [[ -t 1 ]]; then
    SAVED_STTY="$(stty -g <"$TTY_DEV" 2>/dev/null || true)"
fi

# Chech support before doing anything. If -x flag presence, ignore
if [[ "$FORCE_RUN" -ne 1 ]]; then
	if [[ -z "${TERM:-}" || "$TERM" == "dumb" ]]; then
		printf "Error: Dumb or uninitialized terminal environment ($TERM).\n" >&2
		exit 1
	fi
	if [[ "$TERM" == "linux" ]] || [[ "$TTY_DEV" =~ ^/dev/tty[0-9]+$ ]]; then
		printf "Error: Unsupported Linux Virtual Console detected ($TTY_DEV).\n" >&2
		exit 1
	fi
	if [[ ! -c "$TTY_DEV" ]]; then
		printf "Error: $TTY_DEV is not a valid character device.\n" >&2
		exit 1
	fi
fi

# Check presence width and length flags
if [[ "$HAS_W" -ne "$HAS_H" ]]; then
	echo "Error: Both -w and -h flags must be provided together." >&2
	exit 1
fi

# Check Truecolor support
if [[ "${COLORTERM:-}" == *[Tt][Rr][Uu][Ee][Cc][Oo][Ll][Oo][Rr]* || "${COLORTERM:-}" == *24[Bb][Ii][Tt]* ]]; then
	TRUECOLOR=1
fi

TERM_LINES=0
TERM_COLS=0

CANVAS_MAX_LINES=0
CANVAS_MAX_COLS=0

PAINT_COL_SHIFT=0
PAINT_ROW_SHIFT=0
PAINT_OUTLINE_LEFT=0
PAINT_OUTLINE_RIGHT=0
PAINT_OUTLINE_TOP=0
PAINT_OUTLINE_BOTTOM=0
PAINT_ANCHOR_ROW=0
PAINT_ANCHOR_COL=0
PAINT_COLOR=1
PAINT_SHADE=4
declare -A PAINT_ITEMS

CURSOR_ROW=0
CURSOR_COL=0

RESIZE=0
DRAG=0
IS_DRAW=0
IS_SAVE=0
MEM_USAGE_STR="0 KB"

PERL_SUPPORT=0

# Color Palette 1
declare -A GNOME_COLOR_MAP=(
    [30]="23 20 33"     [40]="23 20 33"     # Black
    [31]="192 28 40"    [41]="192 28 40"    # Red
    [32]="38 162 105"   [42]="38 162 105"   # Green
    [33]="162 115 0"    [43]="162 115 0"    # Yellow
    [34]="18 72 139"   	[44]="18 72 139"   	# Blue
    [35]="163 71 186"   [45]="163 71 186"   # Magenta
    [36]="42 161 152"   [46]="42 161 152"   # Cyan
    [37]="208 207 204"  [47]="208 207 204"  # White
)
# Color Palette 2
declare -A ALACRITTY_COLOR_MAP=(
    [30]="69 71 90"		[40]="69 71 90"		# Black
    [31]="243 139 168" 	[41]="243 139 168"  # Red
    [32]="166 227 161" 	[42]="166 227 161"  # Green
    [33]="249 226 175" 	[43]="249 226 175"  # Yellow
    [34]="137 180 250" 	[44]="137 180 250"  # Blue
    [35]="245 194 231"	[45]="245 194 231"  # Magenta
    [36]="148 226 213"	[46]="148 226 213"  # Cyan
    [37]="186 194 222"	[47]="186 194 222"  # White
)
# Color Palette 3
declare -A KONSOLE_COLOR_MAP=(
    [30]="35 38 41"		[40]="35 38 41"		# Black
    [31]="237 21 21" 	[41]="237 21 21"  	# Red
    [32]="17 209 22" 	[42]="17 209 22"  	# Green
    [33]="246 116 0" 	[43]="246 116 0" 	# Yellow
    [34]="29 153 243" 	[44]="29 153 243"   # Blue
    [35]="155 89 182"	[45]="155 89 182"   # Magenta
    [36]="26 188 156"	[46]="26 188 156"   # Cyan
    [37]="252 252 252"	[47]="252 252 252"  # White
)
# Color Palette 4
declare -A WEZTERM_COLOR_MAP=(
    [30]="0 0 0"		[40]="0 0 0"		# Black
    [31]="204 0 0" 		[41]="204 0 0"  	# Red
    [32]="78 154 6" 	[42]="78 154 6"  	# Green
    [33]="196 160 0" 	[43]="196 160 0" 	# Yellow
    [34]="52 101 164" 	[44]="52 101 164"  	# Blue
    [35]="117 80 123"	[45]="117 80 123" 	# Magenta
    [36]="6 152 154"	[46]="6 152 154"  	# Cyan
    [37]="211 215 207"	[47]="211 215 207"  # White
)
# Color Palette 5
declare -A XFCE4_COLOR_MAP=(
    [30]="0 0 0"		[40]="0 0 0"		# Black
    [31]="170 0 0" 		[41]="170 0 0"  	# Red
    [32]="0 170 0" 		[42]="0 170 0"  	# Green
    [33]="170 85 0" 	[43]="170 85 0" 	# Yellow
    [34]="0 0 170" 		[44]="0 0 170"  	# Blue
    [35]="170 0 170"	[45]="170 0 170" 	# Magenta
    [36]="0 170 170"	[46]="0 170 170"  	# Cyan
    [37]="170 170 170"	[47]="170 170 170"  # White
)
# Color Palette 6
declare -A KITTY_COLOR_MAP=(
    [30]="0 0 0"		[40]="0 0 0"		# Black
    [31]="204 4 3" 		[41]="204 4 3"  	# Red
    [32]="25 203 0" 	[42]="25 203 0"  	# Green
    [33]="206 203 0" 	[43]="206 203 0" 	# Yellow
    [34]="13 115 204" 	[44]="13 115 204"  	# Blue
    [35]="203 30 209"	[45]="203 30 209" 	# Magenta
    [36]="13 205 205"	[46]="13 205 205"  	# Cyan
    [37]="221 221 221"	[47]="221 221 221"  # White
)
# Color Palette 7
declare -A ITERM2_COLOR_MAP=(
    [30]="7 54 66"		[40]="7 54 66"		# Black
    [31]="220 50 47" 	[41]="220 50 47"  	# Red
    [32]="133 153 0" 	[42]="133 153 0"  	# Green
    [33]="181 137 0" 	[43]="181 137 0" 	# Yellow
    [34]="38 139 210" 	[44]="38 139 210"  	# Blue
    [35]="211 54 130"	[45]="211 54 130" 	# Magenta
    [36]="42 161 152"	[46]="42 161 152"  	# Cyan
    [37]="238 232 213"	[47]="238 232 213"  # White
)
# Color Palette 8
declare -A NORD_COLOR_MAP=(
    [30]="59 66 82"		[40]="59 66 82"		# Black
    [31]="191 97 106" 	[41]="191 97 106"	# Red
    [32]="163 190 140" 	[42]="163 190 140"  # Green
    [33]="235 203 139" 	[43]="235 203 139" 	# Yellow
    [34]="129 161 193" 	[44]="129 161 193"  # Blue
    [35]="180 142 173"	[45]="180 142 173" 	# Magenta
    [36]="136 192 208"	[46]="136 192 208"  # Cyan
    [37]="229 233 240"	[47]="229 233 240"  # White
)
# Color Palette 9
declare -A XTERM_COLOR_MAP=(
    [30]="0 0 0"		[40]="0 0 0"		# Black
    [31]="205 0 0" 		[41]="205 0 0"  	# Red
    [32]="0 205 0" 		[42]="0 205 0"  	# Green
    [33]="205 205 0" 	[43]="205 205 0" 	# Yellow
    [34]="0 0 205" 		[44]="0 0 205"  	# Blue
    [35]="205 0 205"	[45]="205 0 205" 	# Magenta
    [36]="0 205 205"	[46]="0 205 205"  	# Cyan
    [37]="229 229 229"	[47]="229 229 229"  # White
)
update_palette() {
	# Get color palette
	case "$COLOR_PALETTE_TYPE" in
		1)	declare -n -g PALETTE_SELECT=GNOME_COLOR_MAP		;;
		2)	declare -n -g PALETTE_SELECT=ALACRITTY_COLOR_MAP	;;
		3)	declare -n -g PALETTE_SELECT=KONSOLE_COLOR_MAP		;;
		4)	declare -n -g PALETTE_SELECT=WEZTERM_COLOR_MAP		;;
		5)	declare -n -g PALETTE_SELECT=XFCE4_COLOR_MAP		;;
		6)	declare -n -g PALETTE_SELECT=KITTY_COLOR_MAP		;;
		7)	declare -n -g PALETTE_SELECT=ITERM2_COLOR_MAP		;;
		8)	declare -n -g PALETTE_SELECT=NORD_COLOR_MAP			;;
		9)	declare -n -g PALETTE_SELECT=XTERM_COLOR_MAP		;;
		*)	declare -n -g PALETTE_SELECT=GNOME_COLOR_MAP		;; # Default
	esac
}

cleanup() {
    trap - EXIT INT TERM WINCH
    use_mouse 0
    printf '\e[?1003l\e[?1006l\e[0m\e[?25h\e[?1049l' >"$TTY_DEV" 2>/dev/null || true
    if [[ -n "$SAVED_STTY" ]]; then
	stty "$SAVED_STTY" <"$TTY_DEV" 2>/dev/null || true
    fi
    stty echo icanon ixon <"$TTY_DEV" 2>/dev/null || true

    printf "$MSG\n"
}

handle_signal() {
	cleanup
	exit 130
}

ansi_to_rgba_bytes() {
    local str="$1"
    local raw="" char=" "
    local a=0 r=0 g=0 b=0

    if [[ "$str" =~ \e\[([0-9;]+)m ]]; then
        raw="${BASH_REMATCH[1]}"
    fi

    char="${str#*m}"
    char="${char:0:${#char}-5}"

    IFS=';' read -ra codes <<< "$raw"

	local bg="0 0 0"
	if [[ "${codes[0]}" -ne 0 ]]; then
		bg="${PALETTE_SELECT[${codes[0]}]}"
	fi

    local fg="0 0 0"
    if [[ -v codes[1] && "${codes[1]}" -ne 0 ]]; then
        local fg="${PALETTE_SELECT[${codes[1]}]}"
    fi

    # Set opacity
    local bg_a=100 fg_a=0
    if [[ "$char" == "\u2588" ]]; then
        bg_a=0
        fg_a=100
        a=255
    elif [[ "$char" == "\u2593" ]]; then
        bg_a=25
        fg_a=75
        a=191
    elif [[ "$char" == "\u2592" ]]; then
        bg_a=50
        fg_a=50
        a=127
    elif [[ "$char" == "\u2591" ]]; then
        bg_a=75
        fg_a=25
        a=63
    elif [[ "$char" == " " ]]; then
        bg_a=100
        fg_a=0
        a=0
    fi

    # Background full transparent
    if [[ "${codes[0]}" -eq 0 ]]; then
        bg_a=0
    fi

    # Alpha max if background
    if [[ "${codes[0]}" -ne 0 ]]; then
        a=255
    fi
    # Alpha min if foreground is 0
    if [[ -v codes[1] && "${codes[1]}" -eq 0 ]]; then
        a=0
    fi

    local bg_r=0 bg_g=0 bg_b=0
    local fg_r=0 fg_g=0 fg_b=0
    read -r bg_r bg_g bg_b <<< "$bg"
    read -r fg_r fg_g fg_b <<< "$fg"
    r=$(( (fg_r * fg_a + bg_r * bg_a) / 100 ))
    g=$(( (fg_g * fg_a + bg_g * bg_a) / 100 ))
    b=$(( (fg_b * fg_a + bg_b * bg_a) / 100 ))

    # Format to binary sequence (R G B A)
    printf '\\x%02x\\x%02x\\x%02x\\x%02x' "$r" "$g" "$b" "$a"
}

pam_to_bmp() {
	local scale_x="${1:-1}" # x scale factor (default 1)
	local scale_y="${2:-1}" # y scale factor (default 1)

	# Parse PAM Header
	local w h depth line
	while IFS= read -r line; do
		line="${line%$'\r'}" # Strip \r if present
		[[ "$line" =~ ^WIDTH\ ([0-9]+) ]] && w="${BASH_REMATCH[1]}"
		[[ "$line" =~ ^HEIGHT\ ([0-9]+) ]] && h="${BASH_REMATCH[1]}"
		[[ "$line" =~ ^DEPTH\ ([0-9]+) ]] && depth="${BASH_REMATCH[1]}"
		[[ "$line" =~ ^ENDHDR ]] && break
	done

	# Calculate Scaled Dimensions
	local out_w=$(( w * scale_x ))
	local out_h=$(( h * scale_y ))

	local unpadded_row_bytes=$(( out_w * 4 ))
	local padding_bytes=$(( (4 - (unpadded_row_bytes % 4)) % 4 ))
	local padded_row_bytes=$(( unpadded_row_bytes + padding_bytes ))

	local pixel_offset=122 # 14 (File Header) + 108 (V4 Header)
	local image_size=$(( padded_row_bytes * out_h ))
	local file_size=$(( pixel_offset + image_size ))

	# Octal Binary Encoders
	le32() {
		local v=$1
		printf "\\$(printf '%03o\\%03o\\%03o\\%03o' \
			$(( v & 0xFF )) \
			$(( (v >> 8) & 0xFF )) \
			$(( (v >> 16) & 0xFF )) \
			$(( (v >> 24) & 0xFF )))"
	}

	le16() {
		local v=$1
		printf "\\$(printf '%03o\\%03o' \
			$(( v & 0xFF )) \
			$(( (v >> 8) & 0xFF )))"
	}

	# Construct BITMAPFILEHEADER (14 bytes)
	printf "BM"
	le32 "$file_size"
	le16 0; le16 0
	le32 "$pixel_offset"

	# Construct BITMAPV4HEADER (108 bytes)
	le32 108
	le32 "$out_w"
	le32 "$out_h"
	le16 1
	le16 32
	le32 3
	le32 "$image_size"
	le32 2835; le32 2835
	le32 0; le32 0

	# RGBA Bitmasks (Little-Endian BGRA 32-bit)
	printf "\x00\x00\xFF\x00"           # Red Mask   (0x00FF0000)
	printf "\x00\xFF\x00\x00"           # Green Mask (0x0000FF00)
	printf "\xFF\x00\x00\x00"           # Blue Mask  (0x000000FF)
	printf "\x00\x00\x00\xFF"           # Alpha Mask (0xFF000000)

	# (CSType, Endpoints, Gamma Red/Green/Blue)
	printf '\x00%.0s' {1..52}

	# Read PAM raw binary stream as zero-padded 2-digit hex values
	local raw_bytes
	if command -v hexdump >/dev/null 2>&1; then
		raw_bytes=($(hexdump -v -e '1/1 "%02x "'))
	else
		# Fallback for minimal systems using od
		raw_bytes=($(od -An -v -t x1 | tr -s ' ' | sed 's/^ //' | tr ' ' '\n' | awk '{printf "%02s\n", $0}' | tr ' ' '0'))
	fi

	# Pre-build row padding string (if needed)
	local pad_str=""
	if (( padding_bytes > 0 )); then
		for (( p = 0; p < padding_bytes; p++ )); do
			pad_str+="\\x00"
		done
	fi

	local y x i j idx r g b a px
	local row_bytes_out=""

	# Extract Rows Bottom-Up
	for (( y = h - 1; y >= 0; y-- )); do
		row_bytes_out=""

		for (( x = 0; x < w; x++ )); do
			idx=$(( (y * w + x) * depth ))

			# Extract RGBA from array
			r="${raw_bytes[$idx]}"
			g="${raw_bytes[$((idx + 1))]}"
			b="${raw_bytes[$((idx + 2))]}"

			if (( depth == 4 )); then
				a="${raw_bytes[$((idx + 3))]}"
			else
				a="ff" # Full opacity for RGB images
			fi

			# Form BGRA pixel
			px="\\x${b}\\x${g}\\x${r}\\x${a}"

			# x Scaling
			for (( i = 0; i < scale_x; i++ )); do
				row_bytes_out+="$px"
			done
		done

		row_bytes_out+="$pad_str"

		# y Scaling
		for (( j = 0; j < scale_y; j++ )); do
			printf "%b" "$row_bytes_out"
		done
	done
}

pam_to_png() {
	local scaling=$1

	# Scale height
	# Ratio width to height 1:2
	if [[ "$scaling" -eq 1 ]]; then
		perl -e '
			use Compress::Zlib;

			my $scale_x = 10;
			my $scale_y = 20;

			#PAM Header
			my ($w, $h, $depth);
			while (<STDIN>) {
				last if /^ENDHDR/;
				$w = $1 if /^WIDTH\s+(\d+)/;
				$h = $1 if /^HEIGHT\s+(\d+)/;
				$depth = $1 if /^DEPTH\s+(\d+)/;
			}

			#Read pixel bytes
			read(STDIN, my $raw, $w * $h * $depth);

			my $scanlines = "";

			my $out_w = $w * $scale_x;
			my $out_h = $h * $scale_y;

			for my $y (0 .. $h - 1) {
				my $scaled_row = "";

				#Scale horz
				for my $x (0 .. $w - 1) {
					my $offset = ($y * $w + $x) * $depth;
					my $pixel = substr($raw, $offset, $depth);
					$scaled_row .= ($pixel x $scale_x);
				}

				#Scale vert
				for (1 .. $scale_y) {
					$scanlines .= "\x00" . $scaled_row;
				}
			}

			my $idat = compress($scanlines);
			sub crc { return pack("N", Compress::Zlib::crc32($_[0])); }

			print "\x89PNG\r\n\x1a\n";
			my $ihdr = pack("NNCCCCC", $out_w, $out_h, 8, ($depth == 4 ? 6 : 2), 0, 0, 0);
			print pack("N", length($ihdr)) . "IHDR" . $ihdr . crc("IHDR" . $ihdr);
			print pack("N", length($idat)) . "IDAT" . $idat . crc("IDAT" . $idat);
			print pack("N", 0) . "IEND" . crc("IEND");
		'
	# Ratio width to height 1:1
	elif [[ "$scaling" -eq 2 ]]; then
		perl -e '
			use Compress::Zlib;

			my $scale_x = 20;
			my $scale_y = 20;

			#PAM Header
			my ($w, $h, $depth);
			while (<STDIN>) {
				last if /^ENDHDR/;
				$w = $1 if /^WIDTH\s+(\d+)/;
				$h = $1 if /^HEIGHT\s+(\d+)/;
				$depth = $1 if /^DEPTH\s+(\d+)/;
			}

			#Read pixel bytes
			read(STDIN, my $raw, $w * $h * $depth);

			my $scanlines = "";

			my $out_w = $w * $scale_x;
			my $out_h = $h * $scale_y;

			for my $y (0 .. $h - 1) {
				my $scaled_row = "";

				#Scale horz
				for my $x (0 .. $w - 1) {
					my $offset = ($y * $w + $x) * $depth;
					my $pixel = substr($raw, $offset, $depth);
					$scaled_row .= ($pixel x $scale_x);
				}

				#Scale vert
				for (1 .. $scale_y) {
					$scanlines .= "\x00" . $scaled_row;
				}
			}

			my $idat = compress($scanlines);
			sub crc { return pack("N", Compress::Zlib::crc32($_[0])); }

			print "\x89PNG\r\n\x1a\n";
			my $ihdr = pack("NNCCCCC", $out_w, $out_h, 8, ($depth == 4 ? 6 : 2), 0, 0, 0);
			print pack("N", length($ihdr)) . "IHDR" . $ihdr . crc("IHDR" . $ihdr);
			print pack("N", length($idat)) . "IDAT" . $idat . crc("IDAT" . $idat);
			print pack("N", 0) . "IEND" . crc("IEND");
		'
	fi
}

pam_generator() {
	# PAM Header
	printf "P7\nWIDTH %d\nHEIGHT %d\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n" "$PAINT_COL" "$PAINT_ROW"

	# Pixel Data Loop
	for ((r = 1; r <= PAINT_ROW; r++)); do
		for ((c = 1; c <= PAINT_COL; c++)); do
			printf "%b" "$(ansi_to_rgba_bytes "${PAINT_ITEMS["$r:$c"]}")"
		done
	done
}

saving_info() {
	local row=1
	local col=0

	col=$((TERM_COLS / 2 - 6))
	if [[ "$IS_SAVE" -eq 1 ]]; then
		printf '\e[%d;%dH\e[43;30m[  Saving  ]\e[0m' "$row" "$col" >"$TTY_DEV"
	else
		printf '\e[%d;%dH\e[42;30m[  Saved!  ]\e[0m' "$row" "$col" >"$TTY_DEV"
		sleep 1
		top_title
		# Clear mouse buffers
		while read -t 0.001 -n 10000 _; do :; done
	fi
}

save_file() {
	IS_SAVE=1
	saving_info
	use_mouse 0

	local path=$1
	local type=$2

	local color_type="gnome" # Default
	case "$COLOR_PALETTE_TYPE" in
		1)	color_type="gnome"		;;
		2)	color_type="alacritty"	;;
		3)	color_type="konsole"	;;
		4)	color_type="wezterm"	;;
		5)	color_type="xfce4"		;;
		6)	color_type="kitty"		;;
		7)	color_type="iterm2"		;;
		8)	color_type="nord"		;;
		9)	color_type="xterm"		;;
	esac

	case "$type" in
		bytes) # Save as .bin
			{
				printf 'TUI_STATE_V1\0%s\0%s\0%s\0' "$PAINT_ROW" "$PAINT_COL" "$COLOR_PALETTE_TYPE"

				for key in "${!PAINT_ITEMS[@]}"; do
					printf '%s\0%s\0' "$key" "${PAINT_ITEMS[$key]}"
				done
			} > "${path}.bin"
			EDIT=0
			;;
		pam) # Save as .pam
			pam_generator > "${path}-${color_type}.pam"
			;;
		bmp) # Save as .bmp
			pam_generator | pam_to_bmp 20 20 > "${path}-${color_type}-1by1.bmp"
			;;
		bmp1) # Save as .bmp half-width
			pam_generator | pam_to_bmp 10 20 > "${path}-${color_type}-1by2.bmp"
			;;
		png) # Save as .png
			if [[ "$PERL_SUPPORT" -eq 1 ]]; then
				pam_generator | pam_to_png 2 > "${path}-${color_type}-1by1.png"
			else
				col=$((TERM_COLS / 2 - 8))
				printf '\e[%d;%dH\e[41;37m[ Unsupported! ]\e[0m' 1 "$col" >"$TTY_DEV"
				sleep 1
				top_title
				# Clear mouse buffers
				while read -t 0.001 -n 10000 _; do :; done
				use_mouse 1
				return
			fi
			;;
		png1) # Save as .png half-width
			if [[ "$PERL_SUPPORT" -eq 1 ]]; then
				pam_generator | pam_to_png 1 > "${path}-${color_type}-1by2.png"
			else
				col=$((TERM_COLS / 2 - 8))
				printf '\e[%d;%dH\e[41;37m[ Unsupported! ]\e[0m' 1 "$col" >"$TTY_DEV"
				sleep 1
				top_title
				# Clear mouse buffers
				while read -t 0.001 -n 10000 _; do :; done
				use_mouse 1
				return
			fi
			;;
	esac

	IS_SAVE=0
	saving_info
	use_mouse 1
}

load_file() {
	local path=$1
	local magic row col palette key val

	if [[ ! -f "$path" || ! -r "$path" ]]; then
		printf 'Error: State file "%s" is unreadable or missing.\n' "$path" >&2
		return 1
	fi

	exec 3< "$path"

	# Read Metadata Header
	IFS= read -r -d '' magic <&3 || { exec 3<&-; return 1; }
	IFS= read -r -d '' row <&3
	IFS= read -r -d '' col <&3
	IFS= read -r -d '' palette <&3

	# Check Metadata
	if [[ "$magic" != "TUI_STATE_V1" ]]; then
		printf 'Error: Invalid file format (Magic: "%s").\n' "$magic" >&2
		exec 3<&-
		return 1
	fi

	PAINT_ROW="$row"
	PAINT_COL="$col"
	COLOR_PALETTE_TYPE="$palette"

	while IFS= read -r -d '' key <&3 && IFS= read -r -d '' val <&3; do
		PAINT_ITEMS["$key"]="$val"
	done

	exec 3<&-
}

update_dimensions() {
    TERM_LINES="$(tput lines 2>/dev/null || echo 24)"
    TERM_COLS="$(tput cols 2>/dev/null || echo 80)"

    PAINT_ROW_SHIFT=0
    PAINT_COL_SHIFT=0

    # Canvas size
    CANVAS_MAX_LINES=$((TERM_LINES - 2))
    CANVAS_MAX_COLS=$((TERM_COLS - 4))
}

calc_border() {
	local calc_row=$(( ( PAINT_ROW / 2 ) - (( TERM_LINES - 3 ) / 2) ))
	local calc_col=$(( ( PAINT_COL / 2 ) - (( TERM_COLS - 4 ) / 2) ))

	abs_diff_row=$(( calc_row < 0 ? -calc_row : calc_row ))
	abs_diff_col=$(( calc_col < 0 ? -calc_col : calc_col ))

	if [[ "$((CANVAS_MAX_LINES - 3))" -ge "$PAINT_ROW" ]]; then
		PAINT_ANCHOR_ROW=$((abs_diff_row + 1))
	else
		PAINT_ANCHOR_ROW=2
	fi
	if [[ "$((CANVAS_MAX_COLS - 2))" -ge "$PAINT_COL" ]]; then
		PAINT_ANCHOR_COL=$((abs_diff_col + 1))
	else
		PAINT_ANCHOR_COL=2
	fi

	# Border Left
	PAINT_OUTLINE_LEFT=$((PAINT_ANCHOR_COL - 1 + PAINT_COL_SHIFT))
	# Border Right
	PAINT_OUTLINE_RIGHT=$((PAINT_ANCHOR_COL + PAINT_COL + PAINT_COL_SHIFT))

	# Border Top
	PAINT_OUTLINE_TOP=$((1 + PAINT_ANCHOR_ROW - 1 + PAINT_ROW_SHIFT))
	# Border Bottom
	PAINT_OUTLINE_BOTTOM=$((PAINT_ANCHOR_ROW + PAINT_ROW + 1 + PAINT_ROW_SHIFT))
}

save_colors() {
	local row=$1
	local col=$2
	local text=$3

	printf -v bin_val '%b' "$text"
	PAINT_ITEMS["$row:$col"]="$bin_val"
}

init_bg() {
	local text
	case "$PAINT_BG" in
        0)  text="\e[0m " ;;
        1)  text="\e[40m \e[0m" ;;
        2)  text="\e[47m \e[0m" ;;
        3)  text="\e[41m \e[0m" ;;
        4)  text="\e[42m \e[0m" ;;
        5)  text="\e[43m \e[0m" ;;
        6)  text="\e[44m \e[0m" ;;
        7)  text="\e[45m \e[0m" ;;
		8)  text="\e[46m \e[0m" ;;
        *)
            PAINT_BG=2
            text="\e[47m \e[0m"
            ;;
    esac
	for (( r=1; r<=PAINT_ROW; r++ )); do
		for (( c=1; c<=PAINT_COL; c++  )); do
			save_colors "$r" "$c" "$text"
		done
	done
}

rgb_converter() {
	local raw_str="$1"
	local row="$2"
	local col="$3"
	local bg=0 fg=0
	# Extract color sequence
	local color_seq="${raw_str#*$'\e['}"
	color_seq="${color_seq%%m*}"

	# Extract background, foreground and char
	IFS=';' read -r -a codes <<< "$color_seq"
	for c in "${codes[@]}"; do
		if [[ "$c" =~ ^[0-9]+$ ]]; then
			if [[ "$c" -ge 30 && "$c" -le 37 ]]; then
				fg="$c"
			elif [[ "$c" -ge 40 && "$c" -le 47 ]]; then
				bg="$c"
			fi
		fi
	done
	local char="${raw_str#*m}"
	char="${char%%$'\e'*}"

	# Parse background to follow color palette
	local new_raw=""
	local bg_r=0 bg_g=0 bg_b=0
	local fg_r=0 fg_g=0 fg_b=0
	if [[ "$bg" -ne 0 ]]; then
		IFS=' ' read -r -a bg_items <<< "${PALETTE_SELECT[$bg]}"
		bg_r="${bg_items[0]}"
		bg_g="${bg_items[1]}"
		bg_b="${bg_items[2]}"
		new_raw+="\e[48;2;${bg_r};${bg_g};${bg_b}m"
	else
		new_raw+="\e[0m"
	fi
	# Parse foreground to follow color palette
	if [[ "$fg" -ne 0 ]]; then
		IFS=' ' read -r -a fg_items <<< "${PALETTE_SELECT[$fg]}"
		fg_r="${fg_items[0]}"
		fg_g="${fg_items[1]}"
		fg_b="${fg_items[2]}"
		new_raw+="\e[38;2;${fg_r};${fg_g};${fg_b}m"
	fi

	printf '\e[%d;%dH%b' "$row" "$col" \
		"${new_raw}${char}\e[0m" >"$TTY_DEV"
}

# Start UI
# Top Title
top_title() {
	IS_DRAW=1
	use_mouse 0

	rt="(P)alette $COLOR_PALETTE_TYPE (Q)uit "
	if [[ "$EDIT" -eq 1 ]]; then
		cap=$((TERM_COLS - ${#rt} - 4))
		lt=" ${NAME:0:$cap} * "
	else
		cap=$((TERM_COLS - ${#rt} - 2))
		lt=" ${NAME:0:$cap} "
	fi
	lrw=$((TERM_COLS - ${#lt}))
	printf '\e[1;1H\e[7m%b%*b\e[0m' "$lt" "$lrw" "$rt" >"$TTY_DEV"
	# Clear mouse buffers
    while read -t 0.001 -n 10000 _; do :; done
    IS_DRAW=0
    use_mouse 1
}
# Side Color Picker
side_color() {
	IS_DRAW=1
	use_mouse 0

	local pos=$((TERM_COLS - 2))
	# Truecolor or fallback mode
	if [[ "$TRUECOLOR" -eq 1 ]]; then
		printf '\e[2;%dH\e[48;2;%smBLK\e[0m' "$pos" "${PALETTE_SELECT["40"]// /;}" >"$TTY_DEV"
		printf '\e[3;%dH\e[48;2;%sm\e[30mWHI\e[0m' "$pos" "${PALETTE_SELECT["47"]// /;}" >"$TTY_DEV"
		printf '\e[4;%dH\e[48;2;%smRED\e[0m' "$pos" "${PALETTE_SELECT["41"]// /;}" >"$TTY_DEV"
		printf '\e[5;%dH\e[48;2;%smGRE\e[0m' "$pos" "${PALETTE_SELECT["42"]// /;}" >"$TTY_DEV"
		printf '\e[6;%dH\e[48;2;%smYEL\e[0m' "$pos" "${PALETTE_SELECT["43"]// /;}" >"$TTY_DEV"
		printf '\e[7;%dH\e[48;2;%smBLU\e[0m' "$pos" "${PALETTE_SELECT["44"]// /;}" >"$TTY_DEV"
		printf '\e[8;%dH\e[48;2;%smMAG\e[0m' "$pos" "${PALETTE_SELECT["45"]// /;}" >"$TTY_DEV"
		printf '\e[9;%dH\e[48;2;%smCYA\e[0m' "$pos" "${PALETTE_SELECT["46"]// /;}" >"$TTY_DEV"
		printf '\e[10;%dH\e[7mTRA\e[0m' "$pos" >"$TTY_DEV"
	else
		printf '\e[2;%dH\e[40mBLK\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[3;%dH\e[47;30mWHI\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[4;%dH\e[41mRED\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[5;%dH\e[42mGRE\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[6;%dH\e[43mYEL\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[7;%dH\e[44mBLU\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[8;%dH\e[45mMAG\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[9;%dH\e[46mCYA\e[0m' "$pos" >"$TTY_DEV"
		printf '\e[10;%dH\e[7mTRA\e[0m' "$pos" >"$TTY_DEV"
	fi
	# Clear Old Color Pointer
	printf '\e[10;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[2;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[3;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[4;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[5;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[6;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[7;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[8;%dH ' "$((pos - 1))" >"$TTY_DEV"
	printf '\e[9;%dH ' "$((pos - 1))" >"$TTY_DEV"

	case "$PAINT_COLOR" in
		0)  printf '\e[10;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		1)  printf '\e[2;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		2)  printf '\e[3;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		3)  printf '\e[4;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		4)  printf '\e[5;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		5)  printf '\e[6;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		6)  printf '\e[7;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		7)  printf '\e[8;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
		8)  printf '\e[9;%dH#\e[0m' "$((pos - 1))" >"$TTY_DEV";;
	esac
	temp_char=" "
	case "$PAINT_BG" in
		0)
			if [[ "$PAINT_COLOR" -eq 0 ]]; then
				temp_char="#"
			fi
			printf '\e[10;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		1)
			if [[ "$PAINT_COLOR" -eq 1 ]]; then
				temp_char="#"
			fi
			printf '\e[2;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		2)
			if [[ "$PAINT_COLOR" -eq 2 ]]; then
				temp_char="#"
			fi
			printf '\e[3;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		3)
			if [[ "$PAINT_COLOR" -eq 3 ]]; then
				temp_char="#"
			fi
			printf '\e[4;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		4)
			if [[ "$PAINT_COLOR" -eq 4 ]]; then
				temp_char="#"
			fi
			printf '\e[5;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		5)
			if [[ "$PAINT_COLOR" -eq 5 ]]; then
				temp_char="#"
			fi
			printf '\e[6;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		6)
			if [[ "$PAINT_COLOR" -eq 6 ]]; then
				temp_char="#"
			fi
			printf '\e[7;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		7)
			if [[ "$PAINT_COLOR" -eq 7 ]]; then
				temp_char="#"
			fi
			printf '\e[8;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
		8)
			if [[ "$PAINT_COLOR" -eq 8 ]]; then
				temp_char="#"
			fi
			printf '\e[9;%dH\e[41m%b\e[0m' "$((pos - 1))" "$temp_char" >"$TTY_DEV"
			;;
	esac
	# Clear mouse buffers
    while read -t 0.001 -n 10000 _; do :; done
    IS_DRAW=0
    use_mouse 1
}
# Bottom Bar
bottom_bar() {
	IS_DRAW=1
	use_mouse 0

	brsc=19
	op1=" "
	op2=" "
	op3=" "
	op4=" "
	op5=" "
	case "$PAINT_SHADE" in
		1)
		op1="["
		op2="]"
		;;
		2)
		op2="["
		op3="]"
		;;
		3)
		op3="["
		op4="]"
		;;
		4)
		op4="["
		op5="]"
		;;
		*)
		op4="["
		op5="]"
		;;
	esac
	brs="$op1\u2591\u2591$op2\u2592\u2592$op3\u2593\u2593$op4\u2588\u2588$op5 Shade "
	printf '\e[%d;%dH%b' "$((TERM_LINES - 1))" "$((TERM_COLS - brsc))" "$brs"
	printf '\e[%d;1H\e[7m%-*s\e[0m' "$TERM_LINES" "$TERM_COLS" " Size: ${PAINT_COL}x${PAINT_ROW} Pos: 0 0 " >"$TTY_DEV"
	#Show memory
	printf '\e[%d;2H%b' "$((CANVAS_MAX_LINES + 1))" "$MEM_USAGE_STR" >"$TTY_DEV"

	# Clear mouse buffers
    while read -t 0.001 -n 10000 _; do :; done
    IS_DRAW=0
    use_mouse 1
}
# Draw Paint
draw_paint() {
	IS_DRAW=1
	use_mouse 0
	calc_border
	local min_row=2
	local max_row=$((TERM_LINES - 2))
	local min_col=1
	local max_col=$((TERM_COLS - 4))

	# Draw canvas outline
	for (( i=min_row; i<=max_row; i++ )); do
		for (( j=min_col; j<=max_col; j++ )); do
			# Draw Top
			if [[ "$i" -eq "$PAINT_OUTLINE_TOP" ]]; then
				# Top corner left
				if [[ "$PAINT_OUTLINE_LEFT" -ne 0 && "$PAINT_OUTLINE_TOP" -ne 0 ]]; then
					if [[ "$PAINT_OUTLINE_LEFT" -eq "$j" && "$PAINT_OUTLINE_TOP" -eq "$i" ]]; then
						printf '\e[%d;%dH+' "$i" "$j" >"$TTY_DEV"
						continue
					fi
				fi
				# Top corner right
				if [[ "$PAINT_OUTLINE_RIGHT" -eq "$j" && "$PAINT_OUTLINE_TOP" -eq "$i" ]]; then
					printf '\e[%d;%dH+' "$i" "$j" >"$TTY_DEV"
					continue
				fi
				# Top Lines
				if [[ "$j" -gt "$PAINT_OUTLINE_LEFT" && "$j" -lt "$PAINT_OUTLINE_RIGHT" ]]; then
					printf '\e[%d;%dH-' "$i" "$j" >"$TTY_DEV"
					continue
				fi
			fi
			# Draw Bottom
			if [[ "$i" -eq "$PAINT_OUTLINE_BOTTOM" ]]; then
				# Bottom corner left
				if [[ "$PAINT_OUTLINE_LEFT" -ne 0 ]]; then
					if [[ "$PAINT_OUTLINE_LEFT" -eq "$j" && "$PAINT_OUTLINE_BOTTOM" -eq "$i" ]]; then
						printf '\e[%d;%dH+' "$i" "$j" >"$TTY_DEV"
						continue
					fi
				fi
				# Bottom corner right
				if [[ "$PAINT_OUTLINE_RIGHT" -eq "$j" && "$PAINT_OUTLINE_BOTTOM" -eq "$i" ]]; then
					printf '\e[%d;%dH+' "$i" "$j" >"$TTY_DEV"
					continue
				fi
				# Bottom Lines
				if [[ "$j" -gt "$PAINT_OUTLINE_LEFT" && "$j" -lt "$PAINT_OUTLINE_RIGHT" ]]; then
					printf '\e[%d;%dH-' "$i" "$j" >"$TTY_DEV"
					continue
				fi
			fi
			# Draw Sides
			if [[ "$i" -gt "$PAINT_OUTLINE_TOP" && "$i" -lt "$PAINT_OUTLINE_BOTTOM" ]]; then
				if [[ "$j" -eq "$PAINT_OUTLINE_LEFT" || "$j" -eq "$PAINT_OUTLINE_RIGHT" ]]; then
					printf '\e[%d;%dH|' "$i" "$j" >"$TTY_DEV"
					continue
				fi
			fi
		done
    done

	# Draw paint
	for pos in "${!PAINT_ITEMS[@]}"; do
		pos_r=$(( ${pos%%:*} + PAINT_OUTLINE_TOP ))
		pos_c=$(( ${pos#*:} + PAINT_OUTLINE_LEFT ))
		# Check if within canvas
		if [[ "$pos_r" -le "$CANVAS_MAX_LINES" && "$pos_r" -ge 2 ]]; then
			if [[ "$pos_c" -le "$CANVAS_MAX_COLS" && "$pos_c" -ge 1 ]]; then
				rgb_converter "${PAINT_ITEMS[$pos]}" "$pos_r" "$pos_c"
			fi
		fi
	done
	# Clear mouse buffers
    while read -t 0.001 -n 10000 _; do :; done
    IS_DRAW=0
    use_mouse 1
}
# End UI

draw_ui() {
	IS_DRAW=1
	use_mouse 0
	# Clear Screen
    printf '\e[2J' >"$TTY_DEV"
    # Clear mouse buffers
    while read -t 0.001 -n 10000 _; do :; done
    IS_DRAW=0
    use_mouse 1

    if [[ TERM_LINES -ge 13 && TERM_COLS -ge 34 ]]; then
		# Top
		top_title

		# Side
		side_color

		# Bottom
		bottom_bar
    else
		MSG="Please resize to 34 by 13."
		save_file "./$NAME" "bytes" # Save unsave by force
		exit 1
    fi

    # Draw Actual Paint
    draw_paint
}

handle_resize() {
    RESIZE=1
}

use_mouse() {
    local val=$1
    if [[ "$val" -eq 1 ]]; then
	printf '\e[?1003h\e[?1006h' >"$TTY_DEV"
    elif [[ "$val" -eq 0 ]]; then
	printf '\e[?1003l\e[?1006l' >"$TTY_DEV"
    fi
}

init_terminal() {
	if [[ -n "$FILE_PATH" ]]; then
		load_file $FILE_PATH
		temp_name="${FILE_PATH##*/}"
		NAME="${temp_name%%.*}"
	fi

	if command -v perl >/dev/null 2>&1; then
		PERL_SUPPORT=1
	fi

    trap cleanup EXIT
	trap handle_signal INT TERM
    trap handle_resize WINCH

    printf '\e[?1049h\e[?25l\e[?1003h\e[?1006h' >"$TTY_DEV"

    stty -echo -icanon -ixon min 0 time 0 <"$TTY_DEV" 2>/dev/null

    update_dimensions

    if [[ -z "$FILE_PATH" ]]; then
		init_bg
    fi

    update_palette
    draw_ui
}

draw_cursor() {
    local col=$1
    local row=$2

    #Skip if outside canvas area
    if [[ "$row" -eq 1 ]]; then
        return
    fi
    if [[ "$row" -ge "$((TERM_LINES - 1))" ]]; then
		return
    fi
    if [[ "$row" -le "$PAINT_OUTLINE_TOP" || "$row" -ge "$PAINT_OUTLINE_BOTTOM" ]]; then
		return
    fi
    if [[ "$col" -ge "$((TERM_COLS - 3))" ]]; then
		return
    fi
    if [[ "$col" -le "$PAINT_OUTLINE_LEFT" || "$col" -ge "$PAINT_OUTLINE_RIGHT" ]]; then
		return
    fi

    #Delete old
    if [[ "$CURSOR_ROW" -gt 0 ]]; then
	printf '\e[%d;%dH ' "$CURSOR_ROW" "$CURSOR_COL" >"$TTY_DEV"
    fi

    #Select color
    local color=""
    case "$PAINT_COLOR" in
		0)  color="\e[0m" ;;
		1)  color="\e[40m" ;;
		2)  color="\e[47;30m" ;;
		3)  color="\e[41m" ;;
        4)  color="\e[42m" ;;
		5)  color="\e[43m" ;;
		6)  color="\e[44m" ;;
		7)  color="\e[45m" ;;
		8)  color="\e[46m" ;;
		*)
			PAINT_COLOR=1
			color="\e[40m"
            ;;
    esac
    #Select type
    local char=""
    if [[ "$PAINT_COLOR" -eq 9 ]]; then
	char="\u2591"
    else
	char="${color}0"
    fi

    if [[ "$DRAG" -eq 0 ]]; then
		#Draw old
		temp="$((CURSOR_ROW - PAINT_OUTLINE_TOP)):$((CURSOR_COL - PAINT_OUTLINE_LEFT))"
		if [[ -v PAINT_ITEMS["$temp"] ]]; then
			rgb_converter "${PAINT_ITEMS[$temp]}" "$CURSOR_ROW" "$CURSOR_COL"
		fi

		#Draw new
		printf '\e[%d;%dH%b\e[0m' "$row" "$col" "$char" >"$TTY_DEV"
    fi

    CURSOR_ROW=$row
    CURSOR_COL=$col
}

paint_pixel() {
    local col=$1
    local row=$2
    local char=""

    # Skip paint UI areas
    #Skip if no move or outside canvas area
    if [[ "$row" -eq 1 ]]; then
		return
    fi
    if [[ "$row" -ge "$((TERM_LINES - 1))" ]]; then
        return
    fi
	if [[ "$row" -le "$PAINT_OUTLINE_TOP" || "$row" -ge "$PAINT_OUTLINE_BOTTOM" ]]; then
		return
    fi
    if [[ "$col" -ge "$((TERM_COLS - 3))" ]]; then
        return
    fi
    if [[ "$col" -le "$PAINT_OUTLINE_LEFT" || "$col" -ge "$PAINT_OUTLINE_RIGHT" ]]; then
		return
    fi

    EDIT=1
	top_title

    #Set bacground
    case "$PAINT_BG" in
        0)  char="\e[0" ;;
        1)  char="\e[40" ;;
        2)  char="\e[47" ;;
        3)  char="\e[41" ;;
        4)  char="\e[42" ;;
        5)  char="\e[43" ;;
        6)  char="\e[44" ;;
        7)  char="\e[45" ;;
		8)  char="\e[46" ;;
        *)
            PAINT_BG=2
            char="\e[47"
            ;;
    esac
    #Select color
    case "$PAINT_COLOR" in
		0)  char+="m"    ;;
        1)  char+=";30m" ;;
        2)  char+=";37m" ;;
        3)  char+=";31m" ;;
        4)  char+=";32m" ;;
        5)  char+=";33m" ;;
        6)  char+=";34m" ;;
        7)  char+=";35m" ;;
        8)  char+=";36m" ;;
        *)
            PAINT_COLOR=1
            char+=";30m"
            ;;
    esac

    #Select Shade
    if [[ "$PAINT_COLOR" -eq 0 ]]; then
		char+=" "
    else
		case "$PAINT_SHADE" in
			1)  char+="\u2591" ;;
			2)  char+="\u2592" ;;
			3)  char+="\u2593" ;;
			4)  char+="\u2588" ;;
			*)
			PAINT_SHADE=4
			char+="\u2591"
			;;
		esac
    fi

    char+="\e[0m"

    save_colors "$(( row - PAINT_OUTLINE_TOP ))" "$(( col - PAINT_OUTLINE_LEFT ))" "$char"
    rgb_converter "$(printf '%b' "$char")" "$row" "$col"

    CURSOR_ROW=$row
    CURSOR_COL=$col
}

scroll_handler() {
	local type=$1
	case "$type" in
		up)
			if [[ "$PAINT_OUTLINE_TOP" -lt 2 ]]; then
				CURSOR_ROW=0
				CURSOR_COL=0
				if [[ "$PAINT_ROW_SHIFT" -eq -1 ]]; then
					PAINT_ROW_SHIFT=0
					draw_paint
				else
					(( PAINT_ROW_SHIFT += 1 ))
					draw_paint
				fi
			fi
			;;
		down)
			if [[ "$PAINT_OUTLINE_BOTTOM" -gt "$CANVAS_MAX_LINES" ]]; then
				CURSOR_ROW=0
				CURSOR_COL=0
				if [[ "$PAINT_ROW_SHIFT" -eq 1 ]]; then
					PAINT_ROW_SHIFT=0
					draw_paint
				else
					(( PAINT_ROW_SHIFT -= 1 ))
					draw_paint
				fi
			fi
			;;
		left)
			if [[ "$PAINT_OUTLINE_LEFT" -lt 1 ]]; then
				CURSOR_ROW=0
				CURSOR_COL=0
				if [[ "$PAINT_COL_SHIFT" -eq -1 ]]; then
					PAINT_COL_SHIFT=0
					draw_paint
				else
					(( PAINT_COL_SHIFT += 1 ))
					draw_paint
				fi
			fi
			;;
		right)
			if [[ "$PAINT_OUTLINE_RIGHT" -gt "$CANVAS_MAX_COLS" ]]; then
				CURSOR_ROW=0
				CURSOR_COL=0
				if [[ "$PAINT_COL_SHIFT" -eq 1 ]]; then
					PAINT_COL_SHIFT=0
					draw_paint
				else
					(( PAINT_COL_SHIFT -= 1 ))
					draw_paint
				fi
			fi
			;;
	esac
}

click_handler() {
    local button=$1
    local col=$2
    local row=$3
    local state=$4

    if [[ "$state" = "m" ]]; then
		DRAG=0
		draw_cursor "$col" "$row"
		return
    fi

	#Wait draw finish
    if [[ "$IS_DRAW" -eq 1 ]]; then
		return
    fi

    #Wait save finish
	if [[ "$IS_SAVE" -eq 1 ]]; then
		return
	fi

    case "$button" in
		0) #Left Click
			# Select Color
			if [[ "$col" -ge "$TERM_COLS - 2" ]]; then
				case "$row" in
					2)
						PAINT_COLOR=1
						side_color
					;;
					3)
						PAINT_COLOR=2
						side_color
					;;
							4)
						PAINT_COLOR=3
						side_color
					;;
							5)
						PAINT_COLOR=4
						side_color
					;;
							6)
						PAINT_COLOR=5
						side_color
					;;
							7)
						PAINT_COLOR=6
						side_color
					;;
							8)
						PAINT_COLOR=7
						side_color
					;;
							9)
						PAINT_COLOR=8
						side_color
					;;
							10)
						PAINT_COLOR=0
						side_color
					;;
				esac
			elif [[ "$row" -eq "$((TERM_LINES - 1))" ]]; then
				# Select Shade
				brsc=19
				if [[ "$col" -eq "$((TERM_COLS - brsc + 1))" || "$col" -eq "$((TERM_COLS - brsc + 2))" ]]; then
					PAINT_SHADE=1
					bottom_bar
				elif [[ "$col" -eq "$((TERM_COLS - brsc + 4))" || "$col" -eq "$((TERM_COLS - brsc + 5))" ]]; then
					PAINT_SHADE=2
					bottom_bar
				elif [[ "$col" -eq "$((TERM_COLS - brsc + 7))" || "$col" -eq "$((TERM_COLS - brsc + 8))" ]]; then
					PAINT_SHADE=3
					bottom_bar
				elif [[ "$col" -eq "$((TERM_COLS - brsc + 10))" || "$col" -eq "$((TERM_COLS - brsc + 11))" ]]; then
					PAINT_SHADE=4
					bottom_bar
				fi
			else
				DRAG=1
				paint_pixel "$col" "$row"
			fi
			;;
		32) #Left Drag
			DRAG=1
			paint_pixel "$col" "$row"
			;;
		1) #Middle Click
			;;
		2) #Right Click
			if [[ "$col" -ge "$TERM_COLS - 2" ]]; then
				case "$row" in
					2)
						PAINT_BG=1
						side_color
					;;
					3)
						PAINT_BG=2
						side_color
					;;
					4)
						PAINT_BG=3
						side_color
					;;
					5)
						PAINT_BG=4
						side_color
					;;
					6)
						PAINT_BG=5
						side_color
					;;
					7)
						PAINT_BG=6
						side_color
					;;
					8)
						PAINT_BG=7
						side_color
					;;
					9)
						PAINT_BG=8
						side_color
					;;
					10)
						PAINT_BG=0
						side_color
					;;
				esac
			fi
			;;
		35) #Motion
			DRAG=0
			draw_cursor "$col" "$row"
			;;
		64|k_up) #Scroll Up
			scroll_handler "up"
			;;
		65|k_down) #Scroll Down
			scroll_handler "down"
			;;
		66|68|72|k_left) #Scroll Left
			scroll_handler "left"
			;;
		67|69|73|k_right) #Scroll Right
			scroll_handler "right"
			;;
    esac

    #Update cursor position
    printf '\e[%d;1H\e[7m%-*s\e[0m' "$TERM_LINES" "$TERM_COLS" " Size: ${PAINT_COL}x${PAINT_ROW} Pos: $((CURSOR_COL - PAINT_OUTLINE_LEFT)) $((CURSOR_ROW - PAINT_OUTLINE_TOP)) " >"$TTY_DEV"
}

get_mem_usage() {
	local total_pages rss_pages page_size_kb=4
	local rss_kb mb_whole mb_dec

	if read -r total_pages rss_pages _ < /proc/self/statm 2>/dev/null; then
		rss_kb=$(( rss_pages * page_size_kb ))

		if [[ "$rss_kb" -ge 1024 ]]; then
			mb_whole=$(( rss_kb / 1024 ))
			mb_dec=$(( ((rss_kb % 1024) * 10) / 1024 ))
			MEM_USAGE_STR="${mb_whole}.${mb_dec} MB"
		else
			MEM_USAGE_STR="$rss_kb KB"
		fi

	else
		MEM_USAGE_STR="0 KB"
	fi
}

save_parse() {
	local type="$1"
	# If no file, make new
	if [[ -z "$FILE_PATH" ]]; then
		save_file "./$NAME" "$type"
	else
		temp_path="${FILE_PATH%%.*}"
		save_file "$temp_path" "$type"
	fi
	top_title
}

main() {
    init_terminal

    local loop_ctr=0
    get_mem_usage
    printf '\e[%d;2H%b' "$((CANVAS_MAX_LINES + 1))" "$MEM_USAGE_STR" >"$TTY_DEV"

    #Event loop
    while true; do
		(( ++loop_ctr ))
		if [[ "$loop_ctr" -ge 200 ]]; then
			get_mem_usage
			printf '\e[%d;2H%b' "$((CANVAS_MAX_LINES + 1))" "$MEM_USAGE_STR" >"$TTY_DEV"
			loop_ctr=0
		fi
		#Resize
		if [[ "$RESIZE" -eq 1 ]]; then
			RESIZE=0
			update_dimensions
			draw_ui # Redraw entire UI
			CURSOR_ROW=0
			CURSOR_COL=0
		fi

		#Read stdin and quit with 'q', palette with 'p'
		byte=""
		IFS= LC_ALL=C read -r -t 0.01 -n 1 -d '' byte <"$TTY_DEV" || continue
		if [[ "$byte" = "q" || "$byte" = "Q" ]]; then
				if [[ "$EDIT" -eq 1 ]]; then
					use_mouse 0
					temp_col=$(( (TERM_COLS / 2) - 16 + 1 ))
					printf '\e[1;%dH\e[43;30m[Quit without saving? (Y)es (N)o]\e[0m' "$temp_col" # Popup Position
					is_exit=0
					while true; do
						read -r -s -n 1 key
						case "${key,,}" in
							y)
								MSG="Quitting without saving..."
								is_exit=1
								break
								;;
							n)
								break
								;;
							*)	;;
						esac
					done
					top_title

					if [[ "$is_exit" -eq 1 ]]; then break; fi
					use_mouse 1
				else
					break
				fi
		fi
		if [[ "$byte" == "p" || "$byte" == "P" ]]; then
			use_mouse 0
			temp_col=$(( (TERM_COLS / 2) - 11 + 1 ))
			input_buffer="**"
			while true; do
				printf '\e[1;%dH\e[43;30m[ Color Palette [%s] ]\e[0m' "$temp_col" "${input_buffer: -2}" # Popup
				read -r -s -n 1 key
				case "$key" in
					[0-9]) # Digits
						if [[ "${#input_buffer}" -lt 4 ]]; then
							input_buffer+="$key"
						fi
						;;
					$'\x7f'|$'\x08') # Backspace
						if [[ -n "$input_buffer" && "${#input_buffer}" -gt 2 ]]; then
							input_buffer="${input_buffer%?}"
						fi
						;;
					""|$'\r'|$'\n') # Enter key
						strip="${input_buffer##*[^0-9]}"
						num=$(( 10#${strip:-0} ))
						case "$num" in
							1)	COLOR_PALETTE_TYPE=1;	EDIT=1;	update_palette;	draw_ui;	break	;;
							2)	COLOR_PALETTE_TYPE=2;	EDIT=1;	update_palette;	draw_ui;	break	;;
							3)	COLOR_PALETTE_TYPE=3;	EDIT=1;	update_palette;	draw_ui;	break	;;
							4)	COLOR_PALETTE_TYPE=4;	EDIT=1;	update_palette;	draw_ui;	break	;;
							5)	COLOR_PALETTE_TYPE=5;	EDIT=1;	update_palette;	draw_ui;	break	;;
							6)	COLOR_PALETTE_TYPE=6;	EDIT=1;	update_palette;	draw_ui;	break	;;
							7)	COLOR_PALETTE_TYPE=7;	EDIT=1;	update_palette;	draw_ui;	break	;;
							8)	COLOR_PALETTE_TYPE=8;	EDIT=1;	update_palette;	draw_ui;	break	;;
							9)	COLOR_PALETTE_TYPE=9;	EDIT=1;	update_palette;	draw_ui;	break	;;
							*) # None
								printf '\e[1;%dH\e[41;30m[   Invalid Number   ]\e[0m' "$temp_col" # Popup
								sleep 1
								;;
						esac
						;;
					p|P) # Cancel
						break
						;;
					*)	;;
				esac
			done
			top_title
			use_mouse 1
		fi

		#Char escape
		if [[ "$byte" = $'\x1b' ]]; then
			seq=""

			while true; do
				IFS= LC_ALL=C read -r -t 0.01 -n 1 -d '' b <"$TTY_DEV" || break
				seq="${seq}${b}"

				# Break on Mouse
				if [[ "$seq" =~ ^\[\<([0-9]+)\;([0-9]+)\;([0-9]+)([mM])$ ]]; then
					break
				fi
				# Break on Keyboard
				if [[ "$seq" =~ ^\[[A-Za-z~]$ ]]; then
					break
				fi
			done

			# Parse SGR Mouse Sequence
			if [[ "$seq" =~ ^\[\<([0-9]+)\;([0-9]+)\;([0-9]+)([mM])$ ]]; then
				btn="${BASH_REMATCH[1]}"
				col="${BASH_REMATCH[2]}"
				row="${BASH_REMATCH[3]}"
				state="${BASH_REMATCH[4]}"

				click_handler "$btn" "$col" "$row" "$state"

			# Parse Keyboard Arrow Keys (\e[A, \e[B, \e[C, \e[D)
			elif [[ "$seq" =~ ^\[([ABCD])$ ]]; then
				dir="${BASH_REMATCH[1]}"

				case "$dir" in
					A)	click_handler "k_up" "$CURSOR_COL" "$CURSOR_ROW" "M" ;;    # Up Arrow
					B)	click_handler "k_down" "$CURSOR_COL" "$CURSOR_ROW" "M" ;;  # Down Arrow
					C)	click_handler "k_right" "$CURSOR_COL" "$CURSOR_ROW" "M" ;; # Right Arrow
					D)	click_handler "k_left" "$CURSOR_COL" "$CURSOR_ROW" "M" ;;  # Left Arrow
				esac
			fi
		# Ctrl + S (Save as bin)
		elif [[ "$byte" = $'\x13' ]]; then save_parse "bytes"
		# Ctrl + A (Save as PAM)
		elif [[ "$byte" = $'\x01' ]]; then save_parse "pam"
		# Ctrl + E (Save as BMP Half-width size)
		elif [[ "$byte" = $'\x05' ]]; then save_parse "bmp1"
		# Ctrl + R (Save as BMP Full-width size)
		elif [[ "$byte" = $'\x12' ]]; then save_parse "bmp"
		#Ctrl + D (Save as PNG Half-width size)
		elif [[ "$byte" = $'\x04' ]]; then save_parse "png1"
		#Ctrl + F (Save as PNG Full-width size)
		elif [[ "$byte" = $'\x06' ]]; then save_parse "png"
		fi
    done
}

main "$@"
