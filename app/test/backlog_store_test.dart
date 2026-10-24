// The store is checked against rows shaped exactly like Amenbo's, written out by hand. Nothing
// here runs Amenbo or reaches a Worker: the app has to be verifiable on its own,
// and a test that needed a snapshot from somewhere would end that.

import 'dart:io';

import 'package:amenbo_viewer/store/backlog_queries.dart';
import 'package:amenbo_viewer/store/backlog_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'backlog_fixture.dart';

void main() {
  late BacklogStore store;

  setUp(() => store = BacklogStore.openInMemory());
  tearDown(() => store.close());

  group('what arrives', () {
    test('a row is kept as it came, and can be read back whole', () {
      store.applyPage([
        BacklogChange.put(
          'task',
          1,
          task(id: 1, title: 'QR を読む', notes: '## やること\n本文'),
        ),
      ]);

      expect(store.record('task', 1)!['notes'], '## やること\n本文');
      expect(store.task(1)!.title, 'QR を読む');
    });

    test('a record that comes again replaces the one before it', () {
      store.applyPage([BacklogChange.put('task', 1, task(id: 1, title: 'まえ'))]);
      store.applyPage([BacklogChange.put('task', 1, task(id: 1, title: 'あと'))]);

      expect(store.task(1)!.title, 'あと');
      expect(store.taskCount(const TaskQuery()).value, 1);
    });

    test('a deleted record leaves nothing behind, index included', () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'めずらしい言葉')),
      ]);
      store.applyPage([const BacklogChange.deleted('task', 1)]);

      expect(store.record('task', 1), isNull);
      expect(store.task(1), isNull);
      expect(store.tasks(const TaskQuery(text: 'めずらしい')), isEmpty);
    });

    test('a comment landing before its task is kept, not rejected', () {
      // Records arrive in whatever order the place hands them over, so arriving early has to be
      // survivable — otherwise a page boundary silently drops rows.
      store.applyPage([
        BacklogChange.put('task_comment', 9, comment(id: 9, taskId: 1)),
      ]);
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))]);

      expect(store.comments(1).single.id, 9);
    });

    test("the plugin's own settings are not kept on the phone", () {
      store.applyPage([
        BacklogChange.put('plugin_config', 1, {'id': 1, 'key': 'worker_url'}),
      ]);

      expect(store.record('plugin_config', 1), isNull);
    });

    test('a key from the contract names the record', () {
      final put = BacklogChange.fromKey('task/2812', row: task(id: 2812))!;
      expect(put.dataset, 'task');
      expect(put.id, 2812);
      expect(put.deleted, isFalse);

      expect(BacklogChange.fromKey('task/2812')!.deleted, isTrue);
      expect(BacklogChange.fromKey('task'), isNull);
      expect(BacklogChange.fromKey('task/none'), isNull);
    });

    test('a page that fails part way moves neither the rows nor the cursor', () {
      store.applyPage([
        BacklogChange.put('task', 1, task(id: 1, title: 'さいしょ')),
      ], seq: 7);

      expect(
        () => store.applyPage([
          BacklogChange.put('task', 2, task(id: 2)),
          // Not something that can be written down as JSON, so the page dies half way.
          BacklogChange.put('task', 3, {'id': 3, 'title': Object()}),
        ], seq: 8),
        throwsA(anything),
      );

      // A page is the unit that survives being interrupted: the cursor may not move past rows
      // that did not land, or the next fetch asks for what came after them and they are lost.
      expect(store.taskCount(const TaskQuery()).value, 1);
      expect(store.seq, 7);
    });
  });

  group('the cursor and what the device remembers', () {
    test('the page carries the cursor with it', () {
      store.applyPage(
        [BacklogChange.put('task', 1, task(id: 1))],
        seq: 42,
        version: 12345,
      );

      expect(store.seq, 42);
      expect(store.meta(MetaKey.version), '12345');
    });

    test('a wipe drops the rows but not what the person chose', () {
      store.applyPage([BacklogChange.put('task', 1, task(id: 1))], seq: 42);
      store.setMeta(MetaKey.appearance, 'dark');

      store.wipe();

      expect(store.taskCount(const TaskQuery()).value, 0);
      expect(store.seq, 0);
      // The place being replaced says nothing about how the person wants the app to look.
      expect(store.meta(MetaKey.appearance), 'dark');
    });
  });

  group('a new shape of the tables', () {
    test(
      'an older store is rebuilt from the rows it kept, with no download',
      () async {
        final dir = await Directory.systemTemp.createTemp('backlog');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/backlog.sqlite';

        final before = await BacklogStore.openAt(path);
        // A row from before the PC wrote instants carries neither key at all.
        final older = task(id: 1, dueOn: '2026-08-09')
          ..remove('due_at')
          ..remove('start_at');
        before.applyPage([
          BacklogChange.put('task', 1, older),
          BacklogChange.put(
            'task',
            2,
            task(
              id: 2,
              dueAt: '2026-08-09T06:00:00Z',
              startAt: '2026-08-08T00:00:00Z',
            ),
          ),
        ]);
        before.close();

        final raw = sqlite3.open(path);
        raw.execute('PRAGMA user_version = 2');
        raw.close();

        final after = await BacklogStore.openAt(path);
        addTearDown(after.close);
        expect(
          after.task(1)!.due,
          isA<ScheduleDay>().having((s) => s.day, 'day', '2026-08-09'),
        );
        expect(after.task(1)!.start, isNull);
        expect(
          after.task(2)!.due,
          isA<ScheduleAt>().having(
            (s) => s.at,
            'at',
            DateTime.utc(2026, 8, 9, 6),
          ),
        );
        expect(
          after.task(2)!.start,
          isA<ScheduleAt>().having((s) => s.at, 'at', DateTime.utc(2026, 8, 8)),
        );
      },
    );
  });
}
