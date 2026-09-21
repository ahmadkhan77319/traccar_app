import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../constants/color.dart';

void snackBarCustom({
  required String title,
  required String message,
  required SnackBarType type,
}) {
  final Color backgroundColor;
  switch (type) {
    case SnackBarType.success:
      backgroundColor = AppColors.primary;
      break;
    case SnackBarType.error:
      backgroundColor = kRedColor;
      break;
  }

  Get.snackbar(
    title,
    message,
    backgroundColor: backgroundColor,
    colorText: kWhiteColor,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    borderRadius: 12,
    margin: const EdgeInsets.all(10),
    animationDuration: const Duration(milliseconds: 250),
    titleText: Text(
      title,
      style: const TextStyle(
        color: kWhiteColor,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    ),
    messageText: Text(
      message,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}

enum SnackBarType { success, error }
