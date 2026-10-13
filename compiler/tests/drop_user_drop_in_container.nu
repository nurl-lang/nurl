// A struct holding a value with its own `% Drop` inside a container — a
// Vec, a Vec of Vecs, a Box, an option, an enum payload — drops it once,
// running its drop (tools/fuzz/holes h209).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

: R { String s }

% Drop R { @ drop R r → v { ( nurl_print `drop ` ) ( nurl_print ( string_data . r s ) ) ( nurl_print `\n` ) } }

: | E { N P R }

: InVec { ( Vec R ) xs }
: InVecVec { ( Vec ( Vec R ) ) xs }
: InBox { ( Box R ) b }
: InOpt { ? R o }
: InEnum { E e }

@ mk s t → R { ^ @ R { ( string_from t ) } }

@ main → i {
    {
        : InVec a @ InVec { ( vec_new [R] ) }
        ( vec_push [R] . a xs ( mk `vec` ) )
    }
    {
        : ( Vec R ) inner ( vec_new [R] )
        ( vec_push [R] inner ( mk `vec-vec` ) )
        : InVecVec b @ InVecVec { ( vec_new [( Vec R )] ) }
        ( vec_push [( Vec R )] . b xs inner )
    }
    { : InBox c @ InBox { ( box_new [R] ( mk `box` ) ) } }
    { : InOpt d @ InOpt { @ ?R { T ( mk `option` ) } } }
    { : InEnum e @ InEnum { @ E { P ( mk `enum` ) } } }
    ( nurl_print `done\n` )
    ^ 0
}
