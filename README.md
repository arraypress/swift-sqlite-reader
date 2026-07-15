# Swift SQLite Reader

A tiny, zero-dependency wrapper over the system `libsqlite3` for **reading and introspecting** a SQLite database — tables, schema, foreign keys, row counts, and ad-hoc queries — with values stringified for display. Ideal for database viewers, schema diagrams, and tooling; not a typed ORM.

## Features

- 🗄️ **Open a file** read-write (falling back to read-only, flagged via `readOnly`) with `SQLiteDB(url:)` — never creates a missing database
- 🧠 **Or an in-memory DB from DDL** with `SQLiteDB(sql:)` — visualize a `schema.sql` with no file
- 🔎 **Introspection** — `tables()`, `schema(_:)` (columns, PK, NOT NULL), `foreignKeys(_:)`, `rowCount(_:)`
- ▶️ **Ad-hoc queries** — `run(_:limit:)` returns a `SQLiteDB.Result` (columns, stringified rows, `error`, `rowsAffected`), row-capped for display safety
- 🧱 **Safe identifiers** — table/column names are quote-escaped internally
- 🪶 **Zero dependencies** — Foundation + the system `libsqlite3` (auto-linked via `import SQLite3`)
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-sqlite-reader.git", from: "1.0.0")
]
```

## Usage

```swift
import SQLiteReader

guard let db = SQLiteDB(url: fileURL) else { return }

for table in db.tables() {
    print(table, "—", db.rowCount(table), "rows")
    for column in db.schema(table) {
        print("  \(column.name): \(column.type)\(column.pk ? " PK" : "")")
    }
    for fk in db.foreignKeys(table) {
        print("  \(fk.from) → \(fk.toTable)(\(fk.toColumn))")
    }
}

let result = db.run("SELECT name, email FROM users LIMIT 50")
if let error = result.error { print("error:", error) }
else { for row in result.rows { print(row) } }
```

## Notes

- `SQLiteDB(url:)` **never creates** a database — it returns `nil` for a missing file.
- Row values are stringified (`NULL`, integers, doubles, text; blobs as `‹blob Nb›`).
- `run(_:limit:)` caps returned rows (default 2000) for display safety.

## License

MIT
