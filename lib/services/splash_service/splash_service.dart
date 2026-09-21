import 'package:get/get.dart';
import '../../repositories/shared_pref_repo.dart';
import '../../ui screens/dashboard/dashboard_screen.dart';
import '../../ui screens/login_screen/login_screen.dart';
import '../../controllers/auth_controller/auth_controller.dart';

class SplashServices {
  final SharedPrefsRepository userPreference = SharedPrefsRepository();

  void isLogin() {
    Future.delayed(Duration.zero, () async {
      final authController = Get.put(AuthController(), permanent: true);

      if (userPreference.isLoggedIn) {
        final restored = await authController.restoreSession();
        if (restored) {
          Get.offAll(() => const DashboardScreen());
          return;
        }
      }

      Get.offAll(() => LoginScreen());
    });
  }
}
