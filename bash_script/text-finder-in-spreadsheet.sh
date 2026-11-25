#!/usr/bin/env bash
set -euo pipefail

# Kick if soffice is not installed
if ! type soffice >/dev/null 2>&1; then
  echo "Error: soffice (LibreOffice) is not installed or not in PATH." >&2
  exit 1
fi

SCRIPT_NAME=$(basename "$0" .sh)
FIND_TEXT=""
TEMPDIR=""
CHECK_DUPES=0

cleanup() {
    [[ -n "${TEMPDIR:-}" && -d "$TEMPDIR" ]] && rm -rf -- "$TEMPDIR"
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Helper
usage() {
    echo "Usage: ${SCRIPT_NAME} -f <text> [-d] <path-to-file>" >&2
    exit 1
}

positional_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            if [[ $# -lt 2 ]]; then
                echo "Error: -f requires an argument" >&2
                usage
            fi
            FIND_TEXT="$2"
            shift 2
            ;;
        -d)
            CHECK_DUPES=1
            shift
            ;;
        --)
            shift
            positional_args+=("$@")
            break
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            usage
            ;;
        *)
            positional_args+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$FIND_TEXT" ]]; then
    echo "Error: -f is required" >&2
    usage
fi

if [[ ${#positional_args[@]} -ne 1 ]]; then
    echo "Error: Expected exactly one file path" >&2
    usage
fi

# Spreadsheet path, filename and parent directory
SS_PATH="${positional_args[0]}"

# If file not found
[[ -f "$SS_PATH" ]] || { echo "Error: file not found: $SS_PATH" >&2; exit 1; }

SS_FILENAME="$(basename -- "$SS_PATH")"

echo "Spreadsheet   : $SS_FILENAME"
echo "Text to find  : $FIND_TEXT"

# Temp directory and cleanup when exit
TEMPDIR=$(mktemp -d)

# Convert spreadsheet to temp csv
soffice -env:UserInstallation="file://$TEMPDIR/profile" --headless \
    --convert-to 'csv:Text - txt - csv (StarCalc):9,34,76,1,,0,false,true,false,false,false,-1' \
    --outdir "$TEMPDIR" "$SS_PATH" >/dev/null

# Check if at least one matching .csv file exists
if ! compgen -G "$TEMPDIR/*.csv" >/dev/null; then
    echo "Error: soffice produced no .csv files in '$TEMPDIR'." >&2
    exit 1
fi

# Loop all .csv if multiple sheets
base="${SS_FILENAME%.*}"
echo "----- Results -----"
for csv_file in "$TEMPDIR"/*.csv; do
    [[ -f "$csv_file" ]] || continue

    # Get sheet name from filename
    sheetname=${csv_file##*/}          # drop the directory
    sheetname=${sheetname#"$base"-}     # drop the filename prefix
    sheetname=${sheetname%.csv}   # drop the ".csv" suffix

    # Find text with its coordinate
    LC_ALL=C.UTF-8 FIND_TEXT="$FIND_TEXT" awk -F'\t' -v sheet="$sheetname" -v dupes="$CHECK_DUPES" '
    function unquote(val) {
        if (length(val) >= 2 && substr(val, 1, 1) == "\"" && substr(val, length(val), 1) == "\"") {
            val = substr(val, 2, length(val) - 2)
            gsub(/""/, "\"", val)
        }
        return val
    }
    function col(n,  s, m) {
        while (n > 0) {
            m = (n - 1) % 26
            s = sprintf("%c", 65 + m) s
            n = int((n - 1) / 26)
        }
        return s
    }
    BEGIN {
        t = tolower(ENVIRON["FIND_TEXT"])
        check_dupes = (dupes + 0 != 0)
    }
    {
        sub(/\r$/, "", $0)
        if (t != "") {
            for (i = 1; i <= NF; i++) {
                cell = unquote($i)
                lower_cell = tolower(cell)
                coord = col(i) NR

                if (index(lower_cell, t) > 0) {
                    if (check_dupes) {
                        if (lower_cell in seen) {
                            print sheet "!" coord ": [DUPPLICATE of " seen[lower_cell] "] " cell
                        } else {
                            seen[lower_cell] = coord
                            print sheet "!" coord ": " cell
                        }
                    } else {
                        print sheet "!" coord ": " cell
                    }
                }
            }
        }
    }
    ' "$csv_file"
done
echo "--- End Results ---"

echo "Done."
