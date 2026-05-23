// box_drop_trait.nu — Drop-trait integration for Box[T].
//
// NURL's auto-drop machinery looks up `drop##<LLVM-type>` in the
// impl-name symbol table and emits a call at every scope exit where
// a binding of that LLVM type is owned. For a generic-instantiated
// type like `Box[i]`, the LLVM type is `%Box__i64` — and a concrete
// `% Drop ( Box i ) { … }` impl registers `drop##%Box__i64`.
//
// This test exercises that path: the auto-emitted drop call should
// release the storage at function exit WITHOUT an explicit
// `box_free`. Run under ASan (./build.sh --san) to actually catch a
// leak if the trait dispatch ever silently breaks; here we just
// verify the drop side-effect (print) fires.

$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

% Drop ( Box i ) {
    @ drop ( Box i ) b → v {
        ( nurl_print `[drop ` )
        ( nurl_print ( nurl_str_int ( box_get [i] b ) ) )
        ( nurl_print `]\n` )
        ( box_free [i] b )
    }
}

@ make → ( Box i ) {
    : ( Box i ) b ( box_new [i] 42 )
    ^ b
}

@ main → i {
    ( nurl_print `enter scope\n` )
    : ( Box i ) a ( box_new [i] 100 )
    ( nurl_print `value=` ) ( nurl_print ( nurl_str_int ( box_get [i] a ) ) )
    ( nurl_print `\n` )
    ( nurl_print `leaving main scope...\n` )
    ^ 0
}
