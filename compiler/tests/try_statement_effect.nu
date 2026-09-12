// A discarded try success still propagates failure and may call effects.
: | TryErr { TryFailed }
: ~ i effects 0

@ step b fail → !v TryErr {
    = effects + effects 1
    ? fail { ^ @ !v TryErr { F TryFailed } } {}
    ^ @ !v TryErr { T }
}

@ value → !i TryErr { ^ @ !i TryErr { T 7 } }

@ chain b fail → !v TryErr {
    \ ( value )
    \ ( step fail )
    \ ( step F )
    ^ @ !v TryErr { T }
}

@ main → i {
    ?? ( chain F ) { T → ( nurl_print `success\n` ) F _ → ^ 1 }
    ?? ( chain T ) { T → ^ 2 F _ → ( nurl_print `propagated\n` ) }
    ? != effects 3 { ^ 3 } {}
    ( nurl_print `effects=3\n` )
    ^ 0
}
