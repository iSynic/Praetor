# Shops (Data SD): what the original reads

The editor changes a byte only when the original 1.3.2 binary reads it, and only to values the original's code
handles. This note is the evidence for the shop record. It rests on the original's code, not on any scenario:
a value or a zero byte in the bundled scenario proves nothing about what the code reads or accepts.

| Level | Meaning |
|---|---|
| Static | Read from the original's code: every instruction that touches the record's storage, and its decompilation |
| Dynamic | The original's own machine code run on data this audit authored, so that no scenario is involved |
| Observed | Seen in the bundled scenario; consistency only, never proof |

Reproduce with `python tools/audit_original.py --baseline artifacts/native-startup-08 --reference <the reconstruction> --ghidra <Ghidra> --out artifacts/<new folder>`.
It copies the Ghidra project of the original program (`code1-mapped.bin`, 571 routines, the A5 data block mapped), opens
it read only, and runs `tools/native/AuditConsumers.java`, `AuditDecompile.java` and `AuditLoadItem.java`. It fails if the set of routines that touch the
record changes or if `loaditem` answers differently.

## Where the record lives

`loadshop` (0x12fe54) reads shop number `n` from the game's temporary copy of `Data SD` (offset `n * 0xbba`, 3002 bytes)
into a stack buffer, then keeps it in globals: item words at 0x478288 (1000 words), quantity bytes at 0x478a58 (1000 bytes) and the
price percent word at 0x478e40. `resetgamefiles` (0x14f96e) makes the temporary copy from the scenario's file at the start of a game and `saveshop` (0x13006e),
`save` and `load` write and read it back, so the file's length divided by 3002 is the number of shops.

## Every routine that touches it (static)

The scan lists each instruction that refers to 0x478288 to 0x478e41, by reference or by address operand: 83 instructions in 11 routines.
No other routine names the storage. (A routine that reached it only through a pointer built elsewhere would not show; none is known.)

| Routine | Address | What it does with the record |
|---|---|---|
| `loadshop` | 0x12fe54 | Copies the price word. For each of five lists of 200 slots, **copies a slot only when its quantity byte is not zero**, packing the stocked slots to the front of the list in order; the item word of a slot with quantity zero is never read |
| `Display` | 0x120872 | Draws a stock row: the item word is used only when the row's quantity is not zero; **a negative item ends the drawing**; an item below 2000 is passed to `loaditem` |
| `updateshop` | 0x139244 | The same stock test and item read, four times, for the shop screen |
| `choice` | 0x112820 | The same test and read when a stock row is clicked |
| `moveicon` | 0x13c1ee | A purchase takes one from the quantity and, when it reaches zero, **clears the item word**; a sale looks through the 200 slots of the category in view for the same item word and adds one, else takes the first slot whose quantity is zero and sets quantity 1 and the item word |
| `itemcost` | 0x13c018 | Reads the price word as a signed word: a selling price uses at most 100, then the cost is scaled by the percent and divided by 100 with SANE arithmetic |
| `newland` | 0x1400e4 | The story opcode that changes a shop: adds to the price word, adds to a matching item's quantity, clears a quantity |
| `loaditem` | 0x130afe | Not a reader of the record but the consumer of its item word: takes the absolute value and loads a definition for 0 to 999 only (below) |
| `resetgamefiles`, `saveshop`, `save`, `load` | | Move the whole 3002 bytes |

## The record, byte by byte

| Bytes | Field | Read | Accepted | Evidence |
|---|---|---|---|---|
| 0 to 1999 | Item word of slot 0 to 999 | Only when the slot's quantity is not zero | A stocked item is 1 to 999 | Static (`loadshop`, `Display`), dynamic (`loaditem`) |
| 2000 to 2999 | Quantity byte of slot 0 to 999 | Always; not zero means stocked | 1 to 255 for a stocked slot | Static (`loadshop`); a purchase and a sale add and subtract one in a byte, so 255 wraps to 0 in play |
| 3000 to 3001 | Price percent, signed word | Always | -32768 to 32767 | Static (`itemcost`, `moveicon`): the item's cost is made positive, scaled by the percent, and a negative result is not stopped. A purchase refuses only when the party's money is below the cost, then subtracts it, so a negative cost pays the buyer; a sale adds the cost, so it charges the seller. Nothing in either path special-cases zero or a negative percent |

- **Item range.** `loaditem` run on marker tables (dynamic) loads the real definition for ids 0 to 999 and, ignoring the sign, for -999 to -1.
  It loads nothing for 1000 and above or -1000 and below, leaving the previous item in place. `Display` stops drawing at a negative item and treats
  item 0 as an empty row. So only 1 to 999 is stocked cleanly.
- **Categories.** The five lists of 200 slots are the shop's categories. The slot's place in its list is its place in the display, because
  `loadshop` packs the stocked slots; the gaps between stocked slots mean nothing.
- **Observed only:** the bundled scenario's shops hold items whose id equals the slot number and one slot (0) with item 0 and quantity 1. Neither is a rule of the original.

## What the editor now does

- A stocked slot takes an item of 1 to 999 and a quantity of 1 to 255; anything else is refused.
- Emptying a slot writes quantity 0 **and item 0**, as the game does when it sells the last one.
- **Padding.** The item word of a slot whose quantity is zero is never read, so it is padding. The editor never gives it meaning and writes
  zero there when it empties a slot; imported padding is kept as it is.
- **Add item** works as the game takes a sale in: one more where the chosen category already holds the item, else the first empty slot of the category.
- The price percent is -32768 to 32767. The label says a negative percent pays the buyer and charges the seller.

## Open

- The cost is converted to a long integer by SANE; a cost times percent beyond 2,147,483,647 divided by 100 overflows, and the result of the overflow is not measured. The Problems list warns about a stocked scenario item (800 and up) whose price times the percent passes that; the prices of the stock items below 800 are in the installation and are not read.
- A shop with a zero percent gives items away; the storage facility the Realmz editor describes is not in the 1.3.2 purchase path.
- `itemcost` uses SANE floating point, which the Ghidra emulation does not run, so the largest percent that never overflows the result is not measured. The
  reconstruction's `percentage_price` follows the routine and is high confidence in its notes.
- A sale also reuses a slot whose quantity is zero but whose item word matches. The editor does not (that word is padding to it).
- Not run dynamically: `Display`, `moveicon` and `newland` on authored shops. Their reads and writes are known from the code, not exercised.
- The shop number a story passes to `loadshop` is not checked against the file's length by `loadshop`; the editor does not yet check it for stories.
