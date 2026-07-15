// A diagnostic that fires INSIDE a `??` match arm panics out of the open
// function/arm symbol-table scopes. The recovery frame must pop those
// leaked scopes before compiling the next declaration: gen_match's
// synthetic `__matchtmp<n>__res_nurl_T` payload keys otherwise survive,
// and — because the label counter numbering them resets per function —
// the SAME-numbered option match below would read the dead arm's
// `Widget` and type its payload `t0 : %Widget`, reporting a phantom
// "type 'Widget' has no field 'a'" here instead of just the real error
// in the module. Golden pins exactly ONE error, located in the module.

$ `stdlib/core/vec.nu`
$ `compiler/tests/diag_match_arm_recover_mod.nu`

: Thing {
    i a
}

@ user → i {
    : ( Vec Thing ) ts ( vec_new [Thing] )
    : ~ i out 0
    ?? ( vec_get [Thing] ts 0 ) {
        T t0 → { = out . t0 a }
        F → {}
    }
    ( vec_free [Thing] ts )
    ^ out
}

@ main → i {
    ^ ( user )
}
