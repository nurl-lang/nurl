// A forward call to a default sink transfers the handle exactly once.
$ `stdlib/core/vec.nu`

: Holder { ( Vec i ) items }

@ main → i {
    : ( Vec i ) values ( vec_zeroed [i] 42 )
    : Holder item @ Holder { values }
    ( nurl_println_int ( consume item ) )
    ^ 0
}

% Consumable Holder {}

% Consumable [T] {
    @ consume sink T self → i {
        : i value ( vec_len [i] . self items )
        ( vec_free [i] . self items )
        ^ value
    }
}
