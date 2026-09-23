import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'constants/string.dart';
import 'constants/theme.dart';
import 'controllers/engine_state_controller/engine_state_controller.dart';
import 'repositories/shared_pref_repo.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPrefsRepository.initialize();
  _debugPrintSessionForPostman();
  Get.put(EngineStateController(), permanent: true);
  runApp(const MyApp());
  configLoading();
}

/// Temporary: copy Cookie / token into Postman while debugging.
void _debugPrintSessionForPostman() {
  final prefs = SharedPrefsRepository();
  final cookie = prefs.sessionCookie;
  final token = prefs.sessionToken;
  print('========== POSTMAN AUTH (debug) ==========');
  print('Cookie: ${cookie ?? '(none — log in first)'}');
  print('Session token: ${token ?? '(none — log in once to create)'}');
  if (token != null && token.isNotEmpty) {
    print('Positions with token:');
    print('GET https://my.cartag.co.za/api/positions?token=$token');
  }
  print('==========================================');
}

void configLoading() {
  EasyLoading.instance
    ..indicatorType = EasyLoadingIndicatorType.cubeGrid
    ..loadingStyle = EasyLoadingStyle.dark
    ..indicatorSize = 45.0
    ..radius = 10.0
    ..maskType = EasyLoadingMaskType.clear
    ..userInteractions = false
    ..dismissOnTap = false;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: appName,
      theme: AppTheme.lightTheme(context),
      builder: EasyLoading.init(),
      home: const SplashScreen(),
    );
  }
}
