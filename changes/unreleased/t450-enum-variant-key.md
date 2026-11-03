### Fixed

- **An enum is told apart from another by its active variant's buffer**
  (Agora #450; probes enum_owner_given_*,
  inout_enum_given_a_value_with_an_equal_scalar_key). The run-time
  identity test that decides whether an owner was given back its own value
  keyed an enum by its first payload slot. In `: | E { A i String N }`,
  two values `A 7 …` had the same key, so `= o ( epick o other 1 )` took
  `other`'s value for `o`'s own and both released it. An enum is now keyed
  by the first payload of its active variant that owns a heap buffer, so
  an enum owner given back its own value through a forwarder keeps it too.
