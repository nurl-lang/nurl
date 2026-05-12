// Group F: Traits and implementations
// Tests: trait_decl, impl_decl, monomorphised method dispatch
// Expected output:
//   42
//   123

% Stringify {
  @ stringify i n → s
}

% Numify {
  @ numify s str → i
}

% Stringify i {
  @ stringify i n → s {
    ^ (nurl_str_int n)
  }
}

% Numify s {
  @ numify s str → i {
    ^ (nurl_str_to_int str)
  }
}

@ main → v {
  : s1 (stringify 42)
  (nurl_print s1)
  (nurl_print `\n`)
  : n1 (numify `123`)
  (nurl_print_int n1)
}
