// inout_holder_repointed_by_a_callee_on_one_path_only_read_after_its_source_ended: a holder viewing a block-local String is handed `inout` to a callee that gives it a new value on one of its paths only; the block ends; the holder is read.
// Refused: the callee may hand the holder back as it was, so it may still view the String. Found while the ownership engine was written (AGORA-863): the reference checker took the callee's "replaces its parameter" for certain and forgot what the holder held — a summary's effect says what may happen. A parameter that goes back, on some way out, still holding what it held on entry keeps what it holds at the call (`keeps`).
// map: §2.10 | A2 | rejected | - | AGORA-863: an inout holder a callee repoints on some paths only, read after its source ended
$ `stdlib/core/string.nu`

: W { s v }

@ maybe inout W w b c → v { ? c { = w @ W { `a fresh literal` } } {} }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W { ( string_data b ) }
        ( maybe w F )
    }
    ( nurl_println . w v )
    ^ 0
}
