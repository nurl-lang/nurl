// self_recursion_handing_back_a_view_when_a_trusted_generic_is_compiled_last: a self-recursive function hands back a Vec viewing one of its String parameters, swapped at each call; the stdlib's unsafe mem_replace, reached through a safe generic called at main's end, is compiled last.
// Closed: the recursion's answer is its least fixed point (__bck_walk_scc), not "may" read through __rv_holder_result, whose class read stale codegen state (bck_unsafe_ctx) during the parked walks and answered 0.
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: a self-recursive holder of a swapped String parameter's view, a trusted generic compiled last
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`

@ w1 [T] inout T z T x → T { ^ ( mem_replace [T] z x ) }

@ fr String a String b i n → ( Vec s ) {
    ? == n 0 {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h ( string_data a ) )
        ^ h
    } {}
    ^ ( fr b a - n 1 )
}

@ main → i {
    : String a ( string_from `the long-lived heap string, long enough for the heap surely` )
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String b ( string_from `the short-lived heap string, long enough for the heap surely` )
        = hold ( fr a b 1 )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    : ~ i z 3
    ( w1 [i] z 0 )
    ^ 0
}
