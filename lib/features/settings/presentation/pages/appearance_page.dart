import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/app/theme/appearance.dart';
import 'package:drais/app/theme/appearance_controller.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';

/// Lets a user change how DRAIS looks.
///
/// ## Everything applies instantly
///
/// There is no Save button, because there is nothing to commit — the screen
/// you are adjusting *is* the preview. Tapping an accent repaints the app
/// under your finger, which is the only honest way to choose one.
///
/// ## What is deliberately not offered
///
/// A free colour picker, and surface colours. The DRAIS palette was checked
/// for contrast in both themes; letting someone paint the background lets them
/// build an interface they cannot read, on a screen they then cannot use to
/// undo it. The accents below are a fixed, checked set, and **Reset** is
/// always reachable at the bottom for the same reason.
class AppearancePage extends ConsumerWidget {
  /// Creates the appearance page.
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppearanceSettings settings = ref.watch(appearanceProvider);
    final AppearanceController controller = ref.read(
      appearanceProvider.notifier,
    );
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: const DraisAppBar(
        title: 'Appearance',
        subtitle: 'Changes apply immediately',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          _Section(
            title: 'Theme',
            child: SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: <ThemeMode>{settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (Set<ThemeMode> s) =>
                  controller.setThemeMode(s.first),
            ),
          ),

          _Section(
            title: 'Accent',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: DraisAccent.values
                  .map(
                    (DraisAccent accent) => _AccentSwatch(
                      accent: accent,
                      selected: settings.accent == accent,
                      onTap: () => controller.setAccent(accent),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),

          _Section(
            title: 'Corners',
            subtitle: 'Buttons, fields and cards',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DraisCornerStyle.values
                  .map(
                    (DraisCornerStyle style) => ChoiceChip(
                      label: Text(style.label),
                      selected: settings.cornerStyle == style,
                      onSelected: (_) => controller.setCornerStyle(style),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),

          _Section(
            title: 'Density',
            subtitle: 'How much fits on a screen',
            child: Wrap(
              spacing: 8,
              children: DraisDensity.values
                  .map(
                    (DraisDensity d) => ChoiceChip(
                      label: Text(d.label),
                      selected: settings.density == d,
                      onSelected: (_) => controller.setDensity(d),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),

          _Section(
            title: 'Text size',
            subtitle:
                'Multiplies your device setting rather than '
                'replacing it',
            child: Slider(
              value: settings.textScale,
              min: 0.85,
              max: 1.4,
              divisions: 11,
              label: '${(settings.textScale * 100).round()}%',
              onChanged: controller.setTextScale,
            ),
          ),

          _Section(
            title: 'Background',
            subtitle:
                'Kept subtle on purpose — attendance data has to stay '
                'readable on top of it',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DraisWallpaper.values
                  .map(
                    (DraisWallpaper w) => ChoiceChip(
                      label: Text(w.label),
                      selected: settings.wallpaper == w,
                      onSelected: (_) => controller.setWallpaper(w),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),

          const SizedBox(height: 12),
          const _PreviewCard(),

          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: settings.isDefault ? null : controller.reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset to defaults'),
          ),
          const SizedBox(height: 12),
          Text(
            'These settings belong to this device, not your account. '
            'They stay when you sign out.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final DraisAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color colour = accent.of(theme.brightness);

    return Semantics(
      label: accent.label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: accent.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colour,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            // A tick, not just a ring — selection must not depend on noticing
            // a 2px border difference against a coloured circle.
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Shows the settings acting on real components rather than abstract swatches.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Preview', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                AttendanceStatusPill('present'),
                AttendanceStatusPill('late'),
                AttendanceStatusPill('absent'),
                AttendanceStatusPill(null),
              ],
            ),
            const SizedBox(height: 14),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Primary'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Secondary'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
