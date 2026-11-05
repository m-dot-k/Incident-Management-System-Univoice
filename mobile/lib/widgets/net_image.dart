import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api.dart';
import '../theme.dart';

// Фото с сервера: ссылки вида /attachments/{id} защищены, поэтому нужен токен
class NetImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  const NetImage(this.path, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) => Image.network(
        '$baseUrl$path',
        headers: Api.token == null ? null : {'Authorization': 'Bearer ${Api.token}'},
        fit: fit,
        frameBuilder: (_, child, frame, sync) => sync
            ? child
            : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), child: child),
        loadingBuilder: (_, child, p) =>
            p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: kMuted)),
      );
}

void openPhoto(BuildContext context, String path) {
  Navigator.push(
    context,
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, _, __) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Hero(tag: path, child: InteractiveViewer(child: NetImage(path, fit: BoxFit.contain))),
          ),
        ),
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}
