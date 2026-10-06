// raw_lend_back_temp.nu — a raw string temporary its callee may hand back.
// `( maybe_view ( mk n ) )`: the callee returns its argument on one path and
// a fresh string on the other, so the argument cannot be dropped after the
// call, and nothing else owned it — it leaked on every call. Per call: the
// result IS the temporary → the temporary becomes the result's owner (a
// binding, a consuming argument, a join arm or a return frees it); the
// result is some other address the callee did not allocate (a view into
// the argument) → the temporary lives until the function returns; the
// result is the callee's own → the temporary is dropped. The sanitizer
// corpus runs this with leak detection.
$ `stdlib/core/string.nu`

@ mk i n → s {
    : ~ s out ( nurl_str_cat `` `` )
    : ~ i k 0
    ~ < k n { = out ( nurl_str_cat out `x` ) = k + k 1 }
    ^ out
}

@ maybe_view s x → s { ? > ( nurl_str_len x ) 100 { ^ x } {} ^ ( nurl_str_cat x `!` ) }

unsafe

@ tail_view s x → s { ? > ( nurl_str_len x ) 100 { ^ # s + # i x 1 } {} ^ ( nurl_str_cat x `!` ) }

@ pick i n → i { : s r ( maybe_view ( mk n ) ) ^ ( nurl_str_len r ) }

@ pick2 i n → i { ^ ( nurl_str_len ( maybe_view ( mk n ) ) ) }

@ pick3 b c i n → i { : s r ? c ( maybe_view ( mk n ) ) ( mk n ) ^ ( nurl_str_len r ) }

@ vpick i n → i { : s r ( tail_view ( mk n ) ) ^ ( nurl_str_len r ) }

@ vpick2 i n → i { ^ ( nurl_str_len ( tail_view ( mk n ) ) ) }

@ out i n → s { : s r ( maybe_view ( mk n ) ) ^ r }

@ out2 i n → s { ^ ( maybe_view ( mk n ) ) }

@ chain i n → i { ^ ( nurl_str_len ( maybe_view ( maybe_view ( mk n ) ) ) ) }

@ in_loop i n → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 5 { : s r ( maybe_view ( mk n ) ) = t + t ( nurl_str_len r ) = k + k 1 }
    ~ < k 10 { : s r ( tail_view ( mk n ) ) = t + t ( nurl_str_len r ) = k + k 1 }
    ^ t
}

@ main → i {
    : ~ i t 0
    : ~ i n 5
    : ~ i j 0
    ~ < j 2 {
        = t + t ( pick n ) = t + t ( pick2 n ) = t + t ( pick3 T n ) = t + t ( pick3 F n )
        = t + t ( vpick n ) = t + t ( vpick2 n ) = t + t ( chain n ) = t + t ( in_loop n )
        : s a ( out n ) : s b ( out2 n )
        = t + t + ( nurl_str_len a ) ( nurl_str_len b )
        = n 150 = j + j 1
    }
    ( nurl_print_int t ) ( nurl_print `\n` )
    ^ 0
}
