import 'package:flutter/material.dart';

/// Borrows a controller from the editor controller or dialog state.
Widget epcrField(
  String label,
  TextEditingController controller, {
  int lines = 1,
  TextInputType keyboard = TextInputType.text,
  bool readOnly = false,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: lines,
      keyboardType: keyboard,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    ),
  );
}
