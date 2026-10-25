import 'package:flutter/material.dart';

const _rules = [
  'Each player has 4 tokens. Be the first to bring all 4 into the centre.',
  'Roll a 6 to move a token out of the yard onto your start square. '
      'If all your tokens are in the yard and you miss a 6 three turns in a '
      'row, your next roll is a 6.',
  'Tokens move clockwise around the board, then up your coloured home '
      'column. You need the exact number to reach the centre.',
  'Land on an opponent to capture it and send it back to its yard.',
  'Start squares and star squares are safe: nobody can be captured there.',
  'Rolling a 6, capturing, or bringing a token home gives you another '
      'roll. Three 6s in a row lose the turn.',
  'Play continues until only one player is left, so everyone gets a place.',
];

Future<void> showRules(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('How to play'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rule in _rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(rule)),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('Got it'),
      ),
    ],
  ),
);
