# Ludo

Offline Ludo for Android, built with Flutter. 2 to 4 players share one
device (pass and play), and any seat can be played by the computer instead.
The game runs full screen (status and navigation bars hidden) in portrait or
landscape, and needs no internet connection or permissions.

## Install
Every push that changes `ludo/` builds an APK in the
[`ludo` workflow](../.github/workflows/ludo.yml) and publishes it as the
`ludo-latest` pre-release. On your Android phone, open the repository's
Releases page, download `ludo.apk` and open it (allow installing from your
browser when asked).

## Play
1. Pick who plays each colour: a person, the computer, or nobody (at least 2).
2. On your turn, tap the dice in your corner, then tap a glowing token.
   If there is only one real choice, the token moves by itself.
3. The pause button opens the menu: rules, restart or quit.

Rules: a 6 brings a token out (with no token on the board, a player who
misses a 6 three turns in a row gets one on the next roll); a 6, a capture or bringing a token home earns
another roll; three 6s in a row lose the turn; start and star squares are
safe; reaching the centre needs an exact roll. Play goes on until every
player has a place.

## Code
- `lib/src/engine.dart`: the rules, with no Flutter dependency.
- `lib/src/ai.dart`: the computer player.
- `lib/src/geometry.dart`: where each square and token sits on the 15x15 board.
- `lib/src/board_painter.dart`, `game_screen.dart`, `setup_screen.dart`: the UI.

```sh
flutter test              # rules, board layout, whole simulated games, UI flow
flutter build apk --release
```
