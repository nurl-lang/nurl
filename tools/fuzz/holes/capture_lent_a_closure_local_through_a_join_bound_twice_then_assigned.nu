// map: §7.4 | A2 | runs-clean | - | AGORA-953 (CodeRabbit on github#2204): `: e ? == k 0 ( id a ) ( id b )  : e2 e  = o e2` in a closure: the second binding is over the join's arms too (`__jalias` follows mem_udrop_link_alias), so o takes over only the selected local
// Was a leak under LSan on main c4c0f35.
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
        : ?String e2 __el
        = o e2
    }
    ( f )
    ( show o )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
