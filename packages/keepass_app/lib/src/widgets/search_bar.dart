import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/vault_state.dart';
import '../theme/spacing.dart';

/// Global search bar for vault entries with 300ms debounce.
///
/// Positioned above the group tree in the sidebar (D-09).
/// Searches title, username, and URL across all entries.
class VaultSearchBar extends StatefulWidget {
  /// Vault state to drive search queries.
  final VaultState vaultState;

  /// Whether search is available (false while entry cache is loading).
  final bool enabled;

  const VaultSearchBar({
    super.key,
    required this.vaultState,
    this.enabled = true,
  });

  @override
  State<VaultSearchBar> createState() => _VaultSearchBarState();
}

class _VaultSearchBarState extends State<VaultSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.vaultState.search(value);
    });
  }

  void _clearSearch() {
    _controller.clear();
    _debounce?.cancel();
    widget.vaultState.clearSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _clearSearch();
          }
        },
        child: TextField(
          controller: _controller,
          enabled: widget.enabled,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: widget.enabled
                ? 'Search entries...'
                : 'Search loading...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear search',
                    onPressed: _clearSearch,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            isDense: true,
          ),
        ),
      ),
    );
  }
}
