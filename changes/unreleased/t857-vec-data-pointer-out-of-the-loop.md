### Performance

- **A loop that indexes a Vec reads its data pointer once, not once per iteration** (AGORA-857). `vec_at` / `vec_put` read the data pointer ahead of their bounds check, but the optimiser sank that load past the check, and from there it could not lift it out of the loop. A load may be lifted above a branch only when the pointer is known to be readable, and nothing said so. Each Vec control-block read now says so (`llvm.assume` with `dereferenceable`) right before its own load. That claims nothing the load does not already require, so the claim stays where the read was written, and the loop keeps the pointer in a register. Instructions executed, bench.sh's pipeline:
  - **`bench/safe_record_array`:** 565.4M → 545.4M (−3.5 %).
  - **`bench/payload_state_machine`:** 252.7M → 242.2M (−4.1 %).
  - **`bench/stdlib_hotpath`, `string_build_16`:** 532 → 451 per operation (−15 %).
  - **The other bench rows** are unchanged (to within ±14 instructions), with the same output.
  - **Every module's IR** gains two lines.
