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

unsafe @ tail_view s x → s { ? > ( nurl_str_len x ) 100 { ^ # s + # i x 1 } {} ^ ( nurl_str_cat x `!` ) }

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

// A callee that hands over its result on NO path answers "not owned"
// without being asked (`__ret_unowned`: its callers do not ask it per
// call), and its result may still be the temporary or point into it. The
// same three outcomes hold for it: `always_view` hands back its argument,
// `always_tail` a view into it, `first_x` what `strstr` finds in it.
@ always_view s x → s { ^ x }

unsafe @ always_tail s x → s { ^ # s + # i x 1 }

unsafe @ first_x s x → s { ^ ( strstr x `x` ) }

@ upick i n → i { : s r ( always_view ( mk n ) ) ^ ( nurl_str_len r ) }

@ upick2 i n → i { ^ ( nurl_str_len ( always_view ( mk n ) ) ) }

@ upick3 b c i n → i { : s r ? c ( always_view ( mk n ) ) ( mk n ) ^ ( nurl_str_len r ) }

@ utail i n → i { : s r ( always_tail ( mk n ) ) ^ ( nurl_str_len r ) }

@ utail2 i n → i { ^ ( nurl_str_len ( always_tail ( mk n ) ) ) }

@ ufind i n → i { : s r ( first_x ( mk n ) ) ^ ( nurl_str_len r ) }

@ uout i n → s { : s r ( always_view ( mk n ) ) ^ r }

@ uout2 i n → s { ^ ( always_view ( mk n ) ) }

@ uchain i n → i { ^ ( nurl_str_len ( always_view ( always_view ( mk n ) ) ) ) }

@ uloop i n → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 5 { : s r ( always_view ( mk n ) ) = t + t ( nurl_str_len r ) = k + k 1 }
    ~ < k 10 { : s r ( first_x ( mk n ) ) = t + t ( nurl_str_len r ) = k + k 1 }
    ^ t
}

// An instance of a generic callee is compiled after its callers: nothing
// about its result is known at the call, so the call asks it, as it asks
// any NURL body (tools/fuzz/holes h105).
@ gview [T] T tag s x → s { ^ x }

@ gmaybe [T] T tag s x → s { ? > ( nurl_str_len x ) 100 { ^ x } {} ^ ( nurl_str_cat x `!` ) }

@ gpick i n → i { : s r ( gview [i] 0 ( mk n ) ) ^ ( nurl_str_len r ) }

@ gpick2 i n → i { ^ ( nurl_str_len ( gmaybe [i] 0 ( mk n ) ) ) }

@ gout i n → s { ^ ( gview [i] 0 ( mk n ) ) }

@ gloop i n → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 5 { : s r ( gmaybe [i] 0 ( mk n ) ) = t + t ( nurl_str_len r ) = k + k 1 }
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
    : ~ i u 0
    = n 5
    = j 0
    ~ < j 2 {
        = u + u ( upick n ) = u + u ( upick2 n ) = u + u ( upick3 T n ) = u + u ( upick3 F n )
        = u + u ( utail n ) = u + u ( utail2 n ) = u + u ( ufind n )
        = u + u ( uchain n ) = u + u ( uloop n )
        : s a ( uout n ) : s b ( uout2 n )
        = u + u + ( nurl_str_len a ) ( nurl_str_len b )
        = n 150 = j + j 1
    }
    ( nurl_print_int u ) ( nurl_print `\n` )
    : ~ i g 0
    = n 5
    = j 0
    ~ < j 2 {
        = g + g ( gpick n ) = g + g ( gpick2 n ) = g + g ( gloop n )
        : s c ( gout n )
        = g + g ( nurl_str_len c )
        = n 150 = j + j 1
    }
    ( nurl_print_int g ) ( nurl_print `\n` )
    ^ 0
}
