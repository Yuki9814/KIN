#!/bin/bash

# Read-only gate for the two signed products that are intended to share a
# private CloudKit container. This script never contacts CloudKit.

set -u
set -o pipefail

readonly STATUS_PASS="PASS"
readonly STATUS_FAIL="FAIL"
readonly STATUS_INCONCLUSIVE="INCONCLUSIVE"

macos_input=""
ios_input=""
positional_inputs=()

usage() {
    cat <<'EOF'
Usage: scripts/verify-cloudkit-readiness.sh --macos PATH --ios PATH
       scripts/verify-cloudkit-readiness.sh MACOS.app IOS.app

PATH may be a signed .app directory, or an archive containing exactly one app
(.ipa/.zip). The gate is read-only and does not contact CloudKit.

Exit status:
  0  PASS
  1  FAIL (both artifacts were supplied, but a check failed)
  2  INCONCLUSIVE (an artifact is missing or the gate cannot inspect it)
  64 invalid command-line usage
EOF
}

report() {
    printf '%s\n' "$*"
}

command_path() {
    command -v "$1" 2>/dev/null || true
}

require_option_value() {
    local option="$1"
    if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        report "ERROR: $option requires a path."
        usage >&2
        exit 64
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --macos|-m)
            require_option_value "$@"
            macos_input="$2"
            shift 2
            ;;
        --ios|-i)
            require_option_value "$@"
            ios_input="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                positional_inputs+=("$1")
                shift
            done
            ;;
        -*)
            report "ERROR: unknown option: $1"
            usage >&2
            exit 64
            ;;
        *)
            positional_inputs+=("$1")
            shift
            ;;
    esac
done

if [ "${#positional_inputs[@]}" -gt 0 ]; then
    if [ -n "$macos_input" ] || [ -n "$ios_input" ] || [ "${#positional_inputs[@]}" -ne 2 ]; then
        report "ERROR: use either two positional paths or --macos/--ios."
        usage >&2
        exit 64
    fi
    macos_input="${positional_inputs[0]}"
    ios_input="${positional_inputs[1]}"
fi

missing_tool=0
for tool in codesign plutil mktemp; do
    if [ -z "$(command_path "$tool")" ]; then
        report "INCONCLUSIVE: required tool is unavailable: $tool"
        missing_tool=1
    fi
done
if [ -z "$(command_path unzip)" ]; then
    report "INCONCLUSIVE: required tool is unavailable: unzip"
    missing_tool=1
fi
if [ ! -x /usr/libexec/PlistBuddy ]; then
    report "INCONCLUSIVE: required tool is unavailable: /usr/libexec/PlistBuddy"
    missing_tool=1
fi
if [ "$missing_tool" -ne 0 ]; then
    exit 2
fi

workspace_tmp="$(mktemp -d "${TMPDIR:-/tmp}/cloudkit-readiness.XXXXXX")" || {
    report "INCONCLUSIVE: unable to create a temporary inspection directory."
    exit 2
}

cleanup() {
    if [ -n "${workspace_tmp:-}" ] && [ -d "$workspace_tmp" ]; then
        rm -rf "$workspace_tmp"
    fi
}
trap cleanup EXIT HUP INT TERM

macos_team=""
ios_team=""
macos_container=""
ios_container=""
macos_ok=1
ios_ok=1
inconclusive=0
failed=0

trim() {
    # PlistBuddy prints array values with indentation. Container IDs and
    # entitlement values cannot contain leading/trailing whitespace.
    printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

is_valid_container_identifier() {
    case "$1" in
        iCloud.[A-Za-z0-9]* )
            # The shell pattern above intentionally only establishes the
            # prefix/non-empty shape; this regex rejects punctuation outside
            # Apple's container identifier character set.
            printf '%s\n' "$1" | /usr/bin/grep -Eq '^iCloud\.[A-Za-z0-9][A-Za-z0-9.-]*$'
            ;;
        *)
            return 1
            ;;
    esac
}

plist_scalar() {
    local keypath="$1"
    local plist_path="$2"
    /usr/libexec/PlistBuddy -c "Print :$keypath" "$plist_path" 2>/dev/null || true
}

plist_type() {
    local keypath="$1"
    local plist_path="$2"
    local value_dump
    local first_line

    value_dump="$(/usr/libexec/PlistBuddy -c "Print :$keypath" "$plist_path" 2>/dev/null || true)"
    first_line="$(printf '%s\n' "$value_dump" | sed -n '1p')"
    case "$first_line" in
        "Array {") printf '%s\n' 'Array' ;;
        "Dict {") printf '%s\n' 'Dict' ;;
        "") printf '%s\n' '' ;;
        *) printf '%s\n' 'Scalar' ;;
    esac
}

plist_array_contains() {
    local keypath="$1"
    local expected="$2"
    local plist_path="$3"
    local array_dump
    local array_line
    local array_value

    array_dump="$(/usr/libexec/PlistBuddy -c "Print :$keypath" "$plist_path" 2>/dev/null || true)"
    while IFS= read -r array_line; do
        array_value="$(trim "$array_line")"
        case "$array_value" in
            ""|"Array {"|"Dict {"|"}"|"}"*)
                continue
                ;;
        esac
        if [ "$array_value" = "$expected" ]; then
            return 0
        fi
    done <<< "$array_dump"
    return 1
}

plist_array_values() {
    local keypath="$1"
    local plist_path="$2"
    local array_dump
    local array_line
    local array_value

    array_dump="$(/usr/libexec/PlistBuddy -c "Print :$keypath" "$plist_path" 2>/dev/null || true)"
    while IFS= read -r array_line; do
        array_value="$(trim "$array_line")"
        case "$array_value" in
            ""|"Array {"|"Dict {"|"}"|"}"*)
                continue
                ;;
        esac
        printf '%s\n' "$array_value"
    done <<< "$array_dump"
}

extract_app() {
    local artifact="$1"
    local role="$2"
    local app_output="$3"
    local archive_dir
    local app_candidates_file
    local app_count
    local extracted_app

    if [ -d "$artifact" ]; then
        case "$artifact" in
            *.app)
                printf '%s\n' "$artifact" > "$app_output"
                return 0
                ;;
            *)
                report "FAIL [$role]: expected a .app directory, got: $artifact"
                return 1
                ;;
        esac
    fi

    if [ ! -f "$artifact" ]; then
        report "INCONCLUSIVE [$role]: artifact is missing: $artifact"
        inconclusive=1
        return 2
    fi

    case "$artifact" in
        *.ipa|*.zip)
            archive_dir="$workspace_tmp/${role}-archive"
            mkdir -p "$archive_dir" || {
                report "INCONCLUSIVE [$role]: unable to create archive inspection directory."
                inconclusive=1
                return 2
            }
            if ! unzip -q "$artifact" -d "$archive_dir" >/dev/null 2>&1; then
                report "FAIL [$role]: unable to read archive: $artifact"
                failed=1
                return 1
            fi
            app_candidates_file="$workspace_tmp/${role}-apps"
            find "$archive_dir" -type d -name '*.app' -print > "$app_candidates_file"
            app_count="$(wc -l < "$app_candidates_file" | tr -d '[:space:]')"
            if [ "$app_count" -ne 1 ]; then
                report "FAIL [$role]: archive must contain exactly one .app (found $app_count)."
                failed=1
                return 1
            fi
            IFS= read -r extracted_app < "$app_candidates_file"
            printf '%s\n' "$extracted_app" > "$app_output"
            return 0
            ;;
        *)
            report "FAIL [$role]: expected .app, .ipa, or .zip: $artifact"
            failed=1
            return 1
            ;;
    esac
}

inspect_artifact() {
    local role="$1"
    local artifact="$2"
    local app_path_file="$workspace_tmp/${role}-app-path"
    local entitlements_file="$workspace_tmp/${role}-entitlements.plist"
    local signature_file="$workspace_tmp/${role}-signature.txt"
    local signature_error_file="$workspace_tmp/${role}-signature-error.txt"
    local info_plist=""
    local team=""
    local entitlement_team=""
    local signature_team=""
    local container=""
    local extract_status=0
    local app_path
    local containers_file
    local container_count
    local unique_count
    local aps=""
    local failed_before="$failed"

    if [ -z "$artifact" ]; then
        report "INCONCLUSIVE [$role]: no artifact path was supplied."
        inconclusive=1
        return 2
    fi

    extract_app "$artifact" "$role" "$app_path_file" || extract_status=$?
    if [ "$extract_status" -ne 0 ]; then
        if [ "$extract_status" -eq 1 ]; then
            failed=1
        fi
        return "$extract_status"
    fi
    IFS= read -r app_path < "$app_path_file"

    if [ "$role" = "macOS" ]; then
        info_plist="$app_path/Contents/Info.plist"
        if [ ! -d "$app_path/Contents" ] || [ ! -f "$info_plist" ]; then
            report "FAIL [$role]: not a macOS app bundle: $app_path"
            failed=1
            return 1
        fi
    else
        info_plist="$app_path/Info.plist"
        if [ -d "$app_path/Contents" ] || [ ! -f "$info_plist" ]; then
            report "FAIL [$role]: not an iOS app bundle: $app_path"
            failed=1
            return 1
        fi
    fi

    if ! /usr/bin/plutil -lint -s -- "$info_plist" >/dev/null 2>&1; then
        report "FAIL [$role]: Info.plist is missing or invalid: $info_plist"
        failed=1
        return 1
    fi

    if ! codesign --verify --deep --strict --verbose=2 "$app_path" > /dev/null 2> "$signature_error_file"; then
        report "FAIL [$role]: code signature verification failed: $app_path"
        sed 's/^/  codesign: /' "$signature_error_file" >&2
        failed=1
        return 1
    fi

    if ! codesign -dv --verbose=4 "$app_path" > "$signature_file" 2>&1; then
        report "FAIL [$role]: signed metadata could not be read: $app_path"
        failed=1
        return 1
    fi

    if ! codesign -d --entitlements :- "$app_path" > "$entitlements_file" 2> "$signature_error_file"; then
        report "FAIL [$role]: signed entitlements could not be read: $app_path"
        sed 's/^/  codesign: /' "$signature_error_file" >&2
        failed=1
        return 1
    fi
    if ! /usr/bin/plutil -lint -s -- "$entitlements_file" >/dev/null 2>&1; then
        report "FAIL [$role]: signed entitlements are not a valid plist: $app_path"
        failed=1
        return 1
    fi

    if [ "$(plist_type 'com.apple.developer.team-identifier' "$entitlements_file")" = "Scalar" ]; then
        entitlement_team="$(plist_scalar 'com.apple.developer.team-identifier' "$entitlements_file")"
    fi
    signature_team="$(sed -n 's/^TeamIdentifier=//p' "$signature_file" | head -n 1 | tr -d '[:space:]')"
    team="$signature_team"
    if [ -z "$team" ] || [ "$team" = "notset" ] || [ "$team" = "not-set" ]; then
        report "FAIL [$role]: signed Team identifier is empty or not set."
        failed=1
    elif [ -n "$entitlement_team" ] && [ "$entitlement_team" != "$signature_team" ]; then
        report "FAIL [$role]: Team identifier in entitlements does not match the signature."
        failed=1
    else
        report "PASS [$role]: signed Team identifier is present ($team)."
    fi

    if [ "$(plist_type 'com.apple.developer.icloud-container-identifiers' "$entitlements_file")" != "Array" ]; then
        report "FAIL [$role]: CloudKit container entitlement is not an array."
        failed=1
    else
        containers_file="$workspace_tmp/${role}-containers"
        plist_array_values 'com.apple.developer.icloud-container-identifiers' "$entitlements_file" > "$containers_file"
        container_count="$(wc -l < "$containers_file" | tr -d '[:space:]')"
        unique_count="$(sort -u "$containers_file" | wc -l | tr -d '[:space:]')"
        if [ "$container_count" -ne 1 ] || [ "$unique_count" -ne 1 ]; then
            report "FAIL [$role]: exactly one unique CloudKit container is required (found $container_count entries, $unique_count unique)."
            failed=1
        else
            IFS= read -r container < "$containers_file"
            if ! is_valid_container_identifier "$container"; then
                report "FAIL [$role]: invalid CloudKit container identifier: $container"
                failed=1
            else
                report "PASS [$role]: one valid CloudKit container is present ($container)."
            fi
        fi
    fi

    if [ "$(plist_type 'com.apple.developer.icloud-services' "$entitlements_file")" != "Array" ] \
        || ! plist_array_contains 'com.apple.developer.icloud-services' 'CloudKit' "$entitlements_file"; then
        report "FAIL [$role]: CloudKit is not enabled in iCloud services entitlement."
        failed=1
    else
        report "PASS [$role]: CloudKit iCloud service entitlement is present."
    fi

    if [ "$role" = "iOS" ]; then
        if [ "$(plist_type 'aps-environment' "$entitlements_file")" = "Scalar" ]; then
            aps="$(plist_scalar 'aps-environment' "$entitlements_file")"
        fi
        if [ -z "$aps" ] && [ "$(plist_type 'com.apple.developer.aps-environment' "$entitlements_file")" = "Scalar" ]; then
            aps="$(plist_scalar 'com.apple.developer.aps-environment' "$entitlements_file")"
        fi
        if [ -z "$aps" ]; then
            report "FAIL [$role]: aps-environment entitlement is empty or missing."
            failed=1
        else
            report "PASS [$role]: aps-environment entitlement is present ($aps)."
        fi

        if [ "$(plist_type 'UIBackgroundModes' "$info_plist")" != "Array" ] \
            || ! plist_array_contains 'UIBackgroundModes' 'remote-notification' "$info_plist"; then
            report "FAIL [$role]: UIBackgroundModes does not include remote-notification."
            failed=1
        else
            report "PASS [$role]: iOS remote-notification background mode is present."
        fi
    fi

    if [ "$role" = "macOS" ]; then
        macos_team="$team"
        macos_container="$container"
    else
        ios_team="$team"
        ios_container="$container"
    fi

    if [ "$failed" -ne "$failed_before" ]; then
        return 1
    fi
    return 0
}

report "CloudKit readiness: read-only signed-artifact gate"
report "macOS input: ${macos_input:-<missing>}"
report "iOS input: ${ios_input:-<missing>}"

inspect_artifact "macOS" "$macos_input" || macos_ok=0
inspect_artifact "iOS" "$ios_input" || ios_ok=0

if [ "$macos_ok" -eq 1 ] && [ "$ios_ok" -eq 1 ]; then
    if [ -z "$macos_team" ] || [ -z "$ios_team" ]; then
        report "FAIL: both signed Team identifiers must be non-empty."
        failed=1
    elif [ "$macos_team" != "$ios_team" ]; then
        report "FAIL: macOS and iOS Team identifiers differ ($macos_team vs $ios_team)."
        failed=1
    else
        report "PASS: macOS and iOS Team identifiers match ($macos_team)."
    fi

    if [ -z "$macos_container" ] || [ -z "$ios_container" ]; then
        report "FAIL: both artifacts must expose one CloudKit container."
        failed=1
    elif [ "$macos_container" != "$ios_container" ]; then
        report "FAIL: macOS and iOS CloudKit containers differ ($macos_container vs $ios_container)."
        failed=1
    else
        report "PASS: both artifacts expose the same unique CloudKit container ($macos_container)."
    fi
fi

if [ "$inconclusive" -ne 0 ]; then
    report "RESULT: $STATUS_INCONCLUSIVE"
    exit 2
fi
if [ "$failed" -ne 0 ] || [ "$macos_ok" -ne 1 ] || [ "$ios_ok" -ne 1 ]; then
    report "RESULT: $STATUS_FAIL"
    exit 1
fi

report "RESULT: $STATUS_PASS"
exit 0
