# Brain Freedom

A split screen studio for making a film, built during the production of **The Brain Brake**.

**Left brain** speaks, remembers and shows the frames. **Right brain** is a genuine pseudo terminal running
the coding agent inside the project repository. You talk, it becomes text, and you watch it typed across the
divide one character at a time.

Built for a director who is dyslexic and works by voice. Everything here follows from that: nothing to type,
nothing to remember, no command line switches, a file picker wherever a key or a path is needed, read aloud
with word highlighting, and text size controls on both halves of the screen.

    bash 8sh_brain_freedom_v8_macos.sh

One file. It opens a menu of single keys, no Enter needed.

    [I]  install, or update if it is already here
    [S]  start it now
    [U]  uninstall everything
    [Q]  quit

## What it does

- **Voice in.** Records Opus at 24 kbps mono in the browser, transcribes through AssemblyAI, drops the text in
  the composer. Multiple keys queue up and it falls through dead ones automatically.
- **The invisible hand.** Types your words into the agent character by character, so the work can be watched.
- **Read aloud.** Any text, any selection, word by word highlighting, adjustable speed.
- **Frames.** Drop a render, it is named, optimised, committed, pushed, and the raw link is on your clipboard,
  ready to paste back into the image tool.
- **Usage.** An honest estimate read from local agent session logs, with a warning when today is running hot.
- **Keys.** A gold gear opens a manager that harvests every key out of any messy file and sorts them by
  provider.

## What it is not

It does not report your official account usage, because no API exposes that. The figure shown is an estimate
from local logs and is labelled as one. It needs an internet connection on first load for the terminal
library. The coding agent must be installed separately.

## Requirements

macOS, python3, and the coding agent on your PATH. Everything else installs into a private environment inside
`~/brain_freedom` and touches nothing system wide.

Keys and settings live in `~/.brain_freedom`, mode 600, never in this repository.

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version and why.
