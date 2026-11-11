// thread_type_name_base_whole.nu — the base of a type's name is the name
// it was declared under, whole: leading underscores included (`__Holder`),
// and for a module's type behind an alias the alias with it
// (`hm__Holder`). The rules that walk a type by its base find its fields:
// here the Send derivation, which lets a `__Counter` of an `Arc Atomic`
// cross to a thread and refuses a `__Holder` of an `Rc`
// (tools/fuzz/holes/struct_named_with_leading_underscores_holding_an_rc_captured_by_a_thread.nu,
// …struct_of_an_aliased_module_holding_an_rc_captured_by_a_thread.nu).
// What keeps the reading unambiguous is held at the declarations: no `__`
// past the leading underscores, no `_` at the end (diag_type_name_*).

$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/thread.nu`
$ `compiler/tests/alias_rewrite_types_mod.nu` geo

: __Counter { ( Arc Atomic ) hits geo::Point at }

: Two [A B] { A a B b }

@ bump __Counter c i n → v {
    : ~ i k 0
    ~ < k n { ( atomic_add ( arc_get [Atomic] . c hits ) 1 ) = k + k 1 }
}

@ main → i {
    : ( Arc Atomic ) hits ( arc_new [Atomic] ( atomic_new 0 ) )
    : __Counter mine @ __Counter { ( arc_clone [Atomic] hits ) ( geo::make_point 1 2 ) }
    : ( Two __Counter geo::Point ) theirs @ ( Two __Counter geo::Point ) { @ __Counter { ( arc_clone [Atomic] hits ) ( geo::make_point 3 4 ) } ( geo::make_point 5 6 ) }
    : i ty . . theirs b y
    ?? ( thread_spawn \ → v { ( bump . theirs a 1000 ) } ) {
        T t → { ( bump mine 1000 ) ( thread_join t ) }
        F _ → {}
    }
    ( nurl_println ( nurl_str_int ( atomic_load ( arc_get [Atomic] hits ) ) ) )
    ( nurl_println ( nurl_str_int + . . mine at x ty ) )
    ^ 0
}
