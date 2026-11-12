// A struct of an aliased module that holds an Rc of another of its structs
// is released with its binding (agora #724). The generic-struct scan read
// the module as written and made an instance `Rc__Pt` beside the module's
// own `Rc__vp__Pt`, and the payload was never released (LSan: 40 bytes).
$ `stdlib/std/rc.nu`
$ `compiler/tests/aliased_module_rc_of_its_own_struct_mod.nu` vp

@ main → i {
    : vp::Hold h ( vp::hold_new 4 )
    ( nurl_println_int ( vp::hold_sum h ) )
    ^ 0
}
