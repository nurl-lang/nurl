# lingbot-map.pt — checkpoint inventory

Extracted from the real checkpoint (`robbyant/lingbot-map`, 4 632 303 465 bytes).
The root object is a **bare `OrderedDict` state_dict** — not wrapped in
`{"model": …}` — so `torchpt` reports these names unprefixed.

**1342 tensors, 1,157,943,540 parameters**, dtypes: f32×1342.

## Top level

| module | tensors | parameters |
|---|---:|---:|
| `aggregator` | 1211 | 909,114,368 |
| `camera_head` | 69 | 216,174,610 |
| `depth_head` | 62 | 32,654,562 |

> There is **no `point_head`** in this checkpoint — `enable_point` is off,
> which is `GCTStream`'s default. World points come from unprojecting the
> depth map, not from a second DPT head.

## Every tensor

Indexed modules are collapsed to `N`; every index has the same shapes.
`count` is how many tensors the collapsed name stands for.


### `aggregator`

| tensor | dtype | shape | count |
|---|---|---|---:|
| `aggregator.camera_token` | f32 | 1×2×1×1024 | 1 |
| `aggregator.register_token` | f32 | 1×2×4×1024 | 1 |
| `aggregator.scale_token` | f32 | 1×2×1×1024 | 1 |
| `aggregator.patch_embed.cls_token` | f32 | 1×1×1024 | 1 |
| `aggregator.patch_embed.pos_embed` | f32 | 1×1370×1024 | 1 |
| `aggregator.patch_embed.register_tokens` | f32 | 1×4×1024 | 1 |
| `aggregator.patch_embed.mask_token` | f32 | 1×1024 | 1 |
| `aggregator.patch_embed.patch_embed.proj.weight` | f32 | 1024×3×14×14 | 1 |
| `aggregator.patch_embed.patch_embed.proj.bias` | f32 | 1024 | 1 |
| `aggregator.patch_embed.blocks.N.norm1.weight` | f32 | 1024 | 24 |
| `aggregator.patch_embed.blocks.N.norm1.bias` | f32 | 1024 | 24 |
| `aggregator.patch_embed.blocks.N.attn.qkv.weight` | f32 | 3072×1024 | 24 |
| `aggregator.patch_embed.blocks.N.attn.qkv.bias` | f32 | 3072 | 24 |
| `aggregator.patch_embed.blocks.N.attn.proj.weight` | f32 | 1024×1024 | 24 |
| `aggregator.patch_embed.blocks.N.attn.proj.bias` | f32 | 1024 | 24 |
| `aggregator.patch_embed.blocks.N.ls1.gamma` | f32 | 1024 | 24 |
| `aggregator.patch_embed.blocks.N.norm2.weight` | f32 | 1024 | 24 |
| `aggregator.patch_embed.blocks.N.norm2.bias` | f32 | 1024 | 24 |
| `aggregator.patch_embed.blocks.N.mlp.fc1.weight` | f32 | 4096×1024 | 24 |
| `aggregator.patch_embed.blocks.N.mlp.fc1.bias` | f32 | 4096 | 24 |
| `aggregator.patch_embed.blocks.N.mlp.fc2.weight` | f32 | 1024×4096 | 24 |
| `aggregator.patch_embed.blocks.N.mlp.fc2.bias` | f32 | 1024 | 24 |
| `aggregator.patch_embed.blocks.N.ls2.gamma` | f32 | 1024 | 24 |
| `aggregator.patch_embed.norm.weight` | f32 | 1024 | 1 |
| `aggregator.patch_embed.norm.bias` | f32 | 1024 | 1 |
| `aggregator.frame_blocks.N.norm1.weight` | f32 | 1024 | 24 |
| `aggregator.frame_blocks.N.norm1.bias` | f32 | 1024 | 24 |
| `aggregator.frame_blocks.N.attn.qkv.weight` | f32 | 3072×1024 | 24 |
| `aggregator.frame_blocks.N.attn.qkv.bias` | f32 | 3072 | 24 |
| `aggregator.frame_blocks.N.attn.q_norm.weight` | f32 | 64 | 24 |
| `aggregator.frame_blocks.N.attn.q_norm.bias` | f32 | 64 | 24 |
| `aggregator.frame_blocks.N.attn.k_norm.weight` | f32 | 64 | 24 |
| `aggregator.frame_blocks.N.attn.k_norm.bias` | f32 | 64 | 24 |
| `aggregator.frame_blocks.N.attn.proj.weight` | f32 | 1024×1024 | 24 |
| `aggregator.frame_blocks.N.attn.proj.bias` | f32 | 1024 | 24 |
| `aggregator.frame_blocks.N.ls1.gamma` | f32 | 1024 | 24 |
| `aggregator.frame_blocks.N.norm2.weight` | f32 | 1024 | 24 |
| `aggregator.frame_blocks.N.norm2.bias` | f32 | 1024 | 24 |
| `aggregator.frame_blocks.N.mlp.fc1.weight` | f32 | 4096×1024 | 24 |
| `aggregator.frame_blocks.N.mlp.fc1.bias` | f32 | 4096 | 24 |
| `aggregator.frame_blocks.N.mlp.fc2.weight` | f32 | 1024×4096 | 24 |
| `aggregator.frame_blocks.N.mlp.fc2.bias` | f32 | 1024 | 24 |
| `aggregator.frame_blocks.N.ls2.gamma` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.norm1.weight` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.norm1.bias` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.attn.qkv.weight` | f32 | 3072×1024 | 24 |
| `aggregator.global_blocks.N.attn.qkv.bias` | f32 | 3072 | 24 |
| `aggregator.global_blocks.N.attn.q_norm.weight` | f32 | 64 | 24 |
| `aggregator.global_blocks.N.attn.q_norm.bias` | f32 | 64 | 24 |
| `aggregator.global_blocks.N.attn.k_norm.weight` | f32 | 64 | 24 |
| `aggregator.global_blocks.N.attn.k_norm.bias` | f32 | 64 | 24 |
| `aggregator.global_blocks.N.attn.proj.weight` | f32 | 1024×1024 | 24 |
| `aggregator.global_blocks.N.attn.proj.bias` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.ls1.gamma` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.norm2.weight` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.norm2.bias` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.mlp.fc1.weight` | f32 | 4096×1024 | 24 |
| `aggregator.global_blocks.N.mlp.fc1.bias` | f32 | 4096 | 24 |
| `aggregator.global_blocks.N.mlp.fc2.weight` | f32 | 1024×4096 | 24 |
| `aggregator.global_blocks.N.mlp.fc2.bias` | f32 | 1024 | 24 |
| `aggregator.global_blocks.N.ls2.gamma` | f32 | 1024 | 24 |

### `camera_head`

| tensor | dtype | shape | count |
|---|---|---|---:|
| `camera_head.empty_pose_tokens` | f32 | 1×1×9 | 1 |
| `camera_head.trunk.N.norm1.weight` | f32 | 2048 | 4 |
| `camera_head.trunk.N.norm1.bias` | f32 | 2048 | 4 |
| `camera_head.trunk.N.attn.qkv.weight` | f32 | 6144×2048 | 4 |
| `camera_head.trunk.N.attn.qkv.bias` | f32 | 6144 | 4 |
| `camera_head.trunk.N.attn.proj.weight` | f32 | 2048×2048 | 4 |
| `camera_head.trunk.N.attn.proj.bias` | f32 | 2048 | 4 |
| `camera_head.trunk.N.ls1.gamma` | f32 | 2048 | 4 |
| `camera_head.trunk.N.norm2.weight` | f32 | 2048 | 4 |
| `camera_head.trunk.N.norm2.bias` | f32 | 2048 | 4 |
| `camera_head.trunk.N.mlp.fc1.weight` | f32 | 8192×2048 | 4 |
| `camera_head.trunk.N.mlp.fc1.bias` | f32 | 8192 | 4 |
| `camera_head.trunk.N.mlp.fc2.weight` | f32 | 2048×8192 | 4 |
| `camera_head.trunk.N.mlp.fc2.bias` | f32 | 2048 | 4 |
| `camera_head.trunk.N.ls2.gamma` | f32 | 2048 | 4 |
| `camera_head.token_norm.weight` | f32 | 2048 | 1 |
| `camera_head.token_norm.bias` | f32 | 2048 | 1 |
| `camera_head.trunk_norm.weight` | f32 | 2048 | 1 |
| `camera_head.trunk_norm.bias` | f32 | 2048 | 1 |
| `camera_head.embed_pose.weight` | f32 | 2048×9 | 1 |
| `camera_head.embed_pose.bias` | f32 | 2048 | 1 |
| `camera_head.poseLN_modulation.N.weight` | f32 | 6144×2048 | 1 |
| `camera_head.poseLN_modulation.N.bias` | f32 | 6144 | 1 |
| `camera_head.pose_branch.fc1.weight` | f32 | 1024×2048 | 1 |
| `camera_head.pose_branch.fc1.bias` | f32 | 1024 | 1 |
| `camera_head.pose_branch.fc2.weight` | f32 | 9×1024 | 1 |
| `camera_head.pose_branch.fc2.bias` | f32 | 9 | 1 |

### `depth_head`

| tensor | dtype | shape | count |
|---|---|---|---:|
| `depth_head.norm.weight` | f32 | 2048 | 1 |
| `depth_head.norm.bias` | f32 | 2048 | 1 |
| `depth_head.projects.N.weight` | f32 | 256×2048×1×1 | 4 |
| `depth_head.projects.N.bias` | f32 | 256 | 4 |
| `depth_head.resize_layers.N.weight` | f32 | 256×256×4×4 | 3 |
| `depth_head.resize_layers.N.bias` | f32 | 256 | 3 |
| `depth_head.scratch.layer1_rn.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.layer2_rn.weight` | f32 | 256×512×3×3 | 1 |
| `depth_head.scratch.layer3_rn.weight` | f32 | 256×1024×3×3 | 1 |
| `depth_head.scratch.layer4_rn.weight` | f32 | 256×1024×3×3 | 1 |
| `depth_head.scratch.refinenet1.out_conv.weight` | f32 | 256×256×1×1 | 1 |
| `depth_head.scratch.refinenet1.out_conv.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit1.conv1.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit1.conv1.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit1.conv2.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit1.conv2.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit2.conv1.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit2.conv1.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit2.conv2.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet1.resConfUnit2.conv2.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet2.out_conv.weight` | f32 | 256×256×1×1 | 1 |
| `depth_head.scratch.refinenet2.out_conv.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit1.conv1.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit1.conv1.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit1.conv2.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit1.conv2.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit2.conv1.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit2.conv1.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit2.conv2.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet2.resConfUnit2.conv2.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet3.out_conv.weight` | f32 | 256×256×1×1 | 1 |
| `depth_head.scratch.refinenet3.out_conv.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit1.conv1.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit1.conv1.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit1.conv2.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit1.conv2.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit2.conv1.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit2.conv1.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit2.conv2.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet3.resConfUnit2.conv2.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet4.out_conv.weight` | f32 | 256×256×1×1 | 1 |
| `depth_head.scratch.refinenet4.out_conv.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet4.resConfUnit2.conv1.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet4.resConfUnit2.conv1.bias` | f32 | 256 | 1 |
| `depth_head.scratch.refinenet4.resConfUnit2.conv2.weight` | f32 | 256×256×3×3 | 1 |
| `depth_head.scratch.refinenet4.resConfUnit2.conv2.bias` | f32 | 256 | 1 |

> `refinenet4` has **no `resConfUnit1`** — it is built with
> `has_residual=False` because it is the coarsest block and has nothing
> to fuse with, and the unit is not constructed at all rather than
> constructed and left unused. A loader that reads `resConfUnit1` for
> all four blocks will fail on this one.
>
> The residual units are built with `nn.ReLU(inplace=True)`, so the
> first activation overwrites the tensor handed in and the residual
> added at the end is `relu(x)`, not `x`. This is not visible in the
> checkpoint at all, and getting it wrong is silent — see the stage 5
> notes in the README.
| `depth_head.scratch.output_conv1.weight` | f32 | 128×256×3×3 | 1 |
| `depth_head.scratch.output_conv1.bias` | f32 | 128 | 1 |
| `depth_head.scratch.output_conv2.N.weight` | f32 | 32×128×3×3 | 2 |
| `depth_head.scratch.output_conv2.N.bias` | f32 | 32 | 2 |
