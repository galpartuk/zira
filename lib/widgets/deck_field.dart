import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/stats.dart';
import '../theme.dart';

/// Free-text deck name with suggestions from names already used, so the same
/// deck keeps one spelling. Saves by itself a moment after typing stops.
class DeckField extends StatefulWidget {
  final String? initial;
  final List<String> suggestions;
  final String hint;
  final ValueChanged<String> onSave;
  final bool dense;

  const DeckField({
    super.key,
    required this.initial,
    required this.suggestions,
    required this.hint,
    required this.onSave,
    this.dense = false,
  });

  @override
  State<DeckField> createState() => _DeckFieldState();
}

class _DeckFieldState extends State<DeckField> {
  Timer? _debounce;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _saved = widget.initial?.trim();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _save(v));
  }

  void _save(String v) {
    _debounce?.cancel();
    if (v.trim() == (_saved ?? '')) return;
    _saved = v.trim();
    widget.onSave(v);
  }

  TextEditingController? _ctrl;
  FocusNode? _focus;

  void _onFocus() {
    if (!(_focus?.hasFocus ?? true)) _save(_ctrl?.text ?? '');
  }

  @override
  void dispose() {
    // Leaving the screen right after typing still saves it.
    if (_debounce?.isActive ?? false) _save(_ctrl?.text ?? '');
    _debounce?.cancel();
    _focus?.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.initial ?? ''),
      optionsBuilder: (v) {
        final q = deckKey(v.text);
        return widget.suggestions.where((s) => deckKey(s) != q && (q.isEmpty || deckKey(s).contains(q)));
      },
      onSelected: _save,
      fieldViewBuilder: (context, ctrl, focus, onSubmit) {
        _ctrl = ctrl;
        if (!identical(_focus, focus)) {
          _focus?.removeListener(_onFocus);
          _focus = focus..addListener(_onFocus);
        }
        return TextField(
          controller: ctrl,
          focusNode: focus,
          onChanged: _changed,
          onSubmitted: (v) {
            _save(v);
            onSubmit();
          },
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: widget.hint,
            isDense: widget.dense,
            prefixIcon: Icon(Icons.style_outlined, size: widget.dense ? 18 : 22, color: Z.muted),
          ),
        );
      },
    );
  }
}
