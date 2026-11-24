# octree

An octree over 3-D points in which each node holds an **even sample** of what
falls in it. This is the structure behind level of detail for big point
clouds (Potree, 3D Tiles point tilesets): drawing a node and its ancestors
shows its region at that node's spacing, and its children add detail.

```nurl
$ `deps/octree/src/octree.nu`

@ main → i {
    : ( Vec f ) xyz ( vec_new [f] )     // x y z, x y z, …
    ( vec_push [f] xyz 0.0 ) ( vec_push [f] xyz 0.0 ) ( vec_push [f] xyz 0.0 )
    ( vec_push [f] xyz 1.0 ) ( vec_push [f] xyz 2.0 ) ( vec_push [f] xyz 3.0 )
    : Octree t ( oc_build ( slice_from_vec [f] xyz ) 50000 128 1 )  // capacity, grid, seed
    : ~ i k 0
    ~ < k ( oc_count t ) {
        : ( Slice i ) own ( oc_points t k )  // indices into xyz / 3
        ( nurl_print ( nurl_str_int ( slice_len [i] own ) ) ) ( nurl_print `\n` )
        = k + k 1
    }
    ^ 0
}
```

**How a node is filled.**
- The root's cube encloses every point.
- A node lays a `grid`³ grid over its cube and keeps the first point to land in each empty cell. The rest go to its octants, which have half-size cubes and so finer cells.
- A node with at most `capacity` points keeps them all and is a leaf.
- Points are visited in a seeded shuffle, so the sample is even instead of following the input's write order, and a build is repeatable.

Every point is in exactly one node, which is 3D Tiles' ADD refinement.

| function | |
|---|---|
| `oc_build xyz capacity grid seed → Octree` | `xyz` holds three numbers per point |
| `oc_count t` | nodes, numbered parents first |
| `oc_parent t k`, `oc_level t k` | `-1` is the root's parent |
| `oc_points t k → ( Slice i )` | the node's own points (indices) |
| `oc_center t k axis`, `oc_half t k` | the node's cube |
| `oc_spacing t k` | its sampling cell's size: the detail it adds |
| `oc_min t k axis`, `oc_max t k axis` | tight bounds of its whole subtree |
| `oc_used t`, `oc_dropped t` | points placed, and non-finite points left out |

**Edge cases.**
- Non-finite points are dropped and counted.
- A node becomes a leaf when its cube is too small to halve at its coordinates (1e-12 of their magnitude). So one point copied many times, or a survey 6700 km from the origin, ends in sensible leaves instead of boxes below float64's resolution.

## Tests

```
sh tests/octree_test.sh
```

The test checks four point sets: a noisy terrain with a dense blob, one point
copied 6000 times, a millimetre of points 6700 km out, and an empty set. On each
tree it checks:
- Every point is placed exactly once.
- Parents come first, and children are half-size octants.
- Points lie inside their cubes.
- An inner node keeps one point per cell, and leaves stay within capacity.
- Tight bounds are exact.
- The same seed gives the same tree, and the root's sample is even.
