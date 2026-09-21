#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uSourceFraction;
uniform float uPhase;
uniform sampler2D uArtwork;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  const float pi = 3.141592653589793;
  float t = uPhase * 2.0 * pi;
  float envelope = sin(pi * p.x) * sin(pi * p.y);
  vec2 displacement = vec2(
    0.12 * envelope * sin(t) * sin(2.0 * pi * p.y + t),
    0.10 * envelope * sin(t * 2.0) * cos(2.0 * pi * p.x - t));
  fragColor = texture(uArtwork, clamp(p + displacement, 0.0, 1.0) * uSourceFraction);
}
