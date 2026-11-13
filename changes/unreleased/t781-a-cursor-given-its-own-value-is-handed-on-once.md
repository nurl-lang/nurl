### Fixed

- **A mutable second name of an owner, given a field or a value of its own and then handed on, frees each value once** (Agora #781). `: ~ P e p` makes `e` a cursor over `p`. After `= . e name ( string_from … )`, `^ e` freed the new name under the caller, and with a second heap field `p` freed the field that went out with `e`. After `= e ( string_from … )`, handing `e` to a `sink` cleared `p`'s flag too, so `p`'s string leaked. Now:
  - A cursor handed back uncopied takes its own fields with it, and the owner drops only the values those fields replaced. The field-owner flag answers per run, so a store inside one arm of a `?` is covered.
  - A cursor handed on clears its sources' flags only on the runs it still holds their value: its own flag, read before the hand-over, is clear.
  - Traversal cursors (`= cur . cur next`) are unchanged. A cursor given a field and then handed to a `sink` is still refused.
