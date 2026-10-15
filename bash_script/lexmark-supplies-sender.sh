#!/usr/bin/env bash

set -euo pipefail

# Printf Status
declare -g -A TERM_STATUS=(
    ["ok"]="[   \e[1;32mOK\e[0m   ]"
    ["warn"]="[  \e[1;33mWARN\e[0m  ]"
    ["error"]="[ \e[1;31mERROR!\e[0m ]"
    ["info"]="[  \e[1;36mINFO\e[0m  ]"
    ["default"]="[   --   ]"
)

# Configure file location (default to user home directory)
SCRIPT_NAME=$(basename "$0" .sh)
CONFIG_DIR="/etc/lexmark-config"
HISTORY_DIR="/etc/lexmark-history"
CONFIG_FILE="${CONFIG_DIR}/config.conf"

# If CLI option provided
CONFIG_UPDATED=false

# CLI Flag overrides
CLI_WEBHOOK_URL=""
CLI_BEARER_TOKEN=""
CLI_PRINTER_IPS=""
CLI_REMOVE_PRINTER_IPS=""
CLI_SCAN=false
CLI_SEND=false

# Helper
usage() {
    cat <<EOF
Must run as sudoer.
Usage: sudo ${SCRIPT_NAME} [OPTIONS]

Options:
  -w URL        Webhook URL to POST data to (Printer Supplies)
  -b TOKEN      Bearer token for Webhook authentication
  -i IP         Add Printer's IP Address (Multiple use commas. E.G. "192.168.0.10,192.168.0.11")
  -r IP         Remove Printer's IP Address (Multiple use commas)
  -s            Scan Printer's supplies
  -u            Send Printer's supplies to webhook
  -h            Show this help message

Examples:
  ${SCRIPT_NAME} -w "https://some.web.com/api/webhooks" -b "my_secret_token"
  ${SCRIPT_NAME} -su (To scan, and send to webhook)
EOF
    exit 1
}

# If no arguments, show help
if [[ "$#" -eq 0 ]]; then
    usage
fi

# If not sudoer, kick
if [[ $EUID -ne 0 ]]; then
    usage
fi

# Parsing Arguments
while getopts "w:b:i:r:suh" opt; do
    case "$opt" in
        w)  CLI_WEBHOOK_URL="$OPTARG"; CONFIG_UPDATED=true ;;
        b)  CLI_BEARER_TOKEN="$OPTARG"; CONFIG_UPDATED=true ;;
        i)  CLI_PRINTER_IPS="$OPTARG"; CONFIG_UPDATED=true ;;
        r)  CLI_REMOVE_PRINTER_IPS="$OPTARG"; CONFIG_UPDATED=true ;;
        s)  CLI_SCAN=true ;;
        u)  CLI_SEND=true ;;
        h)  usage ;;
        *)  usage ;;
    esac
done

# Ensure working directory exists and permission added
if [[ ! -d "$CONFIG_DIR" ]]; then
    mkdir -p "$CONFIG_DIR"
    chmod 755 "$CONFIG_DIR"
fi
if [[ ! -d "$HISTORY_DIR" ]]; then
    mkdir -p "$HISTORY_DIR"
    chmod 755 "$HISTORY_DIR"
fi

# Default values
DETAIL_WEBHOOK_URL=""
DETAIL_BEARER_TOKEN=""
SUPPLY_WEBHOOK_URL=""
SUPPLY_BEARER_TOKEN=""
VERIFIED_PRINTER_IPS=""

# Load config from file
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# CLI Overrides
[[ -n "$CLI_WEBHOOK_URL" ]]     && SUPPLY_WEBHOOK_URL="$CLI_WEBHOOK_URL"
[[ -n "$CLI_BEARER_TOKEN" ]]    && SUPPLY_BEARER_TOKEN="$CLI_BEARER_TOKEN"

print_console() {
    local status="$1"
    shift
    local timestamp
    timestamp=$(date +"%d-%m-%Y %H:%M:%S")

    if [[ ! -v TERM_STATUS["$status"] ]]; then
        status="default"
    fi
    printf '[%s] %b %s\n' "$timestamp" "${TERM_STATUS[$status]}" "$*" >&2
}

# -- Printers Parse --
ip_validation() {
    local ip="$1"
    local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! $ip =~ $rx ]]; then
        return 1
    fi

    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done

    return 0
}

add_ips() {
    IFS=',' read -ra ips <<< "$CLI_PRINTER_IPS"
    IFS=',' read -ra verified_ips <<< "$VERIFIED_PRINTER_IPS"

    local -A exist_map=()
    for vip in "${verified_ips[@]+"${verified_ips[@]}"}"; do
        exist_map["$vip"]=1
    done

    for ip in "${ips[@]+"${ips[@]}"}"; do
        if [[ -v exist_map["$ip"] ]]; then
            print_console "warn" "${ip} already exist. Skipping.."
            continue
        fi

        if ip_validation "$ip"; then
            verified_ips+=("$ip")
            exist_map["$ip"]=1
            print_console "ok" "Added ${ip}."
        else
            print_console "warn" "Unable to parse ${ip} as an IP address. Skipping.."
        fi
    done

    if (( ${#verified_ips[@]} > 0 )); then
        IFS=',' VERIFIED_PRINTER_IPS="${verified_ips[*]}"
    else
        VERIFIED_PRINTER_IPS=""
    fi
}

remove_ips() {
    IFS=',' read -ra ips <<< "$CLI_REMOVE_PRINTER_IPS"
    IFS=',' read -ra verified_ips <<< "$VERIFIED_PRINTER_IPS"

    local -A blacklist=()
    for ip in "${ips[@]+"${ips[@]}"}"; do
        blacklist["$ip"]=1
    done

    local -a filtered_ips=()
    for vip in "${verified_ips[@]+"${verified_ips[@]}"}"; do
        if [[ -v blacklist["$vip"] ]]; then
            print_console "ok" "Removed ${vip}."
            continue
        fi
        filtered_ips+=("$vip")
    done

    if (( ${#filtered_ips[@]} > 0 )); then
        IFS=',' VERIFIED_PRINTER_IPS="${filtered_ips[*]}"
    else
        VERIFIED_PRINTER_IPS=""
    fi
}
# -- End Printer Parse --

# Save config if modified
if "$CONFIG_UPDATED"; then
    # Remove IPs
    if [[ -n "${CLI_REMOVE_PRINTER_IPS//[[:space:]]/}" ]]; then
        remove_ips
    fi

    # Add IPs
    if [[ -n "${CLI_PRINTER_IPS//[[:space:]]/}" ]]; then
        add_ips
    fi

    cat <<EOF > "$CONFIG_FILE"
DETAIL_WEBHOOK_URL="$DETAIL_WEBHOOK_URL"
DETAIL_BEARER_TOKEN="$DETAIL_BEARER_TOKEN"
SUPPLY_WEBHOOK_URL="$SUPPLY_WEBHOOK_URL"
SUPPLY_BEARER_TOKEN="$SUPPLY_BEARER_TOKEN"
VERIFIED_PRINTER_IPS="$VERIFIED_PRINTER_IPS"
EOF
    print_console "ok" "Configuration saved to ${CONFIG_FILE}"

    exit 0
fi

# Ensure required parameters exist
if [[ -z "$SUPPLY_WEBHOOK_URL" ]]; then
    print_console "error" "Webhook URL is missing. Please run with -w <webhook_url>."
    exit 1
fi

fetch_payload() {
    local ip="$1"
    local community="$2"
    local history_file="$3"
    local is_online="Offline"

    local dev_serial dev_printer_install sup_toner_lvl sup_image_lvl sup_maint_lvl sup_bottle_lvl
    local sup_toner_sn sup_image_sn sup_maint_sn sup_bottle_sn
    local sup_toner_install sup_image_install sup_maint_install sup_bottle_install

    print_console "info" "Fetching SNMP datas from ${ip}..."

    # Using Lexmark OIDs
    # Fetch Serial number
    local raw_serial raw_printer_install
    raw_serial=$(snmpget -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.2.3.1.5.1 2>/dev/null || true)
    raw_printer_install=$(snmpget -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.2.3.1.7.1 2>/dev/null || true)

    # Fetch supplies
    declare -A supplies
    declare -A sup_sn
    declare -A sup_install
    local raw_desc raw_maxs raw_currs raw_sn raw_install
    raw_desc=$(snmpbulkwalk -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.4.4.2.1.5.1 2>/dev/null || true)
    raw_maxs=$(snmpbulkwalk -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.4.4.1.1.14.1 2>/dev/null || true)
    raw_currs=$(snmpbulkwalk -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.4.4.1.1.16.1 2>/dev/null || true)
    raw_sn=$(snmpbulkwalk -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.4.4.1.1.6 2>/dev/null || true)
    raw_install=$(snmpbulkwalk -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.4.4.1.1.10 2>/dev/null || true)

    # Check if SNMP successfully fetched datas
    if [[ -n "$raw_serial" ]] && [[ -n "$raw_desc" ]] && [[ -n "$raw_maxs" ]] && [[ -n "$raw_currs" ]] && [[ -n "$raw_sn" ]] && [[ -n "$raw_install" ]]; then
        # Printer details
        dev_serial="${raw_serial:-Unknown}"
        dev_printer_install="${raw_printer_install:-07 B2 01 01 00 00 00 00 2B 00 00}"

        # Cleanup
        dev_serial="${dev_serial//\"/}"
        dev_printer_install="${dev_printer_install//\"/}"

        # Set online
        is_online="Online"

        read -r y1 y2 m d h min s rest <<< "$dev_printer_install"
        if [[ -n "$y1" ]] && [[ -n "$y2" ]]; then
            year=$(( 0x$y1 * 256 + 0x$y2 ))
            month=$(( 0x$m ))
            day=$(( 0x$d ))
            hour=$(( 0x$h ))
            minute=$(( 0x$min ))
            second=$(( 0x$s ))

            dev_printer_install=$(printf '%04d-%02d-%02d %02d:%02d:%02d' "$year" "$month" "$day" "$hour" "$minute" "$second")
        else
            dev_printer_install="1970-01-01 00:00:00"
        fi

        # Printer supplies
        mapfile -t desc_arr <<< "$raw_desc"
        mapfile -t maxs_arr <<< "$raw_maxs"
        mapfile -t currs_arr <<< "$raw_currs"
        mapfile -t sn_arr <<< "$raw_sn"
        mapfile -t install_arr <<< "$raw_install"

        for i in "${!desc_arr[@]}"; do
            desc="${desc_arr[$i]:-}"
            max="${maxs_arr[$i]:-0}"
            curr="${currs_arr[$i]:--2}"
            sn="${sn_arr[$i]:-}"
            install_date="${install_arr[$i]:-}"

            # Clean description
            desc="${desc//[\"\\]/}"
            desc="${desc//$'\t'/ }"
            desc=$(echo "$desc" | xargs)

            # Clean install date
            install_date="${install_date//[\"\\]/}"
            install_date="${install_date//$'\t'/ }"
            install_date=$(echo "$install_date" | xargs)

            # Clean numeric
            max="${max//[^0-9-]/}"
            curr="${curr//[^0-9-]/}"

            [[ -z "$desc" ]] && continue

            # Calculate remainder in percentage
            if [[ "${max:-0}" -gt 0 && "${curr:--2}" -ge 0 ]]; then
                supplies["$desc"]="$(( (curr * 100) / max ))"
            else
                supplies["$desc"]="${curr}"
            fi

            # Convert Hex to Timestamp
            read -r y1 y2 m d h min s rest <<< "$install_date"
            if [[ -n "$y1" ]] && [[ -n "$y2" ]]; then
                year=$(( 0x$y1 * 256 + 0x$y2 ))
                month=$(( 0x$m ))
                day=$(( 0x$d ))
                hour=$(( 0x$h ))
                minute=$(( 0x$min ))
                second=$(( 0x$s ))

                sup_install["$desc"]=$(printf '%04d-%02d-%02d %02d:%02d:%02d' "$year" "$month" "$day" "$hour" "$minute" "$second")
            else
                sup_install["$desc"]="$dev_printer_install"
            fi

            # Supplies serial number
            sn="${sn//[\"\\]/}"
            sn="${sn//$'\t'/ }"
            sup_sn["$desc"]=$(echo "$sn" | xargs)
        done

        # Black Toner
        if [[ -v supplies["Black Cartridge"] ]]; then
            sup_toner_lvl="${supplies['Black Cartridge']}"
        else
            sup_toner_lvl="-4"
        fi

        if [[ -v sup_sn['Black Cartridge'] ]]; then
            sup_toner_sn="${sup_sn['Black Cartridge']}"
        else
            sup_toner_sn=""
        fi

        if [[ -v sup_install['Black Cartridge'] ]]; then
            sup_toner_install="${sup_install['Black Cartridge']}"
        else
            sup_toner_install="$dev_printer_install"
        fi

        # Imaging Unit
        if [[ -v supplies["Imaging Unit"] ]]; then
            sup_image_lvl="${supplies['Imaging Unit']}"
        elif [[ -v supplies["Black Imaging Unit"] ]]; then
            sup_image_lvl="${supplies['Black Imaging Unit']}"
        else
            sup_image_lvl="-4"
        fi

        if [[ -v sup_sn["Imaging Unit"] ]]; then
            sup_image_sn="${sup_sn['Imaging Unit']}"
        elif [[ -v sup_sn["Black Imaging Unit"] ]]; then
            sup_image_sn="${sup_sn['Black Imaging Unit']}"
        else
            sup_image_sn=""
        fi

        if [[ -v sup_install["Imaging Unit"] ]]; then
            sup_image_install="${sup_install['Imaging Unit']}"
        elif [[ -v sup_install["Black Imaging Unit"] ]]; then
            sup_image_install="${sup_install['Black Imaging Unit']}"
        else
            sup_image_install="$dev_printer_install"
        fi

        # Maintenance Kit
        if [[ -v supplies["Maintenance Kit"] ]]; then
            sup_maint_lvl="${supplies['Maintenance Kit']}"
        else
            sup_maint_lvl="-4"
        fi

        if [[ -v sup_sn["Maintenance Kit"] ]]; then
            sup_maint_sn="${sup_sn['Maintenance Kit']}"
        else
            sup_maint_sn=""
        fi

        if [[ -v sup_install["Maintenance Kit"] ]]; then
            sup_maint_install="${sup_install['Maintenance Kit']}"
        else
            sup_maint_install="$dev_printer_install"
        fi

        # Waste Toner Bottle
        if [[ -v supplies["Waste Toner Bottle"] ]]; then
            sup_bottle_lvl="${supplies['Waste Toner Bottle']}"
        else
            sup_bottle_lvl="-4"
        fi

        if [[ -v sup_sn["Waste Toner Bottle"] ]]; then
            sup_bottle_sn="${sup_sn['Waste Toner Bottle']}"
        else
            sup_bottle_sn=""
        fi

        if [[ -v sup_install["Waste Toner Bottle"] ]]; then
            sup_bottle_install="${sup_install['Waste Toner Bottle']}"
        else
            sup_bottle_install="$dev_printer_install"
        fi

    else
    # If fetch failed (offline, unavailable), get history file
        print_console "warn" "Unable to fetch SNMP datas from ${ip}. Fallback to history file..."
        if [[ -s "$history_file" ]] && jq empty "$history_file" 2>/dev/null; then
            dev_serial=$(jq -r '(.serial // "Unknown")' "$history_file")

            sup_toner_lvl=$(jq -r '(.toner_level // -4)' "$history_file")
            sup_image_lvl=$(jq -r '(.image_level // -4)' "$history_file")
            sup_maint_lvl=$(jq -r '(.maint_level // -4)' "$history_file")
            sup_bottle_lvl=$(jq -r '(.bottle_level // -4)' "$history_file")

            sup_toner_sn=$(jq -r '(.toner_sn // "")' "$history_file")
            sup_image_sn=$(jq -r '(.image_sn // "")' "$history_file")
            sup_maint_sn=$(jq -r '(.maint_sn // "")' "$history_file")
            sup_bottle_sn=$(jq -r '(.bottle_sn // "")' "$history_file")

            sup_toner_install=$(jq -r '(.toner_install // "1970-01-01 00:00:00")' "$history_file")
            sup_image_install=$(jq -r '(.image_install // "1970-01-01 00:00:00")' "$history_file")
            sup_maint_install=$(jq -r '(.maint_install // "1970-01-01 00:00:00")' "$history_file")
            sup_bottle_install=$(jq -r '(.bottle_install // "1970-01-01 00:00:00")' "$history_file")
        else
            print_console "warn" "History file for ${ip} does not exists. Create new history file..."
            dev_serial="Unknown"

            sup_toner_lvl="-4"
            sup_image_lvl="-4"
            sup_maint_lvl="-4"
            sup_bottle_lvl="-4"

            sup_toner_sn=""
            sup_image_sn=""
            sup_maint_sn=""
            sup_bottle_sn=""

            sup_toner_install="1970-01-01 00:00:00"
            sup_image_install="1970-01-01 00:00:00"
            sup_maint_install="1970-01-01 00:00:00"
            sup_bottle_install="1970-01-01 00:00:00"
        fi
    fi

    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    jq -c -n \
        --arg timestamp "$timestamp" \
        --arg ip "$ip" \
        --arg serial "$dev_serial" \
        --arg toner "$sup_toner_lvl" \
        --arg image "$sup_image_lvl" \
        --arg maint "$sup_maint_lvl" \
        --arg bottle "$sup_bottle_lvl" \
        --arg toner_sn "$sup_toner_sn" \
        --arg image_sn "$sup_image_sn" \
        --arg maint_sn "$sup_maint_sn" \
        --arg bottle_sn "$sup_bottle_sn" \
        --arg toner_install "$sup_toner_install" \
        --arg image_install "$sup_image_install" \
        --arg maint_install "$sup_maint_install" \
        --arg bottle_install "$sup_bottle_install" \
        --arg online "$is_online" '{
            "timestamp": $timestamp,
            "ip": $ip,
            "serial": $serial,
            "toner_level": $toner,
            "toner_sn": $toner_sn,
            "toner_install": $toner_install,
            "image_level": $image,
            "image_sn": $image_sn,
            "image_install": $image_install,
            "maint_level": $maint,
            "maint_sn": $maint_sn,
            "maint_install": $maint_install,
            "bottle_level": $bottle,
            "bottle_sn": $bottle_sn,
            "bottle_install": $bottle_install,
            "available": $online
        }'
}

save_payload_to_file() {
    local payload="$1"
    local target_file="$2"

    if [[ -z "${payload//[[:space:]]/}" ]]; then
        print_console "error" "Payload is empty. Cannot save to $target_file."
        return 1
    fi

    if jq -c . <<< "$payload" > "${target_file}.tmp" 2>/dev/null; then
        mv "${target_file}.tmp" "$target_file"
        print_console "ok" "Saved payload to $target_file."
    else
        print_console "error" "Invalid JSON. Abort write."
        rm -f "${target_file}.tmp"
        return 1
    fi
}

scan_printers() {
    declare -a files_ready=()
    IFS=',' read -ra verified_ips <<< "$VERIFIED_PRINTER_IPS"
    if [[ -z "$VERIFIED_PRINTER_IPS" ]]; then
        print_console "warn" "No printers has been added. Please run again with -i <Printer IP Addresses>."
        return 1
    fi

    for ip in "${verified_ips[@]+"${verified_ips[@]}"}"; do
        local history_file="$HISTORY_DIR/history_${ip}_supplies.json"

        # Fetch JSON from printer
        local payload_json
        payload_json=$(fetch_payload "$ip" "public" "$history_file")

        # Save payload to history
        save_payload_to_file "$payload_json" "$history_file"

        sleep 0.1
    done
    print_console "ok" "All printers has been scanned and saved in $HISTORY_DIR."
}

send_payload() {
    IFS=',' read -ra verified_ips <<< "$VERIFIED_PRINTER_IPS"

    print_console "info" "Validate supplies files to be compiled..."
    valid_files=()
    for ip in "${verified_ips[@]+"${verified_ips[@]}"}"; do
        file="$HISTORY_DIR/history_${ip}_supplies.json"
        if [[ -f "$file" && -s "$file" ]] && jq empty "$file" 2>/dev/null; then
            print_console "ok" "Supplies file is valid ($file)."
            valid_files+=("$file")
        else
            print_console "warn" "Supplies file not found ($file)."
        fi
    done

    if [[ ${#valid_files[@]} -eq 0 ]]; then
        print_console "warn" "No history files created. Will not POST nothing."
    else
        print_console "info" "Merging and sending payload to webhook..."
        curl_headers=(-H "Content-Type: application/json")
        if [[ -n "$SUPPLY_BEARER_TOKEN" ]]; then
            curl_headers+=(-H "Authorization: Bearer $SUPPLY_BEARER_TOKEN")
        fi

        response_code=$(jq -s -c '.' "${valid_files[@]}" | curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            "${curl_headers[@]}" \
            --data-binary @- \
            "$SUPPLY_WEBHOOK_URL")

        if [[ "$response_code" -ge 200 && "$response_code" -lt 300 ]]; then
            print_console "ok" "Payload delivered successfully (HTTP Status: $response_code)."
        else
            print_console "error" "Failed to deliver payload (HTTP Status: $response_code)."
        fi
    fi
}

# Graceful shutdown handler for Systemd
trap 'print_console "info" "Stopping immaturely..."; exit 0' SIGINT SIGTERM

# Main Service Loop
if $CLI_SCAN; then
    print_console "info" "Scanning printers..."
    scan_printers || true
    sleep 0.1
fi

if $CLI_SEND; then
    print_console "info" "Sending details to webhook..."
    send_payload || true
fi
