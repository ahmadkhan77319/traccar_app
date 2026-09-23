import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart' hide Response;
import '../../model/user_model/user_model.dart';
import '../../repositories/apis.dart';
import '../../repositories/network_client_repo.dart';
import '../../repositories/shared_pref_repo.dart';
import '../../ui screens/dashboard/dashboard_screen.dart';
import '../../ui screens/login_screen/login_screen.dart';
import '../../utills/common.dart';
import '../../utills/custom_snackbar.dart';
import '../../utills/logging.dart';

class AuthController extends GetxController {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final SharedPrefsRepository sharedPrefsRepository = SharedPrefsRepository();
  late final RequestClient _requestClient = RequestClient(
    sharedPrefsRepository: sharedPrefsRepository,
  );

  final isPasswordVisible = false.obs;
  final currentUser = Rxn<UserModel>();

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  Future<bool> login(BuildContext context) async {
    try {
      EasyLoading.show(status: 'Signing in...');

      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      final response = await _requestClient.request<Response>(
        url: AppUrl.session,
        method: RequestType.post,
        body: <String, dynamic>{
          'email': email,
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, dynamic>{
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      final data = response.data;
      Logger.success(data.toString());

      final user = UserModel.fromJson(
        Map<String, dynamic>.from(data as Map),
      );

      final cookie = sharedPrefsRepository.sessionCookie ?? '';
      await sharedPrefsRepository.saveAuth(
        email: email,
        password: password,
        sessionCookie: cookie,
        user: user,
      );

      // Best-effort long-lived token for session restore
      try {
        final tokenResponse = await _requestClient.request<Response>(
          url: AppUrl.sessionToken,
          method: RequestType.post,
          body: <String, dynamic>{},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
          ),
        );
        final token = tokenResponse.data?.toString();
        if (token != null && token.isNotEmpty) {
          await sharedPrefsRepository.setSessionToken(token);
          print('========== POSTMAN AUTH (after login) ==========');
          print('Cookie: ${sharedPrefsRepository.sessionCookie}');
          print('Session token: $token');
          print(
            'GET https://my.cartag.co.za/api/positions?token=$token',
          );
          print('================================================');
        }
      } catch (_) {
        // Token generation is optional
      }

      currentUser.value = user;
      emailController.clear();
      passwordController.clear();

      snackBarCustom(
        title: 'Welcome',
        message: 'Signed in as ${user.name ?? user.email ?? email}',
        type: SnackBarType.success,
      );

      Get.offAll(() => const DashboardScreen());
      return true;
    } on DioException catch (e) {
      if (context.mounted) {
        Common.showDioErrorDialog(context, e: e);
      }
      return false;
    } catch (error) {
      Logger.error(error.toString());
      snackBarCustom(
        title: 'Error',
        message: error.toString(),
        type: SnackBarType.error,
      );
      return false;
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<bool> restoreSession() async {
    try {
      final token = sharedPrefsRepository.sessionToken;
      if (token != null && token.isNotEmpty) {
        final response = await _requestClient.request<Response>(
          url: AppUrl.session,
          method: RequestType.get,
          queryParameters: {'token': token},
        );
        final user = UserModel.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
        currentUser.value = user;
        return true;
      }

      // Fallback: re-login with stored credentials
      final email = sharedPrefsRepository.email;
      final password = sharedPrefsRepository.password;
      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        return false;
      }

      final response = await _requestClient.request<Response>(
        url: AppUrl.session,
        method: RequestType.post,
        body: <String, dynamic>{
          'email': email,
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, dynamic>{
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      final user = UserModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      currentUser.value = user;
      await sharedPrefsRepository.saveAuth(
        email: email,
        password: password,
        sessionCookie: sharedPrefsRepository.sessionCookie ?? '',
        user: user,
      );
      return true;
    } catch (e) {
      Logger.error('Session restore failed: $e');
      await sharedPrefsRepository.clearUserData();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      EasyLoading.show(status: 'Signing out...');
      try {
        await _requestClient.request(
          url: AppUrl.session,
          method: RequestType.delete,
        );
      } catch (_) {}
      await sharedPrefsRepository.clearUserData();
      currentUser.value = null;
      Get.offAll(() => LoginScreen());
    } finally {
      EasyLoading.dismiss();
    }
  }

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
