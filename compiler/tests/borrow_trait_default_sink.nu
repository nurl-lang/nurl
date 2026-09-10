// A default's sink receiver transfers ownership even before body emission.
$ `stdlib/core/vec.nu`

: Holder { ( Vec i ) items }

@ main → i {
    : Holder item @ Holder { ( vec_new [i] ) }
    ( consume item )
    ( consume item )
    ^ 0
}

% Consumable Holder {}

% Consumable [T] {
    @ consume sink T self → v { ( vec_free [i] . self items ) }
}
