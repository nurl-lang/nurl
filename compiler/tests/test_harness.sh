#!/usr/bin/env bash
# Shared compiler invocation and worker protocol for both corpus runners.
# A compiler rejection is exit 1; crashes, watchdogs and tool errors are
# infrastructure failures and must never become COMPILE FAIL goldens.
# A runner invocation owns every generated artifact, including same-test IR,
# binaries, scratch directories and the worker verdict protocol. Per-test names
# only isolate workers within ONE invocation; concurrent runners need this outer
# namespace too. Keep it after completion so printed failure paths stay useful.
create_test_workdir() {
    local base="$1"
    mkdir -p "$base" || return 2
    mktemp -d "$base/run.XXXXXXXX" || return 2
}

# Publish complete records atomically. A check running beside --update must
# never observe a truncated golden; two updates each publish one whole record.
publish_test_golden() {
    local actual="$1" golden="$2" temporary
    temporary=$(mktemp "${golden}.tmp.XXXXXXXX") || return 1
    if cp -p "$actual" "$temporary" && mv -f "$temporary" "$golden"; then
        return 0
    fi
    rm -f "$temporary"
    return 1
}

init_test_harness() {
    NURL_COMPILE_TIMEOUT="${NURL_COMPILE_TIMEOUT:-60}"
    TIMEOUT_CMD=""
    if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD=timeout
    elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD=gtimeout
    else
        echo 'ERROR: tests require timeout (on macOS: brew install coreutils).' >&2
        return 2
    fi
    if ! awk -v t="$NURL_COMPILE_TIMEOUT" 'BEGIN { exit !(t ~ /^[0-9]+([.][0-9]+)?$/ && t > 0) }'; then
        echo 'ERROR: NURL_COMPILE_TIMEOUT must be a positive number of seconds.' >&2
        return 2
    fi
    export NURL_COMPILE_TIMEOUT TIMEOUT_CMD
}

compile_test() {
    local name="$1" src="$2" flag
    shift 2
    flag=$(test_compiler_flag "$name")
    "$TIMEOUT_CMD" -k 1s "${NURL_COMPILE_TIMEOUT}s" "$NURLC" "$@" ${flag:+"$flag"} "$src"
}

test_compiler_flag() {
    case "$1" in
        borrow_strict_*) echo --strict-borrowck ;;
        nobck_*) echo --no-borrowck ;;
        lint_*) echo --lint ;;
        arity_strict_*) echo --strict-arity ;;
    esac
}

# Validate the selected input BEFORE workers can write overlapping outputs.
validate_test_selection() {
    local name mode
    for name in "$@"; do
        if [[ ! "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ || ! -f "$SCRIPT_DIR/$name.nu" ]]; then
            echo "ERROR: unknown or invalid test: $name" >&2
            return 2
        fi
        mode=$(test_mode "$name")
        case "$mode" in
            module)
                if [[ -f "$SCRIPT_DIR/outputs/$name.txt" || -f "$SCRIPT_DIR/outputs-windows/$name.txt" ]]; then
                    echo "ERROR: module has a test golden: $name" >&2; return 2
                fi ;;
            reject|compile|run) ;;
            *) echo "ERROR: invalid test mode for $name: $mode" >&2; return 2 ;;
        esac
    done
    printf '%s\n' "$@" | awk 'seen[$0]++ { print "ERROR: duplicate selected test: " $0; bad=1 } END { exit bad }' >&2
}

# The result stream is a protocol, not best-effort log parsing. Reject
# missing/duplicate/unknown records, including those from crashed workers.
validate_test_verdicts() {
    local selected="$1" verdicts="$2" allowed="$3"
    awk -v allowed="$allowed" '
        NR == FNR { selected[$0]=1; next }
        NF != 2 || !($1 in selected) || index(" " allowed " ", " " $2 " ") == 0 {
            print "ERROR: invalid verdict: " $0; bad=1; next
        }
        { count[$1]++ }
        END {
            for (name in selected) if (count[name] != 1) {
                print "ERROR: expected one verdict for " name ", got " (count[name]+0); bad=1
            }
            exit bad
        }' "$selected" "$verdicts" >&2
}
export -f compile_test test_compiler_flag publish_test_golden
