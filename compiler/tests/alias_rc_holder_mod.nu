// fixture: module; alias_rc_holder_mod.nu — a struct holding an `Rc` and a
// function that clones and drops shares of it. Imported under an alias its
// `Holder` is spelled `<alias>__Holder`: a name whose base is all of it,
// not the alias (tools/fuzz/holes/struct_of_an_aliased_module_holding_an_rc_captured_by_a_thread.nu,
// thread_type_name_base_whole.nu).
$ `stdlib/std/rc.nu`

: Holder { ( Rc i ) r }

@ churn Holder h i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] . h r ) ) = j + j 1 }
        = k + k 1
    }
    ^ ( rc_strong [i] . h r )
}
