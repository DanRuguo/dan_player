import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  const SettingsTile(
      {super.key, required this.description, required this.action, this.icon});

  final String description;
  final Widget action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 22.0,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12.0),
              ],
              Expanded(
                child: Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface, fontSize: 18.0),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16.0),
        action,
      ],
    );
  }
}
