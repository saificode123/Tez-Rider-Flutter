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
              ? 'Retry account synchronization?'
              : blocked
              ? 'Block this user?'
              : 'Unblock this user?',
        ),
        content: Text(
          pending
              ? 'The account remains blocked until Auth synchronization is confirmed. Retry the existing operation.'
              : blocked
              ? 'This user will lose protected access and be signed out. Existing orders will remain unchanged.'
              : 'Restore account access after Auth synchronization. Riders will remain offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text(
              pending
                  ? 'Retry synchronization'
                  : blocked
                  ? 'Block user'
                  : 'Unblock user',
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
          title: const Text('Existing orders need attention'),
          content: Text(
            '${(active['order_ids'] as List).length}${active['more_than_twenty'] == true ? '+' : ''} in-progress orders were identified. Their state and assignments were preserved. Review them before taking further operational action.',
          ),
          actions: [
            TextButton(onPressed: Get.back, child: const Text('Understood')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgLight,
    appBar: AppBar(title: const Text('Manage Users')),
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
                  decoration: const InputDecoration(
                    labelText: 'Search name or email',
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
                        decoration: const InputDecoration(labelText: 'Role'),
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
                                          ? 'All roles'
                                          : v.capitalizeFirst!,
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
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All statuses'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'blocked',
                            child: Text('Blocked'),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                controller.userActionMessage.value!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (controller.usersError.value != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(controller.usersError.value!),
                  TextButton(
                    onPressed: () => controller.loadManagedUsers(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (controller.usersLoading.value) const LinearProgressIndicator(),
          Expanded(
            child:
                controller.managedUsers.isEmpty &&
                    !controller.usersLoading.value
                ? const Center(child: Text('No matching accounts.'))
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
                                : () =>
                                      controller.loadManagedUsers(append: true),
                            child: const Text('Load more users'),
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
                                  (user['name'] as String?)?.isNotEmpty == true
                                      ? user['name'] as String
                                      : 'Unnamed account',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(user['email'] as String? ?? ''),
                                const SizedBox(height: 6),
                                Text(
                                  '${user['role']} · ${blocked ? 'Blocked' : 'Active'}${pending ? ' · Sync pending' : ''}',
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
                                      controller.userAction.value == user['id']
                                          ? 'Working…'
                                          : user['role'] == 'admin'
                                          ? 'Admin protected'
                                          : pending
                                          ? 'Retry synchronization'
                                          : blocked
                                          ? 'Unblock'
                                          : 'Block',
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
