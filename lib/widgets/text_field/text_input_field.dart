import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../../constants/color.dart';

class TextInputFieldWidget extends StatelessWidget {
  const TextInputFieldWidget({
    super.key,
    this.controller,
    this.hintText,
    this.obscure = false,
    this.textInputType,
    this.validators,
    this.suffixIcon,
    this.prefixIcon,
    this.isLableRequired = false,
    this.title,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String? hintText;
  final bool obscure;
  final TextInputType? textInputType;
  final String? Function(String?)? validators;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool isLableRequired;
  final String? title;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLableRequired)
          Text(
            title ?? '',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: kDarkGreyColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
          ),
        if (isLableRequired) const Gap(6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: textInputType,
          validator: validators,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
