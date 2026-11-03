### Fixed

- **An `inout` String given a borrowed local by name copies it** (Agora
  #456; probes inout_string_given_a_*by_name). Inside `@ put inout String o
  String other → v { : String t ( id other )  = o t }`, `t` holds a lend of
  `other`, and it was stored in the caller's binding as it was. The two
  then shared one buffer (heap-use-after-free). The same happened with `:
  String t other`, and with a lend of a `sink` parameter or of a local.
  Such a local is now copied in, as a borrowed parameter given by name
  already was.
