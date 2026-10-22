# shellcheck shell=bash
# ============================================================
#  unikernel/cache_trust.sh — which object cache a unikernel build may
#  link from. Sourced by build_unikernel*.sh; defines functions only.
#
#  Every image links the program-independent objects (boot shim,
#  nolibc, runtimes) from a cache shared by every build after it, so
#  whoever can write that cache can put code in every later kernel.
#  Nothing stored in the cache can vouch for it: a checksum or a stamp
#  kept next to the objects is rewritten by whoever rewrites the
#  objects. The anchor has to be something that writer cannot change,
#  and on a filesystem that is who may write at all.
#
#  The rule: a cached object is linked only if every principal that can
#  write it — the object, the cache directory, or any directory above
#  the cache — can already rewrite this build script. Those principals
#  control every image through the script; the cache adds nobody. When
#  the rule does not hold, the build compiles the objects into a fresh
#  directory of its own and links those (uk_private_dir).
#
#  Who can write a path is read from its mode bits, conservatively:
#    owner         always (an owner can chmod), so the owner of every
#                  component must be root or own part of the script's
#                  own path.
#    group write   the group's members, whoever they are — accepted
#                  only when the same group can write a directory on the
#                  script's path (umask 002 with per-user groups puts the
#                  user's own group on both), and never on a path that
#                  carries an ACL: there the group bits are the ACL mask
#                  and the named entries behind it are not visible here.
#    other write   never, except on a sticky directory (/tmp), where
#                  others may add entries but cannot rename or remove
#                  ones they do not own — and every entry below it on
#                  the path is checked in turn.
#  Cached files must be regular files writable by their owner alone.
#  Root writes everything and is trusted throughout.
#
#  zig keeps its own object cache (ZIG_GLOBAL_CACHE_DIR) and hands a
#  planted object back on a hash match without looking at it. The
#  playground's zig cache belongs to the server user, so every zig
#  invocation in a build gets a cache of its own (uk_private_dir).
#
#  Out of reach of any cache design, and not claimed: a process that
#  runs as a trusted user, or as the build's own user, WHILE a build
#  runs can rewrite that build's out-dir — the program's own object,
#  the image. The out-dir belongs to one caller; the cache is shared
#  between callers, which is why the cache is held to this rule.
# ============================================================

# `stat` prints owner, group and raw mode for each path, one line per
# path in argument order, numbers only — a hostile file name cannot
# forge a line. GNU spells it -c with the mode in hex, BSD -f in octal.
if stat -c '%u' / >/dev/null 2>&1; then
    _uk_stat() {
        local out u g m n=0
        out=$(stat -c '%u %g %f' -- "$@" 2>/dev/null) || return 1
        while read -r u g m; do
            printf '%s %s %d\n' "$u" "$g" "$((16#$m))"; n=$((n + 1))
        done <<< "$out"
        [ "$n" -eq "$#" ]
    }
else
    _uk_stat() {
        local out u g m n=0
        out=$(stat -f '%u %g %p' -- "$@" 2>/dev/null) || return 1
        while read -r u g m; do
            printf '%s %s %d\n' "$u" "$g" "$((8#$m))"; n=$((n + 1))
        done <<< "$out"
        [ "$n" -eq "$#" ]
    }
fi

# 0 when the path carries an ACL: `ls` marks it with a '+' after the
# mode (GNU, BSD and macOS alike; SELinux's '.' and macOS's '@' are not).
_uk_has_acl() {
    local m
    m=$(ls -ld -- "$1" 2>/dev/null) || return 0
    m=${m%% *}
    [ "${m:10:1}" = "+" ]
}

# _uk_components ABS — every directory from / down to ABS, inclusive,
# into _UK_COMPS. A path with a newline in it is refused outright.
_uk_components() {
    local p="$1" acc="" part
    case "$p" in /*) ;; *) return 1 ;; esac
    case "$p" in *$'\n'*) return 1 ;; esac
    _UK_COMPS=("/")
    local parts=()
    IFS=/ read -r -a parts <<< "${p#/}"
    for part in ${parts[@]+"${parts[@]}"}; do
        [ -n "$part" ] || continue
        acc="$acc/$part"
        _UK_COMPS+=("$acc")
    done
}

# uk_trust_init SCRIPT — the trusted set: root, and every principal
# that can write the script's own canonical path.
uk_trust_init() {
    local f="$1" t d u g m perms i=0
    while [ -L "$f" ]; do
        t=$(readlink -- "$f") || return 1
        case "$t" in /*) f="$t" ;; *) f="$(dirname -- "$f")/$t" ;; esac
    done
    d=$(cd -P -- "$(dirname -- "$f")" && pwd -P) || return 1
    _uk_components "$d" || return 1
    _UK_COMPS+=("$d/$(basename -- "$f")")
    _UK_TRUST_UIDS=" 0 "
    _UK_TRUST_GIDS=" "
    while read -r u g m; do
        [ "$u" != FAIL ] || return 1
        t="${_UK_COMPS[$i]}"; i=$((i + 1))
        _UK_TRUST_UIDS="$_UK_TRUST_UIDS$u "
        perms=$((m & 07777))
        # A sticky directory's writers cannot touch the entry below it.
        [ $((m & 0170000)) -eq $((0040000)) ] && [ $((perms & 01000)) -ne 0 ] && continue
        if [ $((perms & 020)) -ne 0 ] && ! _uk_has_acl "$t"; then
            _UK_TRUST_GIDS="$_UK_TRUST_GIDS$g "
        fi
    done < <(_uk_stat "${_UK_COMPS[@]}" || echo FAIL)
    [ "$i" -eq "${#_UK_COMPS[@]}" ]
}

# _uk_dirs_ok DIR... — each is a directory only trusted principals can
# write (see the rule at the top).
_uk_dirs_ok() {
    local u g m perms i=0 seen=0 p
    local paths=("$@")
    while read -r u g m; do
        p="${paths[$i]}"; i=$((i + 1))
        [ "$u" != FAIL ] || return 1
        [ $((m & 0170000)) -eq $((0040000)) ] || return 1
        case "$_UK_TRUST_UIDS" in *" $u "*) ;; *) return 1 ;; esac
        perms=$((m & 07777))
        [ $((perms & 01000)) -ne 0 ] && { seen=$((seen + 1)); continue; }
        [ $((perms & 02)) -eq 0 ] || return 1
        if [ $((perms & 020)) -ne 0 ]; then
            case "$_UK_TRUST_GIDS" in *" $g "*) ;; *) return 1 ;; esac
            _uk_has_acl "$p" && return 1
        fi
        seen=$((seen + 1))
    done < <(_uk_stat "${paths[@]}" || echo FAIL)
    [ "$seen" -eq "${#paths[@]}" ]
}

# _uk_files_ok FILE... — each is a regular file owned by a trusted
# principal and writable by its owner alone.
_uk_files_ok() {
    local u g m seen=0
    [ "$#" -gt 0 ] || return 0
    while read -r u g m; do
        [ "$u" != FAIL ] || return 1
        [ $((m & 0170000)) -eq $((0100000)) ] || return 1
        case "$_UK_TRUST_UIDS" in *" $u "*) ;; *) return 1 ;; esac
        [ $((m & 022)) -eq 0 ] || return 1
        seen=$((seen + 1))
    done < <(_uk_stat "$@" || echo FAIL)
    [ "$seen" -eq "$#" ]
}

# uk_dir_trusted DIR — 0 when DIR and every directory above it pass
# the rule: what is in DIR can then change only at a trusted hand.
uk_dir_trusted() {
    _UK_DIR=$(cd -P -- "$1" 2>/dev/null && pwd -P) || return 1
    _uk_components "$_UK_DIR" || return 1
    _uk_dirs_ok "${_UK_COMPS[@]}"
}

# uk_cache_trusted DIR — uk_dir_trusted, and every entry in DIR passes
# too. The lock file is not an input to any image and is the one entry
# exempt; anything that is not a regular file — a subdirectory, a
# symlink, a fifo — fails the cache.
uk_cache_trusted() {
    local d e
    uk_dir_trusted "$1" || return 1
    d="$_UK_DIR"
    local entries=()
    for e in "$d"/* "$d"/.[!.]* "$d"/..?*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        [ "${e##*/}" = .lock ] && continue
        entries+=("$e")
    done
    _uk_files_ok ${entries[@]+"${entries[@]}"}
}

# uk_private_dir OUTDIR — a fresh directory only this build's user can
# reach, removed when the build exits, into UK_PRIVATE; zig's object
# cache moves into it for every zig invocation of the build.
uk_private_dir() {
    UK_PRIVATE=$(mktemp -d "$1/.uk-build.XXXXXX") || return 1
    trap 'rm -rf -- "$UK_PRIVATE"' EXIT
    export ZIG_GLOBAL_CACHE_DIR="$UK_PRIVATE/zig-cache"
    export ZIG_LOCAL_CACHE_DIR="$UK_PRIVATE/zig-cache"
}
