// private_type_in_pub_generic.nu — a module's public generic struct over its
// own private type, instantiated in another file.
//
// private_type_in_pub_generic_mod.nu keeps `Impl` private and writes
// `[Impl]` inside its own generic functions. Instantiating `( GBox i )` here
// re-reads that text in synthetic lexers (`<generic_ret>`, the instance's
// rescan); AGORA-861's type-argument check must judge it where it was
// written, not refuse it here. This file never names `Impl`.
$ `compiler/tests/private_type_in_pub_generic_mod.nu`

@ main → i {
    : ( GBox i ) b ( gbox_new [i] 3 )
    : i n ( gbox_n [i] b )
    ( nurl_println ( nurl_str_int n ) )
    ^ 0
}
