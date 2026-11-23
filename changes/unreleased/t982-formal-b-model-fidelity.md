### Changed

- **The `Vec` models in `formal/B/Vec.lean` follow the runtime more closely.**
  These are proof-only changes. The compiler, stdlib and runtime are not
  touched.
  - `releaseFrom` (`__vec_release_from` with elements whose drop runs code)
    now frees its private buffer after the drop loop, as
    `nurl_vec_move_drop_dtor` does. `releaseFrom_ok` states that the buffer
    is no longer live afterwards.
  - A packed `Vec` (`vec_with_cap_packed`, `vec_split_off_packed`) is now
    modelled with its stored capacity (`PVec`, `PRep`):
    - below that capacity, a push stores in place and allocates nothing
      (`packedPush_room`);
    - at it, the push detaches and grows from the stored capacity, not from
      4 (`packedPush_ok`).
  - When the last strong `Arc` handle drops, the value slot is now emptied
    in the model too, as it is in the emitted code. Moving the value out
    through the field stores `zeroinitializer` into the slot. `RcCell`
    gains `.gone`, and `ArcInv` requires it on a block that only `Weak`
    handles name. `upgrade_ok` also states that a failed upgrade finds the
    slot empty.
