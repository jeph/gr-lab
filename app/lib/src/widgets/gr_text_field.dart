import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:grphoto/src/theme/tokens.dart';
import 'package:intl/intl.dart';

/// One line of text to type: a filled box with the radius of the cards'
/// inner tiles, edged and haloed in the accent while it has focus. With a
/// [maxLength] it shows how much of it is used at its trailing edge, in
/// the monospace of the camera's readouts, instead of Material's counter
/// under the field.
class GrTextField extends StatefulWidget {
  const new({
    required this.controller,
    super.key,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// The most characters the field takes; no limit when null.
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<GrTextField> createState() => _GrTextFieldState();
}

class _GrTextFieldState extends State<GrTextField> {
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final maxLength = widget.maxLength;
    final radius = BorderRadius.circular(GrRadii.md);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (_focus.hasFocus) BoxShadow(color: c.accentSoft, spreadRadius: 4),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        maxLength: maxLength,
        inputFormatters: widget.inputFormatters,
        textCapitalization: widget.textCapitalization,
        onSubmitted: widget.onSubmitted,
        cursorColor: c.accent,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: c.t1,
        ),
        buildCounter: _noCounter,
        decoration: InputDecoration(
          filled: true,
          fillColor: c.s2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: c.line2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: c.accent, width: 2),
          ),
          suffixIcon: maxLength == null
              ? null
              : _Used(controller: widget.controller, maxLength: maxLength),
          suffixIconConstraints: const BoxConstraints(),
        ),
      ),
    );
  }

  /// The count is in the field ([_Used]), so nothing goes under it.
  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}

/// How many of [maxLength] characters [controller]'s text uses.
class _Used extends StatelessWidget {
  const new({required this.controller, required this.maxLength});

  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 14),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Text(
          '${number.format(controller.text.characters.length)}'
          '/${number.format(maxLength)}',
          style: GrFonts.monoStyle(
            context,
            size: 11.5,
            color: GrColors.of(context).t3,
          ),
        ),
      ),
    );
  }
}
