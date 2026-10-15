// packages/lingbot-map/src/geom.nu — camera geometry for LingBot-Map.
//
// The model predicts, per frame, a 9-vector "pose encoding":
//
//     [0:3]  T      translation, world→camera
//     [3:7]  quat   rotation, world→camera, XYZW (scalar LAST)
//     [7]    fov_h
//     [8]    fov_w
//
// Everything downstream — the extrinsics, the intrinsics, unprojecting a
// depth map into world space — falls out of that. This module is the
// arithmetic, host-side in f64: it runs once per frame over 9 numbers
// and a H*W depth map, so there is nothing here worth a kernel.
//
// Conventions, kept exactly as the reference has them because they are
// the kind of thing that silently mirrors a reconstruction:
//   * OpenCV camera axes: x right, y down, z forward.
//   * Extrinsics are world→camera ("camera from world"), [R|t], 3x4.
//   * The quaternion is scalar-LAST (i, j, k, r), not scalar-first.
//   * The principal point is assumed to be the image centre.
//
//   ( quat_to_mat qx qy qz qw out )     → v    out = 9 doubles, row-major
//   ( mat_to_quat m out )               → v    out = 4 doubles, XYZW
//   ( pose_enc_to_extri pe out )        → v    out = 12 doubles (3x4)
//   ( pose_enc_to_intri pe H W out )    → v    out = 9 doubles (3x3)
//   ( se3_inverse m4 out )              → v    4x4 → 4x4
//   ( unproject px py depth Kinv c2w out ) → v  one pixel → world xyz

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

// ── quaternion (XYZW, scalar last) → 3x3 rotation, row-major ────────
//
// The reference divides by the quaternion's own squared norm rather than
// normalising first, so a non-unit quaternion still produces a proper
// rotation. Predicted quaternions are never exactly unit, and the two
// spellings differ in the last bits — this one matches.
@ quat_to_mat f qi f qj f qk f qr ( Slice f ) out → v {
    : f n2 + + + * qi qi * qj qj * qk qk * qr qr
    : f two_s ? > n2 0.0 / 2.0 n2 0.0
    ( slice_put [f] out 0 - 1.0 * two_s + * qj qj * qk qk )
    ( slice_put [f] out 1 * two_s - * qi qj * qk qr )
    ( slice_put [f] out 2 * two_s + * qi qk * qj qr )
    ( slice_put [f] out 3 * two_s + * qi qj * qk qr )
    ( slice_put [f] out 4 - 1.0 * two_s + * qi qi * qk qk )
    ( slice_put [f] out 5 * two_s - * qj qk * qi qr )
    ( slice_put [f] out 6 * two_s - * qi qk * qj qr )
    ( slice_put [f] out 7 * two_s + * qj qk * qi qr )
    ( slice_put [f] out 8 - 1.0 * two_s + * qi qi * qj qj )
}

@ __gm_sqrt_pos f x → f { ^ ? > x 0.0 ( float_sqrt x ) 0.0 }

// 3x3 rotation (row-major) → quaternion XYZW.
//
// Four candidate quaternions are formed, one per component taken as the
// pivot, and the one with the largest |component| is kept — the standard
// guard against the cancellation that ruins the naive trace formula near
// a 180-degree rotation.
@ mat_to_quat ( Slice f ) m ( Slice f ) out → v {
    : f m00 ( slice_at [f] m 0 )
    : f m01 ( slice_at [f] m 1 )
    : f m02 ( slice_at [f] m 2 )
    : f m10 ( slice_at [f] m 3 )
    : f m11 ( slice_at [f] m 4 )
    : f m12 ( slice_at [f] m 5 )
    : f m20 ( slice_at [f] m 6 )
    : f m21 ( slice_at [f] m 7 )
    : f m22 ( slice_at [f] m 8 )
    : f a0 ( __gm_sqrt_pos + 1.0 + m00 + m11 m22 )
    : f a1 ( __gm_sqrt_pos - - + 1.0 m00 m11 m22 )
    : f a2 ( __gm_sqrt_pos - + - 1.0 m00 m11 m22 )
    : f a3 ( __gm_sqrt_pos + - - 1.0 m00 m11 m22 )
    // candidate k, as (r, i, j, k) scaled by 2*a_k
    : ( Vec f ) c__v ( vec_zeroed [f] 16 )
    : ( Slice f ) c ( slice_from_vec [f] c__v )
    ( slice_put [f] c 0 * a0 a0 )
    ( slice_put [f] c 1 - m21 m12 )
    ( slice_put [f] c 2 - m02 m20 )
    ( slice_put [f] c 3 - m10 m01 )
    ( slice_put [f] c 4 - m21 m12 )
    ( slice_put [f] c 5 * a1 a1 )
    ( slice_put [f] c 6 + m10 m01 )
    ( slice_put [f] c 7 + m02 m20 )
    ( slice_put [f] c 8 - m02 m20 )
    ( slice_put [f] c 9 + m10 m01 )
    ( slice_put [f] c 10 * a2 a2 )
    ( slice_put [f] c 11 + m12 m21 )
    ( slice_put [f] c 12 - m10 m01 )
    ( slice_put [f] c 13 + m02 m20 )
    ( slice_put [f] c 14 + m12 m21 )
    ( slice_put [f] c 15 * a3 a3 )
    : ~ i best 0
    : ~ f bestv a0
    ? > a1 bestv { = best 1 = bestv a1 } {}
    ? > a2 bestv { = best 2 = bestv a2 } {}
    ? > a3 bestv { = best 3 = bestv a3 } {}
    : f denom ? > bestv 0.1 * 2.0 bestv 0.1
    : i base * best 4
    : f r / ( slice_at [f] c base ) denom
    : f i / ( slice_at [f] c + base 1 ) denom
    : f j / ( slice_at [f] c + base 2 ) denom
    : f k / ( slice_at [f] c + base 3 ) denom
    // scalar LAST on the way out
    ( slice_put [f] out 0 i )
    ( slice_put [f] out 1 j )
    ( slice_put [f] out 2 k )
    ( slice_put [f] out 3 r )
}

// ── pose encoding → camera matrices ─────────────────────────────────

// Extrinsics [R|t], world→camera, 3x4 row-major (12 doubles).
@ pose_enc_to_extri ( Slice f ) pe ( Slice f ) out → v {
    : ( Vec f ) r__v ( vec_zeroed [f] 9 )
    : ( Slice f ) r ( slice_from_vec [f] r__v )
    ( quat_to_mat ( slice_at [f] pe 3 ) ( slice_at [f] pe 4 ) ( slice_at [f] pe 5 ) ( slice_at [f] pe 6 ) r )
    : ~ i row 0
    ~ < row 3 {
        : ~ i col 0
        ~ < col 3 {
            ( slice_put [f] out + * row 4 col ( slice_at [f] r + * row 3 col ) )
            = col + col 1
        }
        ( slice_put [f] out + * row 4 3 ( slice_at [f] pe row ) )
        = row + row 1
    }
}

// Intrinsics from the two field-of-view angles, 3x3 row-major.
// The principal point is the image centre — the model is only ever fed
// centre-cropped frames, and the reference assumes the same.
@ pose_enc_to_intri ( Slice f ) pe i H i W ( Slice f ) out → v {
    : f fov_h ( slice_at [f] pe 7 )
    : f fov_w ( slice_at [f] pe 8 )
    : f fy / / # f H 2.0 ( float_tan / fov_h 2.0 )
    : f fx / / # f W 2.0 ( float_tan / fov_w 2.0 )
    : ~ i j 0
    ~ < j 9 { ( slice_put [f] out j 0.0 ) = j + j 1 }
    ( slice_put [f] out 0 fx )
    ( slice_put [f] out 2 / # f W 2.0 )
    ( slice_put [f] out 4 fy )
    ( slice_put [f] out 5 / # f H 2.0 )
    ( slice_put [f] out 8 1.0 )
}

// Inverse of an intrinsics matrix of the shape above (fx, fy, cx, cy) —
// upper triangular, so the closed form is exact and needs no pivoting.
@ intri_inverse ( Slice f ) k ( Slice f ) out → v {
    : f fx ( slice_at [f] k 0 )
    : f fy ( slice_at [f] k 4 )
    : f cx ( slice_at [f] k 2 )
    : f cy ( slice_at [f] k 5 )
    : ~ i j 0
    ~ < j 9 { ( slice_put [f] out j 0.0 ) = j + j 1 }
    ( slice_put [f] out 0 ? != fx 0.0 / 1.0 fx 0.0 )
    ( slice_put [f] out 2 ? != fx 0.0 / - 0.0 cx fx 0.0 )
    ( slice_put [f] out 4 ? != fy 0.0 / 1.0 fy 0.0 )
    ( slice_put [f] out 5 ? != fy 0.0 / - 0.0 cy fy 0.0 )
    ( slice_put [f] out 8 1.0 )
}

// Inverse of a 4x4 SE3 (rigid) matrix: [R|t] → [Rᵀ | −Rᵀt].
// Closed form, not a general solve — the whole point is that a rigid
// transform's inverse costs a transpose and a matrix-vector product.
@ se3_inverse ( Slice f ) m ( Slice f ) out → v {
    : ~ i r 0
    ~ < r 3 {
        : ~ i c 0
        ~ < c 3 { ( slice_put [f] out + * r 4 c ( slice_at [f] m + * c 4 r ) ) = c + c 1 }
        = r + r 1
    }
    : ~ i i2 0
    ~ < i2 3 {
        : ~ f acc 0.0
        : ~ i j 0
        ~ < j 3 {
            : i rb * j 4
            = acc + acc * ( slice_at [f] m + rb i2 ) ( slice_at [f] m + rb 3 )
            = j + j 1
        }
        ( slice_put [f] out + * i2 4 3 - 0.0 acc )
        = i2 + i2 1
    }
    ( slice_put [f] out 12 0.0 )
    ( slice_put [f] out 13 0.0 )
    ( slice_put [f] out 14 0.0 )
    ( slice_put [f] out 15 1.0 )
}

// Camera-to-world 4x4 from a pose encoding: build [R|t] world→camera,
// lift to 4x4, invert.
@ pose_enc_to_c2w ( Slice f ) pe ( Slice f ) out → v {
    : ( Vec f ) e__v ( vec_zeroed [f] 16 )
    : ( Slice f ) e ( slice_from_vec [f] e__v )
    ( pose_enc_to_extri pe e )
    ( slice_put [f] e 12 0.0 )
    ( slice_put [f] e 13 0.0 )
    ( slice_put [f] e 14 0.0 )
    ( slice_put [f] e 15 1.0 )
    ( se3_inverse e out )
}

// One pixel of a depth map → a world-space point.
//
//   camera ray   = K⁻¹ · (px, py, 1)
//   camera point = ray · depth        (NOT ray normalised — the model's
//                                      depth is along z, not range)
//   world point  = c2w · (camera point, 1)
@ unproject f px f py f depth ( Slice f ) kinv ( Slice f ) c2w ( Slice f ) out → v {
    : f cxp + + * ( slice_at [f] kinv 0 ) px * ( slice_at [f] kinv 1 ) py ( slice_at [f] kinv 2 )
    : f cyp + + * ( slice_at [f] kinv 3 ) px * ( slice_at [f] kinv 4 ) py ( slice_at [f] kinv 5 )
    : f czp + + * ( slice_at [f] kinv 6 ) px * ( slice_at [f] kinv 7 ) py ( slice_at [f] kinv 8 )
    : f xc * cxp depth
    : f yc * cyp depth
    : f zc * czp depth
    : ~ i r 0
    ~ < r 3 {
        : i rb * r 4
        : f acc + + + * ( slice_at [f] c2w rb ) xc * ( slice_at [f] c2w + rb 1 ) yc * ( slice_at [f] c2w + rb 2 ) zc ( slice_at [f] c2w + rb 3 )
        ( slice_put [f] out r acc )
        = r + r 1
    }
}
