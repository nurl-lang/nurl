// unikernel/net/netdev_virtio.nu — the interface is a virtio-net
// device.
//
// The guest's half of the pair whose other half is netdev_none.nu:
// three functions, chosen by the build, so the socket layer above has
// one seam rather than a conditional. Everything real is in
// drivers/virtionet.nu; this file is the adapter that turns a driver
// object into the four calls the shim makes.
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtq.nu`
$ `stdlib/hal/virtio.nu`
$ `unikernel/drivers/virtionet.nu`

: ~ i g_nic 0

@ netdev_open → i {
    ? != g_nic 0 { ^ 1 } {}
    : *VirtioNet nic ( vnet_open 64 )
    ? ! ( vnet_ready nic ) { ^ 0 } {}
    = g_nic # i nic
    ^ 1
}

@ netdev_mac → i {
    ? == g_nic 0 { ^ 0 } {}
    ^ ( vnet_mac # *VirtioNet g_nic )
}

// One frame into `buf`, or 0 when the device has none. The copy is
// unavoidable at this seam: the driver owns the receive buffer and
// hands it straight back to the device, so a caller that kept a
// pointer into it would be reading a buffer the device is refilling.
@ netdev_rx s buf i cap → i {
    ? == g_nic 0 { ^ 0 } {}
    : ( Vec u ) f ( vec_new [u] )
    : i n ( vnet_rx # *VirtioNet g_nic f )
    : i take ? > n cap cap n
    ? > take 0 { ( nurl_memcpy buf # s ( vec_data [u] f ) take ) } {}
    ( vec_free [u] f )
    ^ take
}

@ netdev_tx s buf i len → i {
    ? == g_nic 0 { ^ 0 } {}
    : ( Vec u ) f ( vec_new [u] )
    ( bytes_extend_raw f buf len )
    : b ok ( vnet_tx # *VirtioNet g_nic f 0 len )
    ( vec_free [u] f )
    ^ ? ok len 0
}
