import 'package:flutter/material.dart';

import '../core/api.dart';
import 'rider_theme.dart';

/// Delivery report built from the authenticated rider history API.
class RiderReportsScreen extends StatefulWidget {
  const RiderReportsScreen({super.key});

  @override
  State<RiderReportsScreen> createState() => _RiderReportsScreenState();
}

class _RiderReportsScreenState extends State<RiderReportsScreen> {
  static const _periods = ['This Week', 'This Month', 'This Year'];
  int _period = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _asList(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : <Map<String, dynamic>>[];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await Api.I.history();
      if (!mounted) return;
      setState(() {
        _items = _asList(response['items']);
        _summary = response['summary'] is Map
            ? Map<String, dynamic>.from(response['summary'] as Map)
            : {};
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load delivery reports. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  DateTime? _deliveredAt(Map<String, dynamic> item) {
    for (final key in const ['delivered_at', 'completed_at']) {
      final raw = item[key]?.toString();
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  List<Map<String, dynamic>> get _periodItems {
    final now = DateTime.now();
    final start = switch (_period) {
      0 => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1)),
      1 => DateTime(now.year, now.month),
      _ => DateTime(now.year),
    };
    return _items.where((item) {
      if (item['status']?.toString() != 'delivered') return false;
      final date = _deliveredAt(item);
      return date != null && !date.isBefore(start) && !date.isAfter(now);
    }).toList();
  }

  double? _distanceOf(Map<String, dynamic> item) {
    final value = item['distance_km'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  List<int> get _trendCounts {
    final now = DateTime.now();
    final start = _period == 0
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1))
        : _period == 1
        ? DateTime(now.year, now.month)
        : DateTime(now.year);
    final buckets = _period == 0
        ? 7
        : _period == 1
        ? (DateTime(now.year, now.month + 1, 0).day <= 28 ? 4 : 5)
        : 12;
    return List<int>.generate(buckets, (index) {
      final from = switch (_period) {
        0 => start.add(Duration(days: index)),
        1 => DateTime(now.year, now.month, 1 + index * 7),
        _ => DateTime(now.year, index + 1),
      };
      final to = switch (_period) {
        0 => from.add(const Duration(days: 1)),
        1 =>
          index == buckets - 1
              ? DateTime(now.year, now.month + 1)
              : DateTime(now.year, now.month, 1 + (index + 1) * 7),
        _ => DateTime(now.year, index + 2),
      };
      return _periodItems.where((item) {
        final date = _deliveredAt(item);
        return date != null && !date.isBefore(from) && date.isBefore(to);
      }).length;
    }, growable: false);
  }

  List<String> get _trendLabels {
    if (_period == 0) {
      return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    }
    if (_period == 1) {
      return List.generate(_trendCounts.length, (index) => 'W${index + 1}');
    }
    return const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
  }

  String get _trendCaption => switch (_period) {
    0 => 'Deliveries by day this week',
    1 => 'Recent weekly delivery trend this month',
    _ => 'Delivery trend across this year',
  };

  @override
  Widget build(BuildContext context) {
    final deliveries = _periodItems;
    final distanceValues = deliveries.map(_distanceOf).toList();
    final hasDistance = distanceValues.every((value) => value != null);
    final distance = hasDistance
        ? distanceValues.fold<double>(0, (sum, value) => sum + value!)
        : null;
    final trend = _trendCounts;
    final hasTimestamps = _items.any((item) => _deliveredAt(item) != null);

    return RiderVisualTheme(
      child: Scaffold(
        appBar: RiderAppBar(
          title: 'Delivery Reports',
          actions: [
            IconButton(
              tooltip: 'Refresh report',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RiderImageBackground(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      if (_error != null) _errorCard(context, _error!),
                      _periodSelector(context),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _metric(
                              context,
                              'Deliveries',
                              '${deliveries.length}',
                              Icons.inventory_2_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metric(
                              context,
                              'Distance',
                              distance == null
                                  ? '—'
                                  : '${distance.toStringAsFixed(2)} km',
                              Icons.route_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metric(
                              context,
                              'Online time',
                              'Not tracked',
                              Icons.schedule_rounded,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.bar_chart_rounded,
                                    color: riderAccent(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Delivery trend',
                                      style: TextStyle(
                                        color: riderPrimaryText(context),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _trendCaption,
                                style: TextStyle(
                                  color: riderSecondaryText(context),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (!hasTimestamps)
                                _emptyTrend(
                                  context,
                                  'Delivery dates are not available from the history API yet.',
                                )
                              else
                                _chart(context, trend),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.emoji_events_outlined,
                                color: riderGold,
                                size: 30,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      deliveries.isEmpty
                                          ? 'Keep going!'
                                          : 'Great work!',
                                      style: TextStyle(
                                        color: riderPrimaryText(context),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      deliveries.isEmpty
                                          ? 'Completed deliveries for this period will appear here.'
                                          : 'You completed ${deliveries.length} deliveries in this period.',
                                      style: TextStyle(
                                        color: riderSecondaryText(context),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!hasTimestamps) ...[
                        const SizedBox(height: 10),
                        Text(
                          'This report uses the latest delivery history provided by the server. Online time is not currently recorded.',
                          style: TextStyle(
                            color: riderSecondaryText(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_summary.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'All-time total: ${_summary['total_deliveries'] ?? 0} completed deliveries · ${_summary['total_km'] ?? 0} km',
                          style: TextStyle(
                            color: riderSecondaryText(context),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _periodSelector(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: List.generate(_periods.length, (index) {
          final selected = _period == index;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: selected,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _period = index),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: selected ? riderCoffee : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _periods[index],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : riderPrimaryText(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool compact = false,
  }) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(7, 13, 7, 12),
      child: Column(
        children: [
          Icon(icon, color: riderAccent(context), size: 22),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: riderPrimaryText(context),
                fontSize: compact ? 12 : 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: riderSecondaryText(context),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _chart(BuildContext context, List<int> counts) {
    final maxCount = counts.fold<int>(
      0,
      (maxValue, value) => value > maxValue ? value : maxValue,
    );
    final labels = _trendLabels;
    return SizedBox(
      height: 145,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(counts.length, (index) {
          final count = counts[index];
          final height = maxCount == 0 ? 4.0 : 18 + 70 * count / maxCount;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      color: riderPrimaryText(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: count == 0
                          ? Theme.of(context).colorScheme.outlineVariant
                          : riderCoffee,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    style: TextStyle(
                      color: riderSecondaryText(context),
                      fontSize: counts.length > 7 ? 8 : 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _emptyTrend(BuildContext context, String message) => Container(
    height: 115,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: riderSecondaryText(context)),
    ),
  );

  Widget _errorCard(BuildContext context, String message) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}
