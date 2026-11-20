### Fixed

- **The ownership engine (`--engine`) follows three more of nurlc's rules** (AGORA-869). An ordinary compile is unchanged.
  - A value taken whole out of its place keeps the views it holds of its own buffer. `?? o { T x → ( vec_push [Tk] d x ) }`, with `x` viewing its own String, was falsely refused.
  - A value handed back must still be live after the exit's own releases (agora #918), for the views it holds of the caller's storage (places rooted at a parameter): a local's `% Drop` that clears a shared payload the result views through a parameter is refused, as in nurlc. What the value took over from the frame's own locals, such as a join's arms, is not checked again there. Five probes the engine accepted are refused now.
  - Releasing an owned slice of `% Drop` values runs each element's drop (agora #931). Two probes are refused now.
