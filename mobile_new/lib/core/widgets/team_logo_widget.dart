import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_constants.dart';

class _SvgWithFallback extends StatelessWidget {
  final String url;
  final double size;
  const _SvgWithFallback({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholderBuilder: (_) =>
          Icon(Icons.sports_soccer_rounded, size: size * 0.85),
      // Intercepte les SVG invalides silencieusement
      errorBuilder: (_, _, _) =>
          Icon(Icons.sports_soccer_rounded, size: size * 0.85),
    );
  }
}

// Proxie les images via le backend pour éviter les blocages réseau sur l'émulateur
String _proxyUrl(String url) {
  if (url.startsWith('https://crests.football-data.org/')) {
    final base = AppConstants.baseUrl.replaceFirst('/api/v1', '');
    return '$base/api/img?url=${Uri.encodeComponent(url)}';
  }
  return url;
}

class TeamLogoWidget extends StatelessWidget {
  final String? url;
  final double size;

  const TeamLogoWidget({super.key, required this.url, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final raw = url ?? '';
    if (raw.isEmpty) {
      return Icon(Icons.sports_soccer_rounded, size: size * 0.85);
    }
    final proxied = _proxyUrl(raw);
    Widget img;
    if (proxied.toLowerCase().contains('.svg') || raw.toLowerCase().endsWith('.svg')) {
      img = _SvgWithFallback(url: proxied, size: size);
    } else {
      // Décodage à la taille d'affichage. Sans `memCacheWidth`, un écusson de
      // 512 px occupait un mégaoctet de bitmap pour être peint dans un rond de
      // vingt-quatre — et une liste de matchs en affiche des dizaines.
      final densite = MediaQuery.devicePixelRatioOf(context);
      final pixels  = (size * densite).round();

      img = CachedNetworkImage(
        imageUrl: proxied,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth:  pixels,
        memCacheHeight: pixels,
        placeholder: (_, _) =>
            Icon(Icons.sports_soccer_rounded, size: size * 0.85),
        errorWidget: (_, _, _) =>
            Icon(Icons.sports_soccer_rounded, size: size * 0.85),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: img),
    );
  }
}
