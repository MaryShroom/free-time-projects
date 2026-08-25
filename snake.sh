#!/usr/bin/env bash
#trap 'read -p "Line $LINENO: $BASH_COMMAND (Press Enter to step)"' DEBUG
set -euo pipefail
SPEED=1
SCORE=0
WIDTH=10
HEIGHT=10
GAP=2

while getopts "s:r:g:h" opt; do
    case ${opt} in
	s)
	  if [[ "$OPTARG" -ge 1 ]] && [[ "$OPTARG" -le 50 ]]; then
	      SPEED="$OPTARG"
	  else
	      echo "Out of range. (1 to 50)"
	      exit 1
	  fi
	  ;;
	r)
	  w=$(echo "$OPTARG" | cut -d':' -f1)
	  h=$(echo "$OPTARG" | cut -d':' -f2)
	  if [[ "$w" -ge 10 && "$h" -ge 10 ]]; then
	      WIDTH="$w"
	      HEIGHT="$h"
	  else
	      echo "Out of range value."
	      exit 1
	  fi
	  ;;
	g)
	  if [[ "$OPTARG" -ge 1 ]]; then
	      GAP="$OPTARG"
	  else
	      echo "Out of range value."
	      exit 1
	  fi
	  ;;
	h)
	  echo "Usage: -s [number] (optional) -r [w:h] (optional) -h (optional)"
	  echo "-s (S)peed	Change (s)peed (1 to 50). Default 1."
	  echo "-r (R)esolution	Change resolution (width:height) OR (length). Default/minimum 10 by 10."
	  echo "-g (G)ap	Change width gap. Default 2."
	  echo "-h (H)elp	Show this"
	  exit 0
	  ;;
	\?)
	  echo "Invalid option."
	  exit 1
	  ;;
    esac
done

shift $((OPTIND - 1))

SAVED_STTY=$(stty -g </dev/tty 2>/dev/null)

cleanup() {
	trap - EXIT INT TERM
	printf "\e[0m\e[?25h\e[?1049l" > /dev/tty
	if [ -n "$SAVED_STTY" ]; then
	    stty "$SAVED_STTY" </dev/tty >/dev/tty 2>/dev/null
	else
	    stty sane icanon echo </dev/tty >/dev/tty 2>/dev/null
	fi

	read -n 10 -p "Player Name (Max 10 characters) : " player_name
	printf "Player : ${player_name:-Player}, Speed : $SPEED , Score : $SCORE\n" | tee -a ~/scores.txt
	exit 0
}

trap cleanup EXIT INT TERM

printf "\e[?1049h\e[?25l" >/dev/tty
stty -echo -icanon min 1 time 0 </dev/tty >/dev/tty 2>/dev/null

init_box() {
    local row=1
    local col=2
    local width_gap=$GAP
    local width=$(( WIDTH * width_gap ))
    local height=$HEIGHT
    local title=" SNAKE' "

    # Title
    tput cup $row $col
    printf "\u2554"
    for ((i=1; i<=width; i++)); do printf "\u2550"; done
    printf "\u2557"
    tput cup $row $(( ( width / 2 ) - (${#title} / 2) + col + 1 ))
    printf "$title"

    # Box
    # Top
    tput cup $(( row + 1 ))  $col
    printf "\u2560"
    for ((i=1; i<=width; i++)); do printf "\u2550"; done
    printf "\u2563"
    # Sides
    for ((r=1; r<=height; r++)); do
	tput cup $((row + 1 + r)) $col
	printf "\u2551"
	tput cup $((row + 1 + r)) $((col + width + 1))
	printf "\u2551"
    done
    # Bottom
    tput cup $((row + height + 2)) $col
    printf "\u2560"
    for ((i=1; i<=width; i++)); do printf "\u2550"; done
    printf "\u2563"

    # Score, Speed
    tput cup $((row + height + 3)) $col
    printf "\u2560 Sco"
    tput cup $((row + height + 3)) $((col + width - 3))
    printf "Spe \u2563"
    tput cup $((row + height + 4)) $col
    printf "\u255A"
    tput cup $((row + height + 4)) $((col + width + 1))
    printf "\u255D"

    # Score Number
    tput cup $((row + height + 4)) $((col + 2))
    printf "0"
    # Speed Number
    tput cup $((row + height + 4)) $((col + width - 2))
    printf "%02d" "$SPEED"
}

draw_snake() {
    local type=$1
    local row=$(( 2 + $2 ))
    local col=$(( 2 + ( $3 * $GAP ) - ( $GAP - 1 ) ))
    local res="\e[0m"

    # Snake Tiles
    local s_body=$(printf '\u2592%.0s' $(seq 1 $GAP))
    local s_head=$(printf '\u2588%.0s' $(seq 1 $GAP))
    local s_food=$(printf ' %.0s' $(seq 1 $GAP))

    #Food generator
    local foods=("\e[41m$s_food$res" "\e[42m$s_food$res" "\e[43m$s_food$res" "\e[44m$s_food$res" "\e[45m$s_food$res" "\e[46m$s_food$res")
    local rand=$(( RANDOM % ${#foods[@]} ))
    local food="${foods[$rand]}"

    # Draw
    tput cup "$row" "$col"
    case "$type" in
	sbody)		printf "$s_body" ;;
	shead)		printf "$s_head" ;;
	food)		printf "$food" ;;
	0)		printf ' %.0s' $(seq 1 $GAP) ;;
	*)		echo "ERROR" ;;
    esac
}

dupt() {
    local -n refA="$1"
    local -n refB="$2"
    local -A seen=()

    for i in "${!refA[@]}"; do
	temp="${refA[$i]}:${refB[$i]}"
	if [[ -v seen["$temp"] ]]; then
	    return 0
	fi
	seen["$temp"]=1
    done

    return 1
}

food_gen() {
    local max_row="$1"
    local max_col="$2"
    local -n refA="$3"
    local -n refB="$4"
    local is_break=0

    local value_row=0 value_col=0

    while (( is_break == 0 )); do
	value_row=$(( RANDOM % (max_row) + 1 ))
	value_col=$(( RANDOM % (max_col) + 1 ))
	temp="$value_row:$value_col"

	for i in "${!refA[@]}"; do
	    temp2="${refA[$i]}:${refB[$i]}"
            if [[ "$temp2" == "$temp" ]]; then
		is_break=0
		break
	    else
		is_break=1
	    fi
	done
    done
    echo "$temp"
}

engine() {
    local death=0
    local speed=$SPEED
    local score=0 food_count=0
    local timeout=$(( 500000 - (speed - 1) * 9183 ))
    local start_time=0 now=0
    local new_move="right"

    local width=$WIDTH height=$HEIGHT

    local max_food=$(( ( width * height ) - 2 ))

    #Initial snake body
    local s_body_row=("$(( height / 2 ))" "$(( height / 2 ))")
    local s_body_col=("$(( ( width / 2 ) - 1 + ( ( width / 2 ) % 2 ) - 1 ))" "$(( ( width / 2 ) - 1 + ( ( width / 2 ) % 2 ) ))")

    #Initial Food
    local food_pos=$(food_gen "$height" "$width" s_body_row s_body_col)
    declare -A local food=()
    food[row]=$(echo "$food_pos" | cut -d':' -f1)
    food[col]=$(echo "$food_pos" | cut -d':' -f2)

    # Countdown
    tput cup 4 $(( ( ( width*GAP ) / 2 ) + 2 ))
    echo -n "03"
    sleep 1
    tput cup 4 $(( ( ( width*GAP ) / 2 ) + 2 ))
    echo -n "02"
    sleep 1
    tput cup 4 $(( ( ( width*GAP ) / 2 ) + 2 ))
    echo -n "01"
    sleep 1
    tput cup 4 $(( ( ( width*GAP ) / 2 ) + 2 ))
    echo -n "  "
    tput cup $(( height + 6 )) 4
    echo -n "(Press q to quit)"

    #First draw
    draw_snake "shead" "${s_body_row[-1]}" "${s_body_col[-1]}"
    draw_snake "sbody" "${s_body_row[0]}" "${s_body_col[0]}"
    draw_snake "food" "${food[row]}" "${food[col]}"

    # Loop
    while [[ "death" -eq 0 ]]; do
	start_time=$(date +%s%6N)

	if (( food_count == 5 )); then
	    food_count=0
	    if (( speed < 50 )); then
		(( ++speed ))
		timeout=$(( 500000 - (speed - 1) * 10000 ))
		tput cup $((2 + height + 3)) $(( ( GAP * width ) ))
    		printf "%02d" "$speed"
	    fi
	fi

	# Get latest key pressed within timeout
	local latest_key=""
	while true; do
	    now=$(date +%s%6N)

	    #Calculate remaining time
            rem=$(( timeout - (now - start_time) ))
	    if (( rem <= 0 )); then break; fi
	    rem_sec=$(printf "0.%06d" "$rem")

	    #Check arrow key is pressed
	    if read -rsn1 -t "$rem_sec" char 2>/dev/null; then
		if [[ $char == $'\x1b' ]]; then
		    read -rsn2 -t 0.005 rest || true
		    char+="$rest"
		fi
		latest_key="$char"
	    else
		break
	    fi
	done

	#Set move
	case "$latest_key" in
	    $'\x1b[A')	[[ "$new_move" != "down" ]] && new_move="up" ;;
            $'\x1b[B')	[[ "$new_move" != "up" ]] && new_move="down" ;;
            $'\x1b[C')	[[ "$new_move" != "left" ]] && new_move="right" ;;
            $'\x1b[D')	[[ "$new_move" != "right" ]] && new_move="left" ;;
	    q|Q)
		tput cup $(( (height / 2) + 2 )) $(( ( ( width*GAP ) / 2 ) - 2 ))
                printf "\e[31mGAME  OVER\e[0m"
		break
		;; #Quit
	esac

	#Delete old head
        draw_snake 0 "${s_body_row[-1]}" "${s_body_col[-1]}"
	#Move new head
	local temp=0
	case "$new_move" in
	    "up")
		if (( s_body_row[-1] > 1 )); then
		    temp=$(( s_body_row[-1] - 1 ))
		    s_body_row+=("$temp")
		    s_body_col+=("${s_body_col[-1]}")
		else
		    s_body_row+=("$height")
		    s_body_col+=("${s_body_col[-1]}")
		fi
		;;
	    "down")
		if (( s_body_row[-1] < height )); then
                    temp=$(( s_body_row[-1] + 1 ))
                    s_body_row+=("$temp")
                    s_body_col+=("${s_body_col[-1]}")
                else
                    s_body_row+=(1)
                    s_body_col+=("${s_body_col[-1]}")
                fi
		;;
	    "right")
		if (( s_body_col[-1] < width )); then
                    temp=$(( s_body_col[-1] + 1 ))
                    s_body_row+=("${s_body_row[-1]}")
                    s_body_col+=("$temp")
                else
                    s_body_row+=("${s_body_row[-1]}")
                    s_body_col+=(1)
                fi
		;;
	    "left")
		if (( s_body_col[-1] > 1 )); then
                    temp=$(( s_body_col[-1] - 1 ))
                    s_body_row+=("${s_body_row[-1]}")
                    s_body_col+=("$temp")
                else
                    s_body_row+=("${s_body_row[-1]}")
                    s_body_col+=("$width")
                fi
		;;
	esac

	# Draw 2nd body
	draw_snake "sbody" "${s_body_row[-2]}" "${s_body_col[-2]}"

	#If not eat, remove oldest body
        if (( s_body_row[-1] != food[row] || s_body_col[-1] != food[col] )); then
	    draw_snake 0 "${s_body_row[0]}" "${s_body_col[0]}"
	    s_body_row=("${s_body_row[@]:1}")
            s_body_col=("${s_body_col[@]:1}")
	else
	    score=$(( score + ( 300 * speed ) ))
	    (( ++food_count ))
	    (( max_food-- ))
	    if (( max_food != 0 )); then
	        food_pos=$(food_gen "$height" "$width" s_body_row s_body_col)
	        food[row]=$(echo "$food_pos" | cut -d':' -f1)
	        food[col]=$(echo "$food_pos" | cut -d':' -f2)

		#Draw food if not max
		draw_snake "food" "${food[row]}" "${food[col]}"
	    fi
	fi

	#Draw new head
        draw_snake "shead" "${s_body_row[-1]}" "${s_body_col[-1]}"

	#Update Score
	tput cup $((2 + height + 3)) 4
        echo -n "$score"

	#Game Over
	if dupt s_body_row s_body_col; then
	    tput cup $(( (height / 2) + 2 )) $(( ( ( width*GAP ) / 2 ) - 2 ))
            printf "\e[31mGAME  OVER\e[0m"
            break
        fi
	if (( max_food == 0 )); then
	    tput cup $(( (height / 2) + 2 )) $(( ( ( width*GAP ) / 2 ) - 2 ))
            printf "\e[32mGAME  OVER\e[0m"
            break
        fi
    done

    SPEED="$speed"
    SCORE="$score"
}

clear
init_box

engine

sleep 5
exit 0
