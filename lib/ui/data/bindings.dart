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
      GameAction.softDrop: [PhysicalKeyboardKey.keyX],
      GameAction.hardDrop: [PhysicalKeyboardKey.keyS, PhysicalKeyboardKey.space],
      GameAction.glassLeft: [PhysicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.keyQ],
      GameAction.glassRight: [PhysicalKeyboardKey.arrowRight, PhysicalKeyboardKey.keyE],
      GameAction.glassOpposite: [PhysicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowDown],
      GameAction.pause: [PhysicalKeyboardKey.escape, PhysicalKeyboardKey.keyP],
      GameAction.restart: [PhysicalKeyboardKey.keyN],
      // Cube's own: the arrows up and down tip the hub there instead.
      GameAction.tipBack: [PhysicalKeyboardKey.arrowUp],
      GameAction.tipFront: [PhysicalKeyboardKey.arrowDown],
      GameAction.frontGlass: [PhysicalKeyboardKey.keyZ],
      GameAction.backGlass: [PhysicalKeyboardKey.keyC],
      GameAction.depthGlass: [],
      GameAction.peek: [PhysicalKeyboardKey.keyV],
    };

/// Whether two actions can be on at the same time, so may not share a key.
bool _overlap(GameAction a, GameAction b) => a.scope == null || b.scope == null || a.scope == b.scope;

Bindings cloneBindings(Bindings bindings) => {
      for (final action in keyActions) action: [...?bindings[action]],
    };

/// The action a key triggers in [game], if any.
GameAction? actionForKey(Bindings bindings, PhysicalKeyboardKey key, [ActionScope game = ActionScope.flat]) {
  for (final action in keyActions) {
    if (action.inScope(game) && bindings[action]!.contains(key)) return action;
  }
  return null;
}

/// Puts [key] into [slot] of [action]. A key can only do one thing, so it is
/// taken away from wherever else it was bound in the same game: it may tip
/// the hub in Cube and turn the cross round in the flat game. Returns new
/// bindings.
Bindings bindKey(Bindings bindings, GameAction action, int slot, PhysicalKeyboardKey key) {
  final next = cloneBindings(bindings);
  for (final other in keyActions) {
    if (!_overlap(action, other)) continue;
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

/// Keys that joined the defaults later: a save that still has the action's
/// earlier default gets them too, unless it uses the key for something else.
const _laterDefaults = [
  (action: GameAction.glassLeft, was: [PhysicalKeyboardKey.arrowLeft], key: PhysicalKeyboardKey.keyQ),
  (action: GameAction.glassRight, was: [PhysicalKeyboardKey.arrowRight], key: PhysicalKeyboardKey.keyE),
  (action: GameAction.softDrop, was: <PhysicalKeyboardKey>[], key: PhysicalKeyboardKey.keyX),
];

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
  // A key bound twice in one game keeps its first use.
  final used = <ActionScope, Set<int>>{for (final game in ActionScope.values) game: {}};
  bool take(GameAction action, PhysicalKeyboardKey key) {
    final games = [for (final game in ActionScope.values) if (action.inScope(game)) game];
    if (games.any((game) => used[game]!.contains(key.usbHidUsage))) return false;
    for (final game in games) {
      used[game]!.add(key.usbHidUsage);
    }
    return true;
  }

  for (final action in keyActions) {
    result[action] = [
      for (final key in result[action]!)
        if (take(action, key)) key,
    ];
  }
  for (final (:action, :was, :key) in _laterDefaults) {
    final keys = result[action]!;
    final unchanged = keys.length == was.length && [for (var i = 0; i < was.length; i++) keys[i] == was[i]].every((same) => same);
    if (unchanged && keys.length < slotsPerAction && take(action, key)) result[action] = [...keys, key];
  }
  return result;
}

/// A key as stored: its USB usage code, which identifies it on any keyboard.
int keyToJson(PhysicalKeyboardKey key) => key.usbHidUsage;

PhysicalKeyboardKey? _keyFromJson(Object? raw) => raw is int ? PhysicalKeyboardKey(raw) : null;

const _labels = {
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
  // PhysicalKeyboardKey.debugName is stripped in release builds.
  final id = key.usbHidUsage;
  final firstLetter = PhysicalKeyboardKey.keyA.usbHidUsage;
  if (id >= firstLetter && id <= PhysicalKeyboardKey.keyZ.usbHidUsage) {
    return String.fromCharCode(65 + id - firstLetter);
  }
  final firstDigit = PhysicalKeyboardKey.digit1.usbHidUsage;
  if (id >= firstDigit && id <= PhysicalKeyboardKey.digit0.usbHidUsage) {
    return ((id - firstDigit + 1) % 10).toString();
  }
  final label = switch (key) {
    PhysicalKeyboardKey.arrowLeft => '←',
    PhysicalKeyboardKey.arrowRight => '→',
    PhysicalKeyboardKey.arrowUp => '↑',
    PhysicalKeyboardKey.arrowDown => '↓',
    PhysicalKeyboardKey.space => 'Пробел',
    PhysicalKeyboardKey.escape => 'Esc',
    PhysicalKeyboardKey.enter || PhysicalKeyboardKey.numpadEnter => 'Enter',
    PhysicalKeyboardKey.backspace => 'Backspace',
    _ => null,
  };
  if (label != null) return label;
  final name = key.debugName ?? '';
  if (_labels.containsKey(name)) return _labels[name]!;
  if (name.startsWith('Key ')) return name.substring(4);
  if (name.startsWith('Digit ')) return name.substring(6);
  if (name.startsWith('Numpad ')) return 'Num ${name.substring(7)}';
  if (name.isEmpty) return key.usbHidUsage.toRadixString(16);
  return name;
}
