import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `slider` section — a swipeable image carousel built from a link group.
///
/// Data source: `GET /api/links/by-group-key/{linkGroupKey}`.
/// Config: `linkGroupKey` (required), `autoplay?`, `interval?` (seconds).
class SliderSection extends StatefulWidget {
  const SliderSection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<SliderSection> createState() => _SliderSectionState();
}

class _SliderSectionState extends State<SliderSection> {
  final _controller = PageController();
  late Future<List<LinkItem>> _future;
  Timer? _timer;
  int _page = 0;
  List<LinkItem> _items = const [];

  @override
  void initState() {
    super.initState();
    final key = widget.section.linkGroupKey;
    _future = (key == null || key.isEmpty)
        ? Future.value(const <LinkItem>[])
        : widget.api.linksByGroup(key);
  }

  void _startAutoplay() {
    _timer?.cancel();
    if (!widget.section.autoplay || _items.length < 2) return;
    final seconds = widget.section.interval.clamp(2, 30).toInt();
    _timer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!_controller.hasClients) return;
      _page = (_page + 1) % _items.length;
      _controller.animateToPage(
        _page,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _open(LinkItem item) async {
    if (item.url.isEmpty) return;
    final uri = Uri.tryParse(item.url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: widget.section.title),
        FutureBuilder<List<LinkItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SectionStatus.loading(height: 180);
            }
            final items = snap.data ?? const <LinkItem>[];
            if (items.isEmpty) return const SizedBox.shrink();

            // Cache + (re)start autoplay once data is available.
            if (!identical(items, _items)) {
              _items = items;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _startAutoplay());
            }

            return Column(
              children: [
                SizedBox(
                  height: 180,
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemCount: items.length,
                    itemBuilder: (context, i) =>
                        _Slide(item: items[i], onTap: () => _open(items[i])),
                  ),
                ),
                const SizedBox(height: 8),
                _Dots(count: items.length, active: _page),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.item, required this.onTap});

  final LinkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: item.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: Colors.black12),
                  errorWidget: (_, __, ___) =>
                      Container(color: Colors.black12, child: const Icon(Icons.image)),
                )
              else
                Container(color: Theme.of(context).colorScheme.primaryContainer),
              if (item.title.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == active ? color : color.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
