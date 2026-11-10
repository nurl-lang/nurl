// slice_views_followed.nu — what a native slice's elements view is followed
// like what a struct's fields or a Vec's elements view (Agora #545), and
// everything that holds no view of a binding still compiles: the checks
// refuse a slice read (or dropped, where its elements run a destructor that
// may read their view) after the storage it views is gone, and nothing else.
//
// `copies` / `fresh_and_clone` / `vecs`: a slice literal copies an owning
// binding in, so the slice holds no view of it and the binding grows freely.
// `dead_before`: a view in a slice that is not read after its source grew.
// `returned`: a function handing back a slice of its parameters' views.
// `stores`: an element given a view of an older binding; given another
// value, or the slice a new literal, it no longer holds the first view.
// `in_struct`: a struct with a slice field of views, by itself and in a Vec.
// `holders`: a slice of destructor values viewing a binding declared before
// it. `walk`: views stored element by element out of a loop over a Vec.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ copies → v {
    : ~ String a ( string_from `first` )
    : ~ String b ( string_from `second` )
    : [String ws [String | a b]
    ~ < ( string_len a ) 200 { ( string_push_str a `more and more and more text` ) }
    ( string_push_str b `!` )
    ~ x ws { ( nurl_println ( string_data x ) ) }
    ( nurl_println ( nurl_str_int ( string_len a ) ) )
}

@ fresh_and_clone → v {
    : ~ String a ( string_from `first` )
    : [String ws [String | ( string_from `x` ) ( string_clone a )]
    ( string_push_str a `more` )
    ~ x ws { ( nurl_println ( string_data x ) ) }
    ( nurl_println ( string_data a ) )
}

@ vecs → v {
    : ~ ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 1 )
    : [( Vec i ) vs [( Vec i ) | w ( vec_new [i] )]
    ( vec_push [i] w 2 )
    ~ e vs { ( nurl_println ( nurl_str_int ( vec_len [i] e ) ) ) }
    ( nurl_println ( nurl_str_int ( vec_len [i] w ) ) )
}

: Pt { i x i y }

@ plain → v {
    : ~ Pt p @ Pt { 1 2 }
    : [Pt ps [Pt | p @ Pt { 3 4 }]
    = . p x 9
    ~ q ps { ( nurl_println ( nurl_str_int . q x ) ) }
    : ~ [i xs [i | 1 2 3]
    : [i ys [i | 4 5]
    : [[i zs [[i | xs ys]
    : i k 0
    = . xs k 9
    ~ r zs { ~ n r { ( nurl_println ( nurl_str_int n ) ) } }
    ~ n xs { ( nurl_println ( nurl_str_int n ) ) }
}

@ dead_before → v {
    : ~ String a ( string_from `first` )
    : [s ws [s | ( string_data a ) `lit`]
    ~ x ws { ( nurl_println x ) }
    ( string_push_str a ` and more` )
    ( nurl_println ( string_data a ) )
}

@ pair s a s b → [s { ^ [s | a b] }

@ words String x → [s { ^ [s | ( string_data x ) `lit`] }

@ returned → v {
    : String x ( string_from `kept` )
    : [s p ( pair ( string_data x ) `other` )
    : [s w ( words x )
    ~ e p { ( nurl_println e ) }
    ~ e w { ( nurl_println e ) }
}

@ stores → v {
    : ~ String c ( string_from `c` )
    : ~ [String ws [String | ( string_from `a` ) ( string_from `b` )]
    = . ws 0 ( string_clone c )
    : i k 1
    = . ws k ( string_from `fresh` )
    : ~ [s vs [s | `a` `b`]
    = . vs 0 ( string_data c )
    ~ x vs { ( nurl_println x ) }
    = . vs 0 `lit again`
    = vs [s | `new`]
    ( string_push_str c `more` )
    ~ x vs { ( nurl_println x ) }
    ~ x ws { ( nurl_println ( string_data x ) ) }
    ( nurl_println ( string_data c ) )
}

: Row { [s cells i n }

@ in_struct → v {
    : String a ( string_from `cell` )
    : Row r @ Row { [s | ( string_data a ) `b`] 2 }
    ~ c . r cells { ( nurl_println c ) }
    : ~ ( Vec Row ) rows ( vec_new [Row] )
    ( vec_push [Row] rows @ Row { [s | ( string_data a )] 1 } )
    ( nurl_println ( nurl_str_int ( vec_len [Row] rows ) ) )
}

: Shout { s text }

% Drop Shout { @ drop Shout self → v { ( nurl_println ( nurl_str_cat `drop ` . self text ) ) } }

@ holders → v {
    : String older ( string_from `an older source` )
    : ~ [Shout ws [Shout | @ Shout { ( string_data older ) } @ Shout { `lit` }]
    : i k 1
    = . ws k @ Shout { ( string_data older ) }
    ( nurl_println `holders: built` )
}

@ walk → v {
    : ~ ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `one` ) )
    ( vec_push [String] names ( string_from `two` ) )
    : ~ [s xs [s | `` ``]
    : ~ i k 0
    ~ nm names { = . xs k ( string_data nm ) = k + k 1 }
    ~ x xs { ( nurl_println x ) }
    ( vec_push [String] names ( string_from `three` ) )
}

@ main → i {
    ( copies )
    ( fresh_and_clone )
    ( vecs )
    ( plain )
    ( dead_before )
    ( returned )
    ( stores )
    ( in_struct )
    ( holders )
    ( walk )
    ^ 0
}
