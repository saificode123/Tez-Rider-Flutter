import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RiderAssignmentController extends GetxController {
  final supabase = Supabase.instance.client;
  
  @override
  void onInit() {
    super.onInit();
    _listenToAssignments();
  }

  void _listenToAssignments() {
    final riderId = supabase.auth.currentUser?.id;
    if (riderId == null) return;

    supabase
        .from('rider_assignments')
        .stream(primaryKey: ['id'])
        .eq('rider_id', riderId)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isNotEmpty) {
            final latestAssignment = data.last;
            
            if (latestAssignment['status'] == 'Pending') {
              _showNewOrderDialog(latestAssignment);
            }
          }
        });
  }

  void _showNewOrderDialog(Map<String, dynamic> assignment) {
    Get.defaultDialog(
      title: "New Delivery Request! ⚡",
      middleText: "A customer is nearby. Fare: RS ${assignment['fare']}",
      textConfirm: "Accept",
      textCancel: "Decline",
      confirmTextColor: Colors.white,
      onConfirm: () => _updateAssignmentStatus(assignment['id'], 'Accepted'),
    );
  }

  Future<void> _updateAssignmentStatus(int id, String status) async {
    await supabase
        .from('rider_assignments')
        .update({'status': status})
        .match({'id': id});
    Get.back(); // Close dialog
  }
}