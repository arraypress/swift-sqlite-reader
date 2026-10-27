# Swift SQLite Reader

Read an app's SQLite store from Swift and never write it — in place read-only, or as a private
copy with its write-ahead log — with typed rows, Apple's stored times, and "missing" told apart
from "give the app Full Disk Access". The one SQLite reader the fleet's Apple-app libraries share.

```swift
import SQLiteReader

let store = try SQLiteReader(path: callHistory, opening: .snapshot)   // or .readOnly
for row in try store.rows("SELECT ZNAME, ZDATE, ZID FROM ZCALL WHERE ZFLAG = ?", [.integer(1)]) {
    print(row["ZNAME"].string ?? "", row["ZDATE"].appleDate ?? .distantPast, row["ZID"].uuid ?? "")
}
store.columns(of: "ZCALL")        // upper-cased: columns come and go between app releases
```

## The two ways in

- **`.readOnly`** opens the store itself with `mode=ro`: for a store its app is not writing, or
  one whose log can be read in place.
- **`.snapshot`** copies the store and its `-wal`/`-shm` into a private temporary folder, reads
  the copy and deletes the folder when the reader goes. The live store is never opened: a call
  history on a real Mac had not been checkpointed for eleven weeks, so every recent call lived
  only in the log. (The copy is opened read-write only so SQLite can fold the log in; only
  queries are ever run.)

Before either, the path is asked of the kernel with `open(2)` (`FileChecks`): privacy
protection refuses with EPERM and plain permissions with EACCES, while Foundation reports a
refusal on a parent folder as "file not found". A protected store can also open and then refuse
its first read; that is reported as `permissionDenied` too — unless SQLite says the file is not a
database, or is damaged or encrypted, which is `unreadable`.

`busyTimeout:` sets how long a query waits for a lock its app holds (0, the default, fails at
once): for a store read in place while its app writes it.

## Values

`SQLiteValue` is what SQLite stored. It reads as `int` (whole reals and numeric text too),
`double`, `string`, `data`, `bool`, `uuid` (a 16-byte blob) and `appleDate` — Apple's times
since 2001, seconds (Core Data) or nanoseconds (Messages): 10¹¹ or more is nanoseconds, since
that many seconds is over three thousand years; 0 or less is "never". Rows read by position or
by column name, ignoring case.

Apps store loosely, so there are lenient readings too, shared rather than repeated in each
library: `truncatedInt` (a whole number stored as a real, truncated toward zero),
`decodedString` (text kept as a blob, read as UTF-8), `nonEmptyString` and `nonEmptyData`
(empty is absent).

## Tested

9 tests on real SQLite files made in the test — a store whose rows live only in its log while
its writer holds it open, a refused file, a file that is not a database, a locked store waited
for and not, a path with `?` and `#` — and every value. Every rule broken on purpose is caught
(22 of 22 mutations). Used by 14 of the fleet's Apple-app libraries.

## Requirements

macOS 14 or iOS 17; Swift 6.2. Nothing to fetch: SQLite is in the OS.

## License

MIT — see [LICENSE](LICENSE).
