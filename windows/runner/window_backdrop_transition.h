#ifndef RUNNER_WINDOW_BACKDROP_TRANSITION_H_
#define RUNNER_WINDOW_BACKDROP_TRANSITION_H_

namespace window_backdrop {

// Accent and frame calls can invalidate the compositor material independently
// of its reported attribute value. Establish the material only after those
// prerequisites, and release alpha if material creation fails.
template <typename ClearAccent, typename RestoreFrame, typename EnableAlpha,
          typename ApplyMaterial, typename DisableAlpha>
bool EstablishAcrylic(bool already_owned, ClearAccent clear_accent,
                      RestoreFrame restore_frame, EnableAlpha enable_alpha,
                      ApplyMaterial apply_material, DisableAlpha disable_alpha) {
  if (!already_owned) clear_accent();
  if (!restore_frame() || !enable_alpha()) return false;
  if (!apply_material()) {
    disable_alpha();
    return false;
  }
  return true;
}

}  // namespace window_backdrop
#endif
