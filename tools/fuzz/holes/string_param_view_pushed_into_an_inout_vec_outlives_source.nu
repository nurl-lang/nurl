// string_param_view_pushed_into_an_inout_vec_outlives_source: agora #301 — an `inout` callee pushes a view of a String parameter's buffer into the caller's Vec of views; the String ends in a block, the element is read after it.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: an `inout` callee pushes a view of a String parameter's buffer into the caller's Vec of views; the String ends in a block, the element is read after it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ add inout ( Vec s ) vs String src → v { ( vec_push [s] vs ( string_data src ) ) }

@ main → i {
    : ~ ( Vec s ) vs ( vec_new [s] )
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( add vs b )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
