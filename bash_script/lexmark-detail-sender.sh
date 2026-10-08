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
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  -w URL        Webhook URL to POST data to (Printer Details)
  -b TOKEN      Bearer token for Webhook authentication
  -i IP         Add Printer's IP Address (Multiple use commas. E.G. "192.168.0.10,192.168.0.11")
  -r IP         Remove Printer's IP Address (Multiple use commas)
  -s            Scan Printer's detail
  -u            Send Printer's detail to webhook
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
[[ -n "$CLI_WEBHOOK_URL" ]]     && DETAIL_WEBHOOK_URL="$CLI_WEBHOOK_URL"
[[ -n "$CLI_BEARER_TOKEN" ]]    && DETAIL_BEARER_TOKEN="$CLI_BEARER_TOKEN"

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
if [[ -z "$DETAIL_WEBHOOK_URL" ]]; then
    print_console "error" "Webhook URL is missing. Please run with -w <webhook_url>."
    exit 1
fi

fetch_payload() {
    local ip="$1"
    local community="$2"
    local history_file="$3"
    local is_online="Offline"

    local dev_name dev_loc dev_model dev_serial dev_mac dev_status

    print_console "info" "Fetching SNMP datas from ${ip}..."

    # Using Lexmark OIDs
    # Fetch name, location, model, serial number and MAC address
    local raw_details
    raw_details=$(snmpget -v2c -c "$community" -t 5 -r 0 -O qv "$ip" \
        .1.3.6.1.4.1.641.1.5.7.6.0 \
        .1.3.6.1.2.1.1.6.0 \
        .1.3.6.1.4.1.641.6.2.3.1.4.1 \
        .1.3.6.1.4.1.641.6.2.3.1.5.1 \
        .1.3.6.1.4.1.641.1.7.4.0 2>/dev/null || true)

    # Fetch statuses
    raw_status=$(snmpbulkwalk -v2c -c "$community" -t 5 -r 0 -O qv "$ip" .1.3.6.1.4.1.641.6.5.1.1.6 2>/dev/null || true)

    # Check if SNMP successfully fetched datas
    if [[ -n "$raw_details" ]] && [[ -n "$raw_status" ]]; then
        # Printer details
        mapfile -t details_arr <<< "$raw_details"

        dev_name="${details_arr[0]:-Unknown}"
        dev_loc="${details_arr[1]:-Unknown}"
        dev_model="${details_arr[2]:-Unknown}"
        dev_serial="${details_arr[3]:-Unknown}"
        dev_mac="${details_arr[4]:-Unknown}"

        # Cleanup
        dev_name="${dev_name//\"/}"
        dev_loc=$(echo "$dev_loc" | tr -d '"\\' | tr '\t' ' ' | xargs)
        dev_model="${dev_model//\"/}"
        dev_serial="${dev_serial//\"/}"
        dev_mac=$(echo "$dev_mac" | tr -d '" ' | tr 'a-f' 'A-F')

        # Statuses
        mapfile -t status_arr <<< "$raw_status"

        if [[ ${#status_arr[@]} -eq 0 ]]; then
            dev_status="OK"
        elif [[ "$status_arr" =~ "No Such Instance" ]] || [[ "$status_arr" =~ "No Such Object" ]]; then
            dev_status="OK"
        else
            dev_status="${raw_status//$'\n'/, }"
            dev_status="${dev_status//\"/}"
            dev_status="${dev_status%, }"
        fi

        # Set online
        is_online="Online"

    else
    # If fetch failed (offline, unavailable), get history file
        print_console "warn" "Unable to fetch SNMP datas from ${ip}. Fallback to history file..."
        if [[ -s "$history_file" ]] && jq empty "$history_file" 2>/dev/null; then
            dev_name=$(jq -r '(.name // "Unknown")' "$history_file")
            dev_loc=$(jq -r '(.location // "Unknown")' "$history_file")
            dev_model=$(jq -r '(.model // "Unknown")' "$history_file")
            dev_serial=$(jq -r '(.serial // "Unknown")' "$history_file")
            dev_mac=$(jq -r '(.mac // "Unknown")' "$history_file")
            dev_status=$(jq -r '(.status // "Unknown")' "$history_file")
        else
            print_console "warn" "History file for ${ip} does not exists. Create new history file..."
            dev_name="Unknown"
            dev_loc="Unknown"
            dev_model="Unknown"
            dev_serial="Unknown"
            dev_mac="Unknown"
            dev_status="Unknown"
        fi
    fi

    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    jq -c -n \
        --arg timestamp "$timestamp" \
        --arg ip "$ip" \
        --arg name "$dev_name" \
        --arg location "$dev_loc" \
        --arg model "$dev_model" \
        --arg serial "$dev_serial" \
        --arg mac "$dev_mac" \
        --arg status "$dev_status" \
        --arg online "$is_online" '{
            "timestamp": $timestamp,
            "ip": $ip,
            "serial": $serial,
            "mac": $mac,
            "name": $name,
            "location": $location,
            "model": $model,
            "status": $status,
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
        local history_file="$HISTORY_DIR/history_${ip}_details.json"

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

    print_console "info" "Validate detail files to be compiled..."
    valid_files=()
    for ip in "${verified_ips[@]+"${verified_ips[@]}"}"; do
        file="$HISTORY_DIR/history_${ip}_details.json"
        if [[ -f "$file" && -s "$file" ]] && jq empty "$file" 2>/dev/null; then
            print_console "ok" "Detail file is valid ($file)."
            valid_files+=("$file")
        else
            print_console "warn" "Detail file not found ($file)."
        fi
    done

    if [[ ${#valid_files[@]} -eq 0 ]]; then
        print_console "warn" "No detail files created. Will not POST nothing."
    else
        print_console "info" "Merging and sending payload to webhook..."
        curl_headers=(-H "Content-Type: application/json")
        if [[ -n "$DETAIL_BEARER_TOKEN" ]]; then
            curl_headers+=(-H "Authorization: Bearer $DETAIL_BEARER_TOKEN")
        fi

        response_code=$(jq -s -c '.' "${valid_files[@]}" | curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            "${curl_headers[@]}" \
            --data-binary @- \
            "$DETAIL_WEBHOOK_URL")

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
