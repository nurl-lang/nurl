// A typo in a binding's type — `: Ptt p @ Pt { 2 3 }` with no `Ptt`
// declared — is an unknown type, as in a parameter (agora #725). It read
// as the inferred binding `Ptt` of the value `p`, and was reported as
// "use of undefined identifier 'p'".
: Pt { i x i y }

@ main → i {
    : Ptt p @ Pt { 2 3 }
    ( nurl_println_int . p x )
    ^ 0
}
