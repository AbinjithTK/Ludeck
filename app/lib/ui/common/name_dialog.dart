import 'package:flutter/material.dart';

import '../../data/repository.dart';

/// Asks for a short name and returns it trimmed, or null on cancel/empty.
///
/// The dialog owns its [TextEditingController] inside a State and disposes it
/// in `State.dispose`, i.e. only once the route has finished animating out and
/// the TextField is unmounted. Disposing a caller-owned controller right after
/// `await showDialog` returns crashed the app on device with
/// `'_dependents.isEmpty': is not true`: the future completes when the route
/// pops, while the TextField is still mounted for the exit animation.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String? hint,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => NameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initial: initial,
      hint: hint,
    ),
  );
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.initial = '',
    this.hint,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? hint;

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: Repository.maxNameLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
