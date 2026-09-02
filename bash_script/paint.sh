#!/usr/bin/env bash

set -euo pipefail

HAS_W=0
HAS_H=0

MSG="Done."

PAINT_ROW=10
PAINT_COL=10
NAME="Untitled.bin"
PAINT_BG=2
EDIT=1
FILE_PATH=""

while getopts "w:l:t:b:f:h" opt; do
    case "$opt" in
        w)
			PAINT_COL="$OPTARG"
			HAS_W=1
			;;
        l)
			PAINT_ROW="$OPTARG"
			HAS_H=1
			;;
        t) NAME="$OPTARG" ;;
        b)
			if [[ "$OPTARG" -ge 0 && "$OPTARG" -le 8 ]]; then
				PAINT_BG="$OPTARG"
			fi
			;;
		f)
			if [[ ! -f "$OPTARG" || ! -r "$OPTARG" ]]; then
				printf 'Error: State file "%s" is unreadable or missing.\n' "$OPTARG" >&2
				exit 1
			fi

			exec 3< "$OPTARG"

			# Read Metadata Header
			IFS= read -r -d '' magic <&3 || { exec 3<&-; exit 1; }

			# Check metadata
			if [[ "$magic" != "TUI_STATE_V1" ]]; then
				printf 'Error: Invalid file format (Magic: "%s").\n' "$magic" >&2
				exec 3<&-
				exit 1
			fi

			FILE_PATH="$OPTARG"
			EDIT=0
			;;
		h)
			printf "# Usage: $0 [-w width -l length -t title -b background -h help]\n"
			printf "# Default backgound color (White)\n#   0 - Transparent\n#   1 - Black\n#   2 - White\n#   3 - Red\n#   4 - Green\n#   5 - Yellow\n#   6 - Blue\n#   7 - Magenta\n#   8 - Cyan\n"
			printf "# Key Input:\n#   Foreground - Left Click on color palette\n#   Background - Right Click on color palette\n#   Shade - Left Click on color shade\n"
			exit 0
			;;
        ?) echo "Usage: $0 [-w width -h height -t title -b background]"; exit 1 ;;
    esac
done

shift $(( OPTIND - 1 ))

if [[ "$HAS_W" -ne "$HAS_H" ]]; then
	echo "Error: Both -w and -h flags must be provided together." >&2
	exit 1
fi

TTY_DEV="$(tty 2>/dev/null || echo "/dev/tty")"

SAVED_STTY=""
if [[ -t 1 ]]; then
    SAVED_STTY="$(stty -g <"$TTY_DEV" 2>/dev/null || true)"
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
MEM_USAGE_STR="0 KB"

check_mouse_support() {
	if [[ -z "${TERM:-}" || "$TERM" == "dumb" ]]; then
		echo "Error: Dumb or uninitialized terminal environment ($TERM)." >&2
		return 1
	fi

	if [[ "$TERM" == "linux" ]] || [[ "$TTY_DEV" =~ ^/dev/tty[0-9]+$ ]]; then
		echo "Error: Unsupported Linux Virtual Console detected ($TTY_DEV)." >&2
		return 1
	fi

	if [[ ! -c "$TTY_DEV" ]]; then
		echo "Error: $TTY_DEV is not a valid character device." >&2
		return 1
	fi

	return 0
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

save_file() {
	local path=$1
	local type=$2

	case "$type" in
		bytes)
			{
				printf 'TUI_STATE_V1\0%s\0%s\0' "$PAINT_ROW" "$PAINT_COL"

				for key in "${!PAINT_ITEMS[@]}"; do
					printf '%s\0%s\0' "$key" "${PAINT_ITEMS[$key]}"
				done
			} > "$path"
			;;
		png)
			;;
	esac
}

load_file() {
	local path=$1
	local magic row col key val

	if [[ ! -f "$path" || ! -r "$path" ]]; then
		printf 'Error: State file "%s" is unreadable or missing.\n' "$path" >&2
		return 1
	fi

	exec 3< "$path"

	# Read Metadata Header
	IFS= read -r -d '' magic <&3 || { exec 3<&-; return 1; }
	IFS= read -r -d '' row <&3
	IFS= read -r -d '' col <&3

	# Check metadata
	if [[ "$magic" != "TUI_STATE_V1" ]]; then
		printf 'Error: Invalid file format (Magic: "%s").\n' "$magic" >&2
		exec 3<&-
		return 1
	fi

	PAINT_ROW="$row"
	PAINT_COL="$col"

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

	PAINT_ITEMS["$row:$col"]="$text"
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

top_title() {
	rt="(Q)uit "
	if [[ "$EDIT" -eq 1 ]]; then
		cap=$((TERM_COLS - ${#rt} - 4))
		lt=" ${NAME:0:$cap} * "
	else
		cap=$((TERM_COLS - ${#rt} - 2))
		lt=" ${NAME:0:$cap} "
	fi
	lrw=$((TERM_COLS - ${#lt}))
	printf '\e[1;1H\e[7m%b%*b\e[0m' "$lt" "$lrw" "$rt" >"$TTY_DEV"
}

draw_paint() {
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
		if [[ "$pos_r" -le "$CANVAS_MAX_LINES" && "$pos_r" -ge 2 ]]; then
			if [[ "$pos_c" -le "$CANVAS_MAX_COLS" && "$pos_c" -ge 1 ]]; then
				printf '\e[%d;%dH%b' "$pos_r" "$pos_c" "${PAINT_ITEMS[$pos]}" >"$TTY_DEV"
			fi
		fi
	done
}

draw_ui() {
	IS_DRAW=1
	# Clear Screen
    printf '\e[2J' >"$TTY_DEV"

    if [[ TERM_LINES -ge 13 && TERM_COLS -ge 34 ]]; then
		# Top
		top_title

		# Side
		sps=$((TERM_COLS - 2))
		printf '\e[2;%dH\e[40mBLK\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[3;%dH\e[30;47mWHI\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[4;%dH\e[41mRED\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[5;%dH\e[42mGRE\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[6;%dH\e[43mYEL\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[7;%dH\e[44mBLU\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[8;%dH\e[45mMAG\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[9;%dH\e[46mCYA\e[0m' "$sps" >"$TTY_DEV"
		printf '\e[10;%dH\e[7mERA\e[0m' "$sps" >"$TTY_DEV"

		case "$PAINT_COLOR" in
			0)  printf '\e[10;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			1)  printf '\e[2;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			2)  printf '\e[3;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			3)  printf '\e[4;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			4)  printf '\e[5;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			5)  printf '\e[6;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			6)  printf '\e[7;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			7)  printf '\e[8;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
			8)  printf '\e[9;%dH#\e[0m' "$((sps - 1))" >"$TTY_DEV";;
		esac
		temp_char=" "
		case "$PAINT_BG" in
			0)
				if [[ "$PAINT_COLOR" -eq 0 ]]; then
					temp_char="#"
				fi
				printf '\e[10;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			1)
				if [[ "$PAINT_COLOR" -eq 1 ]]; then
					temp_char="#"
				fi
				printf '\e[2;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			2)
				if [[ "$PAINT_COLOR" -eq 2 ]]; then
					temp_char="#"
				fi
				printf '\e[3;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			3)
				if [[ "$PAINT_COLOR" -eq 3 ]]; then
					temp_char="#"
				fi
				printf '\e[4;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			4)
				if [[ "$PAINT_COLOR" -eq 4 ]]; then
					temp_char="#"
				fi
				printf '\e[5;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			5)
				if [[ "$PAINT_COLOR" -eq 5 ]]; then
					temp_char="#"
				fi
				printf '\e[6;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			6)
				if [[ "$PAINT_COLOR" -eq 6 ]]; then
					temp_char="#"
				fi
				printf '\e[7;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			7)
				if [[ "$PAINT_COLOR" -eq 7 ]]; then
					temp_char="#"
				fi
				printf '\e[8;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
			8)
				if [[ "$PAINT_COLOR" -eq 8 ]]; then
					temp_char="#"
				fi
				printf '\e[9;%dH\e[41m%b\e[0m' "$((sps - 1))" "$temp_char" >"$TTY_DEV"
				;;
		esac

		# Bottom
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
    else
		MSG="Please resize to 34 by 13."
		exit 1
    fi

    calc_border
    draw_paint

    # Clear mouse buffers
    while read -t 0.001 -n 10000 _; do :; done
    IS_DRAW=0
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
	if ! check_mouse_support; then
		echo "Error: Unsupported terminal environment ($TTY_DEV)." >&2
		exit 1
	fi

	if [[ -n "$FILE_PATH" ]]; then
		load_file $FILE_PATH
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
			printf '\e[%d;%dH%b' "$CURSOR_ROW" "$CURSOR_COL" "${PAINT_ITEMS[$temp]}" >"$TTY_DEV"
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
		0)  char+=";0m" ;;
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
    printf '\e[%d;%dH%b' "$row" "$col" "$char" >"$TTY_DEV"

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
					draw_ui
				else
					(( PAINT_ROW_SHIFT += 1 ))
					draw_ui
				fi
			fi
			;;
		down)
			if [[ "$PAINT_OUTLINE_BOTTOM" -gt "$CANVAS_MAX_LINES" ]]; then
				CURSOR_ROW=0
				CURSOR_COL=0
				if [[ "$PAINT_ROW_SHIFT" -eq 1 ]]; then
					PAINT_ROW_SHIFT=0
					draw_ui
				else
					(( PAINT_ROW_SHIFT -= 1 ))
					draw_ui
				fi
			fi
			;;
		left)
			if [[ "$PAINT_OUTLINE_LEFT" -lt 1 ]]; then
				CURSOR_ROW=0
				CURSOR_COL=0
				if [[ "$PAINT_COL_SHIFT" -eq -1 ]]; then
					PAINT_COL_SHIFT=0
					draw_ui
				else
					(( PAINT_COL_SHIFT += 1 ))
					draw_ui
				fi
			fi
			;;
		right)
			if [[ "$PAINT_OUTLINE_RIGHT" -gt "$CANVAS_MAX_COLS" ]]; then
				CURSOR_ROW=0
				CURSOR_COL=0
				if [[ "$PAINT_COL_SHIFT" -eq 1 ]]; then
					PAINT_COL_SHIFT=0
					draw_ui
				else
					(( PAINT_COL_SHIFT -= 1 ))
					draw_ui
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

    case "$button" in
		0) #Left Click
			# Select Color
			if [[ "$col" -ge "$TERM_COLS - 2" ]]; then
				case "$row" in
					2)
						PAINT_COLOR=1
						draw_ui
					;;
					3)
						PAINT_COLOR=2
						draw_ui
					;;
							4)
						PAINT_COLOR=3
						draw_ui
					;;
							5)
						PAINT_COLOR=4
						draw_ui
					;;
							6)
						PAINT_COLOR=5
						draw_ui
					;;
							7)
						PAINT_COLOR=6
						draw_ui
					;;
							8)
						PAINT_COLOR=7
						draw_ui
					;;
							9)
						PAINT_COLOR=8
						draw_ui
					;;
							10)
						PAINT_COLOR=0
						draw_ui
					;;
				esac
			elif [[ "$row" -eq "$((TERM_LINES - 1))" ]]; then
				# Select Shade
				brsc=19
				if [[ "$col" -eq "$((TERM_COLS - brsc + 1))" || "$col" -eq "$((TERM_COLS - brsc + 2))" ]]; then
					PAINT_SHADE=1
					draw_ui
				elif [[ "$col" -eq "$((TERM_COLS - brsc + 4))" || "$col" -eq "$((TERM_COLS - brsc + 5))" ]]; then
					PAINT_SHADE=2
					draw_ui
				elif [[ "$col" -eq "$((TERM_COLS - brsc + 7))" || "$col" -eq "$((TERM_COLS - brsc + 8))" ]]; then
					PAINT_SHADE=3
					draw_ui
				elif [[ "$col" -eq "$((TERM_COLS - brsc + 10))" || "$col" -eq "$((TERM_COLS - brsc + 11))" ]]; then
					PAINT_SHADE=4
					draw_ui
				fi
			else
				EDIT=1
				top_title
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
						draw_ui
					;;
					3)
						PAINT_BG=2
						draw_ui
					;;
					4)
						PAINT_BG=3
						draw_ui
					;;
					5)
						PAINT_BG=4
						draw_ui
					;;
					6)
						PAINT_BG=5
						draw_ui
					;;
					7)
						PAINT_BG=6
						draw_ui
					;;
					8)
						PAINT_BG=7
						draw_ui
					;;
					9)
						PAINT_BG=8
						draw_ui
					;;
					10)
						PAINT_BG=0
						draw_ui
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
			use_mouse 0
			RESIZE=0
			update_dimensions
			draw_ui
			CURSOR_ROW=0
			CURSOR_COL=0
			use_mouse 1
		fi

		#Read stdin and quit with 'q'
		byte=""
		IFS= LC_ALL=C read -r -t 0.01 -n 1 -d '' byte <"$TTY_DEV" || continue
		if [[ "$byte" = "q" || "$byte" = "Q" ]]; then
			break
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
		elif [[ "$byte" = $'\x13' ]]; then
			save_file "./$NAME" "bytes"
			EDIT=0
			top_title
		fi
    done
}

main "$@"
