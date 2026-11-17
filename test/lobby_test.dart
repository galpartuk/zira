// The player's waiting screen: "you're in", the live player count, the names.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zira/cloud/auth_service.dart';
import 'package:zira/cloud/tournament_repo.dart';
import 'package:zira/engine/models.dart';
import 'package:zira/l10n.dart';
import 'package:zira/screens/player_tournament_screen.dart';
import 'package:zira/theme.dart';
import 'package:zira/widgets/lobby_card.dart';
import 'package:zira/widgets/round_timer.dart';

void main() {
  setUpAll(() {
    // ignore: invalid_use_of_visible_for_testing_member
    KeepAwake.apply = (_) {};
    lobbyAnimations = false; // endless animations never settle
  });
  tearDownAll(() => lobbyAnimations = true);

  testWidgets('joined before the start: "You\'re in", and the count follows new joins', (tester) async {
    Lang.instance.code = 'en';
    final db = FakeFirebaseFirestore();
    final t = Tournament(
      id: 't1',
      name: 'T',
      joinCode: 'ABC234',
      players: [
        Player(id: 'a', name: 'Ann', uid: 'ann', tieRand: 0),
        Player(id: 'b', name: 'Bob', uid: 'bob', tieRand: 1),
      ],
    );
    final store = CloudStore(db, 'host');
    await store.saveAll([t]);
    await db.doc('tournaments/t1/entries/ann').set({'displayName': 'Ann', 'status': 'joined'});
    final auth = AuthService(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'ann', displayName: 'Ann'),
      ),
      db,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService?>.value(value: auth),
          Provider<FirebaseFirestore?>.value(value: db),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const PlayerTournamentScreen(tid: 't1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.t.youAreIn), findsOneWidget);
    expect(find.byKey(const ValueKey('open-memory')), findsOneWidget); // the gauge is one tap away
    expect(find.text(S.t.waitingHostStart), findsOneWidget);
    expect(find.text(S.t.playersIn(2)), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    t.players.add(Player(id: 'c', name: 'Cid', uid: 'cid', tieRand: 2));
    await store.saveAll([t]);
    await tester.pumpAndSettle();
    expect(find.text(S.t.playersIn(3)), findsOneWidget);
    expect(find.text('Cid'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
