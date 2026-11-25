// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

/// Presentation hint for a controllable setting.
enum SettingKind {
  toggle,
  segmented,
  range,
}

/// Addressing mode for a v2 command.
sealed class V2Target {
  const V2Target();
}

/// Fixed v2 target address (0x0000 for RX, 0xffff for broadcast TX).
final class FixedTarget extends V2Target {
  const FixedTarget(this.address);
  final int address;
}

/// Per-transmitter v2 target resolved from zero-based slot index (0 -> 1, 1 -> 2).
final class PerTxTarget extends V2Target {
  const PerTxTarget();
}

/// One selectable value of a [SettingDefinition].
class SettingOption {
  const SettingOption({
    required this.value,
    required this.label,
    required this.wire,
  });

  final String value;
  final String label;
  final int wire;
}

/// Pure data descriptor of a controllable device setting.
class SettingDefinition {
  const SettingDefinition({
    required this.id,
    required this.label,
    required this.group,
    required this.kind,
    required this.v1Command,
    required this.v2Command,
    required this.v2Target,
    required this.options,
    this.exclusiveWith = const <String>[],
    this.note,
  });

  final String id;
  final String label;
  final String group;
  final SettingKind kind;
  final int? v1Command;
  final int v2Command;
  final V2Target v2Target;
  final List<SettingOption> options;
  final List<String> exclusiveWith;
  final String? note;

  SettingOption? optionByValue(String value) {
    for (final opt in options) {
      if (opt.value == value) return opt;
    }
    return null;
  }

  SettingOption? optionByWire(int wire) {
    for (final opt in options) {
      if (opt.wire == wire) return opt;
    }
    return null;
  }
}
