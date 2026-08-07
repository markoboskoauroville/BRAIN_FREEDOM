# CHANGELOG

Brain Freedom is a split screen studio built for one particular pair of hands, during the making of the film
*The Brain Brake*. Left brain speaks and remembers. Right brain is a real terminal running the coding agent.
Everything below was driven by an actual problem hit in production, never by a feature list.

The version label carries an account letter, `(a)`, marking which account last touched it.

---

## v5 (a) — 7.8.2026 — seeing and choosing

**Two coloured buttons.** Record is deep red on near black with a red ring, Read is deep blue on near black
with a blue ring. Two dark buttons, two unmistakable colours, no reading required to tell them apart.

**Text size, independently, on both sides.** Minus, number, plus above the message box for the left panel, and
mirrored in the terminal header for the right. Only text scales, never the controls, and both remember their
setting. Built because the person using this has low vision and dyslexia and needs to change size mid session
without hunting through a preferences pane.

**Terminal breathing room.** The agent was drawing to the very edge of the glass, so the ends of long lines sat
under the frame. Real side margins, and the fit recalculates on every layout change.

**It opens itself, in the browser you choose.** macOS defaults are deliberately ignored. Firefox is picked
first when present, then LibreWolf, Waterfox, Zen. Behind the gear, every browser found on the machine is
listed as a pill, tap one and it is yours permanently. Firefox matters here for a technical reason, its
recorder produces Opus, which is the correct format for speech.

**Golden key favicon**, served by the app, so the tab carries the film's own symbol.

## v4 (a) — 7.8.2026 — never crash on a missing folder

The repository folder had never been created, so git had nowhere to run and Python threw a stack trace at a
person who cannot easily read one. Now the app creates the folders and clones the repository itself, and both
push and frame upload run that check first, repairing rather than failing. Missing token produces one plain
sentence instead of a traceback. The gallery no longer errors when there is nothing in it yet.

## v3 (a) — 7.8.2026 — one keypress, no switches

**Command line switches removed entirely.** A person running twenty five projects will not remember
`--uninstall` tomorrow. The script now opens a menu of single keys, raw input, no Enter. `[I]` install or
update, `[S]` start, `[U]` uninstall, `[Q]` quit. Uninstall asks one more single key about whether to keep the
keys. The stated goal was to be able to work with the eyes closed, like a pianist.

**Solid two colour logo.** The striped outline lettering was replaced with solid blocks, BRAIN in gold and
FREEDOM in cyan, the two poles of the spectrum, which is also the two halves of the brain the app is named
after.

## v2 (a) — 7.8.2026 — the key manager

**One file for everything.** Install, update and uninstall all live in the same script. Two scripts was one
too many.

**No keys asked during installation.** Instead a gold gear in the corner opens a full key manager. Point it at
any file, notes, an export, a scratchpad full of rubbish, and it harvests every token inside, sorts them by
provider and queues them. Each key shows masked with its state, and can be tested, promoted to first, or
deleted. Transcription walks the queue and falls through dead keys automatically, reporting plainly which key
answered. Shape is used only to rank a key, never to reject one, because providers rebrand their key formats
without telling anybody.

**Gold on black.** The whole interface was restyled to the house scheme, pill buttons, mono type, no blur.

## v1 (a) — 6.8.2026 — the first working split

Flask, a real pseudo terminal running the coding agent through xterm.js, and a left panel that speaks.

- **Voice.** The browser records Opus at 24 kbps mono, the server sends it to AssemblyAI and returns text into
  the composer, with live meter showing seconds, kilobytes, transfer rate.
- **The invisible hand.** Text is typed into the terminal one character at a time so the work can be watched
  rather than merely trusted.
- **Read aloud** with word by word highlighting, for dyslexia, at adjustable speed.
- **Frames pipeline.** Drop a render, it is named, optimised to a web copy, committed, pushed, and the raw
  GitHub link lands on the clipboard ready for the image tool. No re-uploading the same reference twice.
- **Usage estimate** read from the local agent session logs, with a plain warning when today is running hotter
  than the weekly average.

---

## Standing rules this software obeys

No command line switches, anywhere. No typing where a file picker will do. Never validate a key by its shape.
Suppress the framework's red warning banner. Scan upward for a free port rather than binding a fixed one.
Print a coloured block logo, a boxed panel and a hotkey legend, because a terminal should never look plain.
Always `q` to quit, `o` to open, `b` to background. Version label in the corner with the account letter.
