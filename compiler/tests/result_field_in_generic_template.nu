// result_field_in_generic_template.nu — AGORA-861's template check reads a
// struct body as `type name` pairs; a result type `! A B` has two types
// before its name. RB's field `! A B Impl` is named `Impl`, which is also a
// type private to another module: instantiating RB must compile.
$ `compiler/tests/result_field_in_generic_template_mod.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( RB i i ) ) ws ( vec_new [( RB i i )] )
    ( nurl_println ( nurl_str_int ( vec_len [( RB i i )] ws ) ) )
    ^ 0
}
