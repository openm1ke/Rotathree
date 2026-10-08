/// One of the four glasses of the cross, named by where it sits in the fixed
/// world frame (the orientation the game starts in).
enum Side {
  top,
  right,
  bottom,
  left;

  /// Switching order: TOP → RIGHT → BOTTOM → LEFT → TOP.
  Side get next => Side.values[(index + 1) % 4];
  Side get previous => Side.values[(index + 3) % 4];
  Side get opposite => Side.values[(index + 2) % 4];

  /// The side reached after [quarterTurns] steps of [next] (negative steps go
  /// backwards).
  Side turned(int quarterTurns) => Side.values[((index + quarterTurns) % 4 + 4) % 4];

  /// Signed number of [next] steps from this side to [other], taking the
  /// short way round: -1, 0, 1 or 2.
  int stepsTo(Side other) {
    final diff = ((other.index - index) % 4 + 4) % 4;
    return diff == 3 ? -1 : diff;
  }
}

/// The side whose glass is currently shown on top and controlled by the player.
typedef ActiveSide = Side;
