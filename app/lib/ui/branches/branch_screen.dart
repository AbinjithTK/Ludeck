// Branches: the user's own grouping of the collection.
//
// This is "organize" in the Gaming criterion. Everything here writes through
// LudeckStore, which re-reads after every change, so the list on screen is always
// what is stored rather than an optimistic guess.
//
// Two decisions shape the screen:
//
// Reorder has a non-drag path. Drag and drop is the least accessible interaction
// there is: it needs a sustained press, a steady hand, and sight of where the
// item is going. The drag handle stays for people who want it, and every row's
// menu also carries "Move up" and "Move down", which work with a screen reader
// and with one unsteady tap.
//
// Delete says what happens to the games, in the dialog, before the button. A
// branch is a container; emptying it does not destroy what was in it. A user who
// suspects otherwise will simply never delete a branch, and will end up with a
// list they cannot tidy.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/ludeck_store.dart';
import '../tokens.dart';

class BranchScreen extends StatelessWidget {
  const BranchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LudeckStore>();
    final branches = store.branches;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tokens.palette.bg,
        title: Text('Branches', style: Theme.of(context).textTheme.titleMedium),
        actions: [
          IconButton(
            // Tooltip doubles as the screen-reader label, so it has to read as
            // an action rather than a noun.
            tooltip: 'New branch',
            icon: Icon(Icons.add, color: Tokens.palette.text),
            onPressed: () => _createBranch(context, store),
          ),
        ],
      ),
      body: branches.isEmpty
          ? _Empty(onCreate: () => _createBranch(context, store))
          : _BranchList(store: store, branches: branches),
    );
  }
}

/// Shown when there are no branches, which is the state of every new install.
///
/// It explains what a branch IS rather than just offering a button. "No branches
/// yet" with a plus tells someone who has never seen the concept nothing about
/// whether they want one.
class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Tokens.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No branches yet.',
                style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: Tokens.space.sm),
            Text(
              'A branch is your own grouping. Short evenings, games to finish '
              'this year, whatever you actually think in. Until you make one, '
              'the collection is grouped by how far you got.',
              style: TextStyle(
                  fontSize: Tokens.type.body, color: Tokens.palette.text),
            ),
            SizedBox(height: Tokens.space.lg),
            TextButton(
              onPressed: onCreate,
              child: Text('Make one',
                  style: TextStyle(color: Tokens.palette.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchList extends StatelessWidget {
  const _BranchList({required this.store, required this.branches});

  final LudeckStore store;
  final List<Branch> branches;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: EdgeInsets.symmetric(
          horizontal: Tokens.space.md, vertical: Tokens.space.sm),
      itemCount: branches.length,
      // The handle is explicit rather than the whole row being draggable: a row
      // that starts dragging on a long press would collide with its own menu.
      buildDefaultDragHandles: false,
      onReorder: (from, to) {
        // ReorderableListView reports the destination as an insertion index in
        // the PRE-removal list, so moving an item down overshoots by one.
        final ids = branches.map((b) => b.id).toList();
        final target = to > from ? to - 1 : to;
        final id = ids.removeAt(from);
        ids.insert(target, id);
        store.reorderBranches(ids);
      },
      itemBuilder: (context, index) {
        final branch = branches[index];
        return _BranchRow(
          key: ValueKey(branch.id),
          store: store,
          branch: branch,
          index: index,
          total: branches.length,
          gameCount: (store.placements[branch.id] ?? const []).length,
        );
      },
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    super.key,
    required this.store,
    required this.branch,
    required this.index,
    required this.total,
    required this.gameCount,
  });

  final LudeckStore store;
  final Branch branch;
  final int index;
  final int total;
  final int gameCount;

  @override
  Widget build(BuildContext context) {
    final countLabel = gameCount == 1 ? '1 game' : '$gameCount games';

    return Padding(
      padding: EdgeInsets.only(bottom: Tokens.space.xs),
      child: Material(
        color: Tokens.palette.surface,
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Tokens.space.sm, vertical: Tokens.space.xs),
          child: Row(
            children: [
              // Position is announced, because "row 2 of 5" is the only way a
              // screen-reader user can tell whether a move landed.
              Expanded(
                child: Semantics(
                  label: '${branch.name}, $countLabel, '
                      '${index + 1} of $total',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        branch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: Tokens.type.body,
                          color: Tokens.palette.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: Tokens.space.xxs),
                      Text(
                        countLabel,
                        style: TextStyle(
                          fontSize: Tokens.type.caption,
                          color: Tokens.palette.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _RowMenu(
                store: store,
                branch: branch,
                index: index,
                total: total,
                gameCount: gameCount,
              ),
              // Touch reorder, for people who prefer it. Excluded from semantics
              // because the menu already offers Move up and Move down, and a
              // screen reader announcing an unusable drag handle is noise.
              ExcludeSemantics(
                child: ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: EdgeInsets.all(Tokens.space.xs),
                    child: Icon(Icons.drag_handle,
                        size: 20, color: Tokens.palette.textDim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RowAction { rename, moveUp, moveDown, delete }

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.store,
    required this.branch,
    required this.index,
    required this.total,
    required this.gameCount,
  });

  final LudeckStore store;
  final Branch branch;
  final int index;
  final int total;
  final int gameCount;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_RowAction>(
      tooltip: 'Options for ${branch.name}',
      icon: Icon(Icons.more_vert, size: 20, color: Tokens.palette.textDim),
      color: Tokens.palette.surface,
      onSelected: (action) => _run(context, action),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _RowAction.rename,
          child: Text('Rename',
              style: TextStyle(color: Tokens.palette.text)),
        ),
        // Offered only where they mean something. A disabled "Move up" on the
        // first row is a control that exists to do nothing.
        if (index > 0)
          PopupMenuItem(
            value: _RowAction.moveUp,
            child:
                Text('Move up', style: TextStyle(color: Tokens.palette.text)),
          ),
        if (index < total - 1)
          PopupMenuItem(
            value: _RowAction.moveDown,
            child:
                Text('Move down', style: TextStyle(color: Tokens.palette.text)),
          ),
        PopupMenuItem(
          value: _RowAction.delete,
          child: Text('Delete',
              style: TextStyle(color: Tokens.palette.danger)),
        ),
      ],
    );
  }

  void _run(BuildContext context, _RowAction action) {
    switch (action) {
      case _RowAction.rename:
        _renameBranch(context, store, branch);
      case _RowAction.moveUp:
        _move(-1);
      case _RowAction.moveDown:
        _move(1);
      case _RowAction.delete:
        _confirmDelete(context, store, branch, gameCount);
    }
  }

  void _move(int delta) {
    final ids = store.branches.map((b) => b.id).toList();
    final to = index + delta;
    if (to < 0 || to >= ids.length) return;
    final id = ids.removeAt(index);
    ids.insert(to, id);
    store.reorderBranches(ids);
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

Future<void> _createBranch(BuildContext context, LudeckStore store) async {
  final name = await _askForName(context, title: 'New branch');
  if (name == null) return;
  await store.createBranch(name);
}

Future<void> _renameBranch(
    BuildContext context, LudeckStore store, Branch branch) async {
  final name = await _askForName(
    context,
    title: 'Rename branch',
    initial: branch.name,
  );
  if (name == null) return;
  await store.renameBranch(branch.id, name);
}

/// Asks for a branch name. Returns null when cancelled.
///
/// Validates to the SAME rules the repository enforces (non-blank after
/// trimming, at most `Repository.maxNameLength`) rather than letting the write
/// throw. The repository must still refuse a bad name, because it cannot trust a
/// caller, but surfacing the refusal as a dialog error is much better than
/// surfacing it as a failed write the user has to infer.
Future<String?> _askForName(
  BuildContext context, {
  required String title,
  String? initial,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title, initial: initial),
    );

/// The name dialog, stateful so it OWNS its controller.
///
/// This is not ceremony. Disposing the controller when the dialog's future
/// completes -- the obvious `.whenComplete(controller.dispose)` -- throws "A
/// TextEditingController was used after being disposed", because the route's exit
/// animation is still rebuilding the field after the future resolves. A State's
/// dispose runs once the route is actually gone, which is the only correct moment.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Tokens.palette.surface,
      title: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: Repository.maxNameLength,
          style: TextStyle(color: Tokens.palette.text),
          decoration: InputDecoration(
            hintText: 'Short evenings',
            hintStyle: TextStyle(color: Tokens.palette.textDim),
          ),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'A branch needs a name.' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Tokens.palette.text)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Save', style: TextStyle(color: Tokens.palette.accent)),
        ),
      ],
    );
  }
}

/// Confirms a delete, and says plainly what happens to the games.
///
/// The sentence about the games is the point of this dialog, not the button. A
/// branch is a container, and someone who suspects deleting it destroys their
/// games will never delete one, which leaves them with a list they cannot tidy.
Future<void> _confirmDelete(
  BuildContext context,
  LudeckStore store,
  Branch branch,
  int gameCount,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Tokens.palette.surface,
      title: Text('Delete ${branch.name}?',
          style: Theme.of(context).textTheme.titleMedium),
      content: Text(
        gameCount == 0
            ? 'Nothing is on this branch, so nothing else changes.'
            : gameCount == 1
                ? 'The 1 game on this branch is kept. It moves to '
                    '"Not on a branch".'
                : 'The $gameCount games on this branch are kept. They move to '
                    '"Not on a branch".',
        style:
            TextStyle(fontSize: Tokens.type.body, color: Tokens.palette.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Keep it', style: TextStyle(color: Tokens.palette.text)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child:
              Text('Delete', style: TextStyle(color: Tokens.palette.danger)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await store.deleteBranch(branch.id);
}
