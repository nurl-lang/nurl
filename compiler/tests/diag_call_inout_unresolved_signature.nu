// A forward callee has an inout type but no parameter name. Signature
// scanning cannot determine the complete address ABI; reject the call
// and also report the malformed declaration during error recovery.
@ main → i {
    : ~ i n 0
    ( bump n )
    ^ 0
}

@ bump inout i → v { ^ }
