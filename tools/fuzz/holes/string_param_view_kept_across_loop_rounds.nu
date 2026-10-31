// string_param_view_kept_across_loop_rounds: agora #301 — an `inout` callee given a String made and freed each loop round; the holder read after the loop.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: an `inout` callee given a String made and freed each loop round; the holder read after the loop
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    : ~ i k 0
    ~ < k 3 {
        : String b ( string_from `a string made and freed each round` )
        ( repoint w b )
        = k + k 1
    }
    ( nurl_println . w v )
    ^ 0
}
