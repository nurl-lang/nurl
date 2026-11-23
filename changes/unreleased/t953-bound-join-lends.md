### Fixed

- **A `:` binding of a join or a value block keeps what its producer lends** (AGORA-953, part of AGORA-242). Four of the elaborated twins of closed probes, and two neighbours, read freed memory. Each binds the form first and then hands the binding on (`: e ? c x ( mk )` and then `= t e`, `^ e`, or `: e2 e`). The unbound form copies, moves or refuses, and the bound one now does the same:
  - handed to a binding of an outer block, the binding's lent paths are copied in there;
  - a value with a `% Drop` is refused, with the unbound form's message;
  - handed back, a non-copyable value is refused where the join's calls lend this frame's values;
  - a value block's raw `s` view of its own local gets a copy.

  No source changes: programs that compiled before compile the same, except the ones that read freed memory, which are now copied or refused. Three closure-valued twins stay open (tools/fuzz/holes/open/t242.md).
