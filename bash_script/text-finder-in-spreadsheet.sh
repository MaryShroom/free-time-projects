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
EXACT=0
CASE_SENSITIVE=0

cleanup() {
    [[ -n "${TEMPDIR:-}" && -d "$TEMPDIR" ]] && rm -rf -- "$TEMPDIR"
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Helper
usage() {
    echo "Usage: ${SCRIPT_NAME} -f <text> [-d] [-x] [-c] <path-to-file>" >&2
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
        -x)
            EXACT=1
            shift
            ;;
        -c)
            CASE_SENSITIVE=1
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

if [[ -z "${FIND_TEXT//[[:space:]]/}" ]]; then
    echo "Error: -f is required and cannot be empty or whitespace only." >&2
    exit 1
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

labels=("OFF" "ON")
echo "Spreadsheet         : '$SS_FILENAME'"
echo "Text to find        : '$FIND_TEXT'"
echo "Show Duplicate Only : ${labels[CHECK_DUPES]}"
echo "Exact Matching      : ${labels[EXACT]}"
echo "Case-Sensitive      : ${labels[CASE_SENSITIVE]}"

# Temp directory and cleanup when exit
TEMPDIR=$(mktemp -d)

# Convert spreadsheet to temp csv
soffice -env:UserInstallation="file://$TEMPDIR/profile" --headless \
    --convert-to 'csv:Text - txt - csv (StarCalc):9,34,76,1,,0,false,false,false,false,false,-1' \
    --outdir "$TEMPDIR" "$SS_PATH" >/dev/null

# Check if at least one matching .csv file exists
if ! compgen -G "$TEMPDIR/*.csv" >/dev/null; then
    echo "Error: soffice produced no .csv files in '$TEMPDIR'." >&2
    exit 1
fi

# Search all sheets in one pass
base="${SS_FILENAME%.*}"
echo "----- Results -----"

# Find text with its coordinate
LC_ALL=C.UTF-8 BASE="$base" FIND_TEXT="$FIND_TEXT" awk -F'\t' \
    -v dupes="$CHECK_DUPES" \
    -v exact="$EXACT" \
    -v casesens="$CASE_SENSITIVE" '
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
FNR == 1 {
    sheet = FILENAME
    sub(/^.*\//, "", sheet)                      # drop directory
    sheet = substr(sheet, length(base) + 2)      # drop "<base>-"
    sheet = substr(sheet, 1, length(sheet) - 4)  # drop ".csv"
}
BEGIN {
    case_sens = (casesens + 0 != 0)
    check_dupes = (dupes + 0 != 0)
    exact_match = (exact + 0 != 0)
    base = ENVIRON["BASE"]
    t = ENVIRON["FIND_TEXT"]
    gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (!case_sens) t = tolower(t)
}
{
    sub(/\r$/, "", $0)
    if (t != "") {
        for (i = 1; i <= NF; i++) {
            cell = unquote($i)
            gsub(/^[ \t]+|[ \t]+$/, "", cell)
            key = case_sens ? cell : tolower(cell)
            coord = sheet "!" col(i) FNR

            hit = exact_match ? (key == t) : (index(key, t) > 0)
            if (hit) {
                if (key in seen) {
                    print coord ": [DUPLICATE of " seen[key] "] " cell
                    dup_count++
                } else {
                    seen[key] = coord
                    if (!check_dupes) {
                        print coord ": " cell
                    }
                }
            }
        }
    }
}
END { print (dup_count + 0) " duplicate(s) found" }
' "$TEMPDIR"/*.csv

echo "--- End Results ---"

echo "Done."
