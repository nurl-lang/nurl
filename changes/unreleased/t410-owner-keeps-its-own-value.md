### Fixed

- **An owner given back its own old value keeps it** (Agora #410; probes
  *_owner_given_back_*). Take `: ?String e ? == c 1 ( fwd o ) ( make2 )`
  and then `= o ( fwd e )`. On the run where `e` held `o`'s value, the `=`
  released it while `o` went on to hold it (heap-use-after-free). The same
  happened when `e` came from a forwarder defined below its caller, from `(
  fwd ( fwd o ) )`, or was re-pointed to `( fwd o )` by `=`, or with `= o
  e` by name. Where `e` was a known borrower, the old value went to the
  first borrower holding it, which could release it under `o`. An owner
  given a value whose key at run time is its old value's now keeps it, for
  options, Strings, Vecs and keyed structs, and nothing is dropped or
  handed over.
