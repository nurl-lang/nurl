// unikernel/net/netdev_none.nu — the machine has no network interface.
//
// One of two implementations of the same three functions; the other is
// netdev_virtio.nu, and the build picks one. This is not a stub in the
// sense this directory distrusts: "there is no interface" is a true
// statement about a Linux -nostdlib process, which reaches the network
// through a kernel it is not allowed to call, and the socket layer
// above answers it by running everything over loopback — which is
// exactly what the 449 corpus tests exercise.

@ netdev_open → i { ^ 0 }

@ netdev_mac → i { ^ 0 }

@ netdev_rx s buf i cap → i { ^ 0 }

@ netdev_tx s buf i len → i { ^ 0 }
