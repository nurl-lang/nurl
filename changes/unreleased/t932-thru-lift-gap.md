### Known issues

- **The formal proof does not yet type a through-changing call that passes an argument holding views** (AGORA-932). A2 still refuses a call such as `( f vv )`, where `f` changes through an element of the slices `vv` holds, the shape AGORA-933 fixed in nurlc. `formal/A2/THRU_LIFT_DESIGN.md` records why:
  - the lift gives every callee binding what all the arguments hold;
  - a change reached through a view or an element ends more at the caller than in the callee (`A2/ThruLiftKinds.lean` proves this case by case);
  - a move out of a parameter erases what it points into.

  It also records what typing the call would take: symbolic provenance for parameters that hold views. nurlc refuses these programs, so this is a gap in what the proof covers, not a hole. NURL source is unchanged.
