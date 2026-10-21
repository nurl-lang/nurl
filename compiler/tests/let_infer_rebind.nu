// let_infer_rebind.nu — the inferred binding `: NAME EXPR` rebinding a
// name that is already in scope (spec §5.1, docs/MEMORY.md §2.1).
//
// The parser picked the annotated form `: TYPE NAME EXPR` whenever the
// first word was in the symbol table at all — and the table holds values
// as well as types. `: i n 0` then `: n 5` therefore read the VALUE n as
// a type ("unknown type 'n' in a binding type"), and a struct value `p`
// rebound as `: p @ P { … }` was "type 'p' … declared LATER". Only a word
// that names a TYPE opens the annotated form; every other word is the
// inferred form's name, exactly as `: i n 5` spells the same rebinding.
$ `stdlib/core/string.nu`

: P { i a }

& `c` @ abs i x → i

@ take sink String s → i { ^ ( string_len s ) }

@ main → i {
    // A scalar, rebound with a new value and a new type.
    : i n 0
    : n 5
    ( nurl_println_int n )
    : n `five`
    ( nurl_println n )
    // A struct value: the name maps to `%P`, which is its TYPE, not a
    // type named `p`.
    : P p @ P { 1 }
    : p @ P { + . p a 1 }
    ( nurl_println_int . p a )
    // Moved, then made usable again by an inferred rebinding (§2.1); the
    // second String is owned and dropped like the first would have been.
    : s0 ( string_from `abc` )
    ( nurl_println_int ( take s0 ) )
    : s0 ( string_from `rebound` )
    ( nurl_println_int ( string_len s0 ) )
    // Rebinding inside a loop body, once per iteration.
    : ~ i k 0
    : ~ i sum 0
    ~ < k 3 {
        : sq * k k
        : sq + sq 1
        = sum + sum sq
        = k + k 1
    }
    ( nurl_println_int sum )
    // A local may take the name of a function, as `: i abs 3` may; the
    // inferred spelling agrees.
    : abs 3
    ( nurl_println_int abs )
    ^ 0
}
