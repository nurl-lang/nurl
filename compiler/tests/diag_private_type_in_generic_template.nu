// diag_private_type_in_generic_template.nu — AGORA-861: a generic struct's
// template is stored unparsed and first read when an instance is made, so a
// field type it names (`( Vec Impl )`, private to another module) is judged
// then, against the file that wrote the template, and refused.
$ `compiler/tests/private_type_in_generic_template_mod.nu`

@ main → i {
    : ( Vec ( GW i ) ) ws ( vec_new [( GW i )] )
    ^ ( vec_len [( GW i )] ws )
}
