// 移動ルートの地図（OpenStreetMap）
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';

class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.trip, this.height = 220, this.follow = false});

  final Trip trip;
  final double height;

  /// 記録中は最後の点を中心に表示する
  final bool follow;

  @override
  Widget build(BuildContext context) {
    final pts = trip.route.map((p) => LatLng(p.lat, p.lng)).toList();
    final s = trip.startPlace;
    final e = trip.endPlace;
    if (pts.isEmpty && s.lat != null) pts.add(LatLng(s.lat!, s.lng!));
    if (pts.isEmpty) {
      return Container(
        height: height,
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Text('位置情報がありません'),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final MapOptions options;
    if (follow || pts.length < 2) {
      options = MapOptions(initialCenter: pts.last, initialZoom: 15);
    } else {
      options = MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: pts,
          padding: const EdgeInsets.all(32),
          maxZoom: 16,
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          key: ValueKey('${trip.id}-${follow ? pts.length : 0}'),
          options: options,
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'app.farelog.fare_log',
            ),
            if (pts.length >= 2)
              PolylineLayer(polylines: [
                Polyline(points: pts, strokeWidth: 5, color: scheme.primary),
              ]),
            MarkerLayer(markers: [
              Marker(
                point: pts.first,
                width: 28,
                height: 28,
                child: const Icon(Icons.trip_origin, color: Colors.green, size: 24),
              ),
              if (!trip.isRecording && e.lat != null)
                Marker(
                  point: LatLng(e.lat!, e.lng!),
                  width: 32,
                  height: 32,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                ),
              if (trip.isRecording)
                Marker(
                  point: pts.last,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
            ]),
            const RichAttributionWidget(
              attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
            ),
          ],
        ),
      ),
    );
  }
}
