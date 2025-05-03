import 'package:flutter/material.dart';

import '../models/vault_group.dart';
import '../state/vault_state.dart';
import '../theme/spacing.dart';
import 'search_bar.dart';

class GroupTree extends StatefulWidget {
 final List<VaultGroup> groups;
 final VaultGroup? selectedGroup;
 final void Function(VaultGroup) onGroupSelected;
 final VaultState vaultState;

 const GroupTree({
 super.key,
 required this.groups,
 this.selectedGroup,
 required this.onGroupSelected,
 required this.vaultState,
 });

 @override
 State<GroupTree> createState() => _GroupTreeState();
}

class _GroupTreeState extends State<GroupTree> {
 final Set<String> _expanded = {};

 @override
 void initState() {
 super.initState();
 for (final group in widget.groups) {
 if (group.children.isNotEmpty) {
 _expanded.add(group.uuid);
 }
 }
 }

 List<_FlatGroupNode> _flatten(
 List<VaultGroup> groups,
 int depth,
 ) {
 final result = <_FlatGroupNode>[];
 for (final group in groups) {
 result.add(_FlatGroupNode(group: group, depth: depth));
 if (_expanded.contains(group.uuid) && group.children.isNotEmpty) {
 result.addAll(_flatten(group.children, depth + 1));
 }
 }
 return result;
 }

 void _toggleExpanded(VaultGroup group) {
 setState(() {
 if (_expanded.contains(group.uuid)) {
 _expanded.remove(group.uuid);
 } else {
 _expanded.add(group.uuid);
 }
 });
 }

 @override
 Widget build(BuildContext context) {
 final nodes = _flatten(widget.groups, 0);

 return Column(
 children: [
 VaultSearchBar(
 vaultState: widget.vaultState,
 enabled: widget.vaultState.allEntriesCached,
 ),
 Expanded(
 child: ListView.builder(
 itemCount: nodes.length,
 itemBuilder: (context, index) {
 final node = nodes[index];
 return _GroupTile(
 group: node.group,
 depth: node.depth,
 isSelected: widget.selectedGroup?.uuid == node.group.uuid,
 isExpanded: _expanded.contains(node.group.uuid),
 hasChildren: node.group.children.isNotEmpty,
 onTap: () => widget.onGroupSelected(node.group),
 onToggleExpand: () => _toggleExpanded(node.group),
 );
 },
 ),
 ),
 ],
 );
 }
}

class _FlatGroupNode {
 final VaultGroup group;
 final int depth;

 _FlatGroupNode({required this.group, required this.depth});
}

class _GroupTile extends StatelessWidget {
 final VaultGroup group;
 final int depth;
 final bool isSelected;
 final bool isExpanded;
 final bool hasChildren;
 final VoidCallback onTap;
 final VoidCallback onToggleExpand;

 const _GroupTile({
 required this.group,
 required this.depth,
 required this.isSelected,
 required this.isExpanded,
 required this.hasChildren,
 required this.onTap,
 required this.onToggleExpand,
 });

 @override
 Widget build(BuildContext context) {
 final colorScheme = Theme.of(context).colorScheme;
 final textTheme = Theme.of(context).textTheme;
 final indent = Spacing.lg * depth;

 return Material(
 color: isSelected
 ? colorScheme.primary.withValues(alpha: 0.12)
 : Colors.transparent,
 child: InkWell(
 onTap: onTap,
 hoverColor: colorScheme.surfaceContainerHighest,
 child: Padding(
 padding: EdgeInsets.only(
 left: Spacing.md + indent,
 right: Spacing.sm,
 top: Spacing.sm,
 bottom: Spacing.sm,
 ),
 child: Row(
 children: [
 if (hasChildren)
 GestureDetector(
 onTap: onToggleExpand,
 child: Icon(
 isExpanded
 ? Icons.expand_more
 : Icons.chevron_right,
 size: 20,
 color: colorScheme.onSurface,
 ),
 )
 else
 const SizedBox(width: 20),
 const SizedBox(width: Spacing.xs),
 Icon(
 Icons.folder,
 size: 20,
 color: isSelected
 ? colorScheme.primary
 : colorScheme.onSurface,
 ),
 const SizedBox(width: Spacing.sm),
 Expanded(
 child: Text(
 group.name,
 style: textTheme.titleMedium?.copyWith(
 color: isSelected
 ? colorScheme.primary
 : colorScheme.onSurface,
 ),
 overflow: TextOverflow.ellipsis,
 ),
 ),
 ],
 ),
 ),
 ),
 );
 }
}
