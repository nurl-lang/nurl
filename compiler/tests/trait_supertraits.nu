// trait_supertraits.nu
// Supertraits: `% Sub : Super` requires every type implementing Sub to also
// implement Super. Here Ord : Eq — so an Ord type is always an Eq type, and a
// function generic over `[A: Ord]` may call the supertrait method `eq` (from
// Eq) as well as `cmp` (from Ord). Dispatch resolves through the supertrait
// impl that the coherence sweep proves exists.

: Nat { i v }

% Eq [T] {
    @ eq T a T b → b
}

% Ord [T] : Eq {
    @ cmp T a T b → i  // -1 / 0 / 1
}

% Eq Nat {
    @ eq Nat a Nat b → b { ^ == . a v . b v }
}

% Ord Nat {
    @ cmp Nat a Nat b → i {
        ? < . a v . b v { ^ -1 } {}
        ? > . a v . b v { ^ 1 } {}
        ^ 0
    }
}

// Generic over Ord — calls BOTH the Ord method (cmp) and, because Ord : Eq,
// the supertrait method (eq).
@ describe [A : Ord] A a A b → i {
    ? ( eq a b )
    { ( nurl_print `equal\n` ) ^ 0 }
    { : i c ( cmp a b )
        ? < c 0 { ( nurl_print `less\n` ) } { ( nurl_print `greater\n` ) }
        ^ c }
}

@ main → i {
    : Nat x @ Nat { 3 }
    : Nat y @ Nat { 7 }
    : Nat z @ Nat { 3 }

    : i r1 ( describe [Nat] x y )  // less  → -1
    : i r2 ( describe [Nat] y x )  // greater → 1
    : i r3 ( describe [Nat] x z )  // equal → 0

    : i total + r1 + r2 r3  // -1 + 1 + 0 = 0
    ( nurl_print `total: ` )
    ( nurl_print ( nurl_str_int total ) )
    ( nurl_print `\n` )
    ^ ? == total 0 0 1
}
