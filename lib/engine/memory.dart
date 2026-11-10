/// Digimon Card Game memory gauge.
///
/// The gauge runs 10 … 1 · 0 · 1 … 10. [value] is signed from the bottom
/// player's side: +3 = 3 memory on the bottom player's side, -3 = 3 on the
/// top player's side.
///
/// Rules modelled:
/// * Paying costs moves memory toward the opponent. When it ends up on the
///   opponent's side (1 or more there), the turn passes to them.
/// * At exactly 0 the turn does not pass.
/// * Passing ("end turn") sets memory to 3 on the opponent's side.
/// * The gauge is capped at 10 on each side.
enum Side { bottom, top }

extension SideX on Side {
  Side get other => this == Side.bottom ? Side.top : Side.bottom;
  int get sign => this == Side.bottom ? 1 : -1;
}

class MemoryState {
  final int value;
  final Side turn;
  final int turnNumber;

  const MemoryState({this.value = 0, this.turn = Side.bottom, this.turnNumber = 1});

  /// Memory from [side]'s point of view (positive = on their side).
  int memoryFor(Side side) => value * side.sign;

  MemoryState copyWith({int? value, Side? turn, int? turnNumber}) =>
      MemoryState(value: value ?? this.value, turn: turn ?? this.turn, turnNumber: turnNumber ?? this.turnNumber);

  /// Puts the marker on [v] and passes the turn if it crossed to the
  /// opponent's side of the turn player.
  MemoryState setTo(int v) {
    v = v.clamp(-10, 10);
    if (v * turn.sign < 0) {
      return MemoryState(value: v, turn: turn.other, turnNumber: turnNumber + 1);
    }
    return copyWith(value: v);
  }

  /// [side] gains/pays memory: positive [delta] moves toward [side].
  MemoryState adjust(Side side, int delta) => setTo(value + delta * side.sign);

  /// The turn player passes: memory becomes 3 on the opponent's side.
  MemoryState pass() => MemoryState(value: 3 * turn.other.sign, turn: turn.other, turnNumber: turnNumber + 1);

  Map<String, dynamic> toJson() => {'v': value, 't': turn.index, 'n': turnNumber};
  factory MemoryState.fromJson(Map<String, dynamic> j) =>
      MemoryState(value: j['v'] as int, turn: Side.values[j['t'] as int], turnNumber: j['n'] as int);
}
