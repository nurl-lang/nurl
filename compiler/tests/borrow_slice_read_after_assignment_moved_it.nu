// An owned slice assigned to another moves its buffer (`= t a`), as
// `= b a` moves any owner: reading `a` before it is given a new value is
// a use of a moved value. It compiled before and read the buffer `t`
// owns — freed memory once `t` was given a new value (agora #634).
@ main → i {
    : ~ [i a [i | 1 2]
    : ~ [i t [i | 6]
    = t a
    = t [i | 7 8 9]
    : ~ i sum 0
    ~ x a { = sum + sum x }
    ~ y t { = sum + sum y }
    ( nurl_println_int sum )
    ^ 0
}
