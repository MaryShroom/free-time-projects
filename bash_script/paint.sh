#!/usr/bin/env bash

set -euo pipefail

TTY_DEV="$(tty 2>/dev/null || echo "/dev/tty")"

SAVED_STTY=""
if [[ -t 1 ]]; then
    SAVED_STTY="$(stty -g <"$TTY_DEV" 2>/dev/null || true)"
fi

TERM_LINES=0
TERM_COLS=0
TERM_LINES_SCALE=1
TERM_COLS_SCALE=1

CANVAS_LINES=0
CANVAS_COLS=0

PAINT_ROW=10
PAINT_COL=10
PAINT_TL_POS="1:1"
PAINT_COLOR=0
PAINT_SHADE=4

CURSOR_ROW=0
CURSOR_COL=0
CURSOR_L=1
CURSOR_H=1

RESIZE=0
DRAG=0
NAME="Untitled Longest Name ever test test 1234"
EDIT=1

cleanup() {
    trap - EXIT INT TERM WINCH
    use_mouse 0
    printf '\e[?1003l\e[?1006l\e[0m\e[?25h\e[?1049l' >"$TTY_DEV" 2>/dev/null || true
    if [[ -n "$SAVED_STTY" ]]; then
	stty "$SAVED_STTY" <"$TTY_DEV" 2>/dev/null || true
    fi
    stty echo icanon <"$TTY_DEV" 2>/dev/null || true
}

update_dimensions() {
    TERM_LINES="$(tput lines 2>/dev/null || echo 24)"
    TERM_COLS="$(tput cols 2>/dev/null || echo 80)"

    # Scale (Max 3)
    if [[ "$((TERM_LINES % 13))" -eq 0 && "$TERM_LINES_SCALE" -le 3 ]]; then
	TERM_LINES_SCALE=$((TERM_LINES / 13))
    fi
    if [[ "$((TERM_COLS % 33))" -eq 0 && "$TERM_COLS_SCALE" -le 3 ]]; then
	TERM_COLS_SCALE=$((TERM_COLS / 33))
    fi

    # Canvas size
    CANVAS_LINES=$((TERM_LINES - 3))
    CANVAS_COLS=$((TERM_COLS - 4))
}

draw_ui() {
   # Clear Screen
    printf '\e[2J' >"$TTY_DEV"

    if [[ TERM_LINES -ge 13 && TERM_COLS -ge 34 ]]; then
	# Top
	rt="(H)elp (Q)uit "
	if [[ "$EDIT" -eq 1 ]]; then
	    cap=$((TERM_COLS - ${#rt} - 4))
	    lt=" ${NAME:0:$cap} * "
	else
	    cap=$((TERM_COLS - ${#rt} - 2))
	    lt=" ${NAME:0:$cap} "
	fi
	lrw=$((TERM_COLS - ${#lt}))
	printf '\e[1;1H\e[7m%b%*b\e[0m' "$lt" "$lrw" "$rt" >"$TTY_DEV"

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
	    0)  printf '\e[2;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    1)  printf '\e[4;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    2)  printf '\e[5;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    3)  printf '\e[6;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    4)  printf '\e[7;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    5)  printf '\e[8;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    6)  printf '\e[9;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    7)  printf '\e[3;%dH>' "$((sps - 1))" >"$TTY_DEV";;
	    9)  printf '\e[10;%dH>' "$((sps - 1))" >"$TTY_DEV";;
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
	printf '\e[%d;1H\e[7m%-*s\e[0m' "$TERM_LINES" "$TERM_COLS" " Size: ${CANVAS_COLS}x${CANVAS_LINES} Pos: $CURSOR_COL $CURSOR_ROW " >"$TTY_DEV"
    else
	t="Please resize to 34 by 13."
	l=$((TERM_LINES / 2))
	c=$((TERM_COLS / 2 - (26 / 2)))

	printf '\e[%d;%dH\e[1m%b\e[0m' "$l" "$c" "$t" >"$TTY_DEV"
    fi
}

draw_paint() {
    return 0
}

handle_resize() {
    RESIZE=1
}

use_mouse() {
    local val=$1
    if [[ "$val" -eq 1 ]]; then
	printf '\e[?1000h\e[?1006h' >"$TTY_DEV"
    elif [[ "$val" -eq 0 ]]; then
	printf '\e[?1000l\e[?1006l' >"$TTY_DEV"
    fi
}

init_terminal() {
    trap cleanup EXIT INT TERM

    trap handle_resize WINCH

    printf '\e[?1049h\e[?25l\e[?1003h\e[?1006h' >"$TTY_DEV"

    stty -echo -icanon min 1 time 0 <"$TTY_DEV" 2>/dev/null

    update_dimensions
    draw_ui
}

draw_cursor() {
    local col=$1
    local row=$2

    #Skip if no move or outside canvas area
    if [[ "$row" -eq 1 ]]; then
        return
    fi
    if [[ "$row" -ge "$((TERM_LINES - 1))" ]]; then
	return
    fi
    if [[ "$col" -ge "$((TERM_COLS - 3))" ]]; then
	return
    fi

    #Delete old
    if [[ "$CURSOR_ROW" -gt 0 ]]; then
	printf '\e[%d;%dH ' "$CURSOR_ROW" "$CURSOR_COL" >"$TTY_DEV"
    fi

    #Select color
    local color=""
    case "$PAINT_COLOR" in
	0)  color="\e[40m" ;;
	1)  color="\e[41m" ;;
        2)  color="\e[42m" ;;
	3)  color="\e[43m" ;;
	4)  color="\e[44m" ;;
	5)  color="\e[45m" ;;
	6)  color="\e[46m" ;;
	7)  color="\e[47;30m" ;;
	9)  color="\e[0m" ;;
	*)
	    PAINT_COLOR=0
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

    #Draw new
    if [[ "$DRAG" -eq 0 ]]; then
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
    if [[ "$col" -ge "$((TERM_COLS - 3))" ]]; then
        return
    fi

    #Select color
    case "$PAINT_COLOR" in
        0)  char="\e[30m" ;;
        1)  char="\e[31m" ;;
        2)  char="\e[32m" ;;
        3)  char="\e[33m" ;;
        4)  char="\e[34m" ;;
        5)  char="\e[35m" ;;
        6)  char="\e[36m" ;;
        7)  char="\e[37m" ;;
	9)  char="\e[0m" ;;
        *)
            PAINT_COLOR=0
            char="\e[30m"
            ;;
    esac

    #Select Shade
    if [[ "$PAINT_COLOR" -eq 9 ]]; then
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

    printf '\e[%d;%dH%b\e[0m' "$row" "$col" "$char" >"$TTY_DEV"

    CURSOR_ROW=$row
    CURSOR_COL=$col
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

    case "$button" in
	0) #Left Click
	    # Select Color
	    if [[ "$col" -ge "$TERM_COLS - 2" ]]; then
		case "$row" in
		    2)
			PAINT_COLOR=0
			draw_ui
			;;
		    3)
			PAINT_COLOR=7
                        draw_ui
			;;
                    4)
			PAINT_COLOR=1
                        draw_ui
			;;
                    5)
			PAINT_COLOR=2
                        draw_ui
			;;
                    6)
			PAINT_COLOR=3
                        draw_ui
			;;
                    7)
			PAINT_COLOR=4
                        draw_ui
			;;
                    8)
			PAINT_COLOR=5
                        draw_ui
			;;
                    9)
			PAINT_COLOR=6
                        draw_ui
			;;
                    10)
			PAINT_COLOR=9
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
	    EDIT=0 #TEST
	    ;;
	35) #Motion
	    DRAG=0
	    draw_cursor "$col" "$row"
	    ;;
	64) #Scroll Up
	    ;;
	65) #Scroll Down
	    ;;
    esac

    #Update cursor position
    printf '\e[%d;1H\e[7m Size: %b Pos: %d %d \e[0m' "$TERM_LINES" "${CANVAS_COLS}x${CANVAS_LINES}" "$CURSOR_COL" "$((CURSOR_ROW - 1))" >"$TTY_DEV"
}

main() {
    init_terminal

    #Event loop
    while true; do
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

	#Read stdin and quit with 'q', help with 'h'
	byte=""
	IFS= LC_ALL=C read -r -t 0.01 -n 1 -d '' byte <"$TTY_DEV" || continue
	if [[ "$byte" = "q" || "$byte" = "Q" ]]; then
	    break
	fi
	if [[ "$byte" = "h" || "$byte" = "H" ]]; then
	    break
	fi

	#Char escape
	if [[ "$byte" = $'\x1b' ]]; then
	    seq=""

	    while true; do
		IFS= LC_ALL=C read -r -t 0.01 -n 1 -d '' b <"$TTY_DEV" || break
		seq="${seq}${b}"

		if [[ "$b" = "m" || "$b" = "M" ]]; then
		    break
		fi
	    done

	    if [[ "$seq" =~ ^\[\<([0-9]+)\;([0-9]+)\;([0-9]+)([mM])$ ]]; then
		btn="${BASH_REMATCH[1]}"
		col="${BASH_REMATCH[2]}"
		row="${BASH_REMATCH[3]}"
		state="${BASH_REMATCH[4]}"

		click_handler "$btn" "$col" "$row" "$state"
	    fi
	fi
    done
}

main "$@"
