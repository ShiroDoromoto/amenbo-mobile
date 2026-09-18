/// The phone's copy of the backlog, in SQLite.
///
/// What arrives is Amenbo's own table rows, one encrypted record per row, keyed `table/id`.
/// They are kept here twice, on purpose:
///
/// * [_records] holds each row verbatim, as JSON — the contract's shape, and the only place the
///   long text (a task's notes, a decision's body, a comment) lives. Because it is here, a later
///   version of the app can change every other table below and rebuild them from what is already
///   on the device, instead of asking the person to download their backlog again.
/// * the tables beside it hold only the small columns the screens sort and filter on, so a query
///   for twenty rows reads twenty short rows and no bodies at all.
///
/// Nothing here writes back to Amenbo. The rows are a mirror; the source of truth is the PC.
library;

import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'file_protection.dart';

/// One record on its way in — a row that changed, or one that is gone.
///
/// The contract names records `table/id` ("task/2812"), so that string is what the ingest hands
/// over and [BacklogChange.fromKey] is what turns it into something typed.
class BacklogChange {
  const BacklogChange.put(this.dataset, this.id, Map<String, Object?> this.row)
    : deleted = false;

  const BacklogChange.deleted(this.dataset, this.id)
    : row = null,
      deleted = true;

  /// Reads the contract's `k`. Returns null for a key that is not `<name>/<integer>` — a record
  /// whose key the app cannot parse is one it must skip rather than guess at.
  static BacklogChange? fromKey(String key, {Map<String, Object?>? row}) {
    final slash = key.lastIndexOf('/');
    if (slash <= 0 || slash == key.length - 1) return null;
    final id = int.tryParse(key.substring(slash + 1));
    if (id == null) return null;
    final dataset = key.substring(0, slash);
    return row == null
        ? BacklogChange.deleted(dataset, id)
        : BacklogChange.put(dataset, id, row);
  }

  /// The Amenbo table the row came from — `task`, `task_comment`, `decision`, …
  final String dataset;
  final int id;
  final Map<String, Object?>? row;
  final bool deleted;
}

/// Datasets the app deliberately drops on the way in.
///
/// A plugin's settings are the PC's business and nothing on the phone shows them, so they are not
/// kept. Every other dataset is stored even when no screen reads it yet: keeping it costs a row
/// and saves a full re-download the day one does.
const _ignoredDatasets = {'plugin_config', 'plugin_enable'};

/// Keys in [BacklogStore.meta].
class MetaKey {
  /// The last `seq` taken from the place. The next fetch asks for what came after it.
  static const seq = 'seq';

  /// Amenbo's own `version`, as it was when the last record was written.
  static const version = 'version';

  /// The contract version the records were written under.
  static const specVersion = 'spec_v';

  /// When the last fetch finished — what "12:34 に取得" is read from, and the reason the app can
  /// say how old the picture is while offline.
  static const fetchedAt = 'fetched_at';

  /// When the app goes and looks — see `settings.dart`.
  static const refresh = 'refresh';

  /// Light, dark, or whatever the phone is doing.
  static const appearance = 'appearance';

  /// The last few words typed into the search face.
  static const recentTerms = 'recent_terms';

  /// The last few records opened from it.
  static const recentlyViewed = 'recently_viewed';

  /// The keys that are the device's own rather than the place's, and so the ones a wipe leaves
  /// alone. Everything else in `meta` describes the copy being thrown away; these describe the
  /// person holding the phone, who has not changed their mind — nor forgotten what they were
  /// looking for — just because the PC re-uploaded everything.
  static const deviceOwn = {refresh, appearance, recentTerms, recentlyViewed};
}

class BacklogStore {
  BacklogStore._(this.db);

  final Database db;

  /// The file name under the app's support directory. It is not in Documents: nothing here is a
  /// document the person made, and on iOS Documents is the directory that gets backed up and
  /// shown.
  static const fileName = 'backlog.sqlite';

  /// Opens the store where the app keeps it.
  ///
  /// Application support, not documents: nothing in here is a document the person made, and on
  /// iOS the documents directory is the one that gets backed up and shown to them. This is a copy
  /// of what the PC holds — restoring it from a backup would restore a stale one.
  static Future<BacklogStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return openAt('${directory.path}/$fileName');
  }

  /// Opens (and creates) the store at [path].
  ///
  /// On iOS the file is then marked `NSFileProtectionComplete`: a locked phone cannot read it.
  /// That is affordable here because the app only reads at launch and on coming to the front,
  /// both of which happen unlocked — see [FileProtection].
  static Future<BacklogStore> openAt(String path) async {
    final store = BacklogStore._(sqlite3.open(path));
    store._migrate();
    await FileProtection.completeFor(path);
    return store;
  }

  /// For tests, and for anything that wants a store it can throw away.
  static BacklogStore openInMemory() {
    final store = BacklogStore._(sqlite3.openInMemory());
    store._migrate();
    return store;
  }

  void close() => db.close();

  // ---------------------------------------------------------------- schema

  /// Bumped whenever the tables below change shape. The rows in `record` survive it, so a bump
  /// costs a rebuild on the device and no traffic.
  static const schemaVersion = 2;

  void _migrate() {
    db.execute('PRAGMA journal_mode = WAL');
    // Records arrive a page at a time, in the order the place hands them over, so a comment can
    // land before the task it belongs to. Enforcing references here would reject rows that are
    // merely early.
    db.execute('PRAGMA foreign_keys = OFF');

    final current = db.select('PRAGMA user_version').first.values.first as int;
    if (current == schemaVersion) return;
    if (current != 0) _dropProjections();

    db.execute(_schema);
    if (current != 0) _rebuildProjections();
    db.execute('PRAGMA user_version = $schemaVersion');
  }

  static const _projections = [
    'project',
    'task',
    'task_comment',
    'decision',
    'decision_comment',
    'task_dependency',
    'decision_task_link',
    'decision_edge',
    'dimension',
    'dimension_value',
    'task_dimension_value',
    'task_commit',
    'attachment',
  ];

  void _dropProjections() {
    for (final table in _projections) {
      db.execute('DROP TABLE IF EXISTS $table');
    }
    db.execute('DROP TRIGGER IF EXISTS search_row_ai');
    db.execute('DROP TRIGGER IF EXISTS search_row_ad');
    db.execute('DROP TRIGGER IF EXISTS search_row_au');
    db.execute('DROP TABLE IF EXISTS search_fts');
    db.execute('DROP TABLE IF EXISTS search_row');
  }

  /// Fills the query tables from [_records] after a schema change, so an app update does not send
  /// the person back to the network for rows the device already has.
  void _rebuildProjections() {
    final rows = db.select('SELECT dataset, id, raw FROM record');
    db.execute('BEGIN');
    for (final row in rows) {
      _project(
        row['dataset'] as String,
        row['id'] as int,
        jsonDecode(row['raw'] as String) as Map<String, Object?>,
      );
    }
    db.execute('COMMIT');
  }

  // ---------------------------------------------------------------- writing

  /// Writes one page of records in one transaction.
  ///
  /// A page is the unit the contract pages by, and it is also the unit that survives being
  /// interrupted: either the whole page is in and the cursor moves with it, or none of it is.
  void applyPage(Iterable<BacklogChange> changes, {int? seq, int? version}) {
    db.execute('BEGIN');
    try {
      for (final change in changes) {
        if (_ignoredDatasets.contains(change.dataset)) continue;
        if (change.deleted) {
          _remove(change.dataset, change.id);
        } else {
          _put(change.dataset, change.id, change.row!);
        }
      }
      if (seq != null) _writeMeta(MetaKey.seq, '$seq');
      if (version != null) _writeMeta(MetaKey.version, '$version');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Empties the store, keeping the settings that are the device's own.
  ///
  /// The place is replaced wholesale on a reset and after a gap on the PC, which the device sees
  /// as `seq` going backwards. What it must not throw away is [MetaKey.deviceOwn]: the person has
  /// not stopped looking, nor changed how they want the app to look, just because the PC
  /// re-uploaded everything.
  void wipe() {
    db.execute('BEGIN');
    db.execute('DELETE FROM record');
    for (final table in _projections) {
      db.execute('DELETE FROM $table');
    }
    db.execute('DELETE FROM search_row');
    final kept = MetaKey.deviceOwn.map((key) => "'$key'").join(', ');
    db.execute('DELETE FROM meta WHERE key NOT IN ($kept)');
    db.execute('COMMIT');
  }

  void _put(String dataset, int id, Map<String, Object?> row) {
    db.execute(
      'INSERT INTO record (dataset, id, raw) VALUES (?, ?, ?) '
      'ON CONFLICT (dataset, id) DO UPDATE SET raw = excluded.raw',
      [dataset, id, jsonEncode(row)],
    );
    _project(dataset, id, row);
  }

  void _remove(String dataset, int id) {
    db.execute('DELETE FROM record WHERE dataset = ? AND id = ?', [
      dataset,
      id,
    ]);
    if (_projections.contains(dataset)) {
      db.execute('DELETE FROM $dataset WHERE id = ?', [id]);
    }
    db.execute('DELETE FROM search_row WHERE dataset = ? AND record_id = ?', [
      dataset,
      id,
    ]);
  }

  // ---------------------------------------------------------------- meta

  String? meta(String key) {
    final rows = db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  void setMeta(String key, String? value) {
    db.execute('BEGIN');
    _writeMeta(key, value);
    db.execute('COMMIT');
  }

  void _writeMeta(String key, String? value) {
    if (value == null) {
      db.execute('DELETE FROM meta WHERE key = ?', [key]);
      return;
    }
    db.execute(
      'INSERT INTO meta (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  /// The `seq` the next fetch continues from. Zero means nothing has been taken yet.
  int get seq => int.tryParse(meta(MetaKey.seq) ?? '') ?? 0;

  set seq(int value) => setMeta(MetaKey.seq, '$value');

  // ---------------------------------------------------------------- projection

  void _project(String dataset, int id, Map<String, Object?> row) {
    switch (dataset) {
      case 'project':
        _insert('project', {
          'id': id,
          'name': _text(row['name']),
          'archived': _flag(row['archived']),
          'order_key': _text(row['order_key']),
        });
      case 'task':
        _insert('task', {
          'id': id,
          'project_id': _int(row['project_id']),
          'title': _text(row['title']),
          'status': _text(row['status']),
          'priority': row['priority'] as String?,
          'priority_rank': _priorityRank(row['priority'] as String?),
          'assignee_kind': row['assignee_kind'] as String?,
          'draft': _flag(row['draft']),
          'due_on': row['due_on'] as String?,
          'start_on': row['start_on'] as String?,
          'created_at': _text(row['created_at']),
          'updated_at': _text(row['updated_at']),
          'status_changed_at': row['status_changed_at'] as String?,
          'completed_at': row['completed_at'] as String?,
        });
        _index(
          dataset,
          id,
          kind: 'task',
          ownerId: id,
          sortKey: _text(row['created_at']),
          parts: {'title': _text(row['title']), 'body': _text(row['notes'])},
        );
      case 'task_comment':
        _insert('task_comment', {
          'id': id,
          'task_id': _int(row['task_id']),
          'author_kind': row['author_kind'] as String?,
          'created_at': _text(row['created_at']),
        });
        _index(
          dataset,
          id,
          kind: 'task',
          ownerId: _int(row['task_id']),
          sortKey: _text(row['created_at']),
          parts: {'comment': _text(row['text'])},
        );
      case 'decision':
        _insert('decision', {
          'id': id,
          'project_id': _int(row['project_id']),
          'title': _text(row['title']),
          'status': _text(row['status']),
          'draft': _flag(row['draft']),
          'created_at': _text(row['created_at']),
          'updated_at': _text(row['updated_at']),
          'decided_at': row['decided_at'] as String?,
        });
        _index(
          dataset,
          id,
          kind: 'decision',
          ownerId: id,
          sortKey: _text(row['created_at']),
          parts: {'title': _text(row['title']), 'body': _text(row['body'])},
        );
      case 'decision_comment':
        _insert('decision_comment', {
          'id': id,
          'decision_id': _int(row['decision_id']),
          'author_kind': row['author_kind'] as String?,
          'created_at': _text(row['created_at']),
        });
        _index(
          dataset,
          id,
          kind: 'decision',
          ownerId: _int(row['decision_id']),
          sortKey: _text(row['created_at']),
          parts: {'comment': _text(row['text'])},
        );
      case 'task_dependency':
        _insert('task_dependency', {
          'id': id,
          'task_id': _int(row['task_id']),
          'blocked_by_id': _int(row['blocked_by_id']),
        });
      case 'decision_task_link':
        _insert('decision_task_link', {
          'id': id,
          'decision_id': _int(row['decision_id']),
          'task_id': _int(row['task_id']),
        });
      case 'decision_edge':
        _insert('decision_edge', {
          'id': id,
          'decision_id': _int(row['decision_id']),
          'target_decision_id': _int(row['target_decision_id']),
          'kind': _text(row['kind']),
        });
      case 'dimension':
        _insert('dimension', {
          'id': id,
          'project_id': _int(row['project_id']),
          'name': _text(row['name']),
          'role': _text(row['role']),
          'order_key': _text(row['order_key']),
        });
      case 'dimension_value':
        _insert('dimension_value', {
          'id': id,
          'dimension_id': _int(row['dimension_id']),
          'name': _text(row['name']),
          'order_key': _text(row['order_key']),
        });
      case 'task_dimension_value':
        _insert('task_dimension_value', {
          'id': id,
          'task_id': _int(row['task_id']),
          'dimension_id': _int(row['dimension_id']),
          'value_id': _int(row['value_id']),
        });
      case 'task_commit':
        _insert('task_commit', {
          'id': id,
          'task_id': _int(row['task_id']),
          'sha': _text(row['sha']),
          'created_at': _text(row['created_at']),
        });
      case 'attachment':
        _insert('attachment', {
          'id': id,
          'target_type': _text(row['target_type']),
          'target_id': _int(row['target_id']),
          'filename': _text(row['filename']),
          'size_bytes': _int(row['size_bytes']),
          'order_key': _text(row['order_key']),
        });
    }
  }

  void _insert(String table, Map<String, Object?> columns) {
    final names = columns.keys.join(', ');
    final marks = List.filled(columns.length, '?').join(', ');
    final sets = columns.keys
        .where((name) => name != 'id')
        .map((name) => '$name = excluded.$name')
        .join(', ');
    db.execute(
      'INSERT INTO $table ($names) VALUES ($marks) '
      'ON CONFLICT (id) DO UPDATE SET $sets',
      columns.values.toList(growable: false),
    );
  }

  /// Puts a record's text into the search index, one row per place it can be found.
  ///
  /// Separate rows are what lets a hit say *where* it hit — a match in a comment reads differently
  /// from a match in the title, and the screen shows the line around it.
  void _index(
    String dataset,
    int id, {
    required String kind,
    required int ownerId,
    required String sortKey,
    required Map<String, String> parts,
  }) {
    db.execute('DELETE FROM search_row WHERE dataset = ? AND record_id = ?', [
      dataset,
      id,
    ]);
    for (final part in parts.entries) {
      if (part.value.isEmpty) continue;
      db.execute(
        'INSERT INTO search_row (dataset, record_id, kind, owner_id, source, sort_key, body) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [dataset, id, kind, ownerId, part.key, sortKey, part.value],
      );
    }
  }

  static String _text(Object? value) => value is String ? value : '';

  static int _int(Object? value) => value is int ? value : 0;

  static int _flag(Object? value) => value == 1 || value == true ? 1 : 0;

  /// Amenbo's priorities do not sort by name, and a task with none belongs at the bottom rather
  /// than wherever `null` lands.
  static int _priorityRank(String? priority) => switch (priority) {
    'high' => 0,
    'medium' => 1,
    'low' => 2,
    _ => 3,
  };
}

const _records = 'record';

const _schema =
    '''
CREATE TABLE IF NOT EXISTS $_records (
  dataset TEXT    NOT NULL,
  id      INTEGER NOT NULL,
  raw     TEXT    NOT NULL,
  PRIMARY KEY (dataset, id)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE project (
  id        INTEGER PRIMARY KEY,
  name      TEXT    NOT NULL,
  archived  INTEGER NOT NULL,
  order_key TEXT    NOT NULL
);

CREATE TABLE task (
  id                INTEGER PRIMARY KEY,
  project_id        INTEGER NOT NULL,
  title             TEXT    NOT NULL,
  status            TEXT    NOT NULL,
  priority          TEXT,
  priority_rank     INTEGER NOT NULL,
  assignee_kind     TEXT,
  draft             INTEGER NOT NULL,
  due_on            TEXT,
  start_on          TEXT,
  created_at        TEXT    NOT NULL,
  updated_at        TEXT    NOT NULL,
  status_changed_at TEXT,
  completed_at      TEXT
);
CREATE INDEX task_by_status ON task (status, priority_rank, updated_at DESC);
CREATE INDEX task_by_project ON task (project_id);
CREATE INDEX task_by_due ON task (due_on);
CREATE INDEX task_by_change ON task (updated_at DESC);

CREATE TABLE task_comment (
  id          INTEGER PRIMARY KEY,
  task_id     INTEGER NOT NULL,
  author_kind TEXT,
  created_at  TEXT    NOT NULL
);
CREATE INDEX task_comment_by_task ON task_comment (task_id, created_at, id);

CREATE TABLE decision (
  id         INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL,
  title      TEXT    NOT NULL,
  status     TEXT    NOT NULL,
  draft      INTEGER NOT NULL,
  created_at TEXT    NOT NULL,
  updated_at TEXT    NOT NULL,
  decided_at TEXT
);
CREATE INDEX decision_by_recency ON decision (created_at DESC);
CREATE INDEX decision_by_project ON decision (project_id);

CREATE TABLE decision_comment (
  id          INTEGER PRIMARY KEY,
  decision_id INTEGER NOT NULL,
  author_kind TEXT,
  created_at  TEXT    NOT NULL
);
CREATE INDEX decision_comment_by_decision
  ON decision_comment (decision_id, created_at, id);

CREATE TABLE task_dependency (
  id            INTEGER PRIMARY KEY,
  task_id       INTEGER NOT NULL,
  blocked_by_id INTEGER NOT NULL
);
CREATE INDEX task_dependency_by_task ON task_dependency (task_id);
CREATE INDEX task_dependency_by_blocker ON task_dependency (blocked_by_id);

CREATE TABLE decision_task_link (
  id          INTEGER PRIMARY KEY,
  decision_id INTEGER NOT NULL,
  task_id     INTEGER NOT NULL
);
CREATE INDEX decision_task_link_by_task ON decision_task_link (task_id);
CREATE INDEX decision_task_link_by_decision ON decision_task_link (decision_id);

CREATE TABLE decision_edge (
  id                 INTEGER PRIMARY KEY,
  decision_id        INTEGER NOT NULL,
  target_decision_id INTEGER NOT NULL,
  kind               TEXT    NOT NULL
);
CREATE INDEX decision_edge_by_decision ON decision_edge (decision_id);
CREATE INDEX decision_edge_by_target ON decision_edge (target_decision_id);

CREATE TABLE dimension (
  id         INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL,
  name       TEXT    NOT NULL,
  role       TEXT    NOT NULL,
  order_key  TEXT    NOT NULL
);

CREATE TABLE dimension_value (
  id           INTEGER PRIMARY KEY,
  dimension_id INTEGER NOT NULL,
  name         TEXT    NOT NULL,
  order_key    TEXT    NOT NULL
);
CREATE INDEX dimension_value_by_dimension ON dimension_value (dimension_id);

CREATE TABLE task_dimension_value (
  id           INTEGER PRIMARY KEY,
  task_id      INTEGER NOT NULL,
  dimension_id INTEGER NOT NULL,
  value_id     INTEGER NOT NULL
);
CREATE INDEX task_dimension_value_by_task ON task_dimension_value (task_id);
CREATE INDEX task_dimension_value_by_value ON task_dimension_value (value_id);

CREATE TABLE task_commit (
  id         INTEGER PRIMARY KEY,
  task_id    INTEGER NOT NULL,
  sha        TEXT    NOT NULL,
  created_at TEXT    NOT NULL
);
CREATE INDEX task_commit_by_task ON task_commit (task_id, created_at);

CREATE TABLE attachment (
  id          INTEGER PRIMARY KEY,
  target_type TEXT    NOT NULL,
  target_id   INTEGER NOT NULL,
  filename    TEXT    NOT NULL,
  size_bytes  INTEGER NOT NULL,
  order_key   TEXT    NOT NULL
);
CREATE INDEX attachment_by_target ON attachment (target_type, target_id, order_key);

CREATE TABLE search_row (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  dataset   TEXT    NOT NULL,
  record_id INTEGER NOT NULL,
  kind      TEXT    NOT NULL,
  owner_id  INTEGER NOT NULL,
  source    TEXT    NOT NULL,
  sort_key  TEXT    NOT NULL,
  body      TEXT    NOT NULL
);
CREATE INDEX search_row_by_record ON search_row (dataset, record_id);

-- Trigrams, not words: the backlog is written in Japanese, which has no spaces for a word
-- tokeniser to split on, and a search for a fragment of an identifier is just as common.
CREATE VIRTUAL TABLE search_fts USING fts5 (
  body,
  content = 'search_row',
  content_rowid = 'id',
  tokenize = 'trigram'
);

CREATE TRIGGER search_row_ai AFTER INSERT ON search_row BEGIN
  INSERT INTO search_fts (rowid, body) VALUES (new.id, new.body);
END;
CREATE TRIGGER search_row_ad AFTER DELETE ON search_row BEGIN
  INSERT INTO search_fts (search_fts, rowid, body) VALUES ('delete', old.id, old.body);
END;
CREATE TRIGGER search_row_au AFTER UPDATE ON search_row BEGIN
  INSERT INTO search_fts (search_fts, rowid, body) VALUES ('delete', old.id, old.body);
  INSERT INTO search_fts (rowid, body) VALUES (new.id, new.body);
END;
''';
