// generic_struct_field_unsigned.nu — a monomorphised generic struct's field
// must carry the signedness of its CONCRETE field type. ensure_struct_
// instantiated recorded each field's index/type/name but not its `__unsigned`
// flag (gen_struct_decl does for concrete structs), so `( Pair u64 i )`'s u64
// field was treated as SIGNED on access: `% . p first 10` emitted `srem`,
// `> . p first n` used `icmp sgt`, `# i . p first` sign-extended.
@ pr s l i v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }

: Pair [A B] { A first B second }

@ mk [A B] A a B b → ( Pair A B ) { ^ @ ( Pair A B ) { a b } }

@ main → i {
    : ( Pair u64 i ) p ( mk [u64 i] 18446744073709551615 -7 )
    ( pr `first_mod10` # i % . p first 10 )  // 5   (urem, not srem -> -1)
    ( pr `first_gt` ? > . p first 1000 1 0 )  // 1   (unsigned compare)
    ( pr `first_widen` # i / . p first 2 )  // 9223372036854775807 (udiv)
    ( pr `second_div` / . p second 2 )  // -3  (signed field unchanged)

    // unsigned field in the SECOND slot too (different width)
    : ( Pair i u32 ) q ( mk [i u32] -1 4000000000 )
    ( pr `q_second` # i . q second )  // 4000000000 (zext)
    ^ 0
}
