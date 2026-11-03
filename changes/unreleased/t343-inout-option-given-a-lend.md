### Fixed

- **An `inout` option given a lend of another value copies it** (Agora
  #343; probes inout_option_given_*). `@ put inout ?String o ( Vec String )
  vs i k → v { = o ( vec_get [String] vs 0 ) }` stored the element as it
  was, so the caller's binding and the Vec both owned it
  (heap-use-after-free). The same happened with a lend of another
  parameter (`= o ( idopt other )`) or a call that hands one back on some
  runs. The same shape with a local Vec failed to compile (an undefined
  helper). The result is now compared with the old value by its payload,
  as for an `inout` String: the old value itself stays, and anything else
  is copied in and the old value released.
