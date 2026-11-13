// A value block's tail that is a block-local spelled like the assign
// target is handed over to the target, as one spelled otherwise is (agora
// #806): fresh, a % Drop struct, a Vec filled in the block, the self-shadow
// alias of #792, a double shadow, a nested block and a `: ~` block-local
// reassigned. Each value is released once.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String t i n }

% Drop R { @ drop R r → v { ( nurl_println_int . r n ) } }

@ fresh → v {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String s ( string_from `inner fresh string long enough for heap` ) s } = k + k 1 }
    ( nurl_println ( string_data s ) )
}

@ alias → v {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String s s s } = k + k 1 }
    ( nurl_println ( string_data s ) )
}

@ drop_struct → v {
    : ~ R s @ R { ( string_from `outer string long enough for a heap buffer` ) 1 }
    : ~ i k 0
    ~ < k 2 { = s { : R s @ R { ( string_from `inner fresh string long enough for heap` ) + k 2 } s } = k + k 1 }
    ( nurl_println_int . s n )
}

@ vec_tail → v {
    : ~ ( Vec i ) s ( vec_new [i] )
    : ~ i k 0
    ~ < k 3 { = s { : ( Vec i ) s ( vec_new [i] ) ( vec_push [i] s k ) s } = k + k 1 }
    ( nurl_println_int ( vec_len [i] s ) )
}

@ double_shadow → v {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String s ( string_from `inner fresh string long enough for heap` ) : String s s s } = k + k 1 }
    ( nurl_println ( string_data s ) )
}

@ nested → v {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { { : String s ( string_from `inner fresh string long enough for heap` ) s } } = k + k 1 }
    ( nurl_println ( string_data s ) )
}

@ mut_inner → v {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : ~ String s ( string_from `inner fresh string long enough for heap` ) = s ( string_from `again a heap string here, long` ) s } = k + k 1 }
    ( nurl_println ( string_data s ) )
}

@ main → i {
    ( fresh )
    ( alias )
    ( drop_struct )
    ( vec_tail )
    ( double_shadow )
    ( nested )
    ( mut_inner )
    ^ 0
}
