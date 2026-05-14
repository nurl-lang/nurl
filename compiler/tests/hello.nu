// NURL hello-world — testaa stdlib-tulosteet.
//
// Käännös:
//   python nurlc.py --llvm tests/hello.nu > /tmp/hello.ll
//   clang /tmp/hello.ll stdlib/runtime.o -o /tmp/hello
//   /tmp/hello
//
// Odotettu tuloste:
//   Hello, NURL!
//   42
//   true
//   false
//   55

@ double i n → i {
    ^ + n n
}

@ sumto i n → i {
    : i acc 0
    : i k 1
    ~ <= k n {
        = acc + acc k
        = k + k 1
    }
    ^ acc
}

@ main → v {
    ( nurl_print_str `Hello, NURL!` )
    ( nurl_print_int ( double 21 ) )
    ( nurl_print_bool T )
    ( nurl_print_bool F )
    ( nurl_print_int ( sumto 10 ) )
}
