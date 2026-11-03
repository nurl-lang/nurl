### Fixed

- **A trait-object owner given back its own value keeps it** (Agora #459;
  probe trait_object_owner_given_back_its_own_value_on_some_runs).
  `= o ( pass o 0 )`, with `pass` handing back its `%Show` parameter on one
  run and a fresh trait object on another, released `o`'s value on the run
  that handed it back, and `o` went on to hold freed memory. A trait object
  is now told apart from another by the box that holds its value, as a
  String is by its buffer.
- **Handing back a lend of a local `?( Vec D )` is refused** (Agora #459;
  probe option_of_a_vec_of_drop_values_lent_out_of_a_local_returned).
  `^ ( maybe o k )` of a local option of a Vec of `% Drop` values that
  cannot be copied was accepted, and the caller read the Vec after it was
  released. It is now refused as an option of such a value already was.
