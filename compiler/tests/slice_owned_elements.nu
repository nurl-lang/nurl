// slice_owned_elements.nu — a slice releases its elements with its buffer
// (agora #510): Strings, structs holding one, other slices — wherever the
// slice is held (a binding, a struct, an enum, an option, a result, a Vec)
// and however it was made (a literal, a call, a copy of a parameter).
// Before, only a literal bound in the function that wrote it released its
// elements; the sanitizer run (run_san_tests.sh) holds every shape here.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// #510: a struct element holding a slice of Strings
: SfieldH { [String names i n }
@ run_sfield → i {
    : [SfieldH hs [SfieldH | @ SfieldH { [String | ( string_from `a long enough string to be on the heap for sure` )] 1 }]
    ~ h hs { ( nurl_println ( nurl_str_int . h n ) ) }
    ^ 0
}

// a slice of Strings
@ run_strs → i { : [String a [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two` )]
    ~ x a { ( nurl_println ( string_data x ) ) } ^ 0 }

// structs with a slice field pushed to a Vec
: VecBuf { [i xs }
@ run_vec → i { : ( Vec VecBuf ) v ( vec_new [VecBuf] ) ( vec_push [VecBuf] v @ VecBuf { [i | 1 2] } ) : [i q [i | 3 4] ( vec_push [VecBuf] v @ VecBuf { q } )
    ~ r v { ~ x . r xs { ( nurl_println ( nurl_str_int x ) ) } } ^ 0 }

// an element given a new String
@ run_estore → i { : ~ [String a [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two` )]
    = . a 0 ( string_from `a long enough string to be on the heap, three` )
    ~ x a { ( nurl_println ( string_data x ) ) } ^ 0 }

// struct elements holding a String
: SelemP { String name i n }
@ run_selem → i { : [SelemP a [SelemP | @ SelemP { ( string_from `a long enough string to be on the heap, one` ) 1 } @ SelemP { ( string_from `a long enough string to be on the heap, two` ) 2 }]
    ~ x a { ( nurl_println ( string_data . x name ) ) } ^ 0 }

// a String binding copied into a literal
@ run_fromb → i { : String s ( string_from `a long enough string to be on the heap, one` ) : [String a [String | s ( string_from `two two two two two two two two two two` )]
    ~ x a { ( nurl_println ( string_data x ) ) } ( nurl_println ( string_data s ) ) ^ 0 }

// an inout slice of Strings given a literal
@ inouts_fill inout [String p → v { = p [String | ( string_from `a long enough string to be on the heap, new` )] }
@ run_inouts → i { : ~ [String a [String | ( string_from `a long enough string to be on the heap, one` )] ( inouts_fill a ) ~ x a { ( nurl_println ( string_data x ) ) } ^ 0 }

// a result of a slice, or a String error
@ ress_f b c → ![i String { ? c { ^ @ ![i String { T [i | 1 2] } } {} ^ @ ![i String { F ( string_from `an error string long enough for the heap` ) } }
@ run_ress → i { ?? ( ress_f T ) { T sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } F e → {} } ?? ( ress_f F ) { T sl → {} F e → { ( nurl_println ( string_data e ) ) } } ^ 0 }

// an option of a slice of Strings
@ opts_f → ?[String { ^ @ ?[String { T [String | ( string_from `a long enough string to be on the heap, one` )] } }
@ run_opts → i { : ?[String o ( opts_f ) ?? o { T sl → { ~ x sl { ( nurl_println ( string_data x ) ) } } F → {} } ^ 0 }

// an enum payload
: | EnumpBox { EnumpBFull [String EnumpBEmpty }
@ enump_mk → EnumpBox { ^ @ EnumpBox { EnumpBFull [String | ( string_from `a long enough string to be on the heap, one` )] } }
@ run_enump → i { : EnumpBox b ( enump_mk ) ?? b { EnumpBFull sl → { ~ x sl { ( nurl_println ( string_data x ) ) } } EnumpBEmpty → {} } ^ 0 }

// slices of Strings as arguments and through a call
@ args_tot i z [String a → i { : ~ i t z ~ x a { = t + t ( string_len x ) } ^ t }
@ args_mk → [String { ^ [String | ( string_from `a long enough string to be on the heap, one` )] }
@ args_pass [String a → [String { ^ a }
@ run_args → i { : String st ( string_from `another long enough string for the heap, two` )
    ( nurl_println ( nurl_str_int ( args_tot 0 ( args_mk ) ) ) )
    ( nurl_println ( nurl_str_int ( args_tot 0 [String | st ( string_from `third long enough string for the heap, three` )] ) ) )
    ( nurl_println ( nurl_str_int ( args_tot 0 ( args_pass ( args_mk ) ) ) ) )
    : [String r ( args_pass ( args_mk ) )
    ( nurl_println ( nurl_str_int ( args_tot 0 r ) ) )
    ( nurl_println ( string_data st ) )
    ^ 0 }

// a slice of raw strings: a parameter on one path, a literal on another
@ mixr_pick b c [s a → [s { ? c { ^ a } {} ^ [s | `x` `y`] }
@ mixr_n i z [s a → i { : ~ i t z ~ x a { = t + t ( nurl_str_len x ) } ^ t }
@ run_mixr → i { : [s q [s | `hello` `there`]
    : [s r ( mixr_pick T q )
    : [s r2 ( mixr_pick F q )
    ( nurl_println ( nurl_str_int + ( mixr_n 0 r ) ( mixr_n 0 r2 ) ) )
    ( nurl_println ( nurl_str_int ( mixr_n 0 ( mixr_pick T q ) ) ) )
    ( nurl_println ( nurl_str_int ( mixr_n 0 q ) ) )
    ^ 0 }

// a Vec of structs holding slices of Strings; a slice of slices
: VecsW { [String names }
@ run_vecs → i {
    : ~ ( Vec VecsW ) vs ( vec_new [VecsW] )
    ( vec_push [VecsW] vs @ VecsW { [String | ( string_from `first heap string long enough to allocate` )] } )
    ( vec_push [VecsW] vs @ VecsW { [String | ( string_from `second heap string long enough to allocate` ) ( string_from `third heap string long enough to allocate` )] } )
    : ~ i t 0
    ~ w vs { ~ x . w names { = t + t ( string_len x ) } }
    ( nurl_println ( nurl_str_int t ) )
    : [[i nest [[i | [i | 1 2] [i | 3]]
    ~ row nest { ~ x row { = t + t x } }
    ( nurl_println ( nurl_str_int t ) )
    ^ 0 }

@ main → i {
    ( nurl_println `sfield` ) ( run_sfield )
    ( nurl_println `strs` ) ( run_strs )
    ( nurl_println `vec` ) ( run_vec )
    ( nurl_println `estore` ) ( run_estore )
    ( nurl_println `selem` ) ( run_selem )
    ( nurl_println `fromb` ) ( run_fromb )
    ( nurl_println `inouts` ) ( run_inouts )
    ( nurl_println `ress` ) ( run_ress )
    ( nurl_println `opts` ) ( run_opts )
    ( nurl_println `enump` ) ( run_enump )
    ( nurl_println `args` ) ( run_args )
    ( nurl_println `mixr` ) ( run_mixr )
    ( nurl_println `vecs` ) ( run_vecs )
    ^ 0
}
