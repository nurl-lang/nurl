// diag_defer_body_name_used_after_the_body.nu — a name bound inside a `;`
// defer body ends with the body (agora #636). Used after it, the name
// reached the body's storage, which is written only when the defer runs.

@ main → i {
    ; { : i a 7 ( nurl_println_int a ) }
    ^ a
}
