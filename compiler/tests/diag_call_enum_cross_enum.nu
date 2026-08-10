// diag_call_enum_cross_enum.nu — passing a value of one enum where a
// DIFFERENT enum is declared. Both lower to an i64 tag, so the call
// used to assemble and the callee read this value's tag as the OTHER
// enum's variants (here: Pear's tag 1 arriving as Green).
//
// The message opened "wrong struct type passed by value" about two
// ENUMS. Its parenthetical was accurate; the lead was not, and 'struct'
// is the word a reader takes away. Both kinds are NOMINAL, which is true
// of either and is the rule that matters here.
//
// The enum-specific message written for exactly this case is still
// preempted: it lives in the scalar-agreement pass, and this check runs
// first from __arg_param_checks, which has no 'syms' to test enum-ness
// with. Naming the shared rule was the fix that did not need plumbing.
: | Color { Red Green Blue }
: | Fruit { Apple Pear }

@ show Color c → i {
    ^ 0
}

@ main → i {
    : Fruit x Pear
    ^ ( show x )
}
