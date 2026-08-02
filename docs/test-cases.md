# Test Cases

The full inventory of every headless test case in this repo, grouped by the suite file it
lives in. The `## Totals` table below is the **authoritative pass count** — the README test
badge and any count quoted in the docs must agree with it.

**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`.

### test_constants.lua (25)

- Constants: every SourceType value equals its key (the stable stored form)
- Constants: every SourceType member appears in the display order
- Constants: the display order lists no source twice and invents none
- Constants: every SourceType member has a non-empty display label
- Constants: SourceLabel carries no label for a non-source key
- Constants: the deconstruct abilities are first-class sources, not folded into CRAFT
- Constants: every source has a live capture path (SOURCE_IMPLEMENTED is total)
- Constants: SOURCE_IMPLEMENTED claims nothing outside the enum
- Constants: the mute options are the implemented sources, in display order
- Constants: the confidence enum is exactly CERTAIN/INFERRED, key == value
- Constants: the aliases point at the very same enum tables
- Constants: the quest item class is the locale-independent numeric id 12
- Constants: the context TTL is a short positive window
- Constants: the mono font resolves inside this addon's media folder
- Constants: the quality ladder is Poor..Legendary then Heirloom, skipping 6 and 8
- Constants: every quality option carries a coloured '<name> and above' text
- Constants: the retention presets ascend and end on 'Always' (0 = disabled)
- Constants: every auction key is fully described
- Constants: auction tags are unique
- Constants: every auction provider has a human-readable name
- Constants: the capture options mirror AUCTION_KEYS one-for-one, in order
- Constants: the priority cascade covers every auction key exactly once
- Constants: the default-captured keys all sort ahead of the uncaptured ones
- Constants: every default-captured tag is a real auction key
- Constants: the currency pseudo-type is the reserved 'Currency' string

### test_util.lua (35)

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
- Util: ParseSelfLoot tags a bonus-roll self-loot line as BONUS_ROLL
- Util: ParseSelfLoot tags a created (crafted) self-loot line as CRAFT
- Util: ParseSelfLoot tags a refund self-loot line as REFUND
- Util: ParseSelfLoot leaves the source tag nil for normal loot
- Util: ParseSelfLoot ignores another player's bonus roll
- Util: ParseRollWon matches the player's roll-won line, else nil
- Util: ParseSelfCurrency single currency line -> link, qty 1
- Util: ParseSelfCurrency multiple currency line -> link, qty N
- Util: ParseSelfCurrency bonus + overflow variants -> link, qty
- Util: ParseSelfCurrency tags a refunded currency line as REFUND
- Util: ParseSelfCurrency ignores item loot and other players
- Util: FormatClock is HH:MM
- Util: FormatDate is DD-MMM-YYYY
- Util: FormatMoney shows non-zero parts
- Util: FormatBytes scales B / kB / MB
- Database: InitDB creates account-wide store
- Schema: Set writes through the single seam
- Schema: Set unknown path returns false
- Schema: nested minimap path writes
- Schema: reset does not alias the table-typed default (F-003)
- Util: RecordValue = max(pickedAuction, vendorPrice), else whichever exists

### test_compat.lua (17)

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
- Compat: CurrencyLinkID parses the id from a currency link
- Compat: GetCurrencyInfoFromLink returns id, name, icon
- Compat: CurrencyCategory resolves a currency to its list header
- Compat: CurrencyName resolves via C_CurrencyInfo, nil when unknown
- Compat: CurrencyQuality returns the tier, nil when unknown
- Compat: CurrencyBound is WARBAND when transferable, else BOP, nil when unknown

### test_attribution.lua (23)

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
- Attribution: OnSpellSucceeded memoizes the lookup — a repeated spell skips re-resolution
- Attribution: a memoized deconstruct source survives a later name change
- Attribution: deconstruct's own loot window does not clobber its source
- OnLootOpened logs ONE coalesced summary, not one line per slot
- Attribution: an unrelated player spell does not stamp a source
- Attribution: Auction-House mail stamps AH, ordinary mail stamps MAIL
- Attribution: taking a quest reward stamps QUEST

### test_filters.lua (20)

- Filters: AddBlacklist stores the id in the blacklist set
- Filters: AddBlacklist accepts a numeric string
- Filters: adding to one list removes the id from the other
- Filters: Remove drops the id
- Filters: mutations write a fresh table (no shared-default aliasing)
- Filters: AddBlacklist rejects non-numeric input
- Filters: adding an id already present is a no-op (returns false)
- Filters: change fires HistoryChanged (via Database) and re-caches the Collector
- Filters: ClearList empties one list and returns the count removed
- Filters: ClearList on an empty or unknown list is a no-op returning 0
- Filters: ClearList writes a fresh table (no shared-default aliasing)
- Filters: ClearAll empties both lists and returns the total removed
- Filters: ClearAll with both lists empty is a no-op returning 0
- Filters: ClearList fires HistoryChanged and re-caches the Collector
- Filters: SortedIDs returns ids ascending
- Filters: ParseItemID reads a number, an item link, and an itemString
- Filters: currency blacklist add / remove / query
- Filters: currency blacklist is independent of the item id lists
- Filters: ClearList and ClearAll include the currency blacklist
- Filters: ParseCurrencyID reads a currency link or a bare number

### test_auctionprice.lua (23)

- AuctionPrice: GatherAll collects all captured keys into a nested map
- AuctionPrice: Pick walks the priority list, first present wins
- AuctionPrice: Pick respects a reordered priority list
- AuctionPrice: GatherAll only captures keys in the capture set
- AuctionPrice: GatherAll returns nil when nothing gathered / disabled
- AuctionPrice: IsProviderAvailable reflects addon globals
- AuctionPrice: ReconcilePriority appends missing tags and drops unknown
- AuctionPrice: SwapPriorityTags swaps positions
- AuctionPrice: Pick on a record with no price map yields nothing
- AuctionPrice: Pick ignores a provider present but empty
- AuctionPrice: Pick skips a tag the map does not carry
- AuctionPrice: Pick still works when the stored priority list is empty
- AuctionPrice: the default cascade prefers TSM market value over a min buyout
- AuctionPrice: a provider that throws cannot break the capture
- AuctionPrice: a provider returning zero or negative prices records nothing
- AuctionPrice: GatherAll with no pricing addon installed returns nil
- AuctionPrice: Auctionator falls back to the item link when there is no id
- AuctionPrice: IsProviderAvailable is false for an unknown provider name
- AuctionPrice: ReconcilePriority de-duplicates without reordering the survivors
- AuctionPrice: ReconcilePriority always ends up covering every known key once
- AuctionPrice: ReconcilePriority rewrites in place, keeping the same table
- AuctionPrice: GetPriority creates the array on first use
- AuctionPrice: SwapPriorityTags refuses a tag that is not in the list

### test_collector.lua (33)

- Collector: BuildRecord populates every field
- Collector: ShouldRecord passes at/above threshold
- Collector: ShouldRecord rejects below threshold
- Collector: ShouldRecord rejects excluded source
- Collector: ShouldRecord treats nil quality as 0
- Collector: ShouldRecord drops quest items when excludeQuestItems on
- Collector: ShouldRecord keeps quest items when excludeQuestItems off
- Collector: ShouldRecord unaffected for non-quest class when filter on
- Collector: ShouldRecord reports the drop reason
- Collector: ShouldRecord whitelist forces a below-threshold item to record
- Collector: ShouldRecord whitelist forces a muted-source item to record
- Collector: ShouldRecord blacklist drops a passing item with reason 'blacklist'
- Collector: ShouldRecord flags a whitelist rescue but not a normal pass
- Collector: ShouldRecord id lists ignore other item ids
- Collector: end-to-end drops a blacklisted item, records after un-blacklisting
- Collector: whitelist records below threshold as a plain point-in-time row
- Collector: end-to-end writes an attributed record
- Collector: end-to-end attributes a bonus-roll line to BONUS_ROLL, overriding context
- Collector: end-to-end attributes a created line to CRAFT, overriding context
- Collector: end-to-end attributes a refund line to REFUND
- Collector: a roll-won line writes no record but stamps ROLL for the receive line
- Collector: end-to-end records a currency line as Type=Currency
- Collector: recordCurrency off drops currency
- Collector: a muted source drops its currency too
- Collector: a blacklisted currency is dropped, records after un-blacklisting
- Collector: a currency refund line records as Type=Currency, source REFUND
- Collector: a muted REFUND source drops the refunded currency
- Collector: end-to-end drops loot below the quality threshold
- Collector: end-to-end drops quest items when the filter is on
- Schema: excludeQuestItems row exists, defaults true, settable
- Collector: live SettingsChanged refreshes the collector alongside another bus consumer
- Collector SettingsChanged does not emit a redundant [Cfg] echo
- Collector: BuildRecord stores the auctionPrice map, no priceSource

### test_database.lua (42)

- Database: Add appends, increments Count, returns index
- Database: Add fires RecordAdded with record + index
- Database: Query empty filter returns all
- Database: Query by exact quality
- Database: Query by quality set (multi-select membership)
- Database: Query ignores a non-numeric quality (no crash, returns all)
- Database: QueryList filters an arbitrary array, not the live history
- Database: Query filters by itemType
- Database: Query filters by itemSubType
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
- Database: blacklist does NOT hide already-stored rows (point-in-time)
- Database: ActiveHistory returns raw history (no hide, same reference)
- Database: Export returns metatable-free copies with all fields
- Database: Export carries currencyID through for currency rows
- Database: Export coerces a nil source to OTHER (parity with Stats bySource)
- Database: Delete(pred) removes all matching, compacts, returns count
- Database: PruneOld drops records older than retentionDays
- Database: PruneOld with retentionDays=0 keeps everything
- Database: Purge wipes history and fires HistoryChanged
- Database: PruneOld returns removed count and logs [Prune]
- Database: PruneOld is zero-alloc and silent when debug is off
- Database: Purge returns removed count and logs [Data]
- Database: StorageStats counts records, day span, and estimated bytes
- Database: StorageStats on empty history is zeroed
- Database: RunMigrations sets schemaVersion when absent
- Database: RunMigrations leaves an already-current DB unchanged
- Database: RunMigrations is idempotent across repeated runs
- Database: RunMigrations is a safe no-op when the DB is absent
- NS.MigrationSummary formats from/to/rows
- Database: RunMigrations v1->v2 strips viaWhitelist and bumps schemaVersion
- Migrate: v2->v3 renames sellPrice to vendorPrice
- Migrations: v3->v4 backfills currency-record quality
- Migrations: v4->v5 backfills currency-record bound

### test_stats.lua (18)

- Stats: bySource / byQuality counts
- Stats: byDay buckets via date()
- Stats: byZone counts
- Stats: byItem aggregates by itemID with name/quality
- Stats: totals (records/distinct/first/last)
- Stats: topZones / topItems ordered by count desc
- Stats: respects the filter
- Stats: empty dataset yields zeroed totals
- Stats: vendor value (vendorPrice × quantity) totals + by source/zone
- Stats: byType / byBound / byChar / byConfidence / byKeystone
- Stats: hour/weekday buckets sum to record count (TZ-independent)
- Stats: highlights + topItemsByValue
- Analytics.SummaryLine formats range and count
- Stats: value uses auctionPrice when present, else vendorPrice
- Stats: currency stays out of the item/loot charts (its own section only)
- Stats: currencyBySource sums currency quantity per source across currencies
- Stats: currencyCharMatrix splits each character's currency by type
- Stats: per-character category matrices split each char by category

### test_browser.lua (41)

- Browser.MinWidth is wide enough for both the columns and the toolbar
- Browser.ExportWidth exactly consumes the bar remainder at minimum width
- Browser.ExportWidth never falls below its floor
- Browser.setToFilter turns a selection set into a filter value
- Browser.setToFilter maps an empty selection to nil (no filter at all)
- Browser.setToFilter copies rather than aliases the live selection
- Browser.asSet passes a stored set through, dropping the false entries
- Browser.asSet promotes the legacy scalar form to a one-entry set
- Browser.asSet maps the 'all' sentinel and nil to an empty set
- Browser.asSet round-trips through setToFilter for the stock (unfiltered) view
- Browser.withAll sorts by label and keeps the All sentinel first
- Browser.withAll on an empty dataset still offers the All sentinel
- Browser: source options are the distinct sources, human-labelled, All first
- Browser: type options skip the blank itemType
- Browser: subtype options skip the blank itemSubType
- Browser: zone options are keyed by mapID and de-duplicated
- Browser: a zone with no recorded name falls back to 'Map <id>'
- Browser: quality options run in quality order, not label order
- Browser: quality options carry the quality tint
- Browser: bound options follow the fixed binding order, not data order
- Browser: an unbound record surfaces as the NONE sentinel
- Browser: character options list each looter once, All then Current first
- Browser: character options carry the class colour and icon markup
- Browser: the Current preset lights up only for exactly the logged-in character
- Browser: the stock view filters nothing and sorts newest-first
- Browser: with no saved view, Clear falls back to the stock view
- Browser: a saved view wins over stock
- Browser: a corrupt (non-table) saved view degrades to stock rather than erroring
- Browser.ApplyView pushes the view's group and sort onto the table
- Browser.ApplyView resolves each stored set into the active filter
- Browser.ApplyView turns a date range into an absolute lower bound
- Browser.ApplyView carries the search text into the filter
- Browser.ApplyView scopes to the current player by default, not to everyone
- Browser.ApplyView discards whatever the previous view filtered
- Browser.SetCharSet drives the char filter, and an empty set clears it
- Browser.CurrentFilter hands out a copy, not the live filter
- Browser.CaptureView records the table's group and sort state
- Browser.CaptureView stores unset column filters as empty sets, never nil
- Browser.CaptureView omits the character scope (it is session-only)
- Browser.SaveView then ResetView clears the stored default
- Browser.ResetWindow empties the persisted geometry carve-out

### test_browsertable.lua (50)

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
- BrowserTable: auction column shows the picked price from the map
- BrowserTable: MinFrameWidth accounts for the AH column (>= 1212)
- BrowserTable: quality column is blank for a currency row
- BrowserTable: group keys are namespaced, so a zone can share a source's name
- BrowserTable: a missing zone/character/type groups under 'Unknown'
- BrowserTable: day groups key on the ISO date but read as the Date column
- BrowserTable: day groups run chronologically, not alphabetically
- BrowserTable: records with no quality group under an em-dash
- BrowserTable: ToggleCollapse flips a group shut and open again
- BrowserTable: collapsing one group leaves its siblings open
- BrowserTable: SetGroupBy sets the mode, and nil means flat
- BrowserTable: clicking the grouped column flips the group order, not the row sort
- BrowserTable: grouping by day maps the click to the Date column
- BrowserTable: an unsortable or unknown column key is ignored
- BrowserTable: SortRecords returns a new array and leaves the input alone
- BrowserTable: sorting by a column no record fills still keeps every row
- BrowserTable: the vendor and auction columns sort by copper, not by their text
- BrowserTable: an unrecognised source still shows something in the Source column
- BrowserTable: the vendor column is blank when no price was recorded
- BrowserTable: the auction column is blank when no price map was captured
- BrowserTable: quantity defaults to 1 when a record omits it
- BrowserTable: type and subtype cells are blank rather than nil-crashing
- BrowserTable: the Character cell prefixes a class icon when the class is known
- BrowserTable: ClassIconMarkup is empty for an unknown class
- BrowserTable: every column is fully described and uniquely keyed
- BrowserTable: Character is the last column and Item is the flexing one
- BrowserTable: every column except the flexing one reserves a width
- BrowserTable: the synthetic dataset is byte-identical between builds
- BrowserTable: every synthetic record carries the fields the table and charts read
- BrowserTable: only gear carries an item level in the synthetic dataset
- BrowserTable: only Mythic+ records carry a keystone level
- BrowserTable: synthetic confidence is always one of the two enum values
- BrowserTable: every synthetic auction map is pickable by the priority cascade
- BrowserTable: a large all-ties sort keeps every row in its original order

### test_export.lua (22)

- Export: BoundLabel maps tokens and nil
- Export: WowheadLink with bonus IDs
- Export: WowheadLink without bonuses is bare
- Export: WowheadLink falls back to itemID, then empty
- Export: CSV header order — ts,date,time first; computed + per-key auction cols; link last
- Export: CSV auction/value columns — auction present and vendor fallback
- Export: CSV emits picked price/tag + matching raw sub-columns for a nested auctionPrice map
- Export: CSV omits itemLink, sourceDetail, mapID, subzone, confidence
- Export: CSV row emits friendly bound + quotes commas
- Export: CSV date + time columns are FormatDate/FormatClock(ts)
- Export: CSV quality is human label beside numeric qualityRaw
- Export: CSV vendorPrice is 'Ng Ns Nc' beside raw copper
- Export: CSV emits one header + one row per record, CRLF-terminated
- Export: InsightsCSV header is Section,Label,Count,Value; CRLF-terminated
- Export: InsightsCSV summary reports the record count
- Export: InsightsCSV By Source uses labels + carries the value column
- Export: InsightsCSV quotes a label containing a comma
- Export: InsightsCSV includes already-stored rows regardless of blacklist (point-in-time)
- Export: CSV emits a currency row with currencyID and blank item cells
- Export: InsightsCSV includes currency sections
- Export: InsightsCSV includes the per-character × category companions
- Export: InsightsCSV names the per-currency breakdown Currency by Type x Source (no By-Source section)

### test_debuglog.lua (21)

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
- the console title renders the library's TITLE_SUFFIX as prose, not as its key
- every DebugLog string this addon renders resolves to prose, not to a key
- ConsoleCheckbox composes this addon's slash prefix into its tooltip
- the title bar makes room for this addon's 24-wide close button
- the copy window's buffer text is the whole buffer, in order
- InitSummary reports name, version, schema, active profile, and record count

### test_slash.lua (34)

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
- /lh reset on a table setting echoes (none), not a raw table pointer
- /lh resetall also clears the blacklist and whitelist (non-destructive settings reset)
- Reset All (ResetEverything) purges history and clears settings + filter lists + view + window
- NS.PREFIX is the mandated cyan [LH] tag
- every Slash string this addon renders resolves to prose, not to a key
- the help header names /loothistory as the alias for /lh
- LandingRows and HelpRows are the same rows, differing only by the chat indent
- a command row is gold command, single-spaced em dash, white description
- reset is path-scoped and resetall is the global verb (no page-shaped form)
- set refuses a value outside a numeric enum instead of storing it
- set clamps a number to its slider range and echoes what was stored
- set refuses a bool it cannot read rather than silently storing false
- the set-valued row renders through the format hook, never as <secret>
- OnSlash dispatches a host verb and lower-cases only the verb
- an unknown verb says so and then prints the help index

### test_schema.lua (30)

- Schema: debugConsole row is session-only, in Master Controls
- Schema: setting debugConsole toggles the window, never writes db.global
- Schema: getting debugConsole reflects the window visibility
- Schema: a normal (persisted) row still writes db.global
- Schema: auction rows exist with the AH Price group and defaults
- Schema: auction capture is a MultiCheck row; Rev-1 provider/priority rows are gone
- Schema: recordCurrency row exists, defaults true, settable
- Constants: CURRENCY_TYPE is "Currency"
- Schema: every row is uniquely pathed and fully described
- Schema: every row's default matches its declared type
- Schema: FindRow resolves a known path and rejects an unknown one
- Schema: every persisted path resolves against the shipped defaults
- Schema: the shipped default equals the schema's declared default
- Schema: every dropdown row offers values, and its default is one of them
- Schema: every MultiCheck row offers values
- Schema: the slider default sits inside its own bounds
- Schema: only the session-only rows carry their own get/set
- Schema.ReadPath walks a nested path and stops safely at a missing branch
- Schema.WritePath creates the intermediate tables it needs
- Schema.WritePath replaces a non-table sitting in the way
- Schema.Set refuses an unknown path and reports why
- Schema.Set stores a deep copy, never a reference to the caller's table
- Schema.Default hands out a copy of a table default, not the shared one
- Schema.Default returns nil for an unknown path
- Schema.Set runs the row's onChange with the new value
- Schema.Set honours a row's validate guard and leaves the DB untouched
- Schema.Get on an unknown path reads through rather than erroring
- Schema: every setting round-trips through Set then Get
- Schema: every declared command is uniquely named and dispatchable
- Schema: the settings CLI verbs are all present

### test_analytics.lua (57)

- Analytics._fitFontSize: fits within width returns base size
- Analytics._fitFontSize: overflow scales down proportionally
- Analytics._fitFontSize: clamps to the minimum floor
- Analytics._fitFontSize: zero/negative width returns base
- Analytics.paletteColor: rank 1 is the first palette entry
- Analytics.paletteColor: adjacent ranks differ
- Analytics.paletteColor: cycles past the palette length
- Analytics._tipText: joins the full label and its value
- Analytics._tipText: label alone when there is no value
- Analytics._tipText: value alone when there is no label
- Analytics._truncate: short text passes through
- Analytics._truncate: long text is cut with an ellipsis
- Analytics._truncate: exactly maxChars passes through
- Analytics._charStackSegments: keeps all when within cap
- Analytics._charStackSegments: collapses overflow into __OTHER__
- Analytics._charStackSegments: kept segments follow the global category order
- Analytics._charStackSegments: __OTHER__ always draws last
- Analytics._charStackSegments: a category outside the order sinks to the end
- Analytics._charStackSegments: the total counts every magnitude, kept or lumped
- Analytics._charStackSegments: zero and negative magnitudes are dropped
- Analytics._charStackSegments: an empty character yields no segments
- Analytics._charStackSegments: equal magnitudes break the tie by key, not by chance
- Analytics._buildCharStackRows: rows run by total descending
- Analytics._buildCharStackRows: labels are shortened and class-coloured
- Analytics._buildCharStackRows: the busiest character's bar is full width
- Analytics._buildCharStackRows: every row is scaled against that same maximum
- Analytics._buildCharStackRows: each segment's tip states the category and its value
- Analytics._buildCharStackRows: the row value is the character's total
- Analytics._buildCharStackRows: an unknown class falls back to neutral grey
- Analytics._buildCharStackRows: an empty matrix yields no rows
- Analytics._paletteMap: colours are assigned by list position
- Analytics._paletteMap: a key outside the list has no colour
- Analytics._paletteMap: an empty or missing list maps nothing
- Analytics._paletteMap: the same ordering yields the same colours across charts
- Analytics.paletteColor: every entry is a valid rgb triple
- Analytics._shortChar: drops the realm from a Name-Realm key
- Analytics._shortChar: a missing character reads '?'
- Analytics._classColor: a known class returns its class colour
- Analytics._classColor: an unknown or missing class falls back to neutral grey
- Analytics._qualityColor: returns an rgb triple for a real quality
- Analytics._money: zero and negative values read as a plain '0'
- Analytics._money: a real amount renders its gold/silver/copper parts
- Analytics._money: zero-valued denominations are omitted
- Analytics._dayKeyList: spans first to last day inclusive
- Analytics._dayKeyList: a day with no loot still gets a (zero) bar
- Analytics._dayKeyList: a single day yields exactly one key
- Analytics._dayKeyList: caps a long range to the 60 most recent days
- Analytics._dayKeyList: an empty history yields no keys
- Analytics._shortDay: a day key shortens to M/D with no leading zeros
- Analytics._shortDay: an unrecognised key passes through untouched
- Analytics._sortedByCount: orders by count descending
- Analytics._sortedByCount: equal counts break the tie by key ascending
- Analytics._sortedByCount: an empty map yields no rows
- Analytics._sortedByCount: numeric keys sort without a type error
- Analytics._truncate: reports whether it cut
- Analytics._truncate: a nil label becomes an empty string
- Analytics._truncate: the cut keeps maxChars-1 glyphs plus the ellipsis

### test_panel.lua (24)

- Panel: the parent category and all three sub-pages are registered
- Panel: registration is idempotent
- Panel: each sub-page carries the addon's name for the Blizzard left tree
- Panel: the General page renders one widget per non-skipped schema row, paired 50/50
- Panel: a checkbox row draws a CheckBox, a dropdown row a Dropdown, a slider row a Slider
- Panel: a dropdown is populated from the row's values, in declared order
- Panel: a slider is given the row's own min/max
- Panel: the Reset All action button pairs with the Window scale row
- Panel: the section headings are the schema groups, in declaration order
- Panel: clicking a checkbox writes through NS.Schema:Set
- Panel: choosing a dropdown entry writes the stored value
- Panel: releasing a slider writes the stored value
- Panel: an external write is mirrored back by Refresh
- Panel: the muted-source picker is INVERTED — a ticked box means 'record this source'
- Panel: the Defaults button is built on first OnShow, not at registration
- Panel: the General page's Defaults click restores every schema default
- Panel: the AH Price page's Defaults click restores the capture set AND the priority order
- Panel: the Filters page lists the ids on each list and can remove one
- Panel: the Filters page's Defaults click clears every id list
- Panel: the AH Price page draws one reusable row slot per known price source
- Panel: the AH Price page renders only its own schema group
- Panel: the landing page renders one label per slash command, through the ONE row formatter
- Panel: the landing page shows the tagline
- Panel: Open refuses during combat and never defers-and-replays

### test_libka0s.lua (17)

- NS.LIBKA0S_MISSING is the shared cause clause, verbatim
- the cause clause is published on the HEALTHY path too, not only when the lib is absent
- degraded install: every addon file loads with LibKa0s absent, with no error
- degraded install: the Core stub still prints a tagged, secret-safe line
- degraded install: the notice explains the absence through the shared cause clause, once
- degraded install: the Core stub answers every member the addon calls
- the L-trap matcher flags the value, not one spelling (all three forms)
- no descriptor in this addon is handed NS.L
- tripwire — LibKa0s-Core-1.0 ships no STRINGS table
- tripwire — Core.lua's source names neither STRINGS nor a descriptor L
- tripwire — Options.lua reads no descriptor L
- no rendered LibKa0s string in this addon is an unresolved SCREAMING_SNAKE key
- every file of LibKa0s.xml is vendored and loads
- the vendored copy carries the library's MIT licence
- the four adopted majors all resolved, and the seams are wired to them
- every seam file resolves its major with the silent flag
- the Options page registry built every page this addon declares

## Totals

| Suite | Cases |
|-------|------:|
| test_constants.lua | 25 |
| test_util.lua | 35 |
| test_compat.lua | 17 |
| test_attribution.lua | 23 |
| test_filters.lua | 20 |
| test_auctionprice.lua | 23 |
| test_collector.lua | 33 |
| test_database.lua | 42 |
| test_stats.lua | 18 |
| test_browser.lua | 41 |
| test_browsertable.lua | 50 |
| test_export.lua | 22 |
| test_debuglog.lua | 21 |
| test_slash.lua | 34 |
| test_schema.lua | 30 |
| test_analytics.lua | 57 |
| test_panel.lua | 24 |
| test_libka0s.lua | 17 |
| **Total** | **532** |
