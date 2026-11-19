### Fixed

- **Deeply nested options compile in linear time** (AGORA-914). A chain of `??` matches through options nested N deep took time exponential in N: ×1.9 per level, 31 s at 20 deep, and 70 deep never finished. Each option's drop twin was named through its payload's, recursively, and asked again per level. Whether an inner option owns anything is now asked of its payload directly, not by building its twin: 40 deep checks in 0.08 s, 70 deep in 0.35 s.
