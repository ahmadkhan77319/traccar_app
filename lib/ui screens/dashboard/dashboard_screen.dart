import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shimmer/shimmer.dart';
import '../../constants/color.dart';
import '../../constants/string.dart';
import '../../controllers/auth_controller/auth_controller.dart';
import '../../controllers/dashboard_controller/dashboard_controller.dart';
import '../../ui screens/device_map_screen/device_map_screen.dart';
import '../../widgets/cards/device_card.dart';
import '../../widgets/cards/stat_card.dart';
import '../../widgets/dialogs/logout_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardController controller = Get.put(DashboardController());
  final AuthController authController = Get.isRegistered<AuthController>()
      ? Get.find<AuthController>()
      : Get.put(AuthController(), permanent: true);
  final RefreshController _refreshController = RefreshController();

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Obx(() {
          return Column(
            children: [
              _header(),
              Expanded(
                child: SmartRefresher(
                  controller: _refreshController,
                  onRefresh: () async {
                    await controller.fetchDashboard(showLoader: false);
                    _refreshController.refreshCompleted();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _banner(),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.45,
                        children: [
                          StatCard(
                            title: 'Total',
                            value: controller.totalCount,
                            icon: Icons.devices_rounded,
                            accentColor: AppColors.primary,
                          ),
                          StatCard(
                            title: 'Online',
                            value: controller.onlineCount,
                            icon: Icons.wifi_rounded,
                            accentColor: AppColors.success,
                          ),
                          StatCard(
                            title: 'Offline',
                            value: controller.offlineCount,
                            icon: Icons.wifi_off_rounded,
                            accentColor: AppColors.danger,
                          ),
                          StatCard(
                            title: 'Moving',
                            value: controller.movingCount,
                            icon: Icons.directions_car_rounded,
                            accentColor: kMovingColor,
                          ),
                          StatCard(
                            title: 'Idle',
                            value: controller.idleCount,
                            icon: Icons.pause_circle_outline,
                            accentColor: AppColors.info,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text(
                            'Devices',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${controller.filteredDevices.length} found',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller.searchController,
                        onChanged: controller.onSearchChanged,
                        decoration: InputDecoration(
                          hintText: searchDevices,
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: controller.searchQuery.value.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    controller.searchController.clear();
                                    controller.onSearchChanged('');
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StatusFilterBar(
                        selected: controller.selectedFilter.value,
                        onSelected: controller.setFilter,
                      ),
                      const SizedBox(height: 12),
                      if (controller.isLoading.value)
                        ...List.generate(
                          4,
                          (_) => const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: _DeviceShimmer(),
                          ),
                        )
                      else if (controller.filteredDevices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              noDevices,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        ...controller.filteredDevices.map(
                          (device) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DeviceCard(
                              device: device,
                              onTap: () => Get.to(
                                () => DeviceMapScreen(
                                  deviceId: device.id,
                                  initial: device,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text.rich(
              TextSpan(
                text: 'TRACCAR',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
                children: [
                  TextSpan(
                    text: ' FLEET',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => controller.fetchDashboard(showLoader: false),
            icon: const Icon(Icons.refresh_rounded, size: 22),
            color: AppColors.textPrimary,
          ),
          IconButton(
            onPressed: () {
              LogoutDialog.show(
                context,
                onConfirm: authController.logout,
              );
            },
            icon: const Icon(Icons.logout_rounded, size: 22),
            color: AppColors.primary,
            tooltip: logout,
          ),
        ],
      ),
    );
  }

  Widget _banner() {
    final name = authController.currentUser.value?.name ??
        authController.currentUser.value?.email ??
        'User';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -18,
            child: Icon(
              Icons.directions_car_filled_rounded,
              size: 100,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $name',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Monitor live locations, vehicle status, and engine controls from one place.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  Color _chipColor(String key) {
    switch (key) {
      case 'online':
        return AppColors.success;
      case 'offline':
        return AppColors.danger;
      case 'moving':
        return kMovingColor;
      case 'idle':
        return AppColors.info;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Filter by status',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: DashboardController.statusFilters.map((filter) {
              final key = filter['key']!;
              final label = filter['label']!;
              final isSelected = selected == key;
              final color = _chipColor(key);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: isSelected ? color : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    onTap: () => onSelected(key),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isSelected ? color : AppColors.border,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DeviceShimmer extends StatelessWidget {
  const _DeviceShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
