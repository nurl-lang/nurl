// inout_holder_repointed_by_a_callee_after_an_early_return_read_after_its_source_ended: as inout_holder_repointed_by_a_callee_on_one_path_only_read_after_its_source_ended, the callee returning early before it gives the holder its new value.
// Refused: on the early return the holder goes back as it was (AGORA-863).
// map: §2.10 | A2 | rejected | - | AGORA-863: an inout holder a callee repoints after an early return, read after its source ended
$ `stdlib/core/string.nu`

: W { s v }

@ maybe inout W w b c → v {
    ? c { ^ } {}
    = w @ W { `a fresh literal` }
}

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
