import 'package:flutter/material.dart';

/// Keep the check's natural 18px ink inside the same 24px leading column as
/// ordinary menu icons. The menu row owns focus and activation, as it does for
/// Flutter's CheckboxMenuButton; the checkbox still supplies checked semantics.
class AppCheckboxMenuButton extends StatelessWidget {
  const AppCheckboxMenuButton(
      {super.key,
      required this.value,
      required this.onChanged,
      required this.child});

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) => MenuItemButton(
        onPressed: onChanged == null ? null : () => onChanged!(!value),
        leadingIcon: SizedBox.square(
          dimension: 24,
          child: Center(
              child: ExcludeFocus(
                  child: IgnorePointer(
            child: SizedBox.square(
                dimension: Checkbox.width,
                child: Checkbox(value: value, onChanged: onChanged)),
          ))),
        ),
        child: child,
      );
}
