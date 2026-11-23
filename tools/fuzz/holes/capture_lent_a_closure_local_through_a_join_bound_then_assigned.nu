// map: §7.4 | A2 | runs-clean | - | AGORA-953 (agora #242 twin): `: ?String e ? == k 0 ( id a ) ( id b )  = o e` in a closure, o a by-pointer capture: o takes over the one local the join selected, by its key, and the other keeps its own value to release
// Was a leak under LSan on main 07e02a7 (both locals taken over, the unselected one never released).
// Closed: a capture by pointer given a lend of what dies with the closure (a local or a parameter of it) is given a copy it owns, as an `inout` parameter is (gen_assign; agora #872).
// main 525613db: AddressSanitizer: heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ sid String a → String { ^ a }

@ vid ( Vec i ) a → ( Vec i ) { ^ a }

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String a ( mk `closure a local long enough for heap ok` )
        : ?String b ( mk `closure b local long enough for heap ok` )
        : ?String __el ? == k 0 ( id a ) ( id b )
        = o __el
    }
    ( f )
    ( show o )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
