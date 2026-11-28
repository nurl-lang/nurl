### Removed

- **tools/ncore/prims.py** (AGORA-1046). The reference checker kept its own
  copy of the declared summaries of the standard library's raw functions.
  nurlc's ownership engine has the same table (`eng_prims`), and every new
  primitive had to be added to both. Now `nurlc --emit-core` prints that
  table, one `prim` line per function, and the checker reads it
  (`fromnurlc.py`). The 118 entries agreed except one:
  `__nurl_slice_copy_v`, where nurlc's answer, held at the copy's root,
  now decides. No probe changes verdict over the 4452 hole probes. A
  certificate's `library-summaries` row no longer names the Python file; it
  names what the term rests on, `packages/nurl-cert/src/tolean.nu` and
  `formal/B`. This follows the owner's rule that no Python mirrors a NURL
  component (agora note python-dev-only).
