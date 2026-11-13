### Fixed

- **A view of a value moved into a struct's field ends when that field changes** (Agora #799). After `: X xx @ X { xs }` or `= . xx v xs`, a slice of `xs` taken before the move could outlive a change of the field and read the moved buffer (heap-use-after-free). That happened when the field was grown with `( vec_reserve . xx v 4096 )`, when a callee grew `xx`'s field, or when `( w @ X { xs } )` was called and `w` grew it. The view now belongs to the field `xx.v`:
  - a change of that field, or of anything it is part of, ends the view;
  - a change of another field does not;
  - reading the view stays fine.

  This also covers a nested literal `@ Y { @ X { xs } }`, a nested assignment `= . . yy x v xs`, and views kept in a Vec or captured by a closure.

### Changed

- **Replacing another field after a field assignment keeps the view** (Agora #799): `= . xx v xs`, then `= . xx w ys`, then reading a slice of `xs`. This is now accepted, as it already was for a slice taken from `. xx v`.

### Known issues

- **A callee is judged per argument, not per field.** A callee that grows one field of a struct ends the views of a value moved into another field of it: `( process p )` pushing to `. p out` ends a slice of the `inp` moved into `p`. The same holds on main for a view taken from the field.
- **A join of literals inside a field still hands the moved value's views to the whole owner** (`@ Y { ? c @ X { xs } @ X { ys } }`, Agora #828).
