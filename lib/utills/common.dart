import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../utills/logging.dart';

class Common {
  static void showDioErrorDialog(
    BuildContext context, {
    required DioException e,
  }) {
    showAdaptiveDialog(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(e.response?.statusMessage ?? 'Oops!'),
        content: Text(getErrorMsgOfDio(e)),
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Get.back(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  static String getErrorMsgOfDio(DioException e) {
    try {
      Logger.error(
        'Status Code: ${e.response?.statusCode}, Error: $e, Response: ${e.response?.data}',
      );

      if (e.response?.statusCode == 401) {
        return 'Invalid email or password. Please try again.';
      }

      final data = e.response?.data;
      if (data is String && data.isNotEmpty) return data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }

      return e.message ?? 'Something went wrong. Please try again.';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  static String formatRelativeTime(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final diff = DateTime.now().difference(dateTime.toLocal());
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '—';
    final local = dateTime.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $h:$m:$s';
  }
}
