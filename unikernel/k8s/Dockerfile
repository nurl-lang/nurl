# unikernel/k8s/Dockerfile — a container whose payload is a machine.
#
# The image carries two things: a hypervisor, and a ~610 KB bootable
# ELF that contains an HTTP server and everything under it. There is no
# base OS for the payload to run on, because the payload does not run
# on an OS.
#
# The build context is the staging directory that `build_image.sh`
# assembles (server.elf + entrypoint.sh), not the repository — the
# repository's .dockerignore excludes build/, and a context of two
# files is the honest description of what goes in anyway.
#
# Build:  unikernel/k8s/build_image.sh
FROM alpine:3.22

# qemu-system-x86_64 only. Nothing here is for the guest — the guest
# brought its own everything.
RUN apk add --no-cache qemu-system-x86_64

COPY server.elf /srv/server.elf
COPY entrypoint.sh /srv/entrypoint.sh

# QEMU's user-mode network stack needs no privileges, no tap device and
# no CAP_NET_ADMIN, so the container runs as an ordinary unprivileged
# user. Without /dev/kvm it emulates instead of virtualising; the guest
# cannot tell, and the boot is still under two seconds.
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/srv/entrypoint.sh"]
