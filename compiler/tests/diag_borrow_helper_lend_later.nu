// A helper that hands back what a generic accessor lends says so (h215).
// vec_at is instantiated at the end of the module, so when first_of's
// summary was written it had none, and first_of "lent nothing": a caller
// could release `mid` while still reading what first_of handed back. The
// parameters handed to such a callee are noted with their positions and
// settled once every summary is final (resolve_retfwd_lends) — through a
// binding the helper hands back (`second_of`) too.
$ `stdlib/core/vec.nu`

@ first_of ( Vec ( Vec i ) ) xs → ( Vec i ) { ^ ( vec_at [( Vec i )] xs 0 ) }

@ second_of ( Vec ( Vec i ) ) xs → ( Vec i ) {
    : ( Vec i ) e ( vec_at [( Vec i )] xs 1 )
    ^ e
}

@ use_first ( Vec ( Vec i ) ) mid0 → i {
    : ( Vec ( Vec i ) ) mid ( vec_clone [( Vec i )] mid0 )
    : ( Vec i ) inner ( first_of mid )
    ( vec_free [( Vec i )] mid )
    ^ ( vec_len [i] inner )
}

@ use_second ( Vec ( Vec i ) ) mid0 → i {
    : ( Vec ( Vec i ) ) mid ( vec_clone [( Vec i )] mid0 )
    : ( Vec i ) inner ( second_of mid )
    ( vec_free [( Vec i )] mid )
    ^ ( vec_len [i] inner )
}

@ main → i { ^ 0 }
