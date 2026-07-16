# Test Cases

The full inventory of every headless test case, grouped by suite. This file is the
**authoritative pass count** for the addon.

**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`
whenever the suite changes (see [testing.md](testing.md)).

### test_util.lua (23)

- IsConcatSafe: true for number/string, false for an un-concatenable value
- SafeToString: passes normal values through tostring
- SafeToString: renders a secret value as <secret> instead of raising
- NS.Print: writes a cyan-tagged, space-joined line to the chat sink
- NS.Print: tolerates a secret arg (no concat crash), renders it <secret>
- NS.Print is reclaimed from AceConsole's :Print mixin (architecture-§2)
- Constants: source enum + order
- Util: RangeFrom maps range keys to a lower-bound timestamp
- Util: PlayerKey is Name-Realm
- Util: SplitPath splits dotted paths
- Util: ParseSelfLoot single self-loot → link, qty 1
- Util: ParseSelfLoot multiple self-loot → link, qty N
- Util: ParseSelfLoot pushed variant → link, qty
- Util: ParseSelfLoot ignores another player's loot
- Util: FormatClock is HH:MM
- Util: FormatDate is DD-MMM-YYYY
- Util: FormatMoney shows non-zero parts
- Util: FormatBytes scales B / kB / MB
- Database: InitDB creates account-wide store
- Schema: Set writes through the single seam
- Schema: Set unknown path returns false
- Schema: nested minimap path writes
- Schema: reset does not alias the table-typed default (F-003)

### test_compat.lua (11)

- Compat: DecodeGUID creature → kind + npcID
- Compat: DecodeGUID GameObject → kind, no npcID
- Compat: DecodeGUID Item → kind, no npcID
- Compat: DecodeGUID Vehicle/Pet count as unit kinds
- Compat: DecodeGUID nil-safe
- Compat: GetActiveKeystoneLevel nil when API absent (headless)
- Compat: API-absent guards degrade to nil/false with no flavor flag
- Compat: no game-flavor flags exposed (Retail-only addon)
- Compat: IsAuctionHouseMail matches AH sender + won-subject
- Compat: QualityLabel names qualities
- Compat: GetItemInfo surfaces the item class id

### test_attribution.lua (21)

- Attribution: Consume returns stamped context within TTL
- Attribution: Stamp defaults confidence to CERTAIN
- Attribution: Consume falls back to OTHER/INFERRED past TTL
- Attribution: Consume with no stamp → OTHER/INFERRED
- Attribution: context survives repeated Consume (multi-line loot)
- Attribution: ResolveLootSource creature → KILL + npcID
- Attribution: ResolveLootSource creature in encounter → KILL + encounter detail
- Attribution: ResolveLootSource GameObject in keystone → MPLUS + level
- Attribution: ResolveLootSource GameObject otherwise → CONTAINER
- Attribution: ResolveLootSource Item GUID → CONTAINER
- Attribution: opening a lootable bag item stamps CONTAINER
- Attribution: using a non-lootable bag item does not stamp
- Attribution: applying a pending spell to a bag item does not stamp CONTAINER
- Attribution: deconstruct spells map to their own source
- Attribution: DeconstructSource resolves enumerated ids locale-independently
- Attribution: DeconstructSource matches un-enumerated variants by localized name family
- Attribution: deconstruct's own loot window does not clobber its source
- OnLootOpened logs ONE coalesced summary, not one line per slot
- Attribution: an unrelated player spell does not stamp a source
- Attribution: Auction-House mail stamps AH, ordinary mail stamps MAIL
- Attribution: taking a quest reward stamps QUEST

### test_collector.lua (15)

- Collector: BuildRecord populates every field
- Collector: ShouldRecord passes at/above threshold
- Collector: ShouldRecord rejects below threshold
- Collector: ShouldRecord rejects excluded source
- Collector: ShouldRecord treats nil quality as 0
- Collector: ShouldRecord drops quest items when excludeQuestItems on
- Collector: ShouldRecord keeps quest items when excludeQuestItems off
- Collector: ShouldRecord unaffected for non-quest class when filter on
- Collector: ShouldRecord reports the drop reason
- Collector: end-to-end writes an attributed record
- Collector: end-to-end drops loot below the quality threshold
- Collector: end-to-end drops quest items when the filter is on
- Schema: excludeQuestItems row exists, defaults true, settable
- Collector: live SettingsChanged refreshes the collector alongside another bus consumer
- Collector SettingsChanged does not emit a redundant [Cfg] echo

### test_database.lua (36)

- Database: Add appends, increments Count, returns index
- Database: Add fires RecordAdded with record + index
- Database: Query empty filter returns all
- Database: Query by exact quality
- Database: Query by quality set (multi-select membership)
- Database: Query ignores a non-numeric quality (no crash, returns all)
- Database: QueryList filters an arbitrary array, not the live history
- Database: Query filters by itemType
- Database: QueryList bound=NONE matches unbound records
- Database: QueryList bound set unions tokens
- Database: QueryList ignores non-table bound filter
- Database: Query by char/mapID set (multi-select membership)
- Database: Query by source (string)
- Database: Query by source (set membership)
- Database: Query by char and by mapID
- Database: Query by ts range (from/to inclusive)
- Database: Query by case-insensitive text substring
- Database: Query combines predicates (AND)
- Database: Export returns metatable-free copies with all fields
- Database: DeleteAt removes the row, compacts, fires HistoryChanged
- Database: DeleteAt out-of-range returns false, no change
- Database: Delete(pred) removes all matching, compacts, returns count
- Database: PruneOld drops records older than retentionDays
- Database: PruneOld with retentionDays=0 keeps everything
- Database: Purge wipes history and fires HistoryChanged
- Database: PruneOld returns removed count and logs [Prune]
- Database: PruneOld is zero-alloc and silent when debug is off
- Database: Purge returns removed count and logs [Data]
- Database: DeleteAt logs [Data] with the deleted row's ts
- Database: StorageStats counts records, day span, and estimated bytes
- Database: StorageStats on empty history is zeroed
- Database: RunMigrations sets schemaVersion when absent
- Database: RunMigrations leaves an already-current DB unchanged
- Database: RunMigrations is idempotent across repeated runs
- Database: RunMigrations is a safe no-op when the DB is absent
- NS.MigrationSummary formats from/to/rows

### test_stats.lua (13)

- Stats: bySource / byQuality counts
- Stats: byDay buckets via date()
- Stats: byZone counts
- Stats: byItem aggregates by itemID with name/quality
- Stats: totals (records/distinct/first/last)
- Stats: topZones / topItems ordered by count desc
- Stats: respects the filter
- Stats: empty dataset yields zeroed totals
- Stats: vendor value (sellPrice × quantity) totals + by source/zone
- Stats: byType / byBound / byChar / byConfidence / byKeystone
- Stats: hour/weekday buckets sum to record count (TZ-independent)
- Stats: highlights + topItemsByValue
- Analytics.SummaryLine formats range and count

### test_browsertable.lua (16)

- BrowserTable: CellText renders each column
- BrowserTable: iLvl column shows level only when present
- BrowserTable: Bound column renders no text (icon-driven)
- BrowserTable: bound legend adds a line per state
- BrowserTable: test data covers every bound state, source, quality, class
- BrowserTable: Item column falls back to link name then '?'
- BrowserTable: BuildDisplayList yields one row entry per filtered record
- BrowserTable: SortRecords orders by active column, stable on ties
- BrowserTable: SetSort toggles direction on same column, resets on new
- BrowserTable: GroupRecords partitions into headers + rows with counts
- BrowserTable: group order toggles asc/desc, sorted by the grouped column
- BrowserTable: collapsed group emits only its header
- BrowserTable: groupBy none yields a flat row list
- BrowserTable: test mode filters the synthetic dataset
- BrowserTable: OrderedFilteredRecords returns filtered rows in order, no headers
- BrowserTable.RenderSummary is a single coalesced line

### test_export.lua (8)

- Export: BoundLabel maps tokens and nil
- Export: WowheadLink with bonus IDs
- Export: WowheadLink without bonuses is bare
- Export: WowheadLink falls back to itemID, then empty
- Export: CSV header has all fields plus date + wowheadLink
- Export: CSV row emits friendly bound + quotes commas
- Export: CSV date column is FormatDate(ts)
- Export: CSV emits one header + one row per record, CRLF-terminated

### test_debuglog.lua (16)

- FONT_MONO constant is a JetBrains Mono TTF path
- FormatPlain wraps the tag in brackets with single-space separators
- FormatPlain renders the tag verbatim (no padding or truncation)
- FormatPlain tolerates a nil tag
- FormatColored colors the timestamp and tag; pipe and content default
- NS.Debug renders a secret message arg as <secret> without raising
- NS.Debug formats ordinary args (numbers included) through %s
- /lh debug on enables state
- /lh debug off disables state
- /lh debug (no arg) toggles the window, not state
- header toggle click flips debug state
- SetEnabled(true) prints a green-coded ON ack through the NS.PREFIX printer
- SetEnabled(false) prints a red-coded OFF ack
- SetEnabled(true) appends the [Init] summary right after the enable bracket
- SetEnabled(false) appends a [Debug] logging disabled line after the flag flips off
- InitSummary reports name, version, schema, active profile, and record count

### test_slash.lua (20)

- FormatSchemaValue renders booleans as true/false
- FormatSchemaValue applies a row's fmt to numbers (scale → 1.00x)
- FormatSchemaValue leaves plain (enum) numbers raw
- FormatSchemaValue renders an empty table setting as (none)
- FormatSchemaValue renders a table setting as a sorted key set
- FormatSchemaValue omits falsy keys from a table setting
- FormatKV colours the key gold and the value white with a default separator
- list header is the green 'Available settings' line, no trailing colon
- list emits azure [group] headers in the declared order
- list value rows use FormatKV under their group, four-space indented
- list renders windowScale with its scale fmt
- CliList prints the header through NS.Print, cyan-tagged
- /lh get echoes a single FormatKV line for a known path
- /lh get with no argument prints a Usage line
- /lh get on an unknown path prints Setting not found
- /lh set echoes the stored value read back after writing
- /lh set on an unknown path prints Setting not found
- /lh version prints the cyan-tagged v<version> line
- NS.COMMANDS registers a version verb
- NS.PREFIX is the mandated cyan [LH] tag

## Totals

| Suite | Cases |
|-------|------:|
| test_util.lua | 23 |
| test_compat.lua | 11 |
| test_attribution.lua | 21 |
| test_collector.lua | 15 |
| test_database.lua | 36 |
| test_stats.lua | 13 |
| test_browsertable.lua | 16 |
| test_export.lua | 8 |
| test_debuglog.lua | 16 |
| test_slash.lua | 20 |
| **Total** | **179** |
