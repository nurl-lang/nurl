// Mutable raw pointers (`: ~ *T`) are ordinary, correct bindings. nurlc
// once warned that they "miscompile in long-running write loops", which
// pushed callers to launder pointers through i64. Every shape that
// warning implicated is exercised here and produces the right answer.
// What actually miscompiled was a pointer into a container that
// REALLOCATED — an orthogonal hazard (it needs no `~` at all), diagnosed
// by should_warn_stale_borrow.nu.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Node { i val i next }

@ ck b ok s name → v {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) }
    ( nurl_print name ) ( nurl_print `\n` )
}

@ main → i {
    // 1. a mutable struct pointer walked through a 100k-link chain
    : i N 100000
    : *u arena # *u ( nurl_alloc * N 16 )
    : ~ i k 0
    ~ < k N {
        : *Node nd # *Node + # i arena * k 16
        = . nd val k
        = . nd next + + # i arena * k 16 16
        = k + k 1
    }
    : ~ * Node cur # *Node arena
    : ~ i sum 0
    = k 0
    ~ < k N {
        = sum + sum . cur val
        = cur # *Node . cur next
        = k + k 1
    }
    ( ck == sum / * - N 1 N 2 `struct pointer walked 100k links` )

    // 2. a long advancing write loop through a mutable pointer
    : *u buf # *u ( nurl_alloc 200000 )
    : ~ * u w buf
    = k 0
    ~ < k 200000 {
        = . w 0 # u & k 255
        = w # *u + # i w 1
        = k + k 1
    }
    : ~ i bad 0
    = k 0
    ~ < k 200000 {
        ? != # i . buf k & k 255 { = bad + bad 1 } {}
        = k + k 1
    }
    ( ck == bad 0 `200k advancing writes read back` )

    // 3. a mutable pointer reassigned inside a ?-arm (arm-drop machinery)
    : ~ * u p buf
    ? T {
        = p # *u + # i buf 8
        = . p 0 # u 42
    } {}
    ( ck == # i . buf 8 42 `reassigned inside a ?-arm` )

    // 4. writes through a String's data pointer
    : String s2 ( string_from `xxxxxxxxxxxxxxxxxxxx` )
    : ~ * u sp # *u ( string_data s2 )
    = k 0
    ~ < k 20 {
        = . sp 0 # u + 97 % k 26
        = sp # *u + # i sp 1
        = k + k 1
    }
    ( ck == ( nurl_str_get ( string_data s2 ) 3 ) 100 `write through a String's data pointer` )

    // 5. a borrow that is NOT invalidated: reading a Vec never moves its
    //    buffer, so the pointer stays live and no warning fires.
    : ( Vec i ) v ( vec_with_cap [i] 8 )
    ( vec_push [i] v 11 )
    ( vec_push [i] v 22 )
    : *i vp ( vec_data [i] v )
    : i first ( vec_len [i] v )
    ( ck == + # i . vp 0 # i . vp 1 33 `read-only borrow of a Vec stays live` )
    ( ck == first 2 `vec_len does not invalidate a borrow` )

    ( string_free s2 )
    ( nurl_free # s buf )
    ( nurl_free # s arena )
    ( vec_free [i] v )
    ^ 0
}
