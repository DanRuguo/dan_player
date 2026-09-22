#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uSourceFraction;
// Time-only trigonometry is shared by every pixel and supplied by the CPU.
uniform vec3 uTime;
uniform sampler2D uArtwork;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  const float pi = 3.141592653589793;
  float t = uTime.x;
  float envelope = sin(pi * p.x) * sin(pi * p.y);
  vec2 displacement = vec2(
    0.12 * envelope * uTime.y * sin(2.0 * pi * p.y + t),
    0.10 * envelope * uTime.z * cos(2.0 * pi * p.x - t));
  fragColor = texture(uArtwork, clamp(p + displacement, 0.0, 1.0) * uSourceFraction);
}
