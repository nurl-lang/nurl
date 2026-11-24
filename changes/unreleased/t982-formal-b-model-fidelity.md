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
  - `ArcWeak_share` is covered: `weakClone_ok` clones a held `Weak` with or
    without strong handles left, and only the weak count moves.
    `arcDrop_ok` now states that the value handed back at the last release
    is the one the block held, and `weakDrop_ok` states the block's
    liveness afterwards, not only the returned flag.
  - `vec_set`'s length check is modelled (`setC`, `setC_ok`): at or past
    the length it answers `F` and writes nothing, even with capacity left.
    `set` is named as the raw store it is.
  - `vec_reserve` checks the byte size of the capacity it rounds up to
    (`reserveZ`), as `__vec_grow`'s `alloc_size` does, not only the count.
    `reserveC_size_gap` shows the case the count check alone lets through.
  - `vec_append`'s complete call, with the drop of the emptied source, is
    covered (`appendFree_ok`), also for a source that was already empty.
  - The release of a packed `Vec` after its detach frees both the control
    block and the new buffer (`packedPush_release`).
  - `releaseFrom_fresh` states when no id is reused across a release: for
    destructors that never move the fresh-id counter back.
