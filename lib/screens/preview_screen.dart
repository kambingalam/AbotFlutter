import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/tile_cache_service.dart';
import '../widgets/battery_optimization_dialog.dart';
import '../widgets/fade_scale_transition.dart';
import '../models/place.dart';
import '../models/trip.dart';
import '../services/haptic_service.dart';
import '../services/osrm_service.dart';
import '../services/tts_service.dart';
import '../services/trip_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_bottom_sheet.dart';
import '../widgets/primary_button.dart';
import '../widgets/trip_route_card.dart';
import 'driving_screen.dart';

class PreviewScreen extends StatefulWidget {
  final Place destination;

  const PreviewScreen({super.key, required this.destination});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final MapController _map = MapController();
  bool _loading = true;
  String? _error;
  List<Trip> _trips = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final manager = context.read<TripManager>();
    final osrm = context.read<OsrmService>();

    // Pastikan GPS ada
    if (manager.lastPosition == null) {
      try {
        await manager.gps.start();
        final pos = await manager.gps.positionStream.first.timeout(
          const Duration(seconds: 10),
        );
        manager.lastPosition = pos;
      } catch (_) {
        await HapticService.warning();
        setState(() {
          _loading = false;
          _error = 'GPS belum dapat posisi. Coba di luar ruangan.';
        });
        return;
      }
    }

    final pos = manager.lastPosition!;

    final trips = await osrm.getRoutes(
      fromLat: pos.latitude,
      fromLon: pos.longitude,
      toLat: widget.destination.lat,
      toLon: widget.destination.lon,
      destinationName:
          widget.destination.shortName ?? widget.destination.displayName,
      alternatives: 3,
    );

    if (!mounted) return;

    if (trips.isEmpty) {
      await HapticService.warning();
      setState(() {
        _loading = false;
        _error = 'Gagal hitung rute. Coba lagi.';
      });
      return;
    }

    setState(() {
      _trips = trips;
      _selectedIndex = 0;
      _loading = false;
    });

    _fitBounds(trips.first);
  }

  void _fitBounds(Trip trip) {
    if (trip.coords.isEmpty) return;

    final points = trip.coords.map((c) => LatLng(c[1], c[0])).toList();
    if (points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final bounds = LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));

    // Delay dikit biar map siap, lalu fit bounds
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      try {
        _map.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.only(
              top: 80,
              bottom: 480, // biar tidak ketutup bottom sheet
              left: 40,
              right: 40,
            ),
          ),
        );
      } catch (e) {
        debugPrint('[MAP] fitCamera error: $e');
      }
    });
  }

  void _selectRoute(int idx) {
    setState(() => _selectedIndex = idx);
    _fitBounds(_trips[idx]);
  }

  Future<void> _start({bool simulate = false}) async {
    if (_trips.isEmpty) return;
    if (!simulate) {
      await BatteryOptimizationDialog.showIfNeeded(context);
      if (!mounted) return;
    }

    final trip = _trips[_selectedIndex];

    final manager = context.read<TripManager>();
    final tts = context.read<TtsService>();

    await HapticService.tap();

    final ok = await manager.startTripWithPlan(trip);
    if (!ok || !mounted) return;

    await manager.startDriving();

    if (!mounted) return;
    await tts.speakTripStart(trip.destinationName);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      FadeScalePageRoute(page: DrivingScreen(simulate: simulate)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          // PETA
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: LatLng(
                widget.destination.lat,
                widget.destination.lon,
              ),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile-a.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.abot_drivers',
                maxZoom: 19,
                tileProvider: TileCacheService.tileProvider,
              ),

              // Rute alternatif (tidak terpilih = abu-abu)
              if (_trips.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (var i = 0; i < _trips.length; i++)
                      if (i != _selectedIndex)
                        Polyline(
                          points: _trips[i].coords
                              .map((c) => LatLng(c[1], c[0]))
                              .toList(),
                          strokeWidth: 4,
                          color: onSurface.withValues(alpha: 0.3),
                        ),
                  ],
                ),

              // Rute terpilih
              if (_trips.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trips[_selectedIndex].coords
                          .map((c) => LatLng(c[1], c[0]))
                          .toList(),
                      strokeWidth: 7,
                      color: primary,
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      widget.destination.lat,
                      widget.destination.lon,
                    ),
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on,
                      color: AppColors.destination,
                      size: 44,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Container(
                decoration: BoxDecoration(
                  color: surface,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.card,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    await HapticService.tap();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ),

          // Bottom sheet animated
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBottomSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tujuan
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppColors.destination,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.destination.shortName ??
                              widget.destination.displayName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // List rute
                  if (_loading)
                    Column(
                      children: List.generate(3, (i) => _RouteCardSkeleton()),
                    )
                  else if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.destination,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.destination,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(
                      _trips.length,
                      (i) => TripRouteCard(
                        trip: _trips[i],
                        selected: i == _selectedIndex,
                        onTap: () => _selectRoute(i),
                      ),
                    ),

                  const SizedBox(height: AppSpacing.lg),

                  // Tombol Mulai Trip
                  PrimaryButton(
                    label: 'Mulai Trip',
                    icon: Icons.navigation,
                    onPressed: _loading || _error != null || _trips.isEmpty
                        ? null
                        : () => _start(simulate: false),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Tombol Simulasi
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading || _error != null || _trips.isEmpty
                          ? null
                          : () => _start(simulate: true),
                      icon: const Icon(Icons.smart_toy, size: 20),
                      label: const Text('Simulasi Perjalanan'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.orange.shade800,
                        side: BorderSide(color: Colors.orange.shade800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteCardSkeleton extends StatefulWidget {
  @override
  State<_RouteCardSkeleton> createState() => _RouteCardSkeletonState();
}

class _RouteCardSkeletonState extends State<_RouteCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: onSurface.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _shimmerGradient(onSurface),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: _shimmerGradient(onSurface),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: _shimmerGradient(onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  LinearGradient _shimmerGradient(Color onSurface) {
    return LinearGradient(
      colors: [
        onSurface.withValues(alpha: 0.06),
        onSurface.withValues(alpha: 0.14),
        onSurface.withValues(alpha: 0.06),
      ],
      stops: [
        (_controller.value - 0.3).clamp(0.0, 1.0),
        _controller.value,
        (_controller.value + 0.3).clamp(0.0, 1.0),
      ],
    );
  }
}
