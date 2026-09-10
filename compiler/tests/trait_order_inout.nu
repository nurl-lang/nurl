// Forward callers must preserve exclusive borrows for explicit methods,
// default receivers, and additional inout parameters in a default signature.
: Counter { i value }

@ main → i {
    : ~ Counter counter @ Counter { 39 }
    ( increment counter )
    ( add counter 1 )
    : Counter source @ Counter { 1 }
    ( accumulate source counter )
    ( nurl_println_int . counter value )
    ^ 0
}

% Increment Counter {
    @ add inout Counter self i amount → v { = . self value + . self value amount }
}

% Increment [T] {
    @ add inout T self i amount → v
    @ increment inout T self → v { = . self value + . self value 1 }
    @ accumulate T self inout Counter target → v { = . target value + . target value . self value }
}
