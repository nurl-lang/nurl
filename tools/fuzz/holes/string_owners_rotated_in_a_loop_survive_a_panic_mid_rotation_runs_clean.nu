// string_owners_rotated_in_a_loop_survive_a_panic_mid_rotation_runs_clean: `= t a  = a b  = b t` in a loop, with a panic between `= a b` and `= b t` in the second round, under recover.
// Closed (agora #667): each handover forgot its source's journal entry, and nothing registered it again when the source was given a value — the panic left the rotated strings to nobody (heap-use-after-free before github#1756, a leak after it). The entries are flag-gated, so they are kept and say what each name owns where the panic meets them.
// map: §7 | A2 | runs-clean | - | agora #667: three String owners rotated under recover with a panic mid-rotation; the journal had forgotten the moved-from sources
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

@ rot i n → i {
    : ~ String a ( string_from `the first string, long enough for the heap, yes` )
    : ~ String b ( string_from `the second string, long enough for the heap, yes` )
    : ~ String t ( string_from `the third string, long enough for the heap, yes` )
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        ? & == n 1 == k 1 { ( panic `mid rotation` ) } {}
        = b t
        = k + k 1
    }
    ^ + ( string_len a ) ( string_len b )
}

@ run ( @ v ) f → v { : !v PanicInfo r ( recover f ) }

@ main → i {
    ( run \ → v { : i r ( rot 1 ) } )
    ( nurl_println_int ( rot 0 ) )
    ^ 0
}
