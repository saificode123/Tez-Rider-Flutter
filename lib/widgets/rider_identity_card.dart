import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/order_detail_watch.dart';
import 'private_photo.dart';

typedef DeliveryIdentityRead = Future<dynamic> Function(int orderId);

class RiderIdentityCard extends StatefulWidget {
  const RiderIdentityCard({
    super.key,
    required this.orderId,
    this.read,
    this.identity,
    this.accountChanges,
    this.watch,
  });
  final int orderId;
  final DeliveryIdentityRead? read;
  final String? Function()? identity;
  final Stream<void>? accountChanges;
  final OrderDetailWatcher? watch;
  @override
  State<RiderIdentityCard> createState() => _RiderIdentityCardState();
}

class _RiderIdentityCardState extends State<RiderIdentityCard> {
  late final identity =
      widget.identity ?? (() => Supabase.instance.client.auth.currentUser?.id);
  late final account = identity();
  Map? data;
  bool loading = true;
  String? error;
  int generation = 0;
  Timer? timer;
  StreamSubscription<void>? auth;
  void Function()? stop;
  @override
  void initState() {
    super.initState();
    auth =
        (widget.accountChanges ??
                (widget.read != null
                    ? const Stream<void>.empty()
                    : Supabase.instance.client.auth.onAuthStateChange.map(
                        (_) {},
                      )))
            .listen((_) => load());
    if (widget.watch != null || widget.read == null) {
      stop = (widget.watch ?? watchOrderDetail)(widget.orderId, load);
    }
    timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
    load();
  }

  @override
  void didUpdateWidget(RiderIdentityCard old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId) {
      stop?.call();
      if (widget.watch != null || widget.read == null) {
        stop = (widget.watch ?? watchOrderDetail)(widget.orderId, load);
      }
      load();
    }
  }

  Future<void> load() async {
    if (!mounted) return;
    final request = ++generation;
    setState(() {
      data = null;
      loading = true;
      error = null;
    });
    try {
      if (account == null || identity() != account) throw StateError('account');
      final value =
          await (widget.read != null
                  ? widget.read!(widget.orderId)
                  : Supabase.instance.client.rpc(
                      'final2_customer_delivery_identity',
                      params: {'p_order_id': widget.orderId},
                    ))
              .timeout(const Duration(seconds: 15));
      if (value is! Map ||
          value['order_id'] != widget.orderId ||
          value['order_status'] is! String ||
          value['rider'] != null && value['rider'] is! Map) {
        throw const FormatException('Identity unavailable.');
      }
      final rider = value['rider'];
      if (rider != null &&
          (rider['name'] is! String ||
              rider['rating_count'] is! int ||
              rider['rating'] != null &&
                  num.tryParse(rider['rating'].toString()) == null ||
              rider['cnic_masked'] != null &&
                  (rider['cnic_masked'] is! String ||
                      !RegExp(r'[xX*•]').hasMatch(rider['cnic_masked'])))) {
        throw const FormatException('Identity not confirmed.');
      }
      if (mounted && request == generation && identity() == account) {
        setState(() => data = value);
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = 'Rider identity unavailable. Retry.');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    stop?.call();
    unawaited(auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator();
    if (data == null) {
      return Column(
        children: [
          Text(error ?? 'Rider unavailable.'),
          TextButton(
            onPressed: identity() == account ? load : null,
            child: const Text('Retry rider identity'),
          ),
        ],
      );
    }
    final rider = data!['rider'] as Map?;
    final status = data!['order_status'] as String;
    const steps = [
      'pending',
      'accepted',
      'preparing',
      'ready',
      'on_the_way',
      'delivered',
    ];
    const labels = [
      'Placed',
      'Accepted',
      'Preparing',
      'Ready',
      'On the way',
      'Delivered',
    ];
    final current = steps.indexOf(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rider == null)
          const Text('A verified Rider has not been assigned.')
        else
          Row(
            children: [
              PrivatePhoto(
                imageUrl: rider['photo'] is String ? rider['photo'] : '',
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rider['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      rider['rating'] == null
                          ? 'No ratings yet'
                          : 'Rating ${num.parse(rider['rating'].toString()).toStringAsFixed(2)} / 5 (${rider['rating_count']})',
                    ),
                    if (rider['cnic_masked'] != null)
                      Text('CNIC: ${rider['cnic_masked']}'),
                    if (rider['cnic_masked'] == null)
                      const Text('CNIC unavailable in this record.'),
                    const Text('Approved Rider'),
                  ],
                ),
              ),
            ],
          ),
        Text('Order status: ${status.replaceAll('_', ' ')}'),
        if (current >= 0)
          Wrap(
            spacing: 5,
            children: [
              for (var i = 0; i < steps.length; i++)
                Chip(
                  avatar: Icon(
                    i == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  backgroundColor: i == current
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF2F3F4),
                  label: Text(
                    labels[i],
                    style: const TextStyle(color: Color(0xFF263238)),
                  ),
                ),
            ],
          ),
        if (status == 'cancelled') const Text('Order cancelled.'),
      ],
    );
  }
}
