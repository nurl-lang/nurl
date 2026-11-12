// A second generic struct of one name is refused, as a second plain struct
// is (agora #716): with every template collected before the first instance
// is made, two templates of one name would leave an instance's layout to
// whichever was read last.
: Dup [A] { A x }

: Dup [A] { A y A x }

@ main → i {
    : ( Dup i ) d @ ( Dup i ) { 7 }
    ( nurl_println_int . d x )
    ^ 0
}
