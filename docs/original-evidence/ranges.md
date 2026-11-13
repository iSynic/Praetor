# Ranges the editor had chosen itself, and the soft script values: what the original does

Static evidence from the decompilation of `newland` (the story codes), `spelleffectoutdoors`, `delay`, `getchoice`, `loaditem` and the routines that read the
fields named below, with the instructions of `delay` read one by one. None of it was run in the original unless it says so.

## Code 128, an animation on the map (`spelleffectoutdoors`, `delay`)

| Word | What the code does with it | Range now |
|---|---|---|
| 1 Animation | The eight icons `12000 + 8 x animation` to `+ 7` (a signed word), drawn in turn; a missing icon draws nothing | 0 to 2595, so that the last icon is at most 32767 |
| 2 Column, 3 Row | The map square, taken from the view's origin as word arithmetic (`(column - origin) * 32`); off the screen nothing shows. The bundled scenario draws one animation at (-1, -1) | Soft -1 to 89; hard -1000 to 1000 so that the arithmetic stays in a word |
| 4 Size | The icon is drawn in a square of this many pixels whose top-left corner is on the square's top-left corner and then moved up and left by half the size. The rectangle is word arithmetic (`row * 32 + size`) and is not clipped by the routine | 0 to 29919 so that the arithmetic stays in a word; the form advises 1 to 256 |
| 5 Delay | After each frame, when the word is not zero, `delay(word)` waits **that many ticks of 1/60 second**: it compares the elapsed ticks with the word taken as a **sign-extended long** and waits while the elapsed ticks do not exceed it. A negative word is a huge limit, so the frame never ends | 0 to 32767; the form advises 0 to 60 (one second a frame). A negative value is refused because it waits for ever |

A delay of 0 is not "the default delay": the routine skips the wait. (`delay` itself uses a default, the word at 0x439568, when it is called with 0, but this routine never calls it with 0.)

## The soft script values

Each was run by the original in a fixture, so the game handles it; what it does is:

| Code, value | What the original does | Table |
|---|---|---|
| 43 Give a condition, recipient 3 or more | The recipient is tested as 0 (everyone), 1 (the chosen ones) or 2 (anyone above -10 hit points); another value picks nobody, but the loop first clears the named condition on every warrior that has it | Soft; unchanged |
| 65 Award random items, 22 | The count fills a list of 20 words; entries 21 to 40 land in the next list of 20 words (zeroed just before; what the booty routine does with them was not read); a count of 40 or more writes into the words after that list | Soft, advised 0 to 20; **hard 0 to 40** |
| 106 Set daylight, light 0 | The word minus one is stored in the map's light byte, truncated to a byte, and compared with the next such word for "stop if unchanged"; nothing else reads the byte, and the map picture does not depend on it | Soft; unchanged |
| 14 Pick warriors, 9 | `getchoice` clamps the count to the party's size, so any count of 1 or more picks as many as there are; a count of 0 asks for no warrior and was not seen to finish | Soft 1 to 6, hard 1 or more; unchanged |
| 41 Remove a choice, 7 | The code reads the first 106 bytes of the encounter, clears byte `96 + choice - 1` and writes the 106 bytes back: choices 1 to 4 clear a selector, 5 clears "can back out" (byte 100), 6 clears the tries (101), 7 to 10 clear bytes 102 to 105. A choice of 11 or more writes past the buffer on the stack | Soft, advised 1 to 4; **hard 0 to 10** |
| 50 Pick by race, gender, M.O.S. or class, test 9 | The test is switched over 0 to 4; any other value matches nobody (the picked list is cleared first) | Soft; unchanged |
| 127 Continue if a monster is present, -1 | The code compares a **signed byte** of each living monster with the word, so -1 matches a monster whose byte is 255 and a monster above 127 can never match | Soft; **hard -128 to 127** |

## Ranges that were the editor's own

- **Light level of a map** (`Data RD` offset 522, 0 to 255): a byte that is read only by code 106's unchanged test and copied by save and load of the map; code 57 writes it from its second word truncated to a byte. Audited as 0 to 255.
- **Item class** (`Data NI` offset 26, -255 to 255): `loaditem` takes the absolute value of the class; installing an item copies the class into a byte of the warrior's record. A class that is negative is read as negative by two routines before the absolute value is taken, and the name comes from the item class names by the class plus one. -255 to 255 is kept, with the byte as its reason; a class past the list shows no name.
- Every other item field is the full width of its field.
