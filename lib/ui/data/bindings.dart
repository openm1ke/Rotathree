import 'package:flutter/services.dart';

import '../input/game_action.dart';

/// The physical keys bound to each action, in the order they were chosen.
/// Two slots per action; a key does one thing at a time.
typedef Bindings = Map<GameAction, List<PhysicalKeyboardKey>>;

const slotsPerAction = 2;

/// The actions that can be bound to keys, in the order the settings list them.
final keyActions = [
  for (final action in GameAction.values)
    if (action != GameAction.none) action,
];

/// The keys of the browser version, so both versions play the same way.
Bindings defaultBindings() => {
      GameAction.moveLeft: [PhysicalKeyboardKey.keyA],
      GameAction.moveRight: [PhysicalKeyboardKey.keyD],
      GameAction.rotateCW: [PhysicalKeyboardKey.keyW],
      GameAction.rotateCCW: [],
      GameAction.softDrop: [],
      GameAction.hardDrop: [PhysicalKeyboardKey.keyS, PhysicalKeyboardKey.space],
      GameAction.glassLeft: [PhysicalKeyboardKey.arrowLeft],
      GameAction.glassRight: [PhysicalKeyboardKey.arrowRight],
      GameAction.glassOpposite: [PhysicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowDown],
      GameAction.pause: [PhysicalKeyboardKey.escape, PhysicalKeyboardKey.keyP],
      GameAction.restart: [PhysicalKeyboardKey.keyN],
    };

Bindings cloneBindings(Bindings bindings) => {
      for (final action in keyActions) action: [...?bindings[action]],
    };

/// The action a key triggers, if any.
GameAction? actionForKey(Bindings bindings, PhysicalKeyboardKey key) {
  for (final action in keyActions) {
    if (bindings[action]!.contains(key)) return action;
  }
  return null;
}

/// Puts [key] into [slot] of [action]. A key can only do one thing, so it is
/// taken away from wherever else it was bound. Returns new bindings.
Bindings bindKey(Bindings bindings, GameAction action, int slot, PhysicalKeyboardKey key) {
  final next = cloneBindings(bindings);
  for (final other in keyActions) {
    next[other] = [
      for (final bound in next[other]!)
        if (bound != key) bound,
    ];
  }
  final keys = next[action]!;
  if (slot < keys.length) {
    keys[slot] = key;
  } else {
    keys.add(key);
  }
  next[action] = keys.take(slotsPerAction).toList();
  return next;
}

/// Empties [slot] of [action]. Returns new bindings.
Bindings unbindKey(Bindings bindings, GameAction action, int slot) {
  final next = cloneBindings(bindings);
  final keys = next[action]!;
  next[action] = [
    for (var i = 0; i < keys.length; i++)
      if (i != slot) keys[i],
  ];
  return next;
}

/// Makes sense of whatever was stored: unknown actions are dropped, missing
/// ones get their defaults, and a key bound twice keeps its first use.
Bindings sanitizeBindings(Object? raw) {
  final result = defaultBindings();
  if (raw is! Map) return result;
  for (final action in keyActions) {
    final stored = raw[action.name];
    if (stored is! List) continue;
    final keys = <PhysicalKeyboardKey>[];
    for (final item in stored) {
      final key = _keyFromJson(item);
      if (key != null) keys.add(key);
    }
    result[action] = keys.take(slotsPerAction).toList();
  }
  final used = <int>{};
  for (final action in keyActions) {
    result[action] = [
      for (final key in result[action]!)
        if (used.add(key.usbHidUsage)) key,
    ];
  }
  return result;
}

/// A key as stored: its USB usage code, which identifies it on any keyboard.
int keyToJson(PhysicalKeyboardKey key) => key.usbHidUsage;

PhysicalKeyboardKey? _keyFromJson(Object? raw) => raw is int ? PhysicalKeyboardKey(raw) : null;

const _labels = {
  'Arrow Left': '←',
  'Arrow Right': '→',
  'Arrow Up': '↑',
  'Arrow Down': '↓',
  'Space': 'Пробел',
  'Escape': 'Esc',
  'Backspace': 'Backspace',
  'Delete': 'Del',
  'Shift Left': 'Shift ←',
  'Shift Right': 'Shift →',
  'Control Left': 'Ctrl ←',
  'Control Right': 'Ctrl →',
  'Alt Left': 'Alt ←',
  'Alt Right': 'Alt →',
};

/// A short name for a key, for showing on a keycap.
String keyLabel(PhysicalKeyboardKey key) {
  final name = key.debugName ?? '';
  if (_labels.containsKey(name)) return _labels[name]!;
  if (name.startsWith('Key ')) return name.substring(4);
  if (name.startsWith('Digit ')) return name.substring(6);
  if (name.startsWith('Numpad ')) return 'Num ${name.substring(7)}';
  if (name.isEmpty) return key.usbHidUsage.toRadixString(16);
  return name;
}
