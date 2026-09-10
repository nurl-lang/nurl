// Aliased types, a later nested trait import, and repeated imports must
// agree with a local declaration and emit each default exactly once.
$ `trait_order_impl_mod.nu` model
$ `trait_order_bridge_mod.nu`
$ `trait_order_impl_mod.nu` model
$ `trait_order_contract_lib.nu`

@ main → i {
    : model__IntReading a @ model__IntReading { 21 }
    : model__FloatReading z @ model__FloatReading { 2.5 }
    ( nurl_println_int ( twice a ) )
    ( nurl_println_int # i * ( twice z ) 10.0 )
    ^ 0
}
