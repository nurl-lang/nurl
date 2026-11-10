### Fixed

- **`vec_retain` leaves a `Vec` that can be dropped, or used, when a
  destructor or its predicate panics** (Agora #624). Under `recover`, a
  `% Drop` element that `vec_retain` rejected and whose destructor
  panicked crashed the program: each rejected element was dropped inside
  the loop while the `Vec` still had its old length, so the panic's drain
  dropped the `Vec` over slots already given up (a null read in the
  destructor, a double free). A predicate that panicked part-way did the
  same to elements of any owning type, a `String` included: the slots
  between the kept elements and the one being judged were given up or
  stale. `vec_retain` now judges every element first, swapping the kept
  ones to the front, so the `Vec` holds each of its elements exactly once
  whenever the predicate runs; then it lowers the length to the kept
  elements and drops the others through `mem_drop_range`, as
  `vec_truncate` does. A destructor that panics leaves exactly the kept
  elements, in order, in a `Vec` a `recover` around the call can go on
  with, and the other rejected elements are still dropped, once each; a
  predicate that panics leaves every element, the kept ones so far in
  front.

### Changed

- **`vec_retain` drops the rejected elements after it has judged every
  element** (Agora #624), not one by one between the predicate's calls,
  and in no order of their own (the kept elements keep theirs). Measured
  over a million elements, in instructions: for a `( Vec i )` the same
  when every third is rejected (14,220,197 before, 14,220,195 now) and
  three an element fewer for the kept ones ahead of the first rejected
  (all kept: 9,886,887 before, 6,886,872 now); for a `( Vec String )`
  three more for each rejected element, the second pass over them (0.1 %
  of a program that builds the million, rejects every third and drops
  the rest).
