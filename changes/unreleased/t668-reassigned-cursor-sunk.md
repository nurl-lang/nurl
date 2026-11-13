### Fixed

- **A `: ~` binding of a value block's tail binding is routed like the `:` one** (Agora #668). `: ~ String e { : String s … s }  ( string_push_str e … )  ( eat e )` and its Vec twin freed the block's value twice. The `: ~` spelling was kept off the route because a cursor reassigned later would still hand its first owner's value away. A cursor now hands over only what it holds, by its own per-run flag (Agora #781), so the `: ~` spelling takes the same route. Probes for a reassigned String / Vec / struct cursor handed to a `sink` (#668 item 2, closed by github#1836) are added.
