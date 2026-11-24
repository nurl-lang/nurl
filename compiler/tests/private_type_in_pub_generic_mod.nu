// fixture: module; helper for private_type_in_pub_generic.nu: a strict-mode
// module (it has `pub`) whose public GENERIC struct holds its private
// struct, and whose generic functions name it as a type argument.
$ `stdlib/core/rcbox.nu`

: Impl { i n }

pub : GBox [T] { ( Shared Impl ) ctl T v }

unsafe pub @ gbox_new [T] T v → ( GBox T ) {
    ^ @ ( GBox T ) { ( shared_new [Impl] @ Impl { 7 } ) v }
}

unsafe pub @ gbox_n [T] ( GBox T ) b → i {
    : *Impl p ( shared_ptr [Impl] . b ctl )
    ^ . p n
}
