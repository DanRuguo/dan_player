// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the adjacent FLUTTER-LICENSE.txt file.
// Adapted for Dan Player: interpolate samples along the stretched axis. The
// pinned engine's implicit ImageFilter.shader sampler uses nearest filtering,
// making thin letters/punctuation jump as individual pixel rows change.
// Keep Flutter's uniform ABI and Android mapping/spring, without changing SDK.

// This shader was created based on or with reference to the implementation found at:
// https://cs.android.com/android/platform/superproject/main/+/512046e84bcc51cc241bc6599f83ab345e93ab12:frameworks/base/libs/hwui/effects/StretchEffect.cpp

uniform vec2 u_size;
uniform sampler2D u_texture;

// Multiplier to apply to scale effect.
uniform float u_max_stretch_intensity;

// Normalized overscroll amount in the horizontal direction.
uniform float u_overscroll_x;

// Normalized overscroll amount in the vertical direction.
uniform float u_overscroll_y;

// u_interpolation_strength is the intensity of the interpolation.
uniform float u_interpolation_strength;

float ease_in(float t, float d) {
  return t * d;
}

float compute_overscroll_start(
  float in_pos,
  float overscroll,
  float u_stretch_affected_dist,
  float u_inverse_stretch_affected_dist,
  float distance_stretched,
  float interpolation_strength
) {
  float offset_pos = u_stretch_affected_dist - in_pos;
  float pos_based_variation = mix(
    1.0,
    ease_in(offset_pos, u_inverse_stretch_affected_dist),
    interpolation_strength
  );
  float stretch_intensity = overscroll * pos_based_variation;
  return distance_stretched - (offset_pos / (1.0 + stretch_intensity));
}

float compute_overscroll_end(
  float in_pos,
  float overscroll,
  float reverse_stretch_dist,
  float u_stretch_affected_dist,
  float u_inverse_stretch_affected_dist,
  float distance_stretched,
  float interpolation_strength,
  float viewport_dimension
) {
  float offset_pos = in_pos - reverse_stretch_dist;
  float pos_based_variation = mix(
    1.0,
    ease_in(offset_pos, u_inverse_stretch_affected_dist),
    interpolation_strength
  );
  float stretch_intensity = (-overscroll) * pos_based_variation;
  return viewport_dimension - (distance_stretched - (offset_pos / (1.0 + stretch_intensity)));
}

float compute_streched_effect(
  float in_pos,
  float overscroll,
  float u_stretch_affected_dist,
  float u_inverse_stretch_affected_dist,
  float distance_stretched,
  float distance_diff,
  float interpolation_strength,
  float viewport_dimension
) {
  if (overscroll > 0.0) {
    if (in_pos <= u_stretch_affected_dist) {
      return compute_overscroll_start(
        in_pos, overscroll, u_stretch_affected_dist,
        u_inverse_stretch_affected_dist, distance_stretched,
        interpolation_strength
      );
    } else {
      return distance_diff + in_pos;
    }
  } else if (overscroll < 0.0) {
    float stretch_affected_dist_calc = viewport_dimension - u_stretch_affected_dist;
    if (in_pos >= stretch_affected_dist_calc) {
      return compute_overscroll_end(
        in_pos,
        overscroll,
        stretch_affected_dist_calc,
        u_stretch_affected_dist,
        u_inverse_stretch_affected_dist,
        distance_stretched,
        interpolation_strength,
        viewport_dimension
      );
    } else {
      return -distance_diff + in_pos;
    }
  } else {
    return in_pos;
  }
}

out vec4 frag_color;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
  float in_u_norm = uv.x;
  float in_v_norm = uv.y;

  float out_u_norm;
  float out_v_norm;

  bool isVertical = u_overscroll_y != 0;
  float overscroll = isVertical ? u_overscroll_y : u_overscroll_x;

  float norm_distance_stretched = 1.0 / (1.0 + abs(overscroll));
  float norm_dist_diff = norm_distance_stretched - 1.0;

  const float norm_viewport = 1.0;
  const float norm_stretch_affected_dist = 1.0;
  const float norm_inverse_stretch_affected_dist = 1.0;

  out_u_norm = isVertical ? in_u_norm : compute_streched_effect(
    in_u_norm,
    overscroll,
    norm_stretch_affected_dist,
    norm_inverse_stretch_affected_dist,
    norm_distance_stretched,
    norm_dist_diff,
    u_interpolation_strength,
    norm_viewport
  );

  out_v_norm = isVertical ? compute_streched_effect(
    in_v_norm,
    overscroll,
    norm_stretch_affected_dist,
    norm_inverse_stretch_affected_dist,
    norm_distance_stretched,
    norm_dist_diff,
    u_interpolation_strength,
    norm_viewport
  ) : in_v_norm;

  uv.x = out_u_norm;
  uv.y = out_v_norm;

  // Only one axis is warped. Interpolate its two neighbouring texel centres;
  // preserve the untouched axis exactly and avoid four-tap work at every pixel.
  // Identity sampling lands on a texel centre, including the final spring frame.
  vec2 pixel = uv * u_size - vec2(0.5);
  vec2 step = isVertical ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
  float position = isVertical ? pixel.y : pixel.x;
  float fraction = fract(position);
  vec2 first = (pixel - step * fraction + vec2(0.5)) / u_size;
  frag_color = mix(texture(u_texture, first),
                   texture(u_texture, first + step / u_size), fraction);
}
