// RHS consumption precedes installing the returned owner, including loops.
$ `stdlib/core/string.nu`

: Detail { String text i code }
: | Owned { RebindLive Detail RebindEmpty }

@ replace sink ( Vec i ) xs b fresh → ( Vec i ) {
    ? fresh { ( vec_free [i] xs ) ^ ( vec_new [i] ) } {}
    ^ xs
}

@ renew sink Owned x b fresh → Owned {
    ? fresh { ^ @ Owned { RebindLive @ Detail { ( string_from `new` ) 7 } } } {}
    ^ x
}

@ main → i {
    : ~ ( Vec i ) xs ( vec_new [i] )
    : ~ Owned owner @ Owned { RebindLive @ Detail { ( string_from `old` ) 7 } }
    : ~ i n 0
    ~ < n 100 {
        = xs ( replace xs T )
        = xs ( later xs F )
        = owner ( renew owner T )
        = owner ( renew owner F )
        = n + n 1
    }
    ( nurl_println_int ( vec_len [i] xs ) )
    ?? owner { RebindLive d → ( nurl_println_int . d code ) RebindEmpty → {} }
    ( vec_free [i] xs )
    ^ 0
}

@ later ( Vec i ) xs b fresh → ( Vec i ) { ^ ( replace xs fresh ) }
