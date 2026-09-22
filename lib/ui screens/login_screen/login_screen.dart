import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../constants/color.dart';
import '../../constants/string.dart';
import '../../controllers/auth_controller/auth_controller.dart';
import '../../widgets/buttons/custom_button.dart';
import '../../widgets/form_validation/form_validation.dart';
import '../../widgets/text_field/text_input_field.dart';

class LoginScreen extends StatelessWidget {
  LoginScreen({super.key});

  final AuthController controller = Get.put(AuthController(), permanent: true);
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 48),
                      Image.asset(
                        'assets/brand/cartag_wordmark.png',
                        height: 48,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Fleet tracking made simple',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.15,
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 150,
                        ),
                        child: Align(
                          alignment: const Alignment(0, -0.35),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    26,
                                    22,
                                    24,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0A2540)
                                            .withValues(alpha: 0.04),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Sign in',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          height: 1.2,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Access your vehicles, live locations, and engine controls in one place.',
                                        style: TextStyle(
                                          color: AppColors.textSecondary
                                              .withValues(alpha: 0.95),
                                          fontSize: 13.5,
                                          height: 1.45,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      TextInputFieldWidget(
                                        title: email,
                                        controller: controller.emailController,
                                        hintText: enterYourEmail,
                                        textInputType:
                                            TextInputType.emailAddress,
                                        isLableRequired: true,
                                        prefixIcon: Icon(
                                          Icons.mail_outline_rounded,
                                          size: 18,
                                          color: AppColors.textSecondary
                                              .withValues(alpha: 0.8),
                                        ),
                                        validators:
                                            emailOrUsernameValidator().call,
                                      ),
                                      const SizedBox(height: 14),
                                      Obx(
                                        () => TextInputFieldWidget(
                                          title: password,
                                          controller:
                                              controller.passwordController,
                                          hintText: enterYourPassword,
                                          obscure: !controller
                                              .isPasswordVisible.value,
                                          isLableRequired: true,
                                          prefixIcon: Icon(
                                            Icons.lock_outline_rounded,
                                            size: 18,
                                            color: AppColors.textSecondary
                                                .withValues(alpha: 0.8),
                                          ),
                                          validators: passwordValidator().call,
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              controller
                                                      .isPasswordVisible.value
                                                  ? Icons
                                                      .visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              size: 18,
                                              color: AppColors.textSecondary,
                                            ),
                                            onPressed: controller
                                                .togglePasswordVisibility,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 26),
                                      CustomButton(
                                        text: login,
                                        onTap: () {
                                          if (formKey.currentState!
                                              .validate()) {
                                            controller.login(context);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Use the email and password provided with your CarTag account.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppColors.textSecondary
                                              .withValues(alpha: 0.75),
                                          fontSize: 12,
                                          height: 1.4,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Your session is protected. Always sign out on shared devices.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textSecondary
                                        .withValues(alpha: 0.65),
                                    fontSize: 12,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
