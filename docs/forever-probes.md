# Forever probes — Ka0s Loot History

The in-game facts the WoW Forever port could not settle from source (Ka0sAddonsCommonTasks
`docs/2026-11-22-LOOTHISTORY_BANKLEDGER_FOREVER_PORT/`, `00_DESIGN.md` ruling R4 and
`inputs/research/SYNTHESIS.md` §4b), in one sheet. The build ships a **safe default** for each
one, so the port merged without waiting for them (ruling R3). A probe answer that contradicts its
default becomes a follow-up item, never a silent edit.

These are the owner's to run. An agent never fills a `Result:` line. Record the answer there with
the date and the client build.

## The probe verbs

`/lh debug probe` records most of these facts by itself, so one play session answers most of the
sheet:

| Verb | What it does |
|---|---|
| `/lh debug probe start` | Starts recording, stamps the record with the client key, its version and build, and the addon version, and writes a `start` entry. |
| `/lh debug probe stop` | Stops recording: every probe event unregistered, every pending bank snapshot cancelled. |
| `/lh debug probe status` (or bare `/lh debug probe`) | One chat line: running or stopped, entries against the cap, dropped count, client and build. |
| `/lh debug probe clear` | Drops the record. While running, recording goes on in a fresh record. |

The record is `db.global.probe` inside `LootHistoryDB`. There is no new SavedVariables global. It
holds at most 500 entries (`NS.Probe.CAP`) and drops the oldest first, counting them in `dropped`.
It is **session-only**: a reload or relog stops it, the record stays, and you start it again. It
records nothing while a simulation runs, and the start refuses during one, so every fact comes from
the live client. Every value is cut to 400 characters, and a secret value is stored as `<secret>`.
This is the one place the addon keeps raw chat text, and only while you have started it.

**How to read it.** Log out (or `/reload`) so the client writes the file, then open
`_forever_/WTF/Account/<account>/SavedVariables/LootHistory.lua` (`_retail_` for the Retail
answers) and find `["probe"]` under `["global"]`. Each entry has a `kind` and a `t` (`time()`).

**A session that answers the sheet.** On WoW Forever: `/lh debug probe start`; visit a banker
twice and close the bank between visits; loot a mob solo and in a dungeon; win a group roll; open
a trade with another player; send a mail to an alt; transfer a currency to an alt if any is
transferable; zone into a dungeon; `/lh debug probe stop`; log out. Then do the P1, P2 and P9
parts again on Retail.

| `kind` | When | What it holds | Probes |
|---|---|---|---|
| `start` | At start | `money` (which money-text functions exist and what each answers for 123456 copper, plus the addon's own text), `strings` (`LOOT_ROLL_YOU_WON`, `LOOT_ITEM_BONUS_ROLL_SELF`, the name of spell 13262), `identity` (`UnitName("player")`'s two answers, regional names, the character key, realm key and holder key), `instance`, `keyring`, `currencies` (the visible list rows with their account flags), `transfer` (the newest currency transfer) | P3, P5, P8, P9, P11 |
| `interaction` | Every `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` | The interaction type, and the banker name when it is `Banker`, `CharacterBanker` or `AccountBanker` | P1 |
| `bank` | At a banker's open, then +1 s and +3 s | `phase`, `via` (what opened the visit), `slots` (every container id -3..30 that answers a slot count, and every bank id even at 0), `model` (`CanViewBank(0)` and `(2)`, `FetchNumPurchasedBankTabs(0)` and `(2)`, `FetchMaxNumBankTabs(0)`, `ShouldUsePlayerBagsInBank()`, `FetchDepositedMoney(2)`, the addon's `CanViewCharacterBank`); at open also `sockets` (the -2 reads through an `ItemLocation` and through `GetContainerItemInfo`, slots 1..9) | P1, P2, P10 |
| `cue` | A bank event within 10 s of the open: `BANKFRAME_OPENED`, `BANKFRAME_CLOSED`, `BAG_CONTAINER_UPDATE`, `BANK_TABS_CHANGED`, `PLAYERBANKSLOTS_CHANGED`, `BAG_UPDATE_DELAYED`, the interaction hide | The event, its arguments and `dt`, the seconds after the open | P1 |
| `chat` | Every `CHAT_MSG_LOOT`, `CHAT_MSG_MONEY`, `CHAT_MSG_CURRENCY` | The raw `text`, `sender` (arg 2), `sender2` (arg 5), `guid` (arg 12) | P4, P8 |
| `loot` | Every `LOOT_OPENED` | Each slot's link and first source GUID (what the addon reads) | P4 |
| `transfer` | Every `CURRENCY_TRANSFER_LOG_UPDATE` | The newest transfer, field by field as the client names it | P5 |
| `trade` | Every `TRADE_SHOW` | `UnitName("NPC")`'s two answers, `GetUnitName("NPC", true)`, the key the addon builds | P7 |
| `mail` | Every sent mail | The recipient as typed, and as `Util.QualifyName` keys it | P7 |
| `instance` | Every `PLAYER_ENTERING_WORLD` | `GetInstanceInfo()`'s answers | P11 |
| `error` | A probe handler that raised | The event and the message (the raise never leaves the probe) | n/a |
| `stop` | At stop | Nothing; it marks the end of a session | n/a |

The record's `rejected` lists any probe event this client refused to register. That is a fact
too: an absent event is one the addon cannot listen for on that client.

## The sheet

Each probe is the fact, what the probe verbs record for it, the `/run` fallback for a client where
the verbs are not loaded, and the safe default the build ships.

**P1. Which interaction type a banker sends, and whether the bank reports 0 slots at open.** Both
clients. Recorded: `interaction`, `bank` (open, +1 s, +3 s) and `cue`. Read the type a Forever
banker sends (8 `Banker` or 67 `CharacterBanker`; 68 `AccountBanker` is a finding), whether any bank
container answers 0 at open and its slots later, how long it takes, and which cue events fire while
it loads. Fallback, away from a bank:
`/run local f=CreateFrame("Frame") f:RegisterEvent("BANKFRAME_OPENED") f:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW") f:SetScript("OnEvent",function(_,e,a) local function s() local n=0 for i=6,14 do n=n+C_Container.GetContainerNumSlots(i) end return n end print(e,a,s()) C_Timer.After(1,function() print("+1s",s()) end) C_Timer.After(3,function() print("+3s",s()) end) end)`,
then talk to the banker (Retail: ids 6..11). Safe default: the bank part arms on `Banker`,
`CharacterBanker` and, on Retail only, `AccountBanker` (`R.READABLE_ON`, `modules/Reconciler.lua`).
A bank container that had slots on the last ready read and now answers 0 is "loading" for up to
5 s (`R.READY_WAIT`), and the read waits for `BAG_CONTAINER_UPDATE` or `BANK_TABS_CHANGED`. If the
bank takes longer than 5 s, or neither cue fires while it loads, that is a finding. Result:

**P2. The bank model's answers.** At the banker, both clients. Recorded: `bank.model`, `bank.slots`.
Fallback: `/run print(C_Bank.ShouldUsePlayerBagsInBank(), C_Bank.CanViewBank(0), C_Bank.CanViewBank(2), C_Bank.FetchNumPurchasedBankTabs(0), C_Bank.FetchNumPurchasedBankTabs(2), C_Bank.FetchMaxNumBankTabs(0), C_Bank.FetchDepositedMoney(2))`
and `/run for i=-3,23 do local n=C_Container.GetContainerNumSlots(i) if n>0 then print(i,n) end end`.
Safe default: the warband bank is Retail-only by declaration (`C.FEATURE.warbandBank`, ruling R1),
and the character bank is the `CharacterBankTab_*` ids by member name (6..14 on Forever). A Forever
`CanViewBank(2)` of true or a purchased account tab is a finding. Result:

**P3. The keyring.** Forever; Retail too for the -1 answer. Recorded: `start.keyring` (slots,
contents, `inventorySlot`, which is `ContainerIDToInventoryID(-1)`). Then try to drag a key into the
bank, which no recorder can do for you. Fallback:
`/run print(C_Container.GetContainerNumSlots(-1), C_Container.ContainerIDToInventoryID(-1)) for i=1,C_Container.GetContainerNumSlots(-1) do local x=C_Container.GetContainerItemInfo(-1,i) if x then print(i,x.hyperlink,x.stackCount) end end`.
Safe default: the keyring (-1) is in the bags group on Forever only (ruling R5,
`C.CONTAINER_GROUPS_BY_CLIENT`), and there is no keyring-to-bank pairing. If a key can go into the
bank, keyring-to-bank moves are real transfers and need one. An `inventorySlot` that is not nil means
the equipped-bag scan (`Scanner.ScanEquipped`) reads that slot too; check it adds nothing. On
Retail, a -1 that answers slots is a finding. Result:

**P4. The self loot line, its sender, and the loot source.** Forever, solo and in a dungeon.
Recorded: `chat` and `loot`. Read whether the loot strings match the Retail shapes, whether a
self-chat sender is the first name or "First Surname", and whether the source GUID decodes as on
Retail. Fallback:
`/run local f=CreateFrame("Frame") f:RegisterEvent("CHAT_MSG_LOOT") f:RegisterEvent("LOOT_OPENED") f:SetScript("OnEvent",function(_,e,...) if e=="LOOT_OPENED" then for i=1,GetNumLootItems() do print(i,GetLootSlotLink(i),GetLootSourceInfo(i)) end else local t,p=... print((t:gsub("\124","\124\124")),p,(select(5,...)),(select(12,...))) end end)`.
Safe default: the current parsers (the 36 loot strings are byte-identical) and the GUID decode as
on Retail. The simulator sends the first name (`modules/SimDrivers.lua`). Result:

**P5. The currency list and the transfer record.** Forever. Recorded: `start.currencies`,
`start.transfer` and `transfer`. Read `isAccountWide` and `isAccountTransferable` for Honor Points
(1792) and Merchant's Favor (3402), and whether `destinationCharacterName` carries the surname.
Fallback: `/run for i=1,C_CurrencyInfo.GetCurrencyListSize() do local c=C_CurrencyInfo.GetCurrencyListInfo(i) print(i,c.name,c.isHeader,c.isAccountWide,c.isAccountTransferable,c.quantity) end`;
after a transfer: `/run local l=C_CurrencyInfo.FetchCurrencyTransferTransactions() local t=l and l[#l] if t then for k,v in pairs(t) do print(k,v) end end`.
Safe default: an account-wide currency goes to the account holder (labeled "Account"), and the
transfer destination is used as the client names it, with no realm added on regional names. A
destination without the surname would not match a "First Surname" holder. If either currency is
account-wide, set the `account` flag in the Forever test data (`modules/TestData.lua`,
`modules/SimWorld.lua`). Result:

**P6. The guild vault.** BankLedger's probe (`/bl debug probe`). Loot History records guild
deposits and withdrawals only through its bank model, so nothing here reads the vault. Result: n/a.

**P7. The trade partner's and the mail recipient's forms.** Forever. Recorded: `trade`, `mail`.
Read whether `UnitName("NPC")` answers "First", "Surname" during a trade, and how a typed recipient
compares with the holder key. Fallback, in an open trade: `/run print(UnitName("NPC")) print(GetUnitName("NPC",true))`;
before sending mail: `/run hooksecurefunc("SendMail",function(r) print("["..tostring(r).."]") end)`.
Safe default: the partner is read through `Compat.UnitCharacterName("NPC")` (never a surname read
as a realm), and a typed recipient is kept whole and keeps the case it was typed in. A lower-case
recipient that the client does not normalize would not match its holder. Result:

**P8. The group roll line.** Forever. Recorded: `chat` (the `CHAT_MSG_LOOT` of a roll you win) and
`start.strings.LOOT_ROLL_YOU_WON`. Read that the raw line is `|HlootHistory:N|h[Loot]|h: You won: <link>`,
and that the next receive line is attributed to ROLL in the history. Fallback: P4's frame. Safe
default: the roll-won parser takes the `%s` capture (`Util.ParseRollWon`), so the stamp works with
or without the prefix. Result:

**P9. The money text.** Both clients. Recorded: `start.money`. Read which of `GetCoinTextureString`,
`GetMoneyString` and `C_CurrencyInfo.GetCoinTextureString` exist, and that `formatted` shows coin
glyphs, never "12g 34s 56c". Fallback:
`/run print(GetCoinTextureString, GetMoneyString, C_CurrencyInfo.GetCoinTextureString and C_CurrencyInfo.GetCoinTextureString(123456))`.
Safe default: `C_CurrencyInfo.GetCoinTextureString`, then `GetMoneyString`, then the text
(`Util.FormatMoney`, ruling R8). Result:

**P10. The socketed bank bags (-2).** Forever, at the banker, with a bag in a bank socket. Recorded:
`bank.sockets` at open. Read which slots answer through the `ItemLocation` and through the container
API, and what slot 1 holds. Fallback:
`/run for i=1,9 do local l=ItemLocation:CreateFromBagAndSlot(-2,i) if C_Item.DoesItemExist(l) then print(i,C_Item.GetItemLink(l)) end end`
and `/run for i=1,9 do local x=C_Container.GetContainerItemInfo(-2,i) print(i,x and x.hyperlink) end`.
Safe default: sockets are not scanned (ruling R6), so a bag moved into a socket reads as a bag OUT.
Result:

**P11. The instance difficulty ids.** Forever, in a 5-man and a raid. Recorded: `start.instance` and
`instance`. Fallback: `/run print(GetInstanceInfo())`. Safe default: the difficulty is stored raw,
as today, with no label change. Result:

**P12. The addon loads clean.** After the branch is on the Forever install: `/lh diagnostics`,
and `/lh debug events` reads `none`. Owner smoke; nothing to record. Result:

## The smaller questions the port left open

These ride along with the probes above. The `start` entry records the first three.

- **Disenchant on Forever.** `start.strings.disenchant` is the name of spell 13262. Forever's only
  deconstruct seed is 13262 (D15), so a nil name means that seed is wrong. Result:
- **The bonus-roll string.** `start.strings.LOOT_ITEM_BONUS_ROLL_SELF`: present or nil on Forever.
  The parser is safe either way: on Forever the line takes the loot context's source (R2). Result:
- **The self-chat sender form** (P4's `chat.sender`): the first name or "First Surname". Result:
- **A hyphen in a surname.** Check whether a Forever surname can carry a hyphen (character
  creation). If it can, the realm cut in `shortChar` and `HolderShort` would cut it and needs a
  `RegionalNames()` guard. Result:
- **Waylaid Crate.** Check that 248683 (Waylaid Crate: Apprentice Ore) can be opened on Forever;
  it is the simulator's uncached cache. Result:
