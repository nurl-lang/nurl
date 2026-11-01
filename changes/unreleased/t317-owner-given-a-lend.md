### Fixed

- **A binding that owns its value drops it when it is given a lent one**
  (Agora #317; probes option_owner_given_a_local_vec_get_in_an_arm_drops_its_value,
  enum_option_owner_given_a_local_vec_get_drops_its_value and two of
  #1295's h6). `: ~ ?String o ( make )  = o ( vec_get [String] vs 0 )`
  kept the value `make` handed over whenever the new value was a borrow,
  in case the borrow was of it, and so leaked it on that path. Now the old
  value goes by its flag whenever the call lends only out of other
  owners: its summary is final (or it is `vec_get`), and every argument
  it may lend from is a parameter, or a local that owns its value and
  views nothing. The leak remains, as before, where a lend could be of
  the binding itself, and where the old value has no key to tell it
  apart from what a live borrower of it holds (a `??` payload, a cursor):
  an option payload, a library handle such as a Box, a record whose first
  owned field is an option or an enum without a key in every variant, an
  enum with a variant whose first payload is a number while a later one
  owns memory (Agora #361; #366 gives those types keys).
