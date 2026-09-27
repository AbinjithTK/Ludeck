// A new game goes on the END of its tree. Every placement used to write
// position 0, so a tree sorted by title and each new game re-ordered (and
// re-popped) the fruit already hanging; the drop-onto-tree flight also landed
// on the wrong slot.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/repository.dart';

void main() {
  late Repository repo;
  setUp(() async {
    repo = await Repository.openInMemory();
    await repo.seedIfEmpty();
  });
  tearDown(() async => repo.close());

  test('placing and moving append, whatever the titles', () async {
    final items = await repo.load();
    final byTitle = [...items]..sort((a, b) => b.game.title.compareTo(a.game.title));
    final z = byTitle.first.game.igdbId, a = byTitle.last.game.igdbId;
    final mid = byTitle[1].game.igdbId;
    final t1 = await repo.createBranch('One', sortOrder: 0);
    final t2 = await repo.createBranch('Two', sortOrder: 1);

    await repo.place(z, t1);
    await repo.place(a, t1);
    expect((await repo.placements())[t1], [z, a],
        reason: 'the later game hangs after, even though its title sorts first');

    await repo.place(z, t1); // re-placing does not move it
    expect((await repo.placements())[t1], [z, a]);

    await repo.place(mid, t2);
    await repo.moveGame(a, fromBranchId: t1, toBranchId: t2);
    expect((await repo.placements())[t2], [mid, a]);
  });
}
