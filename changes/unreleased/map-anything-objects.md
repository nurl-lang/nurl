### Added

- **map-anything: 3-D objects from a reconstruction, or a region cut from it** (map-anything 0.10.0, ply 0.4.0, glb 0.1.0). `--scene` keeps each view's camera, depths, mask and colours; `map-anything mesh` fuses them in a box (TSDF), extracts the surface (marching tetrahedra), drops the loose pieces and writes a binary glTF. In `serve`, the cloud viewer gets a region box and a "make 3-D object" button, objects are queued like reconstructions, and the job list links the object and its download; the viewer also shows `.glb` meshes.
