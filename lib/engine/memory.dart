/// Digimon Card Game memory gauge.
///
/// The gauge runs 10 … 1 · 0 · 1 … 10. [value] is signed from the bottom
/// player's side: +3 = 3 memory on the bottom player's side, -3 = 3 on the
/// top player's side.
///
/// Rules modelled:
/// * Paying costs moves memory toward the opponent.
/// * The app never decides that the turn passed: memory landing on the
///   opponent's side does not always end the turn, so the turn player ends it
///   by hand ([MemoryState.endTurn]). To pass, they put the marker on the
///   opponent's 3 themselves and end the turn.
/// * A cost that would push the memory past the opponent's 10 can't be paid
///   at all (you can't pay memory you don't have): at 3, the most is 13.
/// * Gains stop at 10 on the player's own side.
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

  /// Puts the marker on [v]. The turn stays where it is.
  MemoryState setTo(int v) => copyWith(value: v.clamp(-10, 10));

  /// Whether [side] can pay [cost]: it may end on the opponent's 10, not past it.
  bool canPay(Side side, int cost) => memoryFor(side) - cost >= -10;

  /// [side] gains/pays memory: positive [delta] moves toward [side]. A gain
  /// stops at 10; a cost that can't be paid ([canPay]) changes nothing.
  MemoryState adjust(Side side, int delta) =>
      (delta < 0 && !canPay(side, -delta)) ? this : setTo(value + delta * side.sign);

  /// The turn player ends their turn. The memory is left as it is.
  MemoryState endTurn() => MemoryState(value: value, turn: turn.other, turnNumber: turnNumber + 1);

  Map<String, dynamic> toJson() => {'v': value, 't': turn.index, 'n': turnNumber};
  factory MemoryState.fromJson(Map<String, dynamic> j) =>
      MemoryState(value: j['v'] as int, turn: Side.values[j['t'] as int], turnNumber: j['n'] as int);
}
