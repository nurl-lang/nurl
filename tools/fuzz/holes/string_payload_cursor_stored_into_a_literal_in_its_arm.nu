// map: §2.12 | A2 | rejected | - | AGORA-840: `?? o { T x → { : ~ String cur x  : W q @ W { cur 0 } } }` over a `?String` - the literal takes the payload unseen, then o is read
$ `stdlib/core/string.nu`

: W { String s i n }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `a heap string long enough to own a buffer on the heap, surely` ) }
    ?? o {
        T x → {
            : ~ String cur x
            : W q @ W { cur 0 }
            ( nurl_println_int ( string_len . q s ) )
        }
        F → {}
    }
    ?? o { T x → ( nurl_println ( string_data x ) ) F → {} }
    ^ 0
}
