import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/product_image_service.dart';

/// Existing catalogue URLs remain compatible. Validated references are fetched
/// through live authorization and decoded in memory, never the disk image cache.
class ProductImage extends StatefulWidget {
  const ProductImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.service,
    this.accountChanges,
  });
  final String imageUrl;
  final double? width, height;
  final BoxFit? fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final ProductImageService? service;
  final Stream<void>? accountChanges;
  @override
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  Uint8List? bytes;
  Timer? expiry;
  Object? error;
  int generation = 0;
  late final service = widget.service ?? ProductImageService();
  StreamSubscription<void>? auth;
  @override
  void initState() {
    super.initState();
    listenAuth();
    if (isProductImage(widget.imageUrl)) load();
  }

  void listenAuth() {
    if (auth != null || !isProductImage(widget.imageUrl)) return;
    auth =
        (widget.accountChanges ??
                (widget.service != null
                    ? const Stream<void>.empty()
                    : Supabase.instance.client.auth.onAuthStateChange.map(
                        (_) {},
                      )))
            .listen((_) {
              if (isProductImage(widget.imageUrl)) load();
            });
  }

  void clear() {
    expiry?.cancel();
    final previous = bytes;
    bytes = null;
    if (previous != null) unawaited(MemoryImage(previous).evict());
  }

  Future<void> load() async {
    final request = ++generation;
    clear();
    if (mounted) setState(() => error = null);
    try {
      final value = await service.read(widget.imageUrl);
      if (mounted && request == generation) {
        setState(() => bytes = value.bytes);
        expiry = Timer(Duration(seconds: value.expiresIn), () {
          if (mounted && request == generation) {
            clear();
            setState(
              () => error = StateError('Image viewing session expired. Retry.'),
            );
          }
        });
      }
    } catch (failure) {
      if (mounted && request == generation) setState(() => error = failure);
    }
  }

  @override
  void didUpdateWidget(ProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    listenAuth();
    if (oldWidget.imageUrl != widget.imageUrl) {
      ++generation;
      clear();
      if (isProductImage(widget.imageUrl)) load();
    }
  }

  @override
  void dispose() {
    ++generation;
    clear();
    unawaited(auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isProductImage(widget.imageUrl)) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: widget.placeholder,
        errorWidget: widget.errorWidget,
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: bytes != null
          ? Image.memory(
              bytes!,
              fit: widget.fit,
              gaplessPlayback: false,
              errorBuilder: (context, failure, stack) =>
                  failed(context, failure),
            )
          : error != null
          ? failed(context, error!)
          : widget.placeholder?.call(context, widget.imageUrl) ??
                const Center(child: CircularProgressIndicator()),
    );
  }

  Widget failed(BuildContext context, Object failure) => Semantics(
    label: 'Retry product image',
    button: true,
    child: GestureDetector(
      onTap: load,
      child:
          widget.errorWidget?.call(context, widget.imageUrl, failure) ??
          const Center(child: Icon(Icons.broken_image_outlined)),
    ),
  );
}
