### Added

- **New package `glb`: triangle meshes as binary glTF 2.0** (glb 0.1.0). A mesh is built vertex by vertex (position, optional normal and RGBA colour) and triangle by triangle, and written as one `.glb` that Blender, three.js and phone AR viewers open; dangling indices and partial attributes are refused. Its test checks the bytes without dependencies and, when available, with Khronos's validator (no errors, no warnings).
