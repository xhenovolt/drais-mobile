import 'package:flutter/material.dart';

import 'package:drais/features/students/domain/entities/students.dart';

/// A labelled dropdown over [Choice]s, keeping its value only while that
/// value is still offered — so narrowing a list (streams by class, terms by
/// year) never leaves a stale selection showing.
class ChoicePicker extends StatelessWidget {
  /// Creates a picker.
  const ChoicePicker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.required = true,
    super.key,
  });

  /// Field label.
  final String label;

  /// Selected id.
  final int? value;

  /// The options.
  final List<Choice> items;

  /// Selection callback.
  final ValueChanged<int?> onChanged;

  /// Adds the `*` and omits the "None" option.
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<int?>(
      key: ValueKey<String>('$label-$value-${items.length}'),
      initialValue: items.any((Choice c) => c.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<int?>>[
        if (!required) const DropdownMenuItem<int?>(child: Text('None')),
        for (final Choice c in items)
          DropdownMenuItem<int?>(value: c.id, child: Text(c.label)),
      ],
      onChanged: onChanged,
    ),
  );
}
