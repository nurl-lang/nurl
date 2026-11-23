// map: §7.6 | A2 | runs-clean | - | AGORA-953: a join over an inner field view, bound by `:` and assigned to an outer binding inside a `recover` closure that then panics: the outer binding owns a copy
// Was a heap-use-after-free under ASan on main 3f08626.
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ boom b c → i { ? c { ( panic `boom` ) } {} ^ 1 }

@ main → i {
    : ~ String t ( mk )
    : !v PanicInfo r ( recover \ → v {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        : String e ? T x ( mk )
        = t e
        : i z ( boom T )
    } )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
