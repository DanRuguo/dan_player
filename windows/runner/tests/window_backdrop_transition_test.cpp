#include "window_backdrop_transition.h"
#include <cassert>
#include <iostream>

int main() {
  bool alpha = false, material = false, solid = true;
  int clears = 0;
  auto apply = [&](bool owned, bool supports_alpha, bool supports_material) {
    return window_backdrop::EstablishAcrylic(owned,
      [&]() { ++clears; solid = false; material = false; },
      [&]() { material = false; return true; },
      [&]() { alpha = supports_alpha; return supports_alpha; },
      [&]() { material = alpha && !solid && supports_material; return material; },
      [&]() { alpha = false; });
  };
  for (int i = 0; i < 20; ++i) {
    solid = true; material = false; alpha = false;
    assert(apply(false, true, true));
    assert(material && alpha && !solid);
    const auto old_clears = clears;
    assert(apply(true, true, true));
    assert(material && alpha && clears == old_clears);
  }
  assert(!apply(false, false, true));
  assert(!material && !alpha);
  assert(!apply(false, true, false));
  assert(!material && !alpha);
  std::cout << "Acrylic restore: 20 solid/restore cycles, owned refresh and failure cleanup passed\n";
}
