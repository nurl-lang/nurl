@ fib i n → i {
    ? < n 2 { ^ n } {}
    : i a ( fib - n 1 )
    : i b ( fib - n 2 )
    ^ + a b
}

@ main → i {
    : i x ( fib 10 )
    ? > x 50 { ^ 1 } {}
    ^ 0
}
