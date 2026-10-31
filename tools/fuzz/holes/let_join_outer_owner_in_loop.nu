// let_join_outer_owner_in_loop: agora #242 — a loop body's `: String t ? c a b` over owners made before the loop: `t` takes the selected owner on its pass and must give it back where it dies, or the next pass selects a moved value (let_join_outer_owner_in_loop).
// Closed: a binding that dies still holding what its join moved in hands it back to an owner that lives on (__jpb_putback, at every scope exit; agora #242).
// main: accepted, ran clean (the binding only lent); the probe holds the give-back.
// map: §2.2 | A2 | runs-clean | - | agora #242: a loop body's `:` binding of a `?` over owners made before the loop, every pass
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `alpha string long enough for a heap buffer` )
    : String b ( string_from `beta string long enough for a heap buffer` )
    : ~ i k 0
    : ~ i n 0
    ~ < k 4 {
        : String t ? == % k 2 0 a b
        = n + n ( string_len t )
        ? == k 2 { = k + k 1 continue } {}
        = k + k 1
    }
    ( nurl_println_int n )
    ^ 0
}
