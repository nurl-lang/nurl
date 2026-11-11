// Owners rotated by assignment in a loop (`= t a  = a b  = b t`): each
// assignment out of an owner is a move where it runs, so every round
// leaves two owners and a spare, whichever line made which name hold what
// in the round before (agora #634). String, Vec, struct and owned slice;
// a rotation of four, one in a nested loop, one in a closure called three
// times, and a slice moved in one arm only.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ mk s x → P { ^ @ P { ( string_from x ) 1 } }

@ strings → v {
    : ~ String a ( string_from `the first string, long enough for the heap` )
    : ~ String b ( string_from `the second string, long enough for the heap` )
    : ~ String t ( string_from `the third string, long enough for the heap` )
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
}

@ four → v {
    : ~ String a ( string_from `four: the first string, long enough for the heap` )
    : ~ String b ( string_from `four: the second string, long enough for the heap` )
    : ~ String c ( string_from `four: the third string, long enough for the heap` )
    : ~ String t ( string_from `four: the spare string, long enough for the heap` )
    : ~ i k 0
    ~ < k 5 {
        = t a
        = a b
        = b c
        = c t
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data c ) )
}

@ nested → v {
    : ~ String a ( string_from `nested: the first string, long enough for the heap` )
    : ~ String b ( string_from `nested: the second string, long enough for the heap` )
    : ~ String t ( string_from `nested: the third string, long enough for the heap` )
    : ~ i k 0
    ~ < k 3 {
        : ~ i j 0
        ~ < j 2 {
            = t a
            = a b
            = b t
            = j + j 1
        }
        = t b
        = b a
        = a t
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
}

@ vecs → v {
    : ~ ( Vec i ) a ( vec_new [i] )
    : ~ ( Vec i ) b ( vec_new [i] )
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] a 1 )
    ( vec_push [i] b 2 )
    ( vec_push [i] b 3 )
    ( vec_push [i] t 4 )
    : ~ i k 0
    ~ < k 3 {
        = t a
        ( vec_push [i] t k )
        = a b
        = b t
        = k + k 1
    }
    ( nurl_println_int ( vec_len [i] a ) )
    ( nurl_println_int ( vec_len [i] b ) )
}

@ structs → v {
    : ~ P a ( mk `struct: the first string, long enough for the heap` )
    : ~ P b ( mk `struct: the second string, long enough for the heap` )
    : ~ P t ( mk `struct: the third string, long enough for the heap` )
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    ( nurl_println ( string_data . a name ) )
    ( nurl_println ( string_data . b name ) )
}

@ slices → v {
    : ~ [i a [i | 1 2]
    : ~ [i b [i | 3 4 5]
    : ~ [i t [i | 6]
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    : ~ i sum 0
    ~ x a { = sum + sum x }
    ~ y b { = sum + sum * 10 y }
    ( nurl_println_int sum )
    // …and moved in one arm only: freed once, through the name that
    // holds it on the path taken.
    : ~ [i u [i | 7 8]
    : ~ [i w [i | 9]
    ? == k 3 { = w u } {}
    : ~ i sum2 0
    ~ z w { = sum2 + sum2 z }
    ( nurl_println_int sum2 )
}

@ in_closure → v {
    : ~ String a ( string_from `closure: the first string, long enough for the heap` )
    : ~ String b ( string_from `closure: the second string, long enough for the heap` )
    : ~ String t ( string_from `closure: the third string, long enough for the heap` )
    : ( @ v ) f \ → v { = t a = a b = b t }
    : ~ i k 0
    ~ < k 3 { ( f ) = k + k 1 }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
}

@ main → i {
    ( strings )
    ( four )
    ( nested )
    ( vecs )
    ( structs )
    ( slices )
    ( in_closure )
    ^ 0
}
