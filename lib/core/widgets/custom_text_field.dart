import 'package:flutter/material.dart';

class CustomTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color? accentColor;
  final bool isPassword;
  final String? Function(String?)? validator;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.accentColor,
    this.isPassword = false,
    this.validator,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? Colors.cyanAccent;

    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword && _obscureText,
      validator: widget.validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(widget.icon, color: color),
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white54,
                ),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : null,
        hintText: widget.hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white12,
        border: _buildBorder(color.withOpacity(0.2)),
        enabledBorder: _buildBorder(color.withOpacity(0.2)),
        focusedBorder: _buildBorder(color.withOpacity(0.5), width: 1.4),
        errorBorder: _buildBorder(Colors.redAccent),
        focusedErrorBorder: _buildBorder(Colors.redAccent, width: 1.4),
      ),
    );
  }

  OutlineInputBorder _buildBorder(Color color, {double width = 1.0}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
