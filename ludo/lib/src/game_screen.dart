import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai.dart';
import 'board_painter.dart';
import 'dice.dart';
import 'engine.dart';
import 'geometry.dart';
import 'rules.dart';

const Duration _stepTime = Duration(milliseconds: 140);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.players, this.random});

  final List<Player> players;

  /// For tests: makes dice rolls predictable.
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final LudoGame game = LudoGame(widget.players, random: widget.random);
  final Random _faces = Random();

  /// True while the dice rolls, a token moves or the game pauses between
  /// turns; taps are ignored meanwhile.
  bool _busy = false;
  int? _rollingFace;
  (LudoColor, int)? _movingToken;
  Offset? _movingPos;
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeComputerTurn());
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<bool> _wait(Duration d) async {
    await Future<void>.delayed(d);
    return mounted;
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _maybeComputerTurn() {
    if (!mounted || _busy || game.isOver) return;
    if (game.current.isComputer && game.phase == TurnPhase.roll) {
      setState(() => _busy = true);
      _wait(const Duration(milliseconds: 550)).then((ok) {
        if (ok) _roll();
      });
    }
  }

  void _onDiceTapped(LudoColor color) {
    if (_busy ||
        game.phase != TurnPhase.roll ||
        game.current.color != color ||
        game.current.isComputer) {
      return;
    }
    _roll();
  }

  Future<void> _roll() async {
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final value = game.rollDie();
    for (var i = 0; i < 7; i++) {
      setState(() => _rollingFace = _faces.nextInt(6) + 1);
      if (!await _wait(const Duration(milliseconds: 65))) return;
    }
    final roller = game.current;
    final result = game.roll(value);
    setState(() => _rollingFace = null);

    switch (result) {
      case RollResult.mustMove:
        final movable = game.movableTokens();
        final positions = movable.map((t) => game.tokens[roller.color]![t]);
        if (roller.isComputer) {
          if (!await _wait(const Duration(milliseconds: 450))) return;
          await _move(chooseMove(game));
        } else if (positions.toSet().length == 1) {
          // Only one real choice: move it without asking.
          if (!await _wait(const Duration(milliseconds: 300))) return;
          await _move(movable.first);
        } else {
          setState(() => _busy = false);
        }
        return;
      case RollResult.noMoves:
        if (!await _wait(const Duration(milliseconds: 750))) return;
      case RollResult.threeSixes:
        _showToast('Three sixes! ${roller.color.label} loses the turn');
        if (!await _wait(const Duration(milliseconds: 1100))) return;
    }
    setState(() => _busy = false);
    _maybeComputerTurn();
  }

  void _onTokenTapped(LudoColor color, int token) {
    if (_busy ||
        game.phase != TurnPhase.move ||
        game.current.isComputer ||
        game.current.color != color ||
        !game.movableTokens().contains(token)) {
      return;
    }
    _move(token);
  }

  Future<void> _move(int token) async {
    setState(() => _busy = true);
    final c = game.current.color;
    final from = game.tokens[c]![token];
    final to = LudoGame.targetFor(from, game.dice!)!;
    for (final p in BoardGeometry.path(c, token, from, to)) {
      setState(() {
        _movingToken = (c, token);
        _movingPos = p;
      });
      if (!await _wait(_stepTime)) return;
    }
    final result = game.move(token);
    setState(() {
      _movingToken = null;
      _movingPos = null;
    });

    if (result.captures.isNotEmpty) {
      HapticFeedback.heavyImpact();
      final victims = result.captures.map((x) => x.color.label).toSet();
      _showToast('${c.label} captured ${victims.join(' & ')}!');
    }
    if (game.ranking.contains(c)) {
      _showToast('${c.label} finished ${_ordinal(game.ranking.indexOf(c))}!');
    } else if (result.reachedHome) {
      _showToast('${c.label} token home!');
    }
    if (!await _wait(
      Duration(milliseconds: result.captures.isEmpty ? 200 : 500),
    )) {
      return;
    }
    if (game.isOver) {
      _showResults();
      return;
    }
    setState(() => _busy = false);
    _maybeComputerTurn();
  }

  static String _ordinal(int i) => const ['1st', '2nd', '3rd', '4th'][i];

  void _showResults() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Game over', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < game.ranking.length; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: seatColors[game.ranking[i]],
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  game.players
                      .firstWhere((p) => p.color == game.ranking[i])
                      .name,
                ),
                trailing: i == 0
                    ? const Icon(Icons.emoji_events, color: Color(0xFFFFB300))
                    : null,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Menu'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _restart();
            },
            child: const Text('Play again'),
          ),
        ],
      ),
    );
  }

  void _restart() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(players: widget.players),
      ),
    );
  }

  Future<void> _openMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Paused'),
        children: [
          for (final (value, label, icon) in const [
            ('resume', 'Resume', Icons.play_arrow),
            ('rules', 'How to play', Icons.help_outline),
            ('restart', 'Restart game', Icons.refresh),
            ('quit', 'Quit to menu', Icons.exit_to_app),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(value),
              child: Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 16),
                  Text(label, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'rules':
        await showRules(context);
      case 'restart':
        _restart();
      case 'quit':
        Navigator.of(context).pop();
    }
  }

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text('The current game will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1F2A44), Color(0xFF0B0F1A)],
            ),
          ),
          child: SafeArea(child: LayoutBuilder(builder: _layout)),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints box) {
    const gap = 8.0;
    final menu = IconButton(
      key: const Key('menu'),
      onPressed: _openMenu,
      iconSize: 32,
      color: Colors.white70,
      icon: const Icon(Icons.pause_circle_outline),
      tooltip: 'Menu',
    );
    if (box.maxWidth > box.maxHeight) {
      final panelW = (box.maxWidth * 0.2).clamp(110.0, 220.0);
      final board = min(
        box.maxHeight - 2 * gap,
        box.maxWidth - 2 * panelW - 4 * gap,
      );
      Widget side(LudoColor top, Widget middle, LudoColor bottom) => SizedBox(
        width: panelW,
        child: Column(
          children: [
            Expanded(child: _panel(top)),
            middle,
            Expanded(child: _panel(bottom)),
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(gap),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            side(LudoColor.red, menu, LudoColor.blue),
            _board(board),
            side(LudoColor.green, const SizedBox(height: 48), LudoColor.yellow),
          ],
        ),
      );
    }
    final panelH = (box.maxHeight * 0.15).clamp(90.0, 170.0);
    // The board runs edge to edge; only the panels keep a side margin.
    final board = min(box.maxWidth, box.maxHeight - 2 * panelH - 4 * gap);
    Widget row(LudoColor left, Widget middle, LudoColor right) => Container(
      height: panelH,
      padding: const EdgeInsets.symmetric(horizontal: gap),
      child: Row(
        children: [
          Expanded(child: _panel(left)),
          middle,
          Expanded(child: _panel(right)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: gap),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          row(LudoColor.red, menu, LudoColor.green),
          _board(board),
          row(LudoColor.blue, const SizedBox(width: 48), LudoColor.yellow),
        ],
      ),
    );
  }

  Widget _panel(LudoColor color) {
    final player = game.players.where((p) => p.color == color).firstOrNull;
    final seat = seatColors[color]!;
    if (player == null) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
        ),
      );
    }
    final isTurn = !game.isOver && game.current.color == color;
    final rank = game.ranking.indexOf(color);
    final canRoll =
        isTurn && !_busy && !player.isComputer && game.phase == TurnPhase.roll;
    final showDice = isTurn || game.lastRoller == color;
    final face = isTurn && _rollingFace != null
        ? _rollingFace
        : (game.lastRoller == color ? game.dice : null);

    final String status;
    if (rank >= 0) {
      status = 'Finished ${_ordinal(rank)}';
    } else if (!isTurn) {
      status = '${game.tokens[color]!.where((t) => t == home).length}/4 home';
    } else if (player.isComputer) {
      status = 'Thinking…';
    } else if (_rollingFace != null) {
      status = 'Rolling…';
    } else if (game.phase == TurnPhase.roll) {
      status = _busy ? '' : 'Tap dice to roll';
    } else {
      status = _busy ? '' : 'Tap a glowing token';
    }

    return Padding(
      padding: const EdgeInsets.all(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: isTurn ? seat.withValues(alpha: 0.28) : Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTurn ? seat : Colors.transparent,
            width: 3,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key('dice-${color.name}'),
            borderRadius: BorderRadius.circular(16),
            onTap: canRoll ? () => _onDiceTapped(color) : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          player.isComputer ? Icons.smart_toy : Icons.person,
                          color: seat,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          color.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (rank >= 0) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.emoji_events,
                            size: 20,
                            color: rank == 0
                                ? const Color(0xFFFFB300)
                                : Colors.white54,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: showDice ? (isTurn ? 1 : 0.45) : 0.15,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        scale: canRoll ? 1.12 : 1,
                        child: Transform.rotate(
                          angle: _rollingFace != null && isTurn
                              ? (_rollingFace! - 3.5) * 0.25
                              : 0,
                          child: DieFace(value: face, size: 52),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      status,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _board(double size) {
    final cell = size / BoardGeometry.cells;
    final movable = game.current.isComputer || _busy
        ? const <int>[]
        : game.movableTokens();

    // Tokens sharing a square are drawn smaller and side by side.
    final placed = <(LudoColor, int, Offset)>[];
    for (final p in game.players) {
      for (var t = 0; t < tokensPerPlayer; t++) {
        final pos = _movingToken == (p.color, t)
            ? _movingPos!
            : BoardGeometry.position(p.color, game.tokens[p.color]![t], t);
        placed.add((p.color, t, pos));
      }
    }
    final groups = <(int, int), List<int>>{};
    for (var i = 0; i < placed.length; i++) {
      final pos = placed[i].$3;
      final key = ((pos.dx * 4).round(), (pos.dy * 4).round());
      groups.putIfAbsent(key, () => []).add(i);
    }

    // Drawn in layers so the active player's tokens sit on top.
    final layers = List.generate(4, (_) => <Widget>[]);
    for (final group in groups.values) {
      final n = group.length;
      final cols = sqrt(n).ceil();
      final rows = (n / cols).ceil();
      final scale = n == 1 ? 1.0 : 1.1 / max(cols, rows);
      for (var j = 0; j < n; j++) {
        final (color, t, pos) = placed[group[j]];
        final dx = n == 1 ? 0.0 : ((j % cols) - (cols - 1) / 2) * 0.42;
        final dy = n == 1 ? 0.0 : ((j ~/ cols) - (rows - 1) / 2) * 0.42;
        final tokenSize = cell * 0.95 * scale;
        final isMoving = _movingToken == (color, t);
        final glowing = color == game.current.color && movable.contains(t);
        final z = isMoving
            ? 3
            : (glowing ? 2 : (color == game.current.color ? 1 : 0));
        layers[z].add(
          AnimatedPositioned(
            key: ValueKey('token-${color.name}-$t'),
            duration: isMoving ? _stepTime : const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            left: (pos.dx + dx) * cell - tokenSize / 2,
            top: (pos.dy + dy) * cell - tokenSize / 2,
            width: tokenSize,
            height: tokenSize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onTokenTapped(color, t),
              child: _Token(color: seatColors[color]!, glowing: glowing),
            ),
          ),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: BoardPainter()),
              ),
            ),
            for (final layer in layers) ...layer,
            Positioned(
              left: 0,
              right: 0,
              top: size * 0.44,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _toast == null ? 0 : 1,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        _toast ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Token extends StatefulWidget {
  const _Token({required this.color, required this.glowing});
  final Color color;
  final bool glowing;

  @override
  State<_Token> createState() => _TokenState();
}

class _TokenState extends State<_Token> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.glowing) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Token old) {
    super.didUpdateWidget(old);
    if (widget.glowing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.glowing && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) =>
          Transform.scale(scale: 1 + _pulse.value * 0.15, child: child),
      child: LayoutBuilder(
        builder: (context, box) {
          final s = box.maxWidth;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              border: Border.all(color: Colors.white, width: s * 0.12),
              boxShadow: [
                BoxShadow(
                  color: widget.glowing ? Colors.white : Colors.black54,
                  blurRadius: widget.glowing ? s * 0.35 : s * 0.12,
                  spreadRadius: widget.glowing ? s * 0.05 : 0,
                  offset: widget.glowing ? Offset.zero : Offset(0, s * 0.06),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: s * 0.3,
                height: s * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.18),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
