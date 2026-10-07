# Test Cases

The full inventory of every headless test case in this repo, grouped by the suite file it
lives in. The `## Totals` table below counts the cases that run: its **Total** is the
authoritative pass count, and the README test badge and any count quoted in the docs must equal
it. A declared skip is listed by name in its group and counted on the `Skipped` row, never in
Total.

**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`.

### test_constants.lua (37)

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
- Constants: the mono font is the face the library ships, not one of ours
- Constants: the quality ladder is Poor..Legendary then Heirloom, skipping 6 and 8
- Constants: every quality option carries a colored '<name> and above' text
- Constants: the retention presets ascend and end on 'Always' (0 = disabled)
- Constants: every auction key is fully described
- Constants: auction tags are unique
- Constants: every auction provider has a human-readable name
- Constants: the capture options mirror AUCTION_KEYS one-for-one, in order
- Constants: the priority cascade covers every auction key exactly once
- Constants: the default-captured keys all sort ahead of the uncaptured ones
- Constants: every default-captured tag is a real auction key
- Constants: the currency pseudo-type is the reserved 'Currency' string
- bus: Database:Add sends RecordAdded with the record and its index
- bus: Database:FireHistoryChanged sends HistoryChanged with no payload
- bus: a settings write sends SettingsChanged with its reason
- bus: Reconciler:Flush sends HoldingsChanged once per holder that moved
- bus: NS.MSG declares exactly the four wire names
- bus: NS.MSG is the library's strict catalog, so a mistyped key raises
- bus: no addon file but core/Constants.lua types a Ka0s_LootHistory_ literal
- bus: the degraded build declares the same names, without the library
- Constants: ledger reasons are appended SourceType members with labels
- Constants: existing sources keep their order positions (append-only)
- Constants: no ledger reason is offered as a capture mute
- Constants: direction palette and glyphs

### test_mediasetup.lua (11)

- MediaSetup: NS.Icon answers the vendored path, extensionless
- MediaSetup: an icon the library does not ship answers nil
- MediaSetup: NS.MediaFont answers the vendored face, and only a face it ships
- MediaSetup: the font this addon names is the face the library registers
- MediaSetup: the font no longer resolves inside this addon's own folder
- MediaSetup: every mark this addon draws is one the library ships
- MediaSetup: every name the library ships has a file in the vendored copy
- MediaSetup: the source names no icon the DRAWN list above has forgotten
- MediaSetup: a tinted mark spells the long escape, vertex color last
- MediaSetup: NS.IconMarkup splices the extensionless path and never answers nil
- MediaSetup: with no library there is no art and no face, and that is not an error

### test_envsetup.lua (11)

- EnvSetup: NS.Meta asks about THIS addon's folder, not its title or its slash prefix
- EnvSetup: NS.Meta degrades to nil when the client exposes no manifest reader
- EnvSetup: NS.Version prefers the TOC over this addon's own constant
- EnvSetup: NS.Version falls back to this addon's own constant
- EnvSetup: the fallback constant is the version LootHistory.toc ships
- EnvSetup: NS.Zone answers two strings
- EnvSetup: an absent zone reads as "", which storage buckets with nil
- EnvSetup: NS.PlayerMapID answers the map id
- EnvSetup degraded: an install with no LibKa0s still reads its TOC and stamps its zone
- EnvSetup degraded: a bare global GetAddOnMetadata is not a rung
- EnvSetup: the deleted shims are gone from Compat

### test_poolsetup.lua (3)

- PoolSetup: the seam is published
- PoolSetup: a released object is reused rather than rebuilt
- PoolSetup: ReleaseAll returns every active object to the free list

### test_itemsetup.lua (7)

- ItemSetup: the seam is published
- ItemSetup: the primitives answer what the deleted shims answered
- ItemSetup: this addon now HAS the id parser it lacked
- ItemSetup: the moved shims are gone from Compat
- ItemSetup: the resolver did NOT move, and still guesses when uncached
- ItemSetup: an uncached |cnIQ link answers its quality with no palette installed
- ItemSetup: a stored pre-11.1.5 |cff link still reads through the hex rung

### test_util.lua (47)

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
- Util: a rewritten LOOT_ITEM_SELF is honored on the next parse without a reload
- Util: a rewritten CURRENCY_GAINED_MULTIPLE is honored
- Util: LOOT_ROLL_YOU_WON appearing after a nil first parse is honored
- Util: an unchanged global set does not rebuild
- Util: FormatClock is HH:MM
- Util: FormatDate is DD-MMM-YYYY
- Util: FormatMoney shows non-zero parts
- Util: FormatBytes scales B / kB / MB
- Database: InitDB creates the account-wide store and the Default profile
- Schema: Set writes through the single seam
- Schema: Set unknown path returns false
- Schema: nested minimap path writes
- Schema: reset does not alias the table-typed default (F-003)
- Util: RecordValue = max(pickedAuction, vendorPrice), else whichever exists
- Coalesce: many calls inside one window collapse to a single run
- Coalesce: the run is never LOST, only deferred
- Coalesce: a later burst schedules a fresh run rather than being dropped
- Coalesce: a raise inside the body does not wedge the trigger forever
- Coalesce: a window canceled by the stand-down does not wedge the trigger
- Coalesce: with no C_Timer it runs straight through
- Util: ParseSelfMoney reads looted and shared money
- Util.RangeFrom: 90d and 1y are rolling windows

### test_ledger.lua (36)

- Ledger: ThingKey round-trips for every kind
- Ledger: Diff reports signed deltas, sorted, zeros omitted
- Ledger: Diff treats nil maps as empty
- Ledger: DirSign totals
- Util: row accessors give legacy defaults
- Constants: ledger enums and warband key
- Ledger: ClassifyItems pairs a bag-to-bank deposit into one MOVE, no net
- Ledger: ClassifyItems keeps the unpaired remainder as net change
- Ledger: ClassifyItems ignores containers not rescanned on both sides
- Ledger: mail taken is a gain unless it was own-origin
- Ledger: escrow arrivals and auction exits never become net
- Ledger: posting bags to auctions is a MOVE
- Ledger: PairHolders turns a warband deposit into one pair and clears both nets
- Ledger: PairHolders leaves same-sign changes alone
- Ledger: claims consume fully, partially, and expire
- Ledger: a late claim is still consumed inside its TTL
- Ledger: coalesce key and the 60 s amend window
- Ledger: ShouldHold — one-sided waits 6 s, unclaimed gain waits 1.5 s
- Ledger: Signed applies DirSign
- Ledger: PickReason — forced wins (login drift)
- Ledger: PickReason — a fresh outbound stamp beats scopes, filtered by kind/dir
- Ledger: PickReason — merchant scope
- Ledger: PickReason — guild bank is outside the account
- Ledger: PickReason — gold-out scopes
- Ledger: PickReason — item losses by inference
- Ledger: PickReason — gains read the inbound loot stamp, then mailbox/AH scope
- Ledger: PickReason — currency source names map before scopes
- Ledger: CurrencyReason maps known enum member names, nil otherwise
- Ledger: DayKey is the local calendar day and sorts chronologically
- Ledger: RowThingKey covers items, currencies, gold and legacy rows
- Ledger: RollupClose overwrites the day's close; RollupFlow accumulates by direction
- Ledger: a MOVE or a zero flow creates no cell (the rollup stays sparse)
- Ledger: PruneDaily drops old days and folds each thing's last close onto the cutoff day
- Ledger: PruneDaily never overwrites a close already on the cutoff day
- Ledger: PruneDaily with nothing old is a no-op
- Ledger: ForgetHolderDaily removes a holder's cells and days it leaves empty

### test_ledgerformat.lua (5)

- LedgerFormat: glyph and color per direction, legacy reads as a gain
- LedgerFormat: quantity text is signed; transfers unsigned; gold as money
- LedgerFormat: gold quantity is pale gold; others take the direction color
- LedgerFormat: signed count and money; zero is a gray dash
- LedgerFormat: the warband holder reads as Warband

### test_compat.lua (64)

- Compat: DecodeGUID creature → kind + npcID
- Compat: DecodeGUID GameObject → kind, no npcID
- Compat: DecodeGUID Item → kind, no npcID
- Compat: DecodeGUID Vehicle/Pet count as unit kinds
- Compat: DecodeGUID nil-safe
- Compat: GetActiveKeystoneLevel nil when API absent (headless)
- Compat: API-absent guards degrade to nil/false with no flavor flag
- Compat: no game-flavor flags exposed (Retail-only addon)
- Compat: IsAuctionHouseMail matches AH sender + won-subject
- Compat: an item NAME containing 'Warbound' is not a bind line
- Compat: ScanBound separates warbound from warbound-until-equipped
- Compat: ScanBound still splits UE when the …_UNTIL_EQUIP globals are nil
- Compat: ScanBound reads warbound wording with every global absent
- Compat: ScanBound reads a bind line joined or padded with a no-break space
- Compat: BindState maps every Enum.ItemBind value to a bind token
- Compat: GetItemExtras reads the bind state off bindType when it names one
- Compat: GetItemExtras believes the tooltip when bindType understates it
- Compat: an uncached item's 'Retrieving item information' tooltip is NOT readable
- Compat: ItemBindState isn't settled until the item data is cached too
- Compat: ScanBound reports whether the tooltip was readable at all
- Compat: GetItemExtras falls back to the tooltip when the item isn't cached
- Compat: ItemBindState resolves an id, nil when the client can't answer
- Compat: ItemBindState takes the tooltip's verdict when bindType has none
- Compat: BestBound keeps the more specific verdict, never demotes warbound
- Compat: GetItemInfo surfaces the item class id
- Compat: CurrencyLinkID parses the id from a currency link
- Compat: GetCurrencyInfoFromLink returns id, name, icon
- Compat: CurrencyCategory resolves a currency to its list header
- Compat: CurrencyCategory rebuilds on a miss, so a currency first seen later resolves
- Compat: CurrencyCategory walks the list at most once for an id that is truly absent
- Compat: CurrencyCategory resolves an id that missed once the list grows to include it
- Compat: a nil-id currency refresh lets a missed id resolve when the list size is unchanged
- Compat: ListedCurrencyID keeps a listed id and remaps a hidden one to its one same-name twin
- Compat: ListedCurrencyID drops a hidden id whose name matches two listed currencies
- Compat: ListedCurrencyID keeps an id under a collapsed header that the stored baseline holds
- Compat: the filter-row label shims are gone (LibKa0s IdList labels its own rows)
- Compat: CurrencyName and GetItemTypeInfo answer, and degrade to nil
- Compat: GetItemSellPrice degrades to nil
- Compat: CurrencyQuality returns the tier, nil when unknown
- Compat: CurrencyBound is WARBAND when transferable, else BOP, nil when unknown
- Compat: GetSpellName answers C_Spell.GetSpellName's name, as one value
- Compat: GetSpellName falls back to the legacy global's first return, as one value
- Compat: GetSpellName with a nil id answers nil and calls no rung
- Compat: GetSpellName is LibKa0s-Compat-1.0's member on the live path
- Compat: a nil or empty C_Spell.GetSpellName answer falls through to GetSpellInfo's name
- Compat: the degraded build's GetSpellName answers nil even with C_Spell present
- Compat: bag-id groups come from Enum.BagIndex names, type constants excluded
- Compat: bag-id groups degrade to EMPTY without Enum.BagIndex, never to guessed numbers
- Compat: container slot read and empty slot
- Compat: GetMoney nets cursor and trade money
- Compat: GetWarbandMoney reads the account bank, nil when API absent
- Compat: ListCurrencies expands collapsed headers and restores them
- Compat: IsConsumable reads the item class
- Compat: account-wide currency and currency-source names
- Compat: inbox scan sums attachments by itemID
- Compat: send-mail read returns attachments and money
- Compat: owned auctions count only active ones
- Compat: AuctionMailKind parses the localized subjects
- Compat: TradeTargetKey appends the player's realm when missing
- Compat: LatestCurrencyTransfer appends the realm only when the client knows it
- Compat: HookSecure is presence-gated
- Compat: ShowLinesTooltip draws a gold title and one colored double line per row
- Compat: ShowTintedTooltip draws each line in its own color; false without lines or GameTooltip
- Compat: ShowLinesTooltip answers false without a GameTooltip

### test_scanner.lua (5)

- Scanner: variants sum by itemID across slots and bags
- Scanner: equipped slots and equipped bags
- Scanner: equipped bags come from the Enum.BagIndex-derived BAG_IDS, not a literal range
- Scanner: currencies split account-wide to warband
- Scanner: money reads

### test_holdings.lua (8)

- Holdings: ApplyContainer replaces one column and keeps others
- Holdings: unchanged container reports no change
- Holdings: Total sums holders and warband, sorted by count
- Holdings: gold and currency totals
- Holdings: genesis is set once; partial until bank seen
- Holdings: Holders lists characters then warband
- Holdings: Search keeps uncached items and filters by holder
- Holdings: ForgetHolder drops the entry

### test_rollup.lua (21)

- Rollup: a holdings change writes that day's close for the thing that moved
- Rollup: an unchanged thing writes no cell
- Rollup: a thing leaving every container closes at 0
- Rollup: currency and money changes write closes
- Rollup: the write hook tallies gains and losses; transfers tally nothing
- Rollup: an amend tallies only its delta, on the day it happens
- Rollup: the gate container's first scan after genesis ends the partial window
- Rollup: the warband's gate is its tabs
- Rollup: wired through the write hook - Database:Add reaches the tally
- Rollup: Keys indexes every thing in the rollup and learns new ones
- Rollup: escrow and currency credits write closes too (Phase 2's direct holdings writes)
- Rollup: Disable removes the write hook
- Rollup: ForgetHolder drops every cell of that holder
- Holdings: Describe names a thing by key, Gold included
- Rollup: Prune with Always (0) keeps every day
- Rollup: Prune drops days past the retention and carries their closes
- Rollup: SeedOnce writes today's close for every held thing, once per account
- Rollup: SeedOnce never overwrites a close already written today
- Schema: rollupRetentionDays is account-wide, defaults to Always and is reset-exempt
- Rollup: RecomputeFlows rebuilds only the touched cells from IN / OUT rows, closes untouched
- Rollup: the suite restores the shared state it changed

### test_attribution.lua (37)

- Attribution: Consume returns stamped context within TTL
- Attribution: Stamp defaults confidence to CERTAIN
- Attribution: Consume falls back to OTHER/INFERRED past TTL
- Attribution: Consume with no stamp → OTHER/INFERRED
- Attribution: context survives repeated Consume (multi-line loot)
- Attribution: ResolveLootSource creature → KILL + npcID
- Attribution: ResolveLootSource creature in encounter → KILL + encounter detail
- Attribution: KILL loot inside the post-kill grace window carries the encounter
- Attribution: KILL loot after the grace window has expired carries no encounter
- Attribution: ENCOUNTER_END keeps the context with an expiry on a kill, clears it on a wipe
- Attribution: ResolveLootSource GameObject in keystone → MPLUS + level
- Attribution: ResolveLootSource GameObject otherwise → CONTAINER
- Attribution: ResolveLootSource Item GUID → CONTAINER
- Attribution: opening a lootable bag item stamps CONTAINER
- Attribution: using a non-lootable bag item does not stamp
- Attribution: applying a pending spell to a bag item does not stamp CONTAINER
- Attribution: deconstruct spells map to their own source
- Attribution: DeconstructSource resolves enumerated ids locale-independently
- Attribution: DeconstructSource matches un-enumerated variants by localized name family
- Attribution: a no-break space in a localized spell name does not break the family match
- Attribution: OnSpellSucceeded memoizes the lookup — a repeated spell skips re-resolution
- Attribution: a memoized deconstruct source survives a later name change
- Attribution: deconstruct's own loot window does not clobber its source
- OnLootOpened logs ONE coalesced summary, not one line per slot
- Attribution: an unrelated player spell does not stamp a source
- Attribution: Auction-House mail stamps AH, ordinary mail stamps MAIL
- Attribution: taking a quest reward stamps QUEST
- Attribution: leaving the party instance clears the keystone, so later objects are CONTAINER
- Attribution: a zone change inside the party instance keeps the keystone (MPLUS 12)
- Attribution: CHALLENGE_MODE_RESET clears the keystone
- Attribution: a completion-time keystone level of 0 does not overwrite the started level
- Attribution: zoning back into an active key re-arms the keystone at its level
- Attribution: Enable registers nine bus events, the player-only cast frame and five hooks
- Attribution: a retired ENCOUNTER_START costs only itself (front gate)
- Attribution: a retired UNIT_SPELLCAST_SUCCEEDED leaves the bus events bound (front gate)
- Attribution: a retired ENCOUNTER_START costs only itself (pcall rung)
- Attribution: a retired UNIT_SPELLCAST_SUCCEEDED leaves the bus events bound (pcall rung)

### test_attribution_out.lua (13)

- AttributionOut: StampOut writes the outbound slot with TTL and filters
- AttributionOut: interaction show/hide toggles scopes
- AttributionOut: ReasonContext exposes both slots and the scopes, resetting per-call fields
- AttributionOut: SendMail to an own alt resolves the holder and stages attachments
- AttributionOut: SendMail to a stranger leaves `to` nil
- AttributionOut: posting records the item in flight and stamps the deposit
- AttributionOut: taking AH sale money stamps AH_SOLD and names the item
- AttributionOut: a completed trade stamps TRADE_GIVE and records the partner
- AttributionOut: a trade with an own alt stamps ALT_TRADE on both halves
- AttributionOut: a craft arms the reagent window
- AttributionOut: guild bank frame OnShow/OnHide drive the guildBank scope
- AttributionOut: stood down, stamps and scopes are ignored
- AttributionOut: EnableOut registers on a private target; DisableOut unregisters and clears

### test_filters.lua (19)

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
- Filters: the add-box parsers are gone (LibKa0s IdList parses its own add box)
- Filters: currency blacklist add / remove / query
- Filters: currency blacklist is independent of the item id lists
- Filters: ClearList and ClearAll include the currency blacklist

### test_auctionprice.lua (27)

- AuctionPrice: GatherAll collects all captured keys into a nested map
- AuctionPrice: Pick walks the priority list, first present wins
- AuctionPrice: the shipped cascade reaches a non-default-collected key without the panel
- AuctionPrice: Pick honors a reorder made by MovePriorityWithin
- AuctionPrice: Pick respects a reordered priority list
- AuctionPrice: GatherAll only captures keys in the capture set
- AuctionPrice: GatherAll returns nil when nothing gathered / disabled
- AuctionPrice: IsProviderAvailable reflects addon globals
- AuctionPrice: ReconcilePriority appends missing tags and drops unknown
- AuctionPrice: MovePriorityWithin splices a tag to an index, not a run of swaps
- AuctionPrice: MovePriorityWithin leaves the tags OUTSIDE the subset exactly where they are
- AuctionPrice: MovePriorityWithin refuses a no-op and an out-of-range index
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
- AuctionPrice: MovePriorityWithin refuses a subset naming a tag the cascade does not carry

### test_collector.lua (48)

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
- Collector: OnChatMsgLoot reuses one gate-config table across loot lines
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
- Collector: a recorded loot line logs [Loot] and [AHPrice], prices sorted, the pick named
- Collector: with no price gathered the [AHPrice] line says none and picks nothing
- Collector: a refused loot line logs one [Drop] line naming the reason, and nothing else
- Collector: with logging off a loot line calls the debug sink not at all
- Collector: a recorded loot line claims its stack for the holdings diff
- Collector: a gated-out loot line claims nothing
- Collector: a recorded currency line claims its amount
- Collector: CHAT_MSG_MONEY writes a GOLD gain and claims it
- Collector: CHAT_MSG_MONEY with recordGold or trackLedger off writes nothing
- Collector+Reconciler: a hidden currency with a listed twin records once, under the twin, claimed
- Collector: a hidden currency with no listed twin records nothing and claims nothing
- Collector+Reconciler: a new listed currency already in the list records one claimed chat row
- Collector: with trackLedger off an unlisted, unheld currency with no twin records one chat row
- Collector+Reconciler: a new currency not yet listed at chat time gets one diff row after the rescan

### test_reconciler.lua (7)

- Reconciler: BAG_UPDATE only marks dirty; BAG_UPDATE_DELAYED flushes
- Reconciler: bag flush never touches bank column
- Reconciler: bank is unreadable until the banker interaction shows
- Reconciler: combat defers every scan to PLAYER_REGEN_ENABLED
- Reconciler: LoginScan seeds genesis, partial until bank seen
- Reconciler: account-wide currency lands on the warband holder
- Reconciler: trackLedger off unregisters, on registers again

### test_reconciler_rows.lua (31)

- Reconciler: bag to bank deposit writes one MOVE and no gain or loss
- Reconciler: a one-sided change at an open bank is held, then paired
- Reconciler: vendor sale writes item OUT SELL and gold IN SELL
- Reconciler: combat potion burst lands as one CONSUME row and coalesces
- Reconciler: rows after the 60 s window append
- Reconciler: a warband deposit is an OUT on the character and an IN on the warband
- Reconciler: a warband withdraw of gold and an item is one OUT and one IN each, no MOVE
- Reconciler: coalescing amends each half of a holder move separately
- Reconciler: a posted claim absorbs the gain and stamps the chat row
- Reconciler: blacklisted items never get a row but holdings still count them
- Reconciler: recordGold off suppresses gold rows only
- Reconciler: no genesis, no rows
- Reconciler: an unexplained loss with no stamp is OTHER
- Collector+Reconciler: a looted stack is counted once, chat first
- Collector+Reconciler: a looted stack is counted once, delta first
- Collector+Reconciler: a partial claim leaves the remainder as a diff row
- Collector+Reconciler: looted gold is counted once
- Reconciler: first login is genesis and writes nothing
- Reconciler: login drift writes UNTRACKED rows, no holds, claims untouched
- Reconciler: a login in combat waits for regen
- Reconciler: a currency spend from the event args is an OUT with its mapped reason
- Reconciler: currency events in combat accumulate, one row after regen
- Reconciler: an account-wide currency change lands on the warband holder
- Reconciler: an account currency transfer to an own alt is an OUT and an IN and credits the alt
- Reconciler: changes made while stood down land as UNTRACKED on resume
- Reconciler: a hidden currency's delta writes nothing, and the next login rescan writes nothing
- Reconciler: bank drift since the last visit is UNTRACKED on the first read of the next
- Reconciler: a currency delta pending when the banker opens survives the drift pass
- Reconciler: a bank never read before is a silent first read that ends partial
- Reconciler: warband tab and gold drift lands UNTRACKED on the warband, never paired
- Reconciler: a deferred login with the banker open keeps its bags drift UNTRACKED

### test_escrow.lua (14)

- Escrow: mail to an own alt is an ALT_MAIL loss; the alt's mail and own-origin are credited
- Escrow: taking mail splits own-origin (MOVE) from outside gains (IN)
- Escrow: taking an alt's mail is an ALT_MAIL gain; a returned auction stays a MOVE
- Escrow: posting moves bags to auctions and credits the auctions column
- Escrow: an auction that leaves and comes back by mail is a return, not a sale
- Escrow: an AH sale mail books the pending exit as AH_SOLD
- Escrow: an exit unresolved for 30 days is booked as sold
- Escrow: mail money taken from an own alt's send is an ALT_MAIL gain
- Escrow: mail money credited before Phase 7 (no mailMoneyAlt) is still a MOVE when taken
- Escrow: mixed mail money: the alt-sent part is an ALT_MAIL gain, the pre-Phase 7 rest a MOVE
- Escrow: the mailbox is unreadable once closed
- Escrow: a sale payout taken while an alt's gold waits stays AH_SOLD; the alt's gold is ALT_MAIL
- Escrow: gold from another player is a gain even while an alt's gold waits
- Escrow: a money-only pass leaves the staged items for the item pass; both are ALT_MAIL losses

### test_database.lua (83)

- Database: Add appends, increments Count, returns index
- Database: Add fires RecordAdded with record + index
- Database: Query empty filter returns all
- Database: Query by exact quality
- Database: Query by quality set (multi-select membership)
- Database: Query ignores a non-numeric quality (no crash, returns all)
- Database: QueryList filters an arbitrary array, not the live history
- Database: QueryList treats quality 0 as a filter, not as an absent one
- Database: QueryList quality set matches the raw quality, exact quality defaults it to 0
- Database: QueryList treats a falsy filter field as unfiltered
- Database: Query filters by itemType
- Database: Query filters by itemSubType
- Database: QueryList bound=NONE matches unbound records
- Database: QueryList bound set unions tokens
- Database: QueryList ignores non-table bound filter
- Database: Query by char/zone set (multi-select membership)
- Database: Query by zone spans every map id that carries the name
- Database: Query by zone buckets nameless records under the empty name
- Database: Query by source (string)
- Database: Query by source (set membership)
- Database: Query by char and by zone
- Database: Query by ts range (from/to inclusive)
- Database: Query by case-insensitive text substring
- Database: Query combines predicates (AND)
- Database: blacklist does NOT hide already-stored rows (point-in-time)
- Database: ActiveHistory returns raw history (no hide, same reference)
- Database: Export returns metatable-free copies with all fields
- Database: Export carries currencyID through for currency rows
- Database: Export coerces a nil source to OTHER (parity with Stats bySource)
- Database: Export deep-copies auctionPrice and sourceDetail (mutating the export leaves history intact)
- Database: Delete(pred) removes all matching, compacts, returns count
- Database: PruneOld drops records older than retentionDays
- Database: PruneOld fires HistoryChanged only when it removed rows
- Database: PruneOld with retentionDays=0 keeps everything
- Database: Purge wipes history and fires HistoryChanged
- Database: PruneOld returns removed count and logs [Prune]
- Database: PruneOld is zero-alloc and silent when debug is off
- Database: Delete logs one [Data] line with the removed count, and nothing when debug is off
- Database: Purge returns removed count and logs [Data]
- Database: StorageStats counts records, day span, and estimated bytes
- Database: StorageStats charges a currency record for the strings it does carry
- Database: StorageStats on empty history is zeroed
- Database: RunMigrations sets schemaVersion when absent
- Database: defaults declare schemaVersion 0, and the target is the ladder's highest step
- Database: a fresh store at schemaVersion 0 walks every step to 14
- Database: RunMigrations leaves an already-current DB unchanged
- Database: RunMigrations is idempotent across repeated runs
- Database: RunMigrations is a safe no-op when the DB is absent
- NS.MigrationSummary formats from/to/rows
- Database: RunMigrations v1->v2 strips viaWhitelist and bumps schemaVersion
- Migrate: v2->v3 renames sellPrice to vendorPrice
- Migrations: v3->v4 backfills currency-record quality
- Migrations: v4->v5 backfills currency-record bound
- Migrations: v5->v6 parks the retired ACCOUNT rows on WARBAND
- Migrations: the warbound split is armed, never run inline
- Migrations: v7->v8 rewrites a saved mapID filter as the zone names those ids carried
- Migrations: v7->v8 drops a saved mapID filter whose ids are no longer in the history
- Migrate: v10->v11 creates the ledger stores and rewrites no rows
- Migrate: the v11 step does not arm the reset prompt on an empty (fresh-install) history
- Migrate: v11 step is idempotent and keeps existing holdings
- Migrate: an already-current DB does not arm the reset prompt
- Database: Purge retires the pending reset prompt
- Defaults: trackLedger defaults on; resetPrompt undeclared
- Database: ArmBoundRepair re-arms on a revision bump, and only then
- Database: RepairBoundStates raises rows to the state the tooltip witnesses
- Database: RepairBoundStates promotes a BOE row the bind type filed too loosely
- Database: a readable tooltip settles a row even when the bind type says otherwise
- Database: RepairBoundStates repairs a row that has only a link
- Database: RepairBoundStates warms the cache from the link when a row has no itemID
- Database: RepairBoundStates resets the give-up budget on a pass that fixed something
- Database: RepairBoundStates gives up after the attempt cap
- Database: OnWrite hooks see Add and Amend with the quantity delta
- Database: Amend re-sends RecordAdded with the same record and index
- Database: QueryList dir clause treats legacy rows as gains
- Database: minQuality floors items only, whitelist exempt
- Database: Export carries the ledger fields with legacy defaults
- Migrate v12->v13: a warband deposit pair becomes OUT + IN WARBAND_DEPOSIT with one pairId
- Migrate v12->v13: a warband withdraw of gold becomes OUT on the Warband, IN on the character
- Migrate v12->v13: character-to-character pairs take ALT_MAIL / CURRENCY_TRANSFER / ALT_TRADE
- Migrate v12->v13: a move inside one holder stays a MOVE; an existing pairId is kept
- Migrate v12->v13: a second run changes nothing
- Migrate v12->v13: the touched day's in/out tallies are rebuilt from the rows; closes stay
- Migrate v12->v13: a day the rollup no longer holds is not recreated

### test_stats.lua (25)

- Stats: bySource / byQuality counts
- Stats: byDay buckets via date()
- Stats: byZone counts
- Stats: a missing or blank zone counts under one Unknown bucket
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
- Stats: the time buckets match a per-record date() across 10:00, 10:05 and local midnight
- Stats: legacy breakdowns count only gains of items and currency
- Stats: ledger gains, losses, net and transfers
- Stats: preLedgerRows counts rows older than ledgerSince
- Stats: a holder move is a loss and a gain under its own reason, per holder
- Stats: holder-move pairs stay out of the legacy loot breakdowns

### test_browser.lua (94)

- Browser.MinWidth is wide enough for both the columns and the toolbar
- Browser: Export reaches the bar's right edge at minimum width, never below its floor
- Browser.setToFilter turns a selection set into a filter value
- Browser.setToFilter maps an empty selection to nil (no filter at all)
- Browser.setToFilter copies rather than aliases the live selection
- Browser.asSet passes a stored set through, dropping the false entries
- Browser.asSet promotes the legacy scalar form to a one-entry set
- Browser.asSet maps the 'all' sentinel and nil to an empty set
- Browser.asSet round-trips through setToFilter for the stock (unfiltered) view
- Browser.withAll sorts by label and keeps the All sentinel first
- Browser.withAll on an empty dataset still offers the All sentinel
- Browser: source options are the distinct sources, human-labeled, All first
- Browser: type options skip the blank itemType
- Browser: subtype options skip the blank itemSubType
- Browser: zone options are keyed by name, so one zone lists once per name
- Browser: zones with no recorded name share one 'Unknown' bucket
- Browser: quality options run in quality order, not label order
- Browser: quality options carry the quality tint
- Browser: bound options follow the fixed binding order, not data order
- Browser: an unbound record surfaces as the NONE sentinel
- Browser: character options list each looter once, All then Current first
- Browser: character options carry the class color, and the icon folded into the label
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
- Browser.SaveView stores the tab's view; ClearFilters restores it; ResetView drops it for stock
- Browser: History offers Group: Type & SubType right after Type, and a saved view keeps it
- Browser: an empty multi-select reads as the All sentinel's own label
- Browser: a dropdown with no options at all still labels itself All
- Browser: one selected value reads as that option's label
- Browser: a selected value with no option row falls back to its raw value
- Browser: several selected values collapse to '<Prefix>: N selected'
- Browser: a colon-less All label is used whole as the count prefix
- Browser: an off-list selection still counts toward the summary
- Browser: an active preset option names the whole selection, beating the count
- Browser: a preset that reports itself inactive does not name the selection
- Browser.ResetWindow empties the persisted geometry carve-out
- browser: a burst of RecordAdded collapses to ONE OnHistoryChanged
- browser: HistoryChanged still repaints immediately
- browser: master scale MULTIPLIES the per-window scale, it does not replace it
- browser: an absent master scale/alpha falls back to the shipped 1.0, never to nil
- browser: Lock frame is what the drag handler asks, and it is addon-wide
- browser: General visibility answers all four modes against the combat state
- browser: Show refuses while the visibility setting forbids it, and says why
- browser: a combat transition re-applies visibility through the private event target
- browser: 'Only out of combat' hides the window at the pull, before lockdown engages
- browser: 'Only in combat' hides the window when combat ends
- browser: Lock frame gates the resize grip as well as the title-bar drag
- browser: the History window resizes down to B:MinWidth() x SKIN.minH
- browser: releasing the resize grip persists the window geometry
- browser: a resize refreshes the table once, on release, not per size step
- browser: a locked grip starts no sizing and its release saves nothing
- browser: the resize grip is the Blizzard chat size grabber
- browser: the History grip is Core.MakeResizable, not a hand-rolled copy
- Browser: tab registry orders History, Insights, then registered tabs
- Browser: a registered tab builds lazily and refreshes on select
- Browser: the stock view shows gains and losses, transfers per setting
- Browser: the default view floors items at the minimum-quality setting
- Browser: the Quality 'all' option names the floor
- Browser: group options offer Direction and Holder
- Browser: date options offer 90 days and 1 year after 30 days
- Browser: _filterHonored - no set honors everything, a set honors only its keys
- Browser: a tab grays the controls it does not honor, and History restores them
- Browser: the Holdings tab grays Date, Source, Bound and Zone, and keeps Group live
- Browser: a holders tab lists holders, with the warband as Warband
- Browser: a holder picked on Holdings stays on Holdings; History keeps its own Character scope
- Browser: SetViewField remembers a field with no Save, from a copy of the stock view
- Browser: CaptureView on the Timeline keeps its remembered pick
- Browser: DateRange reads the Date dropdown, all when there is none
- filter bar: every dropdown label is one non-wrapping line
- filter bar: Direction and Bound are the same width
- filter bar: each width covers the widest label that control can show
- filter bar: the window floor fits both rows at the built widths
- filter bar: a saved window narrower than the floor is widened on restore
- filter bar layout: at the base width r == 1 and row 2 ends at the bar's right edge
- filter bar layout: a wider window scales every control by the same ratio
- filter bar layout: row 1 sits on row 2's grid
- filter bar layout: a bar narrower than the base never shrinks a control
- filter bar: the built bar fills the bar width at the base width and 300px wider
- filter bar: resizing the window re-lays the bar out to its new width
- Browser: Character Current shows the character's half of a warband move, Warband the other

### test_browsertable.lua (80)

- BrowserTable: CellText renders each column
- BrowserTable: iLvl column shows level only when present
- BrowserTable: Bound column renders no text (icon-driven)
- BrowserTable: bound legend adds a line per state
- BrowserTable: each legend lock is tinted, and sits on its own line
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
- BrowserTable: MinFrameWidth accounts for the AH and Direction columns (>= 1314)
- BrowserTable: quality column is blank for a currency row
- BrowserTable: group keys are namespaced, so a zone can share a source's name
- BrowserTable: a missing zone/character/type groups under 'Unknown'
- BrowserTable: a blank zone string groups under 'Unknown' too, not a nameless group
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
- BrowserTable: an unrecognized source still shows something in the Source column
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
- BrowserTable: the shipped row height is still the literal it replaced
- BrowserTable: the clamp's bounds ARE the slider's bounds
- BrowserTable: the row height is clamped, because it comes from SavedVariables
- BrowserTable: a corrupt row height falls back to the shipped one, never to nil
- Test mode: ticking the box enters test mode and opens the History window
- Test mode: unticking the box leaves it and never opens a closed window
- Test mode: /lh test and the box drive the same switch and stay in step
- Test mode: combat ends it with one line, unticks the box and opens nothing
- Test mode: a refused start prints one line and leaves the box unticked
- Test mode: a start in combat is refused from the player's combat flag, not the lockdown
- Test mode: Reset all settings and /lh resetall both end it
- BrowserTable: a Direction column follows Time, labeled and wide enough for glyph + Transfer
- BrowserTable: the Direction cell paints glyph, label and color for IN/OUT/MOVE/legacy
- BrowserTable: re-binding a pooled row from MOVE to IN leaves no stale glyph or color
- BrowserTable: a non-direction cell never shows the glyph FontString
- BrowserTable: the Qty column shows signed quantities
- BrowserTable: the Qty column is measured wide enough for the widest signed gold amount
- BrowserTable: a gold row hovers a BankLedger-style Gold tooltip; an item row its own
- BrowserTable: test-mode rows hover a sample tooltip; linked and live rows are unchanged
- BrowserTable: group by Direction and by Holder
- BrowserTable: group by Type & SubType orders by type, then subtype, alphabetically
- BrowserTable: Type & SubType with no subtype reads 'Type: Armor' and leads its type
- BrowserTable: Type & SubType reads a currency row as 'Currency · <category>'
- BrowserTable: Type & SubType keys never collide with plain Type groups
- History row menu: Show in Timeline opens the Timeline on that row's thing
- History row menu: Show in Timeline is disabled for a row that names no thing
- History row menu: the existing four entries keep their order around the new one
- BrowserTable: the Character column shows the row's holder

### test_export.lua (32)

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
- Export: InsightsCSV bound labels match the row CSV's E:BoundLabel
- Export: InsightsCSV names the per-currency breakdown Currency by Type x Source (no By-Source section)
- Export: the copy window comes from LibKa0s-Widgets-1.0
- Export: showing the copy window puts the text in it
- Export: the copy window is built once and reused
- Export: InsightsCSV over items and currency matches the golden document
- Export: InsightsCSV over zero-value items with no currency matches the golden document
- Export: InsightsCSV over an empty history, a bare table and nil
- Export: CSV ledger columns follow wowheadLink and default for legacy rows
- Export: InsightsCSV appends Ledger sections only when the range has losses
- Export: InsightsCSV writes a negative copper value with a leading minus

### test_debuglog.lua (20)

- FONT_MONO constant is a JetBrains Mono TTF path
- the degraded DebugLog stub's formatters carry no library format string
- the degraded DebugLog stub's RunDiagnostics prints the placeholder, writes nothing, returns 0
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
- the console's title bar is three icon controls, which is the folder name arriving
- the DebugLog descriptor passes addonName beside name, not instead of it
- the copy window's buffer text is the whole buffer, in order
- InitSummary reports name, version, schema, active profile, and record count

### test_launcher.lua (22)

- launcher: the 128 logo ships, and it is the uncompressed 32-bit file the client can load
- launcher: the TOC's IconTexture and the LDB object's icon are the SAME file
- launcher: with no LibDataBroker / LibDBIcon nothing raises, and the store is still the truth
- launcher: Register's state lines go to the console's at-enable queue, not the gated sink
- launcher: ONE object, registered twice, under the addon's FOLDER name — and idempotent
- launcher: the stored minimap table is the declared default, unseeded and unreplaced
- launcher: left-click opens the settings panel, enabled or disabled, and does nothing else
- launcher: right-click with no client menu API degrades to the settings panel
- launcher: right-click opens the options menu — the brand title, then the four entries in order
- launcher: each menu entry toggles through the addon's own handler, once
- launcher: while disabled, Enabled stays live and the other three are grayed and call nothing
- launcher: the Minimap button row moves the real button, through the single write seam
- launcher: Reset all settings leaves LibDBIcon's global table alone, so nothing needs re-pointing
- launcher: the broker label is the BRAND NAME in plain text, not the folder name
- launcher: no BULK reset moves the minimap button — /lh resetall and the page Defaults button
- launcher: Reset all settings leaves a hidden button hidden, and the history untouched
- launcher: RESET_EXEMPT maps the row path to the stored path, and the reset honors it
- launcher: Reset all settings leaves a SHOWN button shown, and does not invent a second key
- launcher: the enabled tooltip is the library's block, with the addon's one line inside it
- launcher: Locked and Test mode are read on every show, never cached
- launcher: while disabled the tooltip still shows, says Enabled: No, and keeps the same hints
- launcher: the descriptor answers the library's questions, and every toggle is the addon's own

### test_slash.lua (63)

- FormatSchemaValue renders booleans as true/false
- FormatSchemaValue applies a row's fmt to numbers (scale → 1.00x)
- FormatSchemaValue leaves plain (enum) numbers raw
- FormatSchemaValue renders an empty table setting as (none)
- FormatSchemaValue renders a table setting as a sorted key set
- FormatSchemaValue omits falsy keys from a table setting
- FormatKV colors the key gold and the value white with a default separator
- list header is the green 'Available settings' line, no trailing colon
- list emits azure [group] headers in the declared order
- list value rows use FormatKV under their group, four-space indented
- list renders windowScale with its scale fmt
- CliList prints the header through NS.Print, cyan-tagged
- /lh get echoes a single FormatKV line for a known path
- /lh get with no argument prints a Usage line
- /lh get on an unknown path prints Setting not found
- /lh set echoes the stored value read back after writing
- /lh set a value the row's validate refuses prints INVALID and leaves the value alone
- /lh set on an unknown path prints Setting not found
- /lh get minimap.shown reads the row's SHOWN sense; the old minimap.hide path is unknown
- /lh on a legacy store: hide = true reads minimap.shown false, and a set invents no `shown` key
- /lh version prints the cyan-tagged v<version> line
- NS.COMMANDS registers a version verb
- /lh reset on a table setting echoes (none), not a raw table pointer
- /lh resetall is the profile reset: every setting, list, view and window back, history kept
- /lh resetall logs ONE [Set] reset profile line, N the stored rows off their default
- /lh resetall on settings already at their defaults logs (0 rows)
- a bracket opened around resetall logs only the profile reset's line
- a nested bracket where any level reset the profile logs no bulk line
- /lh reset <path> is still ONE [Set] <path> = <value> line, and not muted
- /lh resetall typed at the dispatcher logs ONE [Set] reset profile line
- a profile reset that raises logs ONE line marked as stopped, re-raises, and unmutes
- the host seam clears its mute when a bracketed row raises
- an unpaired BulkEnd at depth 0 logs nothing
- Reset all settings confirms first, in the profile wording, and runs the one reset act
- Reset all settings resets the ACTIVE profile only, and publishes the profile message
- Reset all settings discards no history and logs no [Data] line
- Reset all settings copies the declared defaults, so a later write cannot change them
- NS.PREFIX is the mandated cyan [LH] tag
- every Slash string this addon renders resolves to prose, not to a key
- the help header names /loothistory as the alias for /lh
- LandingRows and HelpRows are the same rows, differing only by the chat indent
- a command row is gold command, single-spaced em dash, white description
- reset is path-scoped and resetall is the global verb (no page-shaped form)
- set refuses a value outside a numeric enum instead of storing it
- set on the composed key-map enum accepts a mode and refuses anything else
- set clamps a number to its slider range and echoes what was stored
- set refuses a bool it cannot read rather than silently storing false
- the set-valued row renders through the format hook, never as <secret>
- OnSlash dispatches a host verb and lower-cases only the verb
- an unknown verb says so and then prints the help index
- bare /lh runs the config verb with an empty argument and prints no help
- whitespace-only /lh is bare too and runs the config verb
- the config verb opens the settings panel on its landing page
- /lh help prints the command index and does not run the config verb
- /lh enable and /lh disable write the Enable row's path, and hold no state of their own
- /lh enable is the same write as /lh set settings.enabled true, and answers the same line
- the dispatcher answers while the addon is disabled, so the pair is never one-way
- a disabled addon refuses each FEATURE verb on ONE line naming /lh enable, and does not act
- the same feature verbs act normally once the addon is enabled — the gate is not always-on
- the refusal is never turned on a verb slash-commands-§2 keeps live, /lh enable above all
- /lh debug events prints the rejected event names, or none
- Clear-blacklist confirm and /lh test print their exact lines through the printer
- /lh holdings <query> prints the matching name and its account-wide total

### test_slash_degraded.lua (15)

- library-less install: the Slash under test is the degraded stub
- library-less install: the stub's DISABLED_LINE_FORMAT is the library's, byte for byte
- library-less install: the refusal line names /lh enable, as the library's does
- library-less install: the degraded help omits config, which would only decline
- library-less install: the degraded help lists enable, disable and resetall, which work
- library-less install: /lh disable stores false, stands the addon down, and acks once
- library-less install: /lh enable reverses /lh disable
- library-less install: set on any other path, or a non-bool value, stays unavailable
- library-less install: resetall resets the whole profile and says so on one line
- library-less install: resetall is the same act through the verb table
- library-less install: both report forms answer with the library-absent line and nothing else
- library-less install: the degraded help does not offer /lh diagnostics
- library-less install: /lh profile answers with the library-absent line and switches nothing
- library-less install: the degraded help does not offer /lh profile
- library-less install: NS.Perf is the degradation stub and /lh perf answers

### test_resetprompt.lua (7)

- Reset prompt: offered only for an upgraded (armed), non-empty, undecided DB
- Reset prompt: an Esc on the upgrade login is asked again on the NEXT session
- Reset prompt: dialogs are registered with three choices
- Reset prompt: Keep stores the choice; Esc leaves it undecided
- Reset prompt: confirmed reset purges history and keeps holdings
- Reset prompt: in combat the offer waits for PLAYER_REGEN_ENABLED and stand-down drops it
- Reset prompt: closing the export window after "Export first" asks again, once

### test_schema.lua (69)

- Schema: debugConsole row is session-only, on the Master controls tab
- Schema: Master controls is the FIRST group on the General page
- Schema: the Master controls tab holds exactly the canonical rows, in canonical order
- Schema: every canonical row is declared ONCE — nothing was copied here, it was moved
- Schema: the fourth line is [Minimap button] [Test mode], composed and in that order
- Schema: Test mode is never written to the store, and ships no stored default
- Schema: General visibility is a four-value dropdown, not a boolean
- Schema: a profile written before this release gets visibility from the shipped defaults
- Schema: setting debugConsole toggles the window, never writes the store
- Schema: getting debugConsole reflects the window visibility
- Schema: a normal (persisted) row writes the active profile
- Schema: auction rows exist with the AH Price group and defaults
- Schema: auction capture is a MultiCheck row; Rev-1 provider/priority rows are gone
- Schema: recordCurrency row exists, defaults true, settable
- Constants: CURRENCY_TYPE is "Currency"
- Schema: every row is uniquely pathed and fully described
- Schema: every row's default matches its declared type
- Schema: FindRow resolves a known path and rejects an unknown one
- Schema: every persisted path resolves against the shipped defaults
- Schema: Register reports a typo'd path even when the row declares a default
- Schema: Register counts no missing path for the Minimap button row, which owns its storage
- Schema: the shipped default equals the schema's declared default
- Schema: the AH priority cascade is declared once, in core/Constants.lua
- Schema: every dropdown row offers values, and its default is one of them
- Schema: a key-map enum declares an explicit sorting, so its order is not pairs() order
- Schema: every MultiCheck row offers values
- Schema: the slider default sits inside its own bounds
- Schema: only the session-only rows carry their own get/set
- Schema: the Minimap button row's accessors invert onto LibDBIcon's own `hide` key
- Schema.Set refuses an unknown path and reports why
- Schema.Set stores a deep copy, never a reference to the caller's table
- Schema.Default hands out a copy of a table default, not the shared one
- Schema.Default returns nil for an unknown path
- Schema.Set runs the row's onChange with the new value
- Schema.Set honors a row's validate guard and leaves the DB untouched
- Schema.Get on an unknown path reads through rather than erroring
- Schema: every setting round-trips through Set then Get
- Schema: every declared command is uniquely named and dispatchable
- Schema: the reserved verbs are all present
- Schema: every page's tabs are the designed ones, in order, at the designed size
- Schema: a group's rows are contiguous, so no tab is drawn twice
- Schema: no tab holds fewer than two controls
- Schema: a tab name never repeats the page it sits on
- Schema: every row carries a group, so no page can render strip-less
- Schema: no color row exists, so the class-color companion rule has nothing to bind to
- Schema: every slider declares a step it can actually be dragged to
- Schema: every doc that counts the rows counts the same number the schema ships
- Schema: the docs' per-tab breakdown is the schema's own partition
- seam: Set answers true, or false and a reason, in the host's own words
- seam: one write logs its [Set] line, then runs onChange, once each
- seam: on the degraded build a write lands, is copied, reacts, and an unknown path is refused
- seam: on the degraded build the runtime readers read the store
- seam: on the degraded build the composed Master controls rows are absent, and refused
- seam: on the degraded build ApplyDefault restores, and spares an exempt row only in a sweep
- seam: on the degraded build the reset resets the profile and keeps the hidden minimap button
- seam: on the degraded build the boot check passes
- seam: on the degraded build the boot check skips a row that owns its storage
- seam: the live runtime is the library's, and the host names reach it
- seam: a write with no store yet is refused, not raised
- seam: a bracket counts a closure row's READ-BACK, so a write that did not move counts 0
- seam: Register reports a duplicate path and a row with no group
- seam: on the degraded build the boot check still reports a typo'd path, in its own words
- Retention: a shorter value raises the prune confirm and deletes nothing yet
- Retention: accepting the prune confirm deletes the older records
- Retention: declining restores the confirmed value, keeps every record, prints one line
- Retention: accepting applies the agreed value even when the store has moved
- Retention: re-showing the confirm over an open one does not run the decline
- Retention: with no StaticPopup_Show a shorter value prunes at once
- Retention: a value that would delete nothing raises no confirm and prunes nothing

### test_schema_stub.lua (9)

- Schema stub: SetMany refuses a batch holding an invalid entry and stores nothing
- Schema stub: SetMany refuses an unknown path by its index
- Schema stub: SetMany stores every entry, then runs every onChange in order
- Schema stub: SetMany with opts.act runs its stores and reactions inside one bracket
- Schema stub: a writeThrough path with no row stores through Set
- Schema stub: a writeThrough path refuses when there is nowhere to store it
- Schema stub: a row-less path NOT in writeThrough is still refused
- Schema stub: SetMany takes a writeThrough entry, and stores nothing when a sibling refuses
- Schema live: settings.enabled still takes its composed row, not the writeThrough path

### test_analytics.lua (69)

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
- Analytics pool: a released object is reused rather than rebuilt
- Analytics pool: releaseAll returns every active object to the free list
- Analytics pool: acquire shows what it hands back
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
- Analytics._buildCharStackRows: labels are shortened and class-colored
- Analytics._buildCharStackRows: the busiest character's bar is full width
- Analytics._buildCharStackRows: every row is scaled against that same maximum
- Analytics._buildCharStackRows: each segment's tip states the category and its value
- Analytics._buildCharStackRows: the row value is the character's total
- Analytics._buildCharStackRows: an unknown class falls back to neutral gray
- Analytics._buildCharStackRows: an empty matrix yields no rows
- Analytics._buildCharStackRows: segments are computed once per character
- Analytics._paletteMap: colors are assigned by list position
- Analytics._paletteMap: a key outside the list has no color
- Analytics._paletteMap: an empty or missing list maps nothing
- Analytics._paletteMap: the same ordering yields the same colors across charts
- Analytics.paletteColor: every entry is a valid rgb triple
- Analytics._shortChar: drops the realm from a Name-Realm key
- Analytics._shortChar: a missing character reads '?'
- Analytics._classColor: a known class returns its class color
- Analytics._classColor: an unknown or missing class falls back to neutral gray
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
- Analytics._shortDay: an unrecognized key passes through untouched
- Analytics._sortedByCount: orders by count descending
- Analytics._sortedByCount: equal counts break the tie by key ascending
- Analytics._sortedByCount: an empty map yields no rows
- Analytics._sortedByCount: numeric keys sort without a type error
- Analytics._truncate: reports whether it cut
- Analytics._truncate: a nil label becomes an empty string
- Analytics._truncate: the cut keeps maxChars-1 glyphs plus the ellipsis
- Analytics: every pool goes through the LibKa0s seam
- Analytics: the TOC loads Format, then Analytics, then Charts
- Analytics: the module's function surface is exactly the published one
- Insights ledger: the caveat shows only for kept history with pre-ledger rows
- Insights ledger: back-to-back rows share one peak and sort by total
- Insights ledger: HasLedger is false for gains-only ranges
- Insights ledger: every ledger reason has its own chart color
- Insights ledger: the by-character chart names a holder, the Warband as Warband

### test_analytics_layout.lua (9)

- Insights layout: the fixtures exercise the branches they are meant to
- Insights layout: a full pass over items and currency matches the golden snapshot
- Insights layout: a second pass re-acquires the same widgets and draws the same thing
- Insights layout: items with no value and no currency, over a trimmed day range
- Insights layout: an empty range hides every chart and shows the empty text
- Insights layout: a nil stats table takes the empty branch too
- Insights layout: a range with losses draws the gains-vs-losses section first
- Insights layout: losses only — no empty text, no LOOT divider
- Insights layout: nothing it draws stays visible once its pane is hidden (LED-9)

### test_holdingstab.lua (33)

- HoldingsTab: model lists things collapsed by default
- HoldingsTab: expanding a thing adds one line per holder
- HoldingsTab: character filter narrows holders
- HoldingsTab: container and age formatting
- HoldingsTab: tab is registered after History and Insights
- HoldingsTab: attach builds rows and recycles them on refresh
- HoldingsTab: HOLDINGS_CHANGED does not rebuild the pane once the window is closed
- Holdings row actions: a thing line offers Show in Timeline
- Holdings row actions: Forget is offered for an alt, never for the warband or the logged-in character
- Holdings row actions: Forget is disabled in test mode, even for an alt
- Forget this character: drops holdings and rollup cells, keeps history rows, announces once
- Forget this character: a holder with nothing stored is a no-op and announces nothing
- Forget this character: refuses the logged-in character and the warband
- Forget popup: registered, and its accept forgets the holder it carries
- HoldingsTab: an item line carries iLvl, quality label, type, subtype and the AH unit price
- HoldingsTab: a non-gear item has no iLvl
- HoldingsTab: a currency line reads Currency / its category, with no iLvl or AH price
- HoldingsTab: the gold line reads Gold with no subtype, quality, iLvl or AH price
- HoldingsTab: stripes alternate per thing and an expanded thing's holders keep its stripe
- HoldingsTab: header sorts by every column and a second click flips the direction
- HoldingsTab: columns hide right to left as the pane narrows; Name, Total and Value stay
- HoldingsTab: hovering a thing shows the right tooltip for an item, a currency and gold
- HoldingsTab: the pane's rows hover and leave through the tooltip; the header holds exactly the column labels
- HoldingsTab: with no GameTooltip the tooltip shims draw nothing and do not raise
- HoldingsTab group: Quality headers by rank (highest first), N = things in the group
- HoldingsTab group: Type and SubType headers are alphabetical
- HoldingsTab group: Type & SubType reads 'Type: <Type> · <SubType>', a currency its category, gold bare
- HoldingsTab group: Character lists a thing under every holder with that holder's count, Warband last
- HoldingsTab group: under Character an expanded thing lists only that holder's containers
- HoldingsTab group: a collapsed group keeps its header and count and hides its members
- HoldingsTab group: stripes run per thing across groups; headers carry none; holders keep the parent's
- HoldingsTab group: an unsupported mode reads as None and leaves History's group alone
- HoldingsTab group: the Group dropdown is live on Holdings, offers only its modes, and keeps History's pick

### test_timeline.lua (32)

- Timeline model: NextDay and DayStart walk local calendar days
- Timeline model: DailySeries carries the last close forward
- Timeline model: DailySeries starts at genesis and picks up each day's close
- Timeline model: a flow-only cell does not break the carry
- Timeline model: ValueAt and TotalSeries treat a not-yet-started holder as 0
- Timeline model: TotalSeries keeps an intraday step vertical
- Timeline model: RankHolders applies the Character filter before the cap
- Timeline model: Build draws Total plus at most maxLines holders, richest first
- Timeline model: a holder with nothing now but a balance in range is still a candidate
- Timeline model: ledgerSince inside the range is a dashed marker; outside it is not
- Timeline model: a partial holder is dashed from genesis until its bank was first seen
- Timeline model: Flows sum the shown holders' gains and losses per day
- Timeline model: gold reaches the chart in gold units and stays copper in the model
- Timeline model: IntradaySeries rebuilds steps from rows, newest backwards from now
- Timeline model: IntradaySeries gives up when the rows disagree with the rollup
- Timeline model: a MOVE row moves the holder's own balance by its side
- Timeline model: intraday only for Today / 7d, inside retention, after the ledger began
- Timeline model: HoverLines reads each line's value and that day's flows
- Timeline model: Suggest puts Gold first, then the biggest totals, capped
- Timeline model: Visible drops the hidden series and ignores keys it does not draw
- Timeline model: YRange spans only the series it is handed
- Timeline model: ChartData draws only the visible lines and scales y over them
- Timeline model: HoverLines lists only the visible lines, flows unchanged
- Timeline model: FlowLines titles the day as the Total's and signs Gained / Lost / Net
- Timeline model: FlowLines counts a currency, shows a zero side as 0 and a negative net red
- Timeline model: FlowLines answers nil for a day with no flow
- Timeline model: FormatCount groups thousands, FormatHolding reads gold as coins
- Timeline model: LegendTip colors the title by holder kind and reads the current holding
- Timeline model: LegendTip's Total sums only the charted holders and says so
- Timeline model: LegendTip counts currencies and items with separators, and a holder with none reads 0
- Timeline model: LegendTip reads the test-mode store when it is on
- Timeline model: LegendLayout keeps the Total's slot and one gap between the rest, wrapping rows

### test_timelinetab.lua (35)

- Timeline tab: registered between Insights and Holdings
- Timeline tab: Total plus one line per holder; the Character filter narrows it
- Timeline tab: refresh twice recycles Lines and pooled rows
- Timeline tab: maxLines caps the holders drawn
- Timeline tab: typing in Search offers matching things, Gold first
- Timeline tab: the pick is remembered in the saved view
- Timeline tab: grays every filter but Search, Date and Character
- Timeline tab: a hover with no model or index hides the tooltip and does not raise
- Schema: timelineMaxLines is a 2-16 slider under Interface, default 8
- Timeline tab: a live repaint drops a hover left up, so the next tick re-hovers on the new data
- Timeline tab: nothing it draws stays visible over History or Holdings (LED-9)
- Timeline tab: one legend button per series, Total first, reused across rebuilds
- Timeline tab: a legend click hides the line, dims its entry and a second click restores it
- Timeline tab: Total only hides every holder; off restores the set shown before
- Timeline tab: hiding every holder by hand reads as Total only, and showing one clears it
- Timeline tab: every line hidden shows the empty state, not an axis
- Timeline tab: the hidden set survives a change of thing and range, and ignores absent holders
- Timeline tab: Total only is remembered in the saved view, the per-line set is not
- Timeline tab: the hover tooltip lists only the visible lines
- Timeline tab: hovering a day's strip column shows its Gained / Lost / Net, and OnLeave hides it
- Timeline tab: the strip tooltip stays the Total's with lines hidden
- Timeline tab: a day with no flow has no strip hit region; regions are pooled across redraws
- Timeline tab: a repaint under a strip tooltip re-shows it, and one whose day went hides it
- Timeline tab: the chart's hover ending does not hide the strip's tooltip
- Timeline tab: smoother lines -- 6 px per point reaches the chart and the lines are 2 px (Total 2.5)
- Timeline tab: the wider point spacing thins a 120-day series to fewer points
- Timeline tab: a legend entry's tooltip is the holder's color, its holding and the hint
- Timeline tab: the Warband's legend tooltip wears the Warband's series color
- Timeline tab: a legend click under a resting cursor re-shows the entry's tooltip
- Timeline tab: a repaint that rebinds the hovered legend entry re-shows the new holder's tooltip
- Timeline tab: a repaint that leaves the hovered legend entry unbound hides its tooltip
- Timeline tab: a repaint nobody hovers leaves the tooltip alone
- Timeline tab: legend entries sit one even gap apart, the Total keeping its slot
- Timeline tab: the Warband's legend entry takes the same gap as a character's
- Timeline tab: a legend too wide for the pane wraps to a second row and the body makes room

### test_autocomplete.lua (14)

- Autocomplete: the seam answers a library handle on a real box, nil without one
- Autocomplete: typing in Search opens the list directly under the box, as wide as it
- Autocomplete: switching tabs closes the list
- Autocomplete: History offers distinct item and currency names, prefix matches first, no Gold
- Autocomplete: History rows carry their quality's color
- Autocomplete: History's names follow the other filters, with the typed text set aside
- Autocomplete: History reads the test-mode sample, not the live history
- Autocomplete: a History pick puts exactly that name in Search and applies it
- Autocomplete: Insights offers the same names and picks the same way
- Autocomplete: Holdings offers what Holdings search finds, Gold included, and picks the name
- Autocomplete: Timeline offers things, Gold first when it matches
- Autocomplete: a Timeline pick charts the thing and keeps its name in Search
- Autocomplete: the Timeline's own picker list is gone
- Autocomplete: a tab with no suggest, or with Search grayed, offers nothing

### test_testdata.lua (10)

- TestData: the sample holdings and daily stores build deterministically
- TestData: a day's close is its flows applied to the day before
- Test mode: Holdings and Timeline show the sample, and the real stores come back after
- Test mode: ledger writes go to the real stores, never the sample
- TestData: the History sample writes holder moves as a loss and a gain
- TestData: the sample rollup books a holder move's loss and gain on each holder
- TestData: the default Timeline thing is Everlight Crystal, nil without a sample
- Test mode: the Timeline opens on the default sample item with lines drawn, saved view untouched
- Test mode: a pick made in test mode survives refreshes and never reaches the saved view
- Test mode: a pick of a thing the sample lacks falls back to the default

### test_views.lua (16)

- Views: Save on each tab writes only that tab's slot
- Views: Clear on one tab applies its saved view, touching no other tab and no slot
- Views: Reset deletes only the active tab's slot and applies its stock view
- Views: a tab with no saved view clears and resets to its own stock view
- Views: Holdings Save, Reset and Clear take effect on the Holdings view
- Views: a view from another tab applies to Holdings as None, sorted by Name
- Views: switching tabs back and forth restores each tab's own live state exactly
- Views: Insights reads its own filter, even while another tab is on the bar
- Views: a tab never shown opens on its saved view, scoped to the current player
- Views: a profile adopt forgets every tab's parked state
- Views: test mode never writes a saved view
- Views: Clear on the Timeline keeps the remembered thing
- Views: Reset on the Timeline turns Total only off at once; the charted thing lasts the session
- Migrate v13->v14: a profile's saved view becomes four identical per-tab views, the old key goes
- Migrate v13->v14: a second run changes nothing
- Migrate v13->v14: a corrupt (non-table) saved view is dropped, and no slot is made of it

### test_panel.lua (43)

- Panel: the parent category and its ONE sub-page are registered
- Panel: registration is idempotent
- Panel: the sub-page carries the addon's name for the Blizzard left tree
- Panel: the General page draws the whole strip, in order, opening on Master controls
- Panel: every schema group on the page has a tab, and every tab a body
- Panel: the Master controls tab holds the canonical rows and the closing button pair
- Panel: Reset position drives the window carve-out, Reset all settings the §12 popup
- Panel: the Capture tab holds the capture rules and nothing else
- Panel: the Interface tab holds the two size sliders, and the minimap toggle is gone
- Panel: the History tab holds retention, the storage readout and the purge
- Panel: a burst of RecordAdded collapses to ONE StorageStats pass
- Panel: HistoryChanged still repaints the readout immediately
- Panel: a checkbox row draws a CheckBox, a dropdown row a Dropdown, a slider row a Slider
- Panel: a key-map dropdown is populated in its declared sorting, not in pairs() order
- Panel: a dropdown is populated from the row's values, in declared order
- Panel: a slider is given the row's own min, max and step
- Panel: a tabbed page draws no SECTION heading, but a mixed tab draws its SUBSECTIONS
- Panel: a subgroup heading never repeats its own tab's name (options-ui-§7)
- Panel: clicking a checkbox writes through NS.Schema:Set
- Panel: the Test mode checkbox starts test mode, and a refused start redraws it unticked
- Panel: choosing a dropdown entry writes the stored value
- Panel: releasing a slider writes the stored value
- Panel: an external write is mirrored back by Refresh
- Panel: the muted-source picker is INVERTED — a ticked box means 'record this source'
- Panel: the Defaults button is built on first OnShow, not at registration
- Panel: the General Defaults click restores every schema default
- Panel: the General Defaults click is PAGE-wide — it reaches the id-lists and the cascade
- Panel: the General Defaults click does NOT move the window
- Panel: the General Defaults click logs ONE [Set] reset profile line and no per-row [Set]
- Panel: the AH Price tab draws one reusable row slot per known price source
- Panel: the pooled slots survive the tab strip — a second visit re-allocates nothing
- Panel: the price host is parked off the page while another tab is on screen
- Panel: the AH Price tab renders its own schema row and no other tab's
- Panel: the cascade is a reorder list — a handle per draggable row, a box under every row
- Panel: the host draws no row chrome of its own — the library owns the box and the handle
- Panel: a drag is one splice to index, and it repaints
- Panel: the reorder controller is canceled at the TOP of the page render
- Panel: toggling a source's Enabled box writes the capture set and repaints
- Panel: the landing page renders one label per slash command, through the ONE row formatter
- Panel: the landing page shows the tagline
- Panel: Open refuses during combat and never defers-and-replays
- Panel: a WRAPPED strip reserves the same band and the same row offsets on every tab
- Panel: the AH status colors are saturated, not muted

### test_panel_filters.lua (20)

- Panel: the Filters tab draws a SECONDARY strip and renders only the selected list
- Panel: the Filters tab lists the ids on each list and can remove one
- Panel: a blacklist change while the page is hidden repaints it on the next OnShow
- Panel: every filter list packs two entries to a line
- Panel: Filters: an item list adds by id, through AddBlacklist, and keeps the [id] = true shape
- Panel: Filters: an item list adds by a shift-clicked link, and the add still moves it off the other list
- Panel: Filters: an item list adds by name, ignoring case, and names the entry
- Panel: Filters: an unknown name adds nothing, keeps the text and says why
- Panel: Filters: the Currencies list takes an id or a currency link, and refuses a name it cannot know
- Panel: Filters: each entry's X calls that list's own Filters writer, and an emptied list reads (none)
- Panel: Filters: one add redraws the page once, not twice
- Panel: Filters: an item the client has not cached is named once its load lands
- Panel: Filters: typing lists matching items from the loot history and from the lists
- Panel: Filters: a name the game cannot look up resolves through the loot history
- Panel: Filters: picking a suggestion adds that rank through the Filters writer, once
- Panel: Filters: a name several ranks share lists every rank, and Enter without a pick adds none
- Panel: Filters: a name two ranks in the bags share, with none in the history, adds none on Enter
- Panel: Filters: currency names resolve through the loot history, and a refusal says where names work
- Panel: Filters: the candidates are the lists, then the loot history newest first, each id once
- Panel: Filters: each add box's tooltip ends with the hint its refusal ends with

### test_panel_auction.lua (3)

- AH table: two providers present, some sources collecting, one captured but absent
- AH table: every provider present and nothing captured
- AH table: no provider present

### test_profiles.lua (31)

- Migrate v8->v9: every stored setting lands in the Default profile and leaves global
- Migrate v8->v9: recorded data and the minimap table stay account-wide, untouched
- Migrate v8->v9: over a profile AceDB already filled, a stored value wins and an unstored key keeps its default
- Migrate v8->v9: a second run is a no-op
- Migrate v9->v10: a retention stored in the profiles moves to global and leaves every profile
- Migrate v9->v10: keep Always (0) wins over any day count
- Migrate v9->v10: a retention still under global.settings is lifted too, and the empty table goes
- Migrate v9->v10: a second run is a no-op, and a file with no stored retention keeps its own
- Profiles: every read and write resolves against the ACTIVE profile
- Profiles: the loot history is shared by every profile
- Profiles: a switch re-applies every setting through the one adopt path
- Profiles: a switch, a copy and a reset each refresh every open settings panel once
- Profiles: a switch to a profile where the addon is off stands it down, and back brings it up
- Profiles: each profile event logs exactly one line, worded by the event
- profile verb: a COMMANDS row after resetall, and the whole verb order pinned
- profile verb: help prints the header and one row per verb, profile among them
- profile verb: bare /lh profile lists every profile, sorted, current marked, then the hint
- profile verb: /lh profile <name> switches, and the adopt path logs the one switch line
- profile verb: the current profile answers 'Already on', and switches nothing
- profile verb: an unknown name is refused with a did-you-mean and the list, and nothing is created
- profile verb: surrounding quotes are stripped, and inner spaces and case are kept
- profile verb: in combat the switch is refused, and the list still answers
- Profiles: retention reads and writes global, and a switch never changes it
- Profiles: the login prune reads the account-wide retention, never a profile's
- Profiles: a switch, a copy and a reset leave the loot history untouched and never prune
- Profiles page: the global reset's veto keeps only the session-only rows, never the Profiles page
- Profiles page: without AceDBOptions the page opts out, and nothing is registered
- Profiles page: AceDBOptions' table over this db, drawn by AceConfigDialog into a Profiles canvas
- Migrate v11->v12: an explicit showTransfers = false is dropped from every profile
- Migrate v11->v12: a false set after the step stays false; a re-run changes nothing
- Defaults: Show transfers is on for a new profile

### test_harness.lua (7)

- Harness: the runner fed the loader exactly the TOC's files, in the TOC's order
- Harness: every path the runner derived from the TOC exists on disk
- Harness: no libs/ path leaked into the TOC-derived list
- Harness: the suite list matches tests/test_*.lua in both directions
- Harness: the runner's suite list has no duplicates
- Harness: the runner's lifecycle kick is exactly what addon:OnInitialize calls, in order
- Harness: NS.bus is the NewAddon object and carries the message half and the listed mixins

### test_libka0s.lua (31)

- NS.LIBKA0S_MISSING is the shared cause clause, verbatim
- the cause clause is published on the HEALTHY path too, not only when the lib is absent
- degraded install: every addon file loads with LibKa0s absent, with no error
- degraded install: the Core stub still prints a tagged, secret-safe line
- degraded install: the notice explains the absence through the shared cause clause, once
- degraded install: the Core stub answers every member the addon calls
- NS.MakeCloseButton hands the library this addon's FOLDER name as the third argument
- every window this addon owns closes through that one wrapper
- degraded install: NS.MakeLineChart answers nil rather than a dead frame
- degraded install: NS.MakeResizable keeps today's grip, the floor, the lock and the save
- degraded install: a bare /lh prints help listing the verbs that still work
- degraded install: bare /lh skips the config verb, which cannot answer here, for help
- degraded install: /lh help prints the same degraded help list
- the L-trap matcher flags the value, not one spelling (all three forms)
- no descriptor in this addon is handed NS.L
- tripwire — LibKa0s-Core-1.0 ships no STRINGS table
- tripwire — Core.lua's source names neither STRINGS nor a descriptor L
- tripwire — Options.lua reads no descriptor L
- no rendered LibKa0s string in this addon is an unresolved SCREAMING_SNAKE key
- every file of LibKa0s.xml is vendored and loads
- the vendored copy carries the library's MIT license
- the nine adopted majors all resolved, and the seams are wired to them
- every seam file resolves its major with the silent flag
- the Options page registry built every page this addon declares
- the Options descriptor passes addonName, the FOLDER name, to the library
- the vendored info art the help mark points at is on disk
- degraded install: NS.Format with a secret in a %d slot prints a line and raises nothing
- degraded install: the SafeRegister stubs isolate a refused name and record it once
- v1.69.0: the line chart is vendored and attached to the Widgets major
- v1.70.0: the autocomplete is vendored; the line chart takes pxPerPoint
- v1.71.0: the vendored minors and the kit revision match the release

### test_surface_parity.lua (14)

- parity: the Core seam publishes the same NS members on both paths
- parity: the Widgets seam publishes the same NS members on both paths
- parity: the Slash stub carries the whole live surface
- parity: the DebugLog stub carries the whole live surface
- parity: the Options stub carries the whole live surface
- parity: the Bus stub carries the live surface this addon calls
- parity: the Compat seam carries every LibKa0s-Compat-1.0 member it wires
- parity: the Schema stub instance carries every member of the live runtime
- parity: the Schema stub library carries the major's lib-level surface
- parity: the Item stub carries the whole LibKa0s-Item-1.0 surface
- parity: the Pool stub carries the LibKa0s-Pool-1.0 surface this addon calls
- parity: the Lifecycle stand-in carries every member of the live latch
- parity: the Env seam publishes the same NS members on both paths
- parity: the Media seam publishes the same NS members on both paths

### test_disabled.lua (17)

- slash-commands-§7 step 1: enabled, the addon registers a NON-EMPTY set and draws
- slash-commands-§7 step 3: disabling UNREGISTERS every event, unit-event and message the addon owns
- slash-commands-§7 step 3: a row written while stood down tallies NO daily rollup cell
- slash-commands-§7 step 3: a held ledger-reset offer is dropped by NS.StandDown, never shown after
- slash-commands-§7 step 3: an "Export first" re-ask does not pop the reset prompt during NS.StandDown
- slash-commands-§7 step 4: every deferral the addon armed is CANCELED, not left to find a flag
- slash-commands-§7 step 5: the window goes down, and the SHOW LADDER is what keeps it down
- slash-commands-§7 step 6: firing every event it used to watch writes nothing, prints nothing, draws nothing
- slash-commands-§7 step 7: every RESERVED verb and /lh profile still answer, and the bare /lh opens the panel
- slash-commands-§7 step 7: /lh profile switches while disabled, and a profile where the addon is on brings it up
- slash-commands-§7 step 7: every FEATURE verb refuses on ONE line and reaches no write seam
- slash-commands-§7 step 7: the live set the COMMANDS table gates on IS the library's own
- slash-commands-§7 step 7: both diagnostics forms write a full report while stood down
- slash-commands-§7 step 8: the left click opens the panel and writes nothing; the menu grays every feature
- slash-commands-§7 step 9: re-enabling restores the registration set, and from the settings as they are NOW
- slash-commands-§7 step 10: releasing ONE hold does not resurrect an addon the other is still holding down
- slash-commands-§7: the latch persists NOTHING, and the stored switch is the only thing that does

### test_perf.lua (7)

- perf: the buckets are declared in report order
- perf: every declared bucket is reached by a real bracket
- perf: PLAYER_REGEN_ENABLED records no ledgerEvent sample while BAG_UPDATE does
- perf: a dormant probe notes nothing
- perf: suspend makes the addon inert and resume restores it
- perf: suspend and resume log to the console whatever the debug flag says
- perf: /lh perf dispatches to the harness

### test_diagnostics.lua (20)

- diagnostics: the report is bracketed by this addon's brand, and no section fails
- diagnostics: every DX-LH section writes its own lead line, in the report's order
- diagnostics: the identity section names the stored and code schema, and the active profile
- diagnostics: a changed setting prints as path = value (default); the always rows print anyway
- diagnostics: the AH section prints the priority cascade and which providers are loaded
- diagnostics: a filter list past 40 ids prints the first 40 and says how many more
- diagnostics: the history summary is aggregate: counts by source, quality, bound, characters
- diagnostics: the tail is the newest 25 records, stored fields only, with no link escapes
- diagnostics: the rejected events `/lh debug events` prints are folded into the report
- diagnostics: while stood down, the capture section says so instead of printing empty wiring
- diagnostics: the report calls no item, tooltip or keystone API; the sections leave the debug flag alone and the run turns it on
- diagnostics: a raising section costs exactly one line and the sections after it still land
- diagnostics: an over-cap report ends with the truncated line, then the end marker
- diagnostics: a secret value in the stored loot context does not raise the report
- diagnostics: the stored context's detail prints its fields, not a table address
- diagnostics: the COMMANDS row sits directly after debug
- diagnostics: `/lh debug diagnostics` runs before `/lh debug events` could claim the word
- diagnostics: the browser section with no window and no table module
- diagnostics: the browser section with a shown window, test records and saved views
- diagnostics: the browser section with a hidden window, a descending sort and no view

### test_debug_coverage.lua (21)

- coverage: each latch edge is the library's one [Lifecycle] line plus the host's one [State] line
- coverage: a stand-up with logging off holds its dependency line, and `debug on` writes it after [Init]
- coverage: an event name this client refuses is held for `debug on`, once per name
- coverage: with logging off, an edge builds nothing of the host's and writes nothing
- coverage: while stood down, a hook's stamp, an open and a feature verb each name the guard
- coverage: while disabled, a live verb logs no refusal and a typo is the unknown-verb line
- coverage: the library's own lines land in this addon's console, once each
- coverage: an Options combat-lock refusal is the library's one [Cfg] line in this console
- coverage: the visibility refusal and the visibility hide name the mode
- coverage: a refused schema write is one [Set] line with the seam's reason
- coverage: a currency line refused before it names a currency says why
- coverage: a container use logs only the spell-targeting refusal, never a non-loot item
- coverage: a price provider that raises is one [AHPrice] line per distinct error
- coverage: the deferred bound repair's end names done or gave up, with the real attempt
- coverage: a prune with retention Always says it skipped
- coverage: a filter-list edit names the act and all three list sizes
- coverage: N table repaints with nothing changed log one [Table] line, and a real change logs
- coverage: each open of the History window logs its render once, even when unchanged
- coverage: N Insights recomputes with nothing changed log one [Insights] line
- coverage: a console Clear re-arms the change gates, so the next pass logs over an empty console
- coverage: test mode's start, combat stop and refusal are one [Table] line each

### test_doc_structure.lua (8)

- docs/ARCHITECTURE.md carries the ten sections documentation-§3 names
- every anchor pointing into docs/ARCHITECTURE.md resolves to a heading
- the player-facing history has the ONE home documentation-§1 allows, and no second
- README.md's top-level sections are the ones documentation-§1 names, in its order
- README.md's Reporting a bug section is the standard's text with /lh, and links nowhere
- README.md carries no numbered list (CurseForge does not render one)
- every deviation id the register cites is assigned by a bundle in docs/audits/
- docs/smoke-tests.md carries a non-English-client section

### test_lintconfig.lua (4)

- lintconfig: .luacheckrc sets no top-level ignore
- lintconfig: .luacheckrc switches no warning class off wholesale
- lintconfig: every files[...] ignore is narrowed to a file or a name
- lintconfig: no source file carries a bare inline luacheck ignore

### test_prose.lua (15)

- prose: no authored file carries a British spelling from localization-§5's published list
- prose: the gate carries localization-§5's two lists whole, and nothing of its own
- prose self-test: the carve-out suppresses the named generated folder, and only it
- prose self-test: a path the carve-out does not name is not covered by one that looks like it
- prose self-test: a carve-out that is not a set of path strings is a failure, not a silence
- prose self-test: a TOC's file lines are read as paths, and its directives and comments are not
- prose self-test: a .pkgmeta's ignore block is read, and the keys around it are not
- prose self-test: an ignore entry covers a path exactly, by folder, and by wildcard
- prose self-test: the carve-out admits a generated dump and refuses a file the TOC loads
- prose self-test: a waiver-file exclusion meets the same two refusals as the carve-out
- prose self-test: each list is refused on the matching rule its own scan uses
- prose self-test: the scan and the refusals read the added exclusions through one reader
- prose self-test: a narrowing is refused by what it suppresses, not by how it is written
- prose self-test: the disclosure names what each entry suppressed, and says when it is bounded
- prose self-test: a malformed waived is a failure, not a silence

### test_vendor_sync.lua (3)

- libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles
- tests/_kit is the test kit that shipped with that release
- the automated-test runner is recorded executable (100755)

### test_eol.lua (2)

- eol: every tracked file carries the terminator .gitattributes declares for it
- eol: .gitattributes is line-endings-§5's canonical body for this repo kind

### test_layout_cap.lua (13)

- layoutcap: every authored file over the 1500-line cap is named in the census
- layoutcap: no census row outlives the breach it records
- layoutcap: every over-cap census row carries one of layout-§1's three terminal states
- layoutcap: the census and the exempt set agree about which paths were exempted
- layoutcap: an empty census is written as a result rather than left standing empty
- layoutcap self-test: the parser reads the census nested under the register, and stops there
- layoutcap self-test: a census outside its register, or at the wrong level, is not read
- layoutcap self-test: an over-cap file missing from the census is reported, and an exempt one is not
- layoutcap self-test: a census row that outlives its breach is reported
- layoutcap self-test: an over-cap row that names no terminal state is reported
- layoutcap self-test: the census and the exempt set are held to naming the same paths
- layoutcap self-test: a census that states nothing is told apart from one that states none
- layoutcap self-test: the exempt set takes folders as well as paths

### test_diagnostics_contract.lua (9)

- diagnostics contract: both forms run the report
- diagnostics contract: the debug word is matched in any case
- diagnostics contract: both markers carry the brand and the end counts the report
- diagnostics contract: the report appends after what the console already holds
- diagnostics contract: the report lands with logging off and turns it on for the session
- diagnostics contract: an addon that opts out lands the report and leaves logging off (skipped: this addon keeps the default (Kit.diagnostics.enablesLogging is not false), so its report turns logging on; the case above holds it)
- diagnostics contract: with logging already on, the report writes no second enable line
- diagnostics contract: both forms run while the addon is disabled
- diagnostics contract: no other name runs the report

### test_lizard_sighted.lua (8)

- lizard sighted: every hazard lizard loses a function over is neutralized
- lizard sighted: fields, strings, comments and look-alike names come through unchanged
- lizard sighted: a method definition is rewritten to its dot form with self
- lizard sighted: no line is added or removed, CRLF included
- lizard sighted: countFunctions counts the keyword, not strings, comments or longer names
- lizard sighted: listedCounts reads the per-file table, once per file
- lizard sighted: parity names every file whose counts differ, and only those
- lizard sighted: lizard lists every function of a hazard fixture once it is sanitized

### test_widgets.lua (20)

- Widgets: the seam builds a real library dropdown, art passed as parameters
- Widgets: no option table in this addon sets a glyph
- Widgets: the first click builds real menu rows through the library's own makeMenuRow
- Widgets: a selected multi-select row is ticked and gold
- Widgets: the Character preset row lights up through its own isActive
- Widgets: the Character preset is a one-click 'only me', not a toggle of its own value
- Widgets: a selected character with no option row still counts in the collapsed label
- Widgets: the filter bar builds all ten of its dropdowns through the seam
- Widgets: the Character options fold the class icon into the label, not into an icon field
- Widgets: the History window's OnHide closes the shared popup
- Widgets: Browser:Hide closes the shared popup
- Widgets: the export modal's close path closes the shared popup
- Widgets: every frame that owns a dropdown sits below the menu's FULLSCREEN_DIALOG
- degraded install: the dropdown seam answers nil and CloseMenu is a safe no-op
- degraded install: the filter bar refuses to draw and the browser still comes up
- degraded install: the export modal's refusal builds no frame, on the first Open or the tenth
- degraded install: the export modal refuses rather than calling methods on a nil dropdown
- seam: NS.MakeLineChart builds the library's chart and routes hover back to the host
- seam: NS.MakeLineChart copies the host's opts rather than stamping them
- seam: the chart draws Line regions, not textures

## Totals

| Suite | Cases |
|-------|------:|
| test_constants.lua | 37 |
| test_mediasetup.lua | 11 |
| test_envsetup.lua | 11 |
| test_poolsetup.lua | 3 |
| test_itemsetup.lua | 7 |
| test_util.lua | 47 |
| test_ledger.lua | 36 |
| test_ledgerformat.lua | 5 |
| test_compat.lua | 64 |
| test_scanner.lua | 5 |
| test_holdings.lua | 8 |
| test_rollup.lua | 21 |
| test_attribution.lua | 37 |
| test_attribution_out.lua | 13 |
| test_filters.lua | 19 |
| test_auctionprice.lua | 27 |
| test_collector.lua | 48 |
| test_reconciler.lua | 7 |
| test_reconciler_rows.lua | 31 |
| test_escrow.lua | 14 |
| test_database.lua | 83 |
| test_stats.lua | 25 |
| test_browser.lua | 94 |
| test_browsertable.lua | 80 |
| test_export.lua | 32 |
| test_debuglog.lua | 20 |
| test_launcher.lua | 22 |
| test_slash.lua | 63 |
| test_slash_degraded.lua | 15 |
| test_resetprompt.lua | 7 |
| test_schema.lua | 69 |
| test_schema_stub.lua | 9 |
| test_analytics.lua | 69 |
| test_analytics_layout.lua | 9 |
| test_holdingstab.lua | 33 |
| test_timeline.lua | 32 |
| test_timelinetab.lua | 35 |
| test_autocomplete.lua | 14 |
| test_testdata.lua | 10 |
| test_views.lua | 16 |
| test_panel.lua | 43 |
| test_panel_filters.lua | 20 |
| test_panel_auction.lua | 3 |
| test_profiles.lua | 31 |
| test_harness.lua | 7 |
| test_libka0s.lua | 31 |
| test_surface_parity.lua | 14 |
| test_disabled.lua | 17 |
| test_perf.lua | 7 |
| test_diagnostics.lua | 20 |
| test_debug_coverage.lua | 21 |
| test_doc_structure.lua | 8 |
| test_lintconfig.lua | 4 |
| test_prose.lua | 15 |
| test_vendor_sync.lua | 3 |
| test_eol.lua | 2 |
| test_layout_cap.lua | 13 |
| test_diagnostics_contract.lua | 8 |
| test_lizard_sighted.lua | 8 |
| test_widgets.lua | 20 |
| Skipped | 1 |
| **Total** | **1483** |
