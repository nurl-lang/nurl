// struct_behind_an_owner_is_no_cycle.nu — the shapes agora #661's check
// must NOT refuse: a struct that reaches its own type only behind an owner
// (a Box, a Vec, an option of a Box) or through a generic's instance that
// holds it behind one.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

: Node { i v ( Vec Node ) kids }

: Left { i x ( Vec Right ) rs }

: Right { i y ? ( Box Left ) l }

: Holder [T] { ( Vec T ) items i n }

: Self { i k ( Holder Self ) h }

@ main → i {
    : ~ ( Vec Node ) kids ( vec_new [Node] )
    : Node leaf @ Node { 2 ( vec_new [Node] ) }
    ( vec_push [Node] kids leaf )
    : Node n @ Node { 1 kids }
    ( nurl_println_int + . n v ( vec_len [Node] . n kids ) )
    : Left l @ Left { 3 ( vec_new [Right] ) }
    ( nurl_println_int . l x )
    : Self s @ Self { 4 @ ( Holder Self ) { ( vec_new [Self] ) 0 } }
    ( nurl_println_int . s k )
    ^ 0
}
