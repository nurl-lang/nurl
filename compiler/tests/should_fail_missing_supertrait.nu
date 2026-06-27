// should_fail_missing_supertrait.nu
// Ord : Eq — implementing Ord for a type without implementing its supertrait
// Eq for that same type is a coherence error. The compiler must reject this at
// compile time, naming the missing supertrait.

: Nat { i v }

% Eq [T] {
    @ eq T a T b → b
}

% Ord [T] : Eq {
    @ cmp T a T b → i
}

// Ord for Nat, but NO `% Eq Nat` anywhere → must fail.
% Ord Nat {
    @ cmp Nat a Nat b → i {
        ? < . a v . b v { ^ -1 } {}
        ? > . a v . b v { ^ 1 } {}
        ^ 0
    }
}

@ main → i { ^ 0 }
