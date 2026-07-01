// dyn_diamond.nu
// Diamond-level dynamic trait objects (docs/spec.md §4.9): a `%Pet` object
// dispatches BOTH its own method (pet_name) and its supertrait Animal's methods
// (sound + the DEFAULT describe) — the flattened vtable carries the transitive
// supertrait methods, so a sub-trait object upcasts to a super-trait method for
// free. Cat OVERRIDES the default describe; Dog inherits it (which itself calls
// sound back through dynamic dispatch).
$ `stdlib/core/string.nu`

% Animal [T] {
    @ sound T self → s
    @ describe T self → s {  // DEFAULT: calls sound
        ^ ( nurl_str_cat `makes sound: ` ( sound self ) )
    }
}

% Pet [T] : Animal {
    @ pet_name T self → s
}

: Dog { i id }
: Cat { i id }

% Animal Dog { @ sound Dog d → s { ^ `woof` } }

% Pet Dog { @ pet_name Dog d → s { ^ `Rex` } }

% Animal Cat {
    @ sound Cat c → s { ^ `meow` }
    @ describe Cat c → s { ^ `a quiet cat` }  // OVERRIDE the default
}

% Pet Cat { @ pet_name Cat c → s { ^ `Whiskers` } }

@ show_pet %Pet p → v {
    ( nurl_print ( pet_name p ) ) ( nurl_print `: ` )
    ( nurl_print ( sound p ) ) ( nurl_print ` / ` )
    ( nurl_print ( describe p ) ) ( nurl_print `\n` )
}

@ main → i {
    : Dog d @ Dog { 1 }
    : Cat c @ Cat { 2 }
    : %Pet pd ( dyn Pet d )
    : %Pet pc ( dyn Pet c )
    ( show_pet pd )
    ( show_pet pc )
    ^ 0
}
