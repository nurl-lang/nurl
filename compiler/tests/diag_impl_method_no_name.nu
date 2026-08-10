// diag_impl_method_no_name.nu — '@' in an impl body followed by
// something that cannot name a method.
: Dog { i age }

% Speaker [T] { @ speak T self → i }

% Speaker Dog { @ 5 Dog self → i { ^ 1 } }

@ main → i { ^ 0 }
