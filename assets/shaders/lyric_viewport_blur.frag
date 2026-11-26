#version 320 es
#include <flutter/runtime_effect.glsl>

// Separable 1D variable-radius Gaussian blur for LyricViewportBlur.
// Computes a continuous smooth blur radius per physical scanline inside a
// single BackdropFilter region, eliminating discrete ClipRect strip seams.

uniform vec2 u_size;
uniform float u_max_sigma;
uniform float u_vertical;
uniform float u_is_top;

uniform sampler2D u_texture;

out vec4 frag_color;

void main() {
  vec2 center = floor(FlutterFragCoord().xy) + vec2(0.5);
  float safe_height = max(u_size.y, 1.0);
  float progress = u_is_top > 0.5
      ? clamp(1.0 - (center.y / safe_height), 0.0, 1.0)
      : clamp(center.y / safe_height, 0.0, 1.0);

  // Smooth C1/C2 blended easing: zero derivative at both the clear inner
  // boundary (progress = 0) and outer viewport edge (progress = 1), while
  // spreading the perceptually sensitive 0..3px defocus evenly across the band.
  float cubic = progress * progress * (3.0 - 2.0 * progress);
  float quintic = progress * progress * progress *
      (progress * (progress * 6.0 - 15.0) + 10.0);
  float ramp = mix(cubic, quintic, 0.35);

  // Guarantee 3*sigma never crosses the inner clear boundary even on narrow bands.
  float dist_to_clear = u_is_top > 0.5 ? (u_size.y - center.y) : center.y;
  float sigma = min(u_max_sigma * ramp, max(dist_to_clear, 0.0) * 0.3333333);

  vec2 min_pos = vec2(0.5);
  vec2 max_pos = max(u_size - vec2(0.5), vec2(0.5));
  vec2 inv_size = vec2(1.0) / max(u_size, vec2(1.0));

  if (sigma < 0.15) {
    frag_color = texture(u_texture, clamp(center, min_pos, max_pos) * inv_size);
    return;
  }

  // 72 taps covers 3*sigma at maxSigma=8 up to 300% DPI at exact 1-texel stride.
  const int MAX_STEPS = 72;
  float support = min(ceil(3.0 * sigma), float(MAX_STEPS));
  int tap_count = int(support);
  float inv_two_sigma_sq = 0.5 / (sigma * sigma);
  vec2 axis = u_vertical > 0.5 ? vec2(0.0, 1.0) : vec2(1.0, 0.0);

  vec4 acc = texture(u_texture, clamp(center, min_pos, max_pos) * inv_size);
  float weight_sum = 1.0;

  for (int i = 1; i <= MAX_STEPS; i++) {
    if (i > tap_count) {
      break;
    }
    float d = float(i);
    float w = exp(-(d * d) * inv_two_sigma_sq);
    vec2 offset = axis * d;
    vec4 c1 = texture(u_texture, clamp(center + offset, min_pos, max_pos) * inv_size);
    vec4 c2 = texture(u_texture, clamp(center - offset, min_pos, max_pos) * inv_size);
    acc += (c1 + c2) * w;
    weight_sum += 2.0 * w;
  }

  frag_color = acc / weight_sum;
}
