// return_after_param_ternary.nu — a ternary that selects a parameter in an
// EARLIER statement does not make the function's result an alias of it.
//
// `foo_a` / `foo_b` build a handle exactly like `foo_c`; the only
// difference is a `?` that picks the parameter `max` before the return
// (`= . p max ? > max 0 max 64`, or a local). `:` and `=` cleared the
// join channel before their right-hand side but `^` did not, so the
// stale join was read as "`^ @ Foo { … }` may return argument 0": the
// caller's binding did not own the handle and never dropped it (+10 per
// 10 rounds). Found converting stdlib/net/arp.nu's arp_cache_new.
$ `stdlib/core/string.nu`
$ `stdlib/core/rcbox.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: FooImpl { i max }

: Foo { s ctl }

@ Foo_share Foo h → Foo { ^ @ Foo { # s ( rcbox_share # i . h ctl ) } }

@ Foo_drop sink Foo h → v {
    ( mem_forget h )
    ( rcbox_release [FooImpl] # i . h ctl )
}

// a field store of a ternary that selects the parameter
@ foo_a i max → Foo {
    : i box ( rcbox_zero [FooImpl] )
    : *FooImpl p ( rcbox_ptr [FooImpl] box )
    = . p max ? > max 0 max 64
    ^ @ Foo { # s box }
}

// the same ternary into a local that is never returned
@ foo_b i max → Foo {
    : i box ( rcbox_zero [FooImpl] )
    : *FooImpl p ( rcbox_ptr [FooImpl] box )
    : i m ? > max 0 max 64
    = . p max m
    ^ @ Foo { # s box }
}

// no ternary selecting a parameter: correct
@ foo_c i max → Foo {
    : i box ( rcbox_zero [FooImpl] )
    : *FooImpl p ( rcbox_ptr [FooImpl] box )
    = . p max ? > max 0 1 64
    ^ @ Foo { # s box }
}

@ ra → v { : Foo c ( foo_a 8 ) }

@ rb → v { : Foo c ( foo_b 8 ) }

@ rc → v { : Foo c ( foo_c 8 ) }

@ show s name i d → v { ( nurl_println ( nurl_str_cat name ( nurl_str_int d ) ) ) }

@ main → i {
    : ~ i l0 ( live )
    : ~ i k 0
    ~ < k 10 { ( ra ) = k + k 1 }
    ( show `a ` - ( live ) l0 )
    = l0 ( live ) = k 0
    ~ < k 10 { ( rb ) = k + k 1 }
    ( show `b ` - ( live ) l0 )
    = l0 ( live ) = k 0
    ~ < k 10 { ( rc ) = k + k 1 }
    ( show `c ` - ( live ) l0 )
    ^ 0
}
