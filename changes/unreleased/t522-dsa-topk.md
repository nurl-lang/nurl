### Performance

- **nurllama's DSA indexer selects its top-k in linear time** (Agora #522; nurllama 0.26.0, gpukit 0.11.14). The selection was npos² work a position, so it dominated a long prompt's prefill. Now a 32k-key, 64-position launch takes 0.31 ms instead of 25.5 ms on CUDA, and 9.6 ms instead of 3.7 s on the CPU backend. The keys it keeps are the same, ties to the lower index. gpukit's checked kernels gain `FKEY(x)`, a float's order-preserving key, for exact threshold searches.
