import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';
import '../services/history_service.dart';
import '../services/search_service.dart';
import '../services/voice_search_service.dart';
import '../theme/app_theme.dart';
import '../widgets/search_empty_state.dart';
import '../widgets/search_skeleton.dart';
import '../widgets/voice_search_button.dart';

class SearchScreen extends StatefulWidget {
  final Position? currentPosition;

  const SearchScreen({super.key, this.currentPosition});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _search = SearchService();
  final _history = HistoryService();
  final _voice = VoiceSearchService();

  Timer? _debounce;

  List<Place> _results = [];
  List<Place> _historyList = [];

  bool _loading = false;
  bool _listening = false;
  bool _disposed = false;

  String _lastQuery = '';

  @override
  void initState() {
    super.initState();

    _controller.addListener(_onTextChanged);

    _loadHistory();
    _initVoice();
  }

  // ============================================================
  // VOICE INITIALIZATION
  // ============================================================

  Future<void> _initVoice() async {
    _voice.onListeningChanged = (listening) {
      debugPrint('[SEARCH] listening changed: $listening');

      if (!mounted) return;
      if (_disposed) return;

      if (_listening != listening) {
        setState(() => _listening = listening);
      }
    };

    _voice.onFinalResult = (text) {
      if (!mounted) return;
      if (_disposed) return;

      final recognizedText = text.trim();
      if (recognizedText.isEmpty) return;

      debugPrint('[SEARCH] voice final result: "$recognizedText"');

      // Masukkan hasil suara setelah sesi pengenalan selesai.
      _controller.removeListener(_onTextChanged);

      _controller.value = TextEditingValue(
        text: recognizedText,
        selection: TextSelection.collapsed(offset: recognizedText.length),
      );

      _controller.addListener(_onTextChanged);

      // Paksa pencarian baru meskipun teksnya sama.
      _lastQuery = '';
      _onTextChanged();
    };

    _voice.onError = (message) {
      debugPrint('[SEARCH] voice error: $message');

      if (!mounted) return;
      if (_disposed) return;

      setState(() => _listening = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    };

    final available = await _voice.init();

    debugPrint('[SEARCH] voice initialized: $available');
  }

  // ============================================================
  // VOICE BUTTON
  // ============================================================

  Future<void> _toggleVoice() async {
    if (!mounted) return;
    if (_disposed) return;

    debugPrint('[SEARCH] toggle voice: listening=$_listening');

    if (_listening) {
      // Service akan mengatur status listening.
      await _voice.stop();
      return;
    }

    _debounce?.cancel();

    _controller.clear();
    _lastQuery = '';

    setState(() {
      _results = [];
      _loading = false;
    });

    // Tunggu callback onListeningChanged dari service.
    final started = await _voice.start();

    debugPrint('[SEARCH] voice start returned: $started');

    if (!mounted) return;
    if (_disposed) return;

    if (!started) {
      setState(() => _listening = false);
    }
  }

  // ============================================================
  // SEARCH HISTORY
  // ============================================================

  Future<void> _loadHistory() async {
    final history = await _history.getHistory();

    if (!mounted) return;
    if (_disposed) return;

    setState(() {
      _historyList = history;
    });
  }

  // ============================================================
  // TEXT CHANGE & SEARCH
  // ============================================================

  void _onTextChanged() {
    if (!mounted) return;
    if (_disposed) return;

    final query = _controller.text.trim();

    if (query == _lastQuery) return;

    _lastQuery = query;
    _debounce?.cancel();

    if (query.length < 3) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _doSearch(query),
    );
  }

  Future<void> _doSearch(String query) async {
    if (!mounted) return;
    if (_disposed) return;

    try {
      final results = await _search.search(
        query,
        nearLat: widget.currentPosition?.latitude,
        nearLon: widget.currentPosition?.longitude,
      );

      if (!mounted) return;
      if (_disposed) return;

      // Abaikan hasil lama jika query sudah berubah.
      if (_controller.text.trim() != query) return;

      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('[SEARCH] search error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      if (_disposed) return;

      setState(() {
        _results = [];
        _loading = false;
      });
    }
  }

  // ============================================================
  // SELECT PLACE
  // ============================================================

  Future<void> _selectPlace(Place place) async {
    await _history.add(place);

    // Pemeriksaan mounted harus berdiri sendiri setelah await.
    if (!mounted) return;
    if (_disposed) return;

    Navigator.of(context).pop(place);
  }

  Future<void> _clearHistory() async {
    await _history.clear();
    await _loadHistory();
  }

  IconData _iconFor(Place place) {
    final name = place.shortName?.toLowerCase() ?? '';

    if (name.contains('jalan') || name.contains('jl')) {
      return Icons.add_road;
    }

    if (name.contains('rumah') || name.contains('home')) {
      return Icons.home;
    }

    if (name.contains('kantor') || name.contains('office')) {
      return Icons.work;
    }

    if (name.contains('mall') || name.contains('plaza')) {
      return Icons.shopping_bag;
    }

    if (place.type == 'house' || place.type == 'building') {
      return Icons.home;
    }

    if (place.type == 'street') {
      return Icons.add_road;
    }

    if (place.type == 'city') {
      return Icons.location_city;
    }

    return Icons.location_on;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = colorScheme.surface;
    final onSurface = colorScheme.onSurface;

    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: onSurface),
                    onPressed: () async {
                      if (_listening) {
                        await _voice.cancel();
                      }

                      if (!context.mounted) return;

                      Navigator.pop(context);
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: false,
                      style: TextStyle(color: onSurface),
                      decoration: InputDecoration(
                        hintText: _listening
                            ? 'Mendengarkan...'
                            : 'Telusuri di sini',
                        prefixIcon: Icon(
                          Icons.search,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close, color: onSurface),
                                onPressed: () {
                                  _controller.clear();
                                  _lastQuery = '';

                                  setState(() {
                                    _results = [];
                                    _loading = false;
                                  });
                                },
                              )
                            : VoiceSearchButton(
                                listening: _listening,
                                onTap: _toggleVoice,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const SearchSkeleton(itemCount: 5)
                  : _results.isNotEmpty
                  ? _buildResults(onSurface)
                  : _controller.text.trim().length >= 3
                  ? SearchEmptyState(
                      onRetry: () => _doSearch(_controller.text.trim()),
                    )
                  : _buildHistory(onSurface),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEARCH RESULTS
  // ============================================================

  Widget _buildResults(Color onSurface) {
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, index) {
        final place = _results[index];

        return _StaggeredFadeIn(
          key: ValueKey('${place.displayName}_${place.shortName}'),
          index: index,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: onSurface.withValues(alpha: 0.1),
              child: Icon(_iconFor(place), color: AppColors.primary),
            ),
            title: Text(
              place.shortName ?? place.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: onSurface),
            ),
            subtitle: Text(
              place.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.7),
              ),
            ),
            onTap: () => _selectPlace(place),
          ),
        );
      },
    );
  }

  // ============================================================
  // SEARCH HISTORY
  // ============================================================

  Widget _buildHistory(Color onSurface) {
    if (_historyList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Belum ada riwayat',
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                'Terbaru',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: onSurface,
                ),
              ),
              const Spacer(),
              TextButton(onPressed: _clearHistory, child: const Text('Hapus')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _historyList.length,
            itemBuilder: (_, index) {
              final place = _historyList[index];

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: onSurface.withValues(alpha: 0.1),
                  child: const Icon(Icons.history, color: AppColors.primary),
                ),
                title: Text(
                  place.shortName ?? place.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
                subtitle: Text(
                  place.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.7),
                  ),
                ),
                onTap: () => _selectPlace(place),
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _disposed = true;

    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);

    _voice.dispose();
    _controller.dispose();

    super.dispose();
  }
}

// ============================================================
// STAGGERED FADE IN
// ============================================================

class _StaggeredFadeIn extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggeredFadeIn({super.key, required this.index, required this.child});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    final delay = (widget.index * 40).clamp(0, 400);

    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
