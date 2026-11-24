// fall_off_join_with_a_sizeof_condition_runs_clean: AGORA-866 — a fall-off `? > Z D 0 l x`, the condition measuring a type
// Closed: the join's extent is read on tokens, `Z T` (sizeof) one value (the keyword and its type), so the join returns as `^` of it does and the local moves out on its path.
// Earlier: refused as "a borrowed 'D' would have to be copied here" (the tail scan gave up on `Z`, and the join was taken as a statement).
// map: §7.6 | A2 | runs-clean | - | AGORA-866: a fall-off join whose condition is `Z` (sizeof)
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick D x → D {
    : D l @ D { ( string_from `local string long enough for a heap buffer` ) }
    ? > Z D 0 l x
}

@ main → i {
    : D d @ D { ( string_from `outer string long enough for a heap buffer` ) }
    : D r ( pick d )
    ( nurl_println_int + ( string_len . r s ) ( string_len . d s ) )
    ^ 0
}
