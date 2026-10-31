// let_join_sunk_then_selected_again_in_loop: agora #242 (formal's review) — in a loop, `: String t ? == 0 % k 2 a b` takes the owner its arm selects; on the first pass `t` goes to a `sink`, so the give-back never runs and `a` stays moved; the third pass selects `a` again (let_join_sunk_then_selected_again_in_loop).
// Closed: a `?` arm's value is read where its arm ends (bck_handle_cond), and the give-back is in the walk (bck_join_giveback): a path that moves `t` out never gives `a` back, so the next pass's `? … a b` reads a maybe-moved `a` — A2's `ite c (letv t (var a) …) (letv t (var b) …)`, `moveOwn` per path.
// main: accepted; AddressSanitizer reported heap-use-after-free (the next pass's `?` read the moved `a`).
// map: §2.2 | A2 | rejected | - | agora #242: a `:` join's binding sunk on one pass, its owner selected again on a later pass
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : ~ i k 0
    : ~ i n 0
    ~ < k 3 {
        : String t ? == 0 % k 2 a b
        = n + n ( string_len t )
        ? == k 0 { = n + n ( consume t ) } {}
        = k + k 1
    }
    ^ n
}
