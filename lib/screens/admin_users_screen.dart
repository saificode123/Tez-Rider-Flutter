import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../theme/app_theme.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminController controller;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    controller = Get.find<AdminController>();
    search.text = controller.searchText.value;
    unawaited(controller.loadManagedUsers());
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> confirm(Map<String, dynamic> user) async {
    if (controller.userAction.value != null || user['role'] == 'admin') return;
    final pending = user['operation_id'] is String;
    final blocked = pending
        ? user['desired_blocked'] == true
        : user['is_blocked'] != true;
    final approved = await Get.dialog<bool>(
      AlertDialog(
        title: Text(
          pending
              ? "Retry account synchronization?".tr
              : blocked
              ? "Block this user?".tr
              : "Unblock this user?".tr,
        ),
        content: Text(
          pending
              ? "The account remains blocked until Auth synchronization is confirmed. Retry the existing operation."
                    .tr
              : blocked
              ? "This user will lose protected access and be signed out. Existing orders will remain unchanged."
                    .tr
              : "Restore account access after Auth synchronization. Riders will remain offline."
                    .tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text("Cancel".tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text(
              pending
                  ? "Retry synchronization".tr
                  : blocked
                  ? "Block user".tr
                  : "Unblock user".tr,
            ),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final result = await controller.changeManagedUser(user, blocked);
    if (!mounted || result == null) return;
    final active = result['active_orders'];
    if (active is Map &&
        active['order_ids'] is List &&
        (active['order_ids'] as List).isNotEmpty) {
      await Get.dialog(
        AlertDialog(
          title: Text("Existing orders need attention".tr),
          content: Text(
            "@slot0end@slot1end in-progress orders were identified. Their state and assignments were preserved. Review them before taking further operational action."
                .uiTr({
                  "slot0end": ((active['order_ids'] as List).length).toString(),
                  "slot1end": (active['more_than_twenty'] == true ? '+' : '')
                      .toString(),
                }),
          ),
          actions: [
            TextButton(onPressed: Get.back, child: Text("Understood".tr)),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: Text("Manage Users".tr)),
      body: Obx(
        () => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    maxLength: 80,
                    onChanged: controller.searchUsers,
                    decoration: InputDecoration(
                      labelText: "Search name or email".tr,
                      prefixIcon: Icon(Icons.search),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: controller.roleFilter.value ?? 'all',
                          decoration: InputDecoration(labelText: "Role".tr),
                          items:
                              const [
                                    'all',
                                    'customer',
                                    'vendor',
                                    'rider',
                                    'admin',
                                  ]
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                        v == 'all'
                                            ? "All roles".tr
                                            : v.capitalizeFirst!.tr,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => controller.filterUsers(
                            role: v == 'all' ? null : v,
                            blocked: controller.blockedFilter.value,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: controller.blockedFilter.value == null
                              ? 'all'
                              : controller.blockedFilter.value!
                              ? 'blocked'
                              : 'active',
                          decoration: InputDecoration(labelText: "Status".tr),
                          items: [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text("All statuses".tr),
                            ),
                            DropdownMenuItem(
                              value: 'active',
                              child: Text("Active".tr),
                            ),
                            DropdownMenuItem(
                              value: 'blocked',
                              child: Text("Blocked".tr),
                            ),
                          ],
                          onChanged: (v) => controller.filterUsers(
                            role: controller.roleFilter.value,
                            blocked: v == 'all' ? null : v == 'blocked',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (controller.userActionMessage.value != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  controller.userActionMessage.value!.uiMessage,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (controller.usersError.value != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(controller.usersError.value!.uiMessage),
                    TextButton(
                      onPressed: () => controller.loadManagedUsers(),
                      child: Text("Retry".tr),
                    ),
                  ],
                ),
              ),
            if (controller.usersLoading.value) const LinearProgressIndicator(),
            Expanded(
              child:
                  controller.managedUsers.isEmpty &&
                      !controller.usersLoading.value
                  ? Center(child: Text("No matching accounts.".tr))
                  : RefreshIndicator(
                      onRefresh: controller.loadManagedUsers,
                      child: ListView.builder(
                        itemCount:
                            controller.managedUsers.length +
                            (controller.usersMore.value ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == controller.managedUsers.length) {
                            return TextButton(
                              onPressed: controller.usersLoading.value
                                  ? null
                                  : () => controller.loadManagedUsers(
                                      append: true,
                                    ),
                              child: Text("Load more users".tr),
                            );
                          }
                          final user = controller.managedUsers[index];
                          final blocked = user['is_blocked'] == true;
                          final pending = user['operation_id'] is String;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (user['name'] as String?)?.isNotEmpty ==
                                            true
                                        ? user['name'] as String
                                        : "Unnamed account".tr,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(user['email'] as String? ?? ''),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      user['role'].toString().tr,
                                      (blocked ? 'Blocked' : 'Active').tr,
                                      if (pending) 'Sync pending'.tr,
                                    ].join(' · '),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed:
                                          controller.userAction.value != null ||
                                              user['role'] == 'admin'
                                          ? null
                                          : () => confirm(user),
                                      child: Text(
                                        controller.userAction.value ==
                                                user['id']
                                            ? "Working…".tr
                                            : user['role'] == 'admin'
                                            ? "Admin protected".tr
                                            : pending
                                            ? "Retry synchronization".tr
                                            : blocked
                                            ? "Unblock".tr
                                            : "Block".tr,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
