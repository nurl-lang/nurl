#!/bin/sh
# Build + run the playground container locally, with the same defense-in-
# depth limits a production host should apply (the in-image hardening —
# non-root USER, compile timeouts, per-IP rate limit, output GC — rides in
# the image itself; these flags add the kernel-level backstop):
#   --memory / --cpus     compile bombs can't OOM/starve the host
#   --pids-limit          fork bombs die at the cgroup wall
#   --cap-drop ALL        compiling needs no capabilities
#   --security-opt no-new-privileges   no setuid re-escalation
docker build -f nurlapi/Dockerfile -t nurllang/nurl:latest .
docker run --rm -p 8000:8000 \
    --memory 4g --cpus 4 --pids-limit 512 \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    nurllang/nurl:latest
