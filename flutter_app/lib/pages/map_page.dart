import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/ios_options.dart';

import '../app_controller.dart';
import '../core/road_graph.dart';
import '../widgets/app_theme.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/map_marker_geometry.dart';
import '../widgets/map_viewport_geometry.dart';

IconData _placeIcon(String category) => switch (category) {
  '本周活动' || '上期活动' => Icons.event_available_rounded,
  '赛事' => Icons.flag_rounded,
  '广告牌' => Icons.ad_units_rounded,
  '吉祥物' => Icons.pets_rounded,
  '地标' => Icons.landscape_rounded,
  '特技' => Icons.speed_rounded,
  '房屋' => Icons.home_rounded,
  '赛道' => Icons.sports_score_rounded,
  '车房宝物' => Icons.garage_rounded,
  '秘藏座驾' => Icons.directions_car_rounded,
  '嘉年华' => Icons.celebration_rounded,
  '拍照点' => Icons.photo_camera_rounded,
  '车聚' => Icons.groups_rounded,
  _ => Icons.place_rounded,
};

Offset _mapPixel(MapPoint p) =>
    Offset(582.896 + p.x * .046504, 499.376 - p.z * .046504);

const _customPlaceCategories = {'广告牌', '地标', '吉祥物'};
const _placeCategories = [
  '赛事',
  '广告牌',
  '吉祥物',
  '地标',
  '车房宝物',
  '秘藏座驾',
  '特技',
  '房屋',
  '嘉年华',
  '拍照点',
  '车聚',
  '其他',
  '赛道',
];

// Shared vector symbols for map pins, result lists and selection cards.
void _paintPlaceSymbol(Canvas canvas, String category, Color color) {
  switch (category) {
    case '广告牌':
      _paintBillboard(canvas, color);
    case '地标':
      _paintTokyoTower(canvas, color);
    case '吉祥物':
      _paintDango(canvas, color);
  }
}

void _paintBillboard(Canvas canvas, Color color) {
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-9, -7, 9, 4),
      const Radius.circular(1.2),
    ),
    line,
  );
  final details = Path()
    ..moveTo(-5, 4)
    ..lineTo(-5, 8)
    ..moveTo(5, 4)
    ..lineTo(5, 8)
    ..moveTo(-7, 8)
    ..lineTo(7, 8)
    // XP lettering, drawn as vectors to stay sharp at every map scale.
    ..moveTo(-6, -4)
    ..lineTo(-1, 1)
    ..moveTo(-1, -4)
    ..lineTo(-6, 1)
    ..moveTo(2, 1)
    ..lineTo(2, -4)
    ..lineTo(5, -4)
    ..quadraticBezierTo(7, -4, 7, -2.5)
    ..quadraticBezierTo(7, -1, 5, -1)
    ..lineTo(2, -1);
  canvas.drawPath(details, line);
}

void _paintTokyoTower(Canvas canvas, Color color) {
  final steel = Paint()
    ..color = const Color(0xffff8c67)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final frame = Path()
    ..moveTo(0, -10)
    ..lineTo(0, -6)
    ..moveTo(0, -7)
    ..lineTo(-3, 1)
    ..lineTo(-8, 9)
    ..moveTo(0, -7)
    ..lineTo(3, 1)
    ..lineTo(8, 9)
    ..moveTo(-3, 1)
    ..lineTo(5.5, 7)
    ..moveTo(3, 1)
    ..lineTo(-5.5, 7)
    ..moveTo(-9, 9)
    ..lineTo(-5, 9)
    ..moveTo(5, 9)
    ..lineTo(9, 9);
  canvas.drawPath(frame, steel);
  final decks = Paint()..color = Color.lerp(color, Colors.white, .85)!;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-3, -4, 3, -2),
      const Radius.circular(.5),
    ),
    decks,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-5, 0, 5, 2),
      const Radius.circular(.5),
    ),
    decks,
  );
}

void _paintDango(Canvas canvas, Color color) {
  canvas.drawLine(
    const Offset(-4.8, -9.5),
    const Offset(5, 10),
    Paint()
      ..color = const Color(0xffe5b875)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round,
  );
  const dumplings = [
    (Offset(3, 5.8), Color(0xff9ed47f)),
    (Offset(0, 0), Color(0xfffff1d8)),
    (Offset(-3, -5.8), Color(0xfff49fbd)),
  ];
  for (final (center, fill) in dumplings) {
    canvas.drawCircle(center, 3.8, Paint()..color = fill);
    canvas.drawCircle(
      center,
      3.8,
      Paint()
        ..color = color.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
    canvas.drawCircle(
      center + const Offset(-.9, -.9),
      .9,
      Paint()..color = Colors.white.withValues(alpha: .45),
    );
  }
}

class _PlaceCategoryIcon extends StatelessWidget {
  final String category;
  final Color color;
  final double size;
  const _PlaceCategoryIcon(
    this.category, {
    required this.color,
    this.size = 24,
  });
  @override
  Widget build(BuildContext context) =>
      _customPlaceCategories.contains(category)
      ? SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _PlaceSymbolPainter(category, color)),
        )
      : Icon(_placeIcon(category), color: color, size: size);
}

class _PlaceSymbolPainter extends CustomPainter {
  final String category;
  final Color color;
  const _PlaceSymbolPainter(this.category, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(math.min(size.width, size.height) / 22);
    _paintPlaceSymbol(canvas, category, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlaceSymbolPainter old) =>
      old.color != color || old.category != category;
}

class _PlaceMarker {
  final MapPlace place;
  final Offset position;
  _PlaceMarker(this.place) : position = _mapPixel(place.point);

  bool contains(Offset point, Size viewport, double zoom) =>
      MapMarkerGeometry.hitBounds(position, viewport, zoom).contains(point);
}

class MapPage extends StatefulWidget {
  final AppController app;
  const MapPage({super.key, required this.app});
  // Engine RPM and other dashboard-only samples do not change the map UI.
  static Object viewState(AppController app) {
    final n = app.navigation;
    return (
      app.roadGraph,
      app.mapFocus,
      app.weekly.content,
      app.weekly.current?.id,
      app.settings.language,
      app.mapError,
      n?.route,
      n?.destination,
      n?.location?.x,
      n?.location?.y,
      n?.location?.z,
      n?.heading,
      n?.status,
      n?.turn,
      n?.turnDistance,
      n?.remaining,
      n?.arrived,
    );
  }

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  String query = '', season = 'summer';
  // null keeps the original overview: community places, plus tracks on search.
  Set<String>? _categories;
  String get category => _categories == null
      ? '全部'
      : _categories!.length == 1
      ? _categories!.single
      : '';
  MapPlace? selected;
  bool _showWeekly = true;
  int _focusSerial = 0;
  MapPlace? _focusedWeekly;
  String? _weeklyGeneration;
  MapPlace? _pendingCenter;
  bool results = false, roads = true, follow = true;
  final transform = TransformationController();
  final _resultsGroup = Object();
  late final _pins = _MapPinAtlas(() {
    if (mounted) setState(() {});
  });
  final _markerCache = _MapMarkerCache();
  Path? _roads;
  ui.Image? _roadImage;
  int _roadGeneration = 0;
  Path? _routePath;
  NavigationRoute? _route;
  RoadGraph? _graph;
  String? _filter;
  List<MapPlace> _places = [];
  List<_PlaceMarker> _markers = [];
  ui.Picture? _scene;
  Size _sceneSize = Size.zero;
  bool _sceneRoads = true;
  Offset? _followPosition;
  Size _followSize = Size.zero;
  Size _size = Size.zero;
  bool _constrainingTransform = false;
  Timer? _returnTimer;
  late final AnimationController _returnAnimation;
  Matrix4? _returnStart;
  double _followZoom = 5;
  bool _interacting = false, _visible = true, _foreground = true;
  bool _wasNavigating = false;
  bool get _navigating => widget.app.navigation?.route != null;
  bool get _canReturn =>
      _visible &&
      _foreground &&
      _navigating &&
      !_interacting &&
      widget.app.navigation?.location != null;
  Offset pixel(MapPoint p) =>
      Offset(582.896 + p.x * .046504, 499.376 - p.z * .046504);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    transform.addListener(_constrainTransform);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _returnAnimation =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(_animateReturn)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && _canReturn) {
              setState(() {
                follow = true;
                _followPosition = null;
              });
            }
          });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible != visible) {
      _visible = visible;
      _cancelReturn();
      _interacting = false;
      _wasNavigating = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _cancelReturn();
    _interacting = false;
    setState(() => _wasNavigating = false);
  }

  void _cancelReturn() {
    _returnTimer?.cancel();
    _returnTimer = null;
    _returnAnimation.stop();
    _returnStart = null;
  }

  void _scheduleReturn() {
    _cancelReturn();
    if (!_canReturn) return;
    _returnTimer = Timer(const Duration(seconds: 3), () {
      _returnTimer = null;
      if (!mounted || !_canReturn || _size.isEmpty) return;
      _returnStart = transform.value.clone();
      _followZoom = transform.value.getMaxScaleOnAxis();
      _returnAnimation.forward(from: 0);
    });
  }

  void _animateReturn() {
    if (!_canReturn || _returnStart == null) {
      _cancelReturn();
      return;
    }
    // Resolve the latest car position every frame, including while it moves.
    final target = _centeredTransform(
      center: widget.app.navigation!.location,
      zoom: _followZoom,
    );
    transform.value = Matrix4Tween(
      begin: _returnStart,
      end: target,
    ).lerp(Curves.easeInOutCubic.transform(_returnAnimation.value));
  }

  void _syncNavigationFollow() {
    if (!_visible || !_foreground) {
      _cancelReturn();
      _wasNavigating = false;
      return;
    }
    final navigating = _navigating;
    if (navigating && !_wasNavigating) {
      _cancelReturn();
      follow = true;
      _followPosition = null;
    } else if (!navigating && _wasNavigating) {
      _cancelReturn();
    }
    _wasNavigating = navigating;
  }

  void _constrainTransform() {
    if (_constrainingTransform || _size.isEmpty) return;
    final bounded = MapViewportGeometry.constrain(transform.value, _size);
    if (bounded == transform.value) return;
    _constrainingTransform = true;
    try {
      transform.value = bounded;
    } finally {
      _constrainingTransform = false;
    }
  }

  Future<void> _showPlaceFilters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final counts = <String, int>{};
    for (final p in widget.app.roadGraph!.places) {
      counts.update(p.category, (v) => v + 1, ifAbsent: () => 1);
    }
    var draft = {...?_categories};
    if (_categories == null) {
      draft = _placeCategories.where((c) => c != '赛道').toSet();
    }
    final applied = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: Column(
              children: [
                const LText(
                  '筛选地点',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: LText('可多选，地图与列表仅显示勾选类别', textAlign: TextAlign.center),
                ),
                LiquidGlassActions(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () =>
                            update(() => draft = _placeCategories.toSet()),
                        child: const LText('全选'),
                      ),
                      TextButton(
                        onPressed: () => update(draft.clear),
                        child: const LText('清空'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: _placeCategories
                        .map(
                          (c) => CheckboxListTile(
                            key: ValueKey('place-filter-$c'),
                            secondary: _PlaceCategoryIcon(
                              c,
                              color: context.appAccent,
                            ),
                            title: Text('${context.tr(c)} · ${counts[c] ?? 0}'),
                            subtitle: c == '赛道' ? const LText('游戏赛道几何') : null,
                            value: draft.contains(c),
                            onChanged: (checked) => update(() {
                              if (checked == true) {
                                draft.add(c);
                              } else {
                                draft.remove(c);
                              }
                            }),
                          ).forPhone(context),
                        )
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: LiquidGlassActions(
                      child: FilledButton(
                        key: const ValueKey('apply-place-filters'),
                        onPressed: () => Navigator.pop(context, draft),
                        child: const LText('应用筛选'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || applied == null) return;
    _setCategories(applied, showResults: false);
  }

  void _setCategories(Set<String>? categories, {required bool showResults}) {
    setState(() {
      _categories = categories == null ? null : Set.of(categories);
      results = showResults;
      if (selected != null &&
          selected!.id != 'custom' &&
          !(categories?.contains(selected!.category) ??
              (selected!.category != '赛道' || query.isNotEmpty))) {
        selected = null;
        _pendingCenter = null;
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (_pendingCenter != null) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelReturn();
    _returnAnimation.dispose();
    transform.removeListener(_constrainTransform);
    transform.dispose();
    _roadGeneration++;
    _scene?.dispose();
    _markerCache.dispose();
    _roadImage?.dispose();
    _pins.dispose();
    super.dispose();
  }

  Matrix4 _centeredTransform({MapPoint? center, double zoom = 1}) {
    final side = math.min(_size.width, _size.height);
    final offset = Offset((_size.width - side) / 2, (_size.height - side) / 2);
    final p = center == null
        ? Offset(_size.width / 2, _size.height / 2)
        : offset + pixel(center) * (side / 1024);
    final value = Matrix4.identity()
      ..translateByDouble(
        _size.width / 2 - p.dx * zoom,
        _size.height / 2 - p.dy * zoom,
        0,
        1,
      )
      ..scaleByDouble(zoom, zoom, 1, 1);
    return MapViewportGeometry.constrain(value, _size);
  }

  void _fit({MapPoint? center, double zoom = 1}) {
    transform.value = _centeredTransform(center: center, zoom: zoom);
  }

  void _select(MapPlace p) {
    _pendingCenter = p;
    FocusScope.of(context).unfocus();
    setState(() {
      selected = p;
      results = false;
      follow = false;
    });
    _scheduleReturn();
  }

  void _selectFromList(MapPlace p) {
    _select(p);
    _pendingCenter = p;
  }

  void _centerAfterKeyboardDismissed() {
    final place = _pendingCenter;
    if (place == null || View.of(context).viewInsets.bottom != 0) return;
    // Unfocus only requests dismissal. Use the restored viewport after layout,
    // including on devices that report several keyboard animation frames.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingCenter != place) return;
      if (View.of(context).viewInsets.bottom != 0) return;
      _pendingCenter = null;
      if (selected == place && !follow) {
        // Give overview selections some context without repeatedly zooming in
        // when the same location is requested again. Keep closer user zooms.
        _fit(
          center: place.point,
          zoom: math.max(3, transform.value.getMaxScaleOnAxis()),
        );
        _scheduleReturn();
      }
    });
  }

  void _dismissResults() {
    if (!results) return;
    FocusScope.of(context).unfocus();
    setState(() => results = false);
  }

  void _selectOverlapping(List<MapPlace> places) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: places
              .map(
                (p) => ListTile(
                  leading: _PlaceCategoryIcon(
                    p.category,
                    color: context.appAccent,
                  ),
                  title: LText(widget.app.placeName(p)),
                  subtitle: LText(p.category),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _select(p);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _information() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const LText(
                '地图数据',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              const LText(
                '游戏本体 · 四季原始地图\n38,473 个道路节点 · 71,222 条有向路段\n75,626 条允许通行的路段连接',
                style: TextStyle(height: 1.8),
              ),
              const SizedBox(height: 14),
              LText(
                '170 个赛道几何起点来自游戏文件，尚未核对赛事触发点。另有 ${widget.app.roadGraph?.places.where((p) => p.quality == "community").length ?? 0} 个公开地图地点，包含赛事与收藏品，来源为 Forza Horizon Hub 等社区地图；坐标和邻近道路高度尚待游戏实测。',
                style: TextStyle(color: context.appMuted, height: 1.7),
              ),
              const SizedBox(height: 12),
              LText(
                '路线根据原始道路连接、单行线和已解析转向限制计算。底图使用图像对齐；导航坐标直接使用游戏三维坐标。尚未完成实车验证。',
                style: TextStyle(color: context.appMuted, height: 1.7),
              ),
              const SizedBox(height: 18),
              LiquidGlassActions(
                child:
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => roads = !roads);
                      },
                      icon: Icon(
                        roads
                            ? Icons.layers_clear_outlined
                            : Icons.layers_outlined,
                      ),
                      label: LText(roads ? '隐藏道路图层' : '显示道路图层'),
                    ).forChoice(
                      context,
                      roads,
                      context.tr(roads ? '隐藏道路图层' : '显示道路图层'),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncNavigationFollow();
    final app = widget.app, g = app.roadGraph, n = app.navigation;
    if (g == null) {
      return Center(
        child: app.mapError.isEmpty
            ? LText('正在读取离线地图', style: TextStyle(color: context.appMuted))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 40),
                  LText(app.mapError),
                ],
              ),
      );
    }
    if (!identical(_graph, g)) {
      _graph = g;
      _roads = _buildRoads(g);
      _prepareRoadImage();
      _filter = null;
    }
    final generation =
        '${app.weekly.content?.revision}|${app.weekly.current?.id}';
    if (_weeklyGeneration != generation) {
      _weeklyGeneration = generation;
      _focusedWeekly = null;
      if (selected?.id.startsWith('weekly:') == true) {
        MapPlace? replacement;
        for (final p in app.weekly.mapPlaces) {
          if (p.id == selected!.id) {
            replacement = p;
            break;
          }
        }
        selected = replacement;
        _pendingCenter = null;
      }
    }
    final focus = app.mapFocus;
    if (focus != null && focus.serial != _focusSerial) {
      _focusSerial = focus.serial;
      _showWeekly = true;
      _focusedWeekly = focus.place;
      selected = focus.place;
      _pendingCenter = focus.place;
      results = false;
      follow = false;
      _cancelReturn();
      FocusManager.instance.primaryFocus?.unfocus();
      _filter = null;
    }
    final categoryKey = _categories?.toList()?..sort();
    final filter =
        '${categoryKey?.join('|') ?? 'default'}\u0000$query|$_showWeekly|${app.weekly.content?.revision}|${app.weekly.current?.id}';
    if (_filter != filter) {
      _filter = filter;
      _places = g.places
          .where(
            (p) =>
                (_categories?.contains(p.category) ??
                    (p.category != '赛道' || query.isNotEmpty)) &&
                p.matchesName(query),
          )
          .toList();
      if (n?.location != null) {
        _places.sort(
          (a, b) => a.point
              .distance(n!.location!)
              .compareTo(b.point.distance(n.location!)),
        );
      }
      if (_showWeekly) {
        _places.addAll(app.weekly.mapPlaces.where((p) => p.matchesName(query)));
        if (_focusedWeekly != null &&
            !_places.any((p) => p.id == _focusedWeekly!.id)) {
          _places.add(_focusedWeekly!);
        }
      }
      _markers = _places.map(_PlaceMarker.new).toList();
    }
    final places = _places;
    // The selected pin is drawn by the overlay. Hide other pins from both
    // painting and hit testing, without changing the user's saved filters.
    final visibleMarkers = selected == null ? _markers : const <_PlaceMarker>[];
    if (!identical(_route, n?.route)) {
      _route = n?.route;
      _routePath = _route == null ? null : _buildRoute(_route!);
    }
    final active = n?.route != null;
    final glass = LiquidGlass.enabledOf(context);
    final bottomClearance = LiquidGlass.bottomClearanceOf(context);
    final mapButtonStyle = glass
        ? IconButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            backgroundColor: Colors.transparent,
            minimumSize: const Size(44, 44),
          )
        : null;
    return Column(
      children: [
        TapRegion(
          groupId: _resultsGroup,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onTap: () => setState(() => results = true),
                        onChanged: (v) => setState(() {
                          query = v;
                          results = true;
                        }),
                        decoration: InputDecoration(
                          hintText: context.tr('搜索赛道、车房与座驾'),
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: context.tr(results ? '收起地点列表' : '显示地点列表'),
                            onPressed: () => setState(() => results = !results),
                            icon: Icon(
                              results ? Icons.expand_less : Icons.list_rounded,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('地图数据说明'),
                      onPressed: _information,
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .48,
                        ),
                        child: FilterChip(
                          key: const ValueKey('map-place-filters'),
                          avatar: const Icon(
                            Icons.filter_list_rounded,
                            size: 18,
                          ),
                          label: Text(
                            '${context.tr('筛选地点')}${_categories == null ? '' : ' (${_categories!.length})'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: _categories != null,
                          showCheckmark: false,
                          onSelected: (_) => _showPlaceFilters(),
                        ).forPhone(context),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: ['全部', ..._placeCategories]
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(right: 7),
                                child: ChoiceChip(
                                  label: LText(
                                    c,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  selected: category == c,
                                  showCheckmark: false,
                                  onSelected: (_) => _setCategories(
                                    c == '全部' ? null : {c},
                                    showResults: true,
                                  ),
                                ).forPhone(context),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) {
                    if (_size != box.biggest) {
                      _size = box.biggest;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _constrainTransform();
                      });
                    }
                    _centerAfterKeyboardDismissed();
                    if (_scene == null ||
                        _sceneSize != _size ||
                        _sceneRoads != roads) {
                      _scene?.dispose();
                      _sceneSize = _size;
                      _sceneRoads = roads;
                      _scene = _recordScene(_size);
                    }
                    final position = n?.location == null
                        ? null
                        : pixel(n!.location!);
                    if (_visible &&
                        _foreground &&
                        follow &&
                        position != null &&
                        (position != _followPosition || _followSize != _size)) {
                      _followPosition = position;
                      _followSize = _size;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            _visible &&
                            _foreground &&
                            follow &&
                            widget.app.navigation?.location != null) {
                          _fit(
                            center: widget.app.navigation!.location,
                            zoom: _followZoom,
                          );
                        }
                      });
                    }
                    return InteractiveViewer(
                      transformationController: transform,
                      minScale: MapViewportGeometry.minScale(_size),
                      maxScale: math.max(
                        14,
                        MapViewportGeometry.minScale(_size),
                      ),
                      boundaryMargin: EdgeInsets.zero,
                      onInteractionStart: (_) {
                        _cancelReturn();
                        setState(() {
                          _interacting = true;
                          _pendingCenter = null;
                          follow = false;
                        });
                      },
                      onInteractionEnd: (_) {
                        _interacting = false;
                        _followZoom = transform.value.getMaxScaleOnAxis();
                        _scheduleReturn();
                      },
                      child: GestureDetector(
                        onTapUp: (d) {
                          final side = math.min(_size.width, _size.height),
                              offset = Offset(
                                (_size.width - side) / 2,
                                (_size.height - side) / 2,
                              );
                          final point =
                              (d.localPosition - offset) * (1024 / side);
                          final zoom = transform.value.getMaxScaleOnAxis();
                          final hits =
                              visibleMarkers
                                  .where(
                                    (m) =>
                                        m.place.id != selected?.id &&
                                        m.contains(point, _size, zoom),
                                  )
                                  .toList()
                                ..sort(
                                  (a, b) => (a.position - point).distance
                                      .compareTo((b.position - point).distance),
                                );
                          if (hits.isNotEmpty) {
                            if (hits.length > 1) {
                              _selectOverlapping(
                                hits.map((m) => m.place).toList(),
                              );
                            } else {
                              _select(hits.first.place);
                            }
                          }
                        },
                        onLongPressStart: (d) {
                          final side = math.min(_size.width, _size.height),
                              offset = Offset(
                                (_size.width - side) / 2,
                                (_size.height - side) / 2,
                              );
                          final p = (d.localPosition - offset) * (1024 / side),
                              world = MapPoint(
                                (p.dx - 582.896) / .046504,
                                0,
                                (499.376 - p.dy) / .046504,
                              );
                          final matches = g.nearby(
                            world,
                            altitude: false,
                            radius: 1000,
                          );
                          if (matches.isEmpty) {
                            app.notifyMessage('此处没有可导航道路');
                            return;
                          }
                          setState(() {
                            selected = MapPlace(
                              'custom',
                              '地图选点',
                              '自定义',
                              matches.first.point,
                            );
                            results = false;
                            follow = false;
                          });
                          _scheduleReturn();
                        },
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                'assets/map/map_$season.jpg',
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                              ColoredBox(
                                color: Colors.black.withValues(alpha: .22),
                              ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  isComplex: true,
                                  painter: _MapScenePainter(_scene!),
                                ),
                              ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: _MapMarkersPainter(
                                    _markerCache,
                                    visibleMarkers,
                                    _pins,
                                    transform,
                                  ),
                                ),
                              ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: _MapOverlayPainter(
                                    _pins,
                                    selected,
                                    n?.route,
                                    _routePath,
                                    n?.location,
                                    n?.heading,
                                    transform,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: context.appSurface.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: LText(
                    '游戏原图 · UDP 定位',
                    style: TextStyle(fontSize: 10, color: context.appAccent),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 12,
                child: LiquidGlassSurface(
                  capsule: true,
                  child: Padding(
                    padding: glass
                        ? const EdgeInsets.symmetric(horizontal: 2, vertical: 5)
                        : EdgeInsets.zero,
                    child: Column(
                      children: [
                        IconButton.filledTonal(
                          key: const ValueKey('weekly-map-layer'),
                          style: mapButtonStyle,
                          tooltip: context.tr(
                            _showWeekly ? '隐藏本周活动' : '显示本周活动',
                          ),
                          onPressed: () => setState(() {
                            _showWeekly = !_showWeekly;
                            if (!_showWeekly) {
                              _focusedWeekly = null;
                              if (selected?.id.startsWith('weekly:') == true) {
                                selected = null;
                                _pendingCenter = null;
                              }
                            }
                          }),
                          icon: Icon(
                            _showWeekly
                                ? Icons.event_available_rounded
                                : Icons.event_busy_rounded,
                          ),
                        ).forChoice(context, _showWeekly, 'calendar'),
                        const SizedBox(height: 6),
                        PopupMenuButton<String>(
                          tooltip: context.tr('切换季节'),
                          initialValue: season,
                          onSelected: (s) => setState(() => season = s),
                          icon: const Icon(Icons.layers_outlined),
                          style:
                              mapButtonStyle ??
                              IconButton.styleFrom(
                                backgroundColor: context.appSurface.withValues(
                                  alpha: .96,
                                ),
                              ),
                          itemBuilder: (_) =>
                              [
                                    ('summer', '夏季'),
                                    ('autumn', '秋季'),
                                    ('winter', '冬季'),
                                    ('spring', '春季'),
                                  ]
                                  .map(
                                    (s) => PopupMenuItem(
                                      value: s.$1,
                                      child: LText(s.$2),
                                    ),
                                  )
                                  .toList(),
                        ).forPhone(context, symbol: 'square.3.layers.3d'),
                        const SizedBox(height: 6),
                        IconButton.filledTonal(
                          style: mapButtonStyle,
                          tooltip: context.tr('跟随车辆'),
                          onPressed: () {
                            _cancelReturn();
                            setState(() {
                              _pendingCenter = null;
                              follow = true;
                              _followPosition = null;
                            });
                          },
                          icon: Icon(
                            follow
                                ? Icons.gps_fixed
                                : Icons.my_location_rounded,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 6),
                        IconButton.filledTonal(
                          style: mapButtonStyle,
                          tooltip: context.tr('查看全图'),
                          onPressed: () {
                            setState(() => follow = false);
                            _fit();
                            _scheduleReturn();
                          },
                          icon: const Icon(
                            Icons.open_in_full_rounded,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (results)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('map-results-dismiss'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _dismissResults,
                  ),
                ),
              if (results)
                Positioned(
                  top: 60,
                  left: 16,
                  right: 64,
                  bottom: 20 + bottomClearance,
                  child: TapRegion(
                    groupId: _resultsGroup,
                    onTapOutside: (_) => _dismissResults(),
                    child: Material(
                      color: context.appSurface.withValues(alpha: .96),
                      shape: context.panelShape(18),
                      clipBehavior: Clip.antiAlias,
                      child: places.isEmpty
                          ? Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: LText(
                                  '没有找到匹配地点\n可以更换类别或搜索名称',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.appMuted,
                                    height: 1.8,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: places.length,
                              itemBuilder: (context, i) {
                                final p = places[i];
                                return ListTile(
                                  dense: true,
                                  leading: _PlaceCategoryIcon(
                                    p.category,
                                    color: context.appAccent,
                                    size: 20,
                                  ),
                                  title: LText(
                                    app.placeName(p),
                                    maxLines: 2,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  subtitle: LText(
                                    '${n?.location == null ? '' : '直线 ${mapDistance(p.point.distance(n!.location!))} · '}${p.quality == 'community' ? '社区坐标 · 待实测' : '游戏赛道几何'}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: context.appMuted,
                                    ),
                                  ),
                                  onTap: () => _selectFromList(p),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              if (!results)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14 + bottomClearance,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: ShapeDecoration(
                      color: context.appSurface.withValues(alpha: .96),
                      shape: context.panelShape(
                        21,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (active &&
                            (selected == null ||
                                selected!.id == n?.destination?.id)) ...[
                          Row(
                            children: [
                              Icon(
                                n!.turn > 0
                                    ? Icons.turn_right_rounded
                                    : n.turn < 0
                                    ? Icons.turn_left_rounded
                                    : n.arrived
                                    ? Icons.flag_rounded
                                    : Icons.straight_rounded,
                                color: context.appAccent,
                                size: 34,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LText(
                                      '${mapDistance(n.turnDistance)} · ${n.instruction}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    LText(
                                      '${mapDistance(n.remaining)} 剩余 · ${n.status}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: context.appMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: context.tr('结束导航'),
                                onPressed: app.stopNavigation,
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LText(
                            app.placeName(n.destination!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ] else if (selected != null) ...[
                          Row(
                            children: [
                              _PlaceCategoryIcon(
                                selected!.category,
                                color: context.appAccent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: LText(
                                  app.placeName(selected!),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: context.tr('取消选点'),
                                onPressed: () =>
                                    setState(() => selected = null),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ],
                          ),
                          LText(
                            selected!.note,
                            style: TextStyle(
                              color: context.appMuted,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                  ),
                                  onPressed: () => app.navigateTo(selected!),
                                  icon: const Icon(
                                    Icons.navigation_rounded,
                                    size: 17,
                                  ),
                                  label: const LText(
                                    '导航到这里',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const LText(
                            '探索地平线',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          LText(
                            '点击地点或长按地图，规划你的下一段旅程',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LText(
                            n?.status ?? '定位中',
                            style: TextStyle(
                              fontSize: 10,
                              color: context.appAccent,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => results = true),
                            icon: const Icon(Icons.explore_outlined, size: 18),
                            label: LText('浏览 ${places.length} 个地点'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  ui.Picture _recordScene(Size size) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _mapCanvas(canvas, size);
    if (roads && _roadImage != null) {
      canvas.drawImageRect(
        _roadImage!,
        const Rect.fromLTWH(0, 0, 2048, 2048),
        const Rect.fromLTWH(0, 0, 1024, 1024),
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    return recorder.endRecording();
  }

  Future<void> _prepareRoadImage() async {
    final generation = ++_roadGeneration;
    _roadImage?.dispose();
    _roadImage = null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    canvas.drawPath(
      _roads!,
      Paint()
        ..color = const Color(0x99c9d4bd)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(2048, 2048);
      if (!mounted || generation != _roadGeneration) {
        image.dispose();
        return;
      }
      setState(() {
        _roadImage = image;
        _scene?.dispose();
        _scene = null;
      });
    } finally {
      picture.dispose();
    }
  }

  Path _buildRoute(NavigationRoute route) {
    final path = Path();
    final first = pixel(route.points.first);
    path.moveTo(first.dx, first.dy);
    for (final point in route.points.skip(1)) {
      final p = pixel(point);
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  Path _buildRoads(RoadGraph g) {
    final path = Path(), seen = <(int, int)>{};
    for (final s in g.segments) {
      final key = (math.min(s.from, s.to), math.max(s.from, s.to));
      if (!seen.add(key)) continue;
      final a = pixel(g.points[s.from]), b = pixel(g.points[s.to]);
      path.moveTo(a.dx, a.dy);
      path.lineTo(b.dx, b.dy);
    }
    return path;
  }
}

Color _placeColor(String category) => switch (category) {
  '本周活动' || '上期活动' => const Color(0xff65d8ff),
  '赛事' || '赛道' => const Color(0xffeeeede),
  '广告牌' => const Color(0xffffb05e),
  '吉祥物' => const Color(0xfff38bcc),
  '地标' => const Color(0xff7edbd1),
  '车房宝物' || '秘藏座驾' => const Color(0xffffd66d),
  _ => const Color(0xffb2bdd6),
};

void _mapCanvas(Canvas canvas, Size size) {
  final side = math.min(size.width, size.height);
  canvas.translate((size.width - side) / 2, (size.height - side) / 2);
  canvas.scale(side / 1024);
}

class _MapScenePainter extends CustomPainter {
  final ui.Picture scene;
  const _MapScenePainter(this.scene);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPicture(scene);
  @override
  bool shouldRepaint(covariant _MapScenePainter old) => old.scene != scene;
}

class _MapMarkerCache {
  ui.Picture? _picture;
  List<_PlaceMarker>? _markers;
  Size? _size;
  double? _zoom;
  int _atlasRevision = -1;

  ui.Picture picture(
    List<_PlaceMarker> markers,
    Size size,
    double zoom,
    _MapPinAtlas pins,
  ) {
    if (_picture == null ||
        !identical(markers, _markers) ||
        size != _size ||
        zoom != _zoom ||
        _atlasRevision != pins.revision) {
      _picture?.dispose();
      _markers = markers;
      _size = size;
      _zoom = zoom;
      _atlasRevision = pins.revision;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      _mapCanvas(canvas, size);
      final unit = MapMarkerGeometry.unit(size, zoom);
      for (final marker in markers) {
        pins.paint(
          canvas,
          marker.position,
          unit,
          _placeIcon(marker.place.category),
          _placeColor(marker.place.category),
        );
      }
      _picture = recorder.endRecording();
    }
    return _picture!;
  }

  void dispose() => _picture?.dispose();
}

class _MapMarkersPainter extends CustomPainter {
  final _MapMarkerCache cache;
  final List<_PlaceMarker> markers;
  final _MapPinAtlas pins;
  final TransformationController transform;
  final int atlasRevision;
  _MapMarkersPainter(this.cache, this.markers, this.pins, this.transform)
    : atlasRevision = pins.revision,
      super(repaint: transform);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPicture(
    cache.picture(markers, size, transform.value.getMaxScaleOnAxis(), pins),
  );
  @override
  bool shouldRepaint(covariant _MapMarkersPainter old) =>
      old.markers != markers || old.atlasRevision != atlasRevision;
}

class _MapOverlayPainter extends CustomPainter {
  final _MapPinAtlas pins;
  final MapPlace? selected;
  final NavigationRoute? route;
  final Path? routePath;
  final MapPoint? location;
  final double? heading;
  final TransformationController transform;
  final int atlasRevision;
  _MapOverlayPainter(
    this.pins,
    this.selected,
    this.route,
    this.routePath,
    this.location,
    this.heading,
    this.transform,
  ) : atlasRevision = pins.revision,
      super(repaint: transform);

  static final _arrow = Path()
    ..moveTo(0, -17)
    ..lineTo(11, 12)
    ..lineTo(0, 7)
    ..lineTo(-11, 12)
    ..close();

  @override
  void paint(Canvas c, Size size) {
    final side = math.min(size.width, size.height);
    final unit = 1024 / (side * transform.value.getMaxScaleOnAxis());
    final markerUnit = MapMarkerGeometry.unit(
      size,
      transform.value.getMaxScaleOnAxis(),
    );
    c.save();
    _mapCanvas(c, size);
    if (routePath != null) {
      c.drawPath(
        routePath!,
        Paint()
          ..color = const Color(0xbb101a15)
          ..strokeWidth = 9 * unit
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      c.drawPath(
        routePath!,
        Paint()
          ..color = appAccent
          ..strokeWidth = 4 * unit
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    if (selected != null) {
      pins.paint(
        c,
        _mapPixel(selected!.point),
        markerUnit * 1.4,
        _placeIcon(selected!.category),
        appAccent,
      );
    }
    if (route != null) {
      pins.paint(
        c,
        _mapPixel(route!.points.last),
        markerUnit * 1.4,
        Icons.sports_score_rounded,
        appAccent,
      );
    }
    if (location != null) {
      final q = _mapPixel(location!);
      c.drawCircle(q, 24 * unit, Paint()..color = const Color(0x443be1d2));
      c.drawCircle(q, 12 * unit, Paint()..color = const Color(0xff102b27));
      c.save();
      c.translate(q.dx, q.dy);
      c.rotate(heading ?? 0);
      c.scale(unit * .8);
      c.drawPath(_arrow, Paint()..color = const Color(0xff65f1df));
      c.restore();
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _MapOverlayPainter old) =>
      old.routePath != routePath ||
      old.selected != selected ||
      old.location?.x != location?.x ||
      old.location?.z != location?.z ||
      old.heading != heading ||
      old.atlasRevision != atlasRevision;
}

// Finite category atlas: layout each glyph once, reuse on every map frame.
class _MapPinAtlas {
  _MapPinAtlas(this.onReady);
  final VoidCallback onReady;
  final _pictures = <(IconData, Color), ui.Picture>{};
  final _images = <(IconData, Color), ui.Image>{};
  final _imagePaint = Paint()..filterQuality = FilterQuality.low;
  bool _disposed = false;
  int revision = 0;
  // Four pixels per atlas unit keeps selected pins sharp on high-DPI phones.
  static const _bounds = Rect.fromLTWH(-16, -40, 32, 44);

  Future<void> _rasterize((IconData, Color) key, ui.Picture picture) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(4)
      ..translate(16.0, 40.0);
    canvas.drawPicture(picture);
    final snapshot = recorder.endRecording();
    try {
      final image = await snapshot.toImage(128, 176);
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[key] = image;
      revision++;
      onReady();
    } catch (_) {
      // Keep the vector fallback if the GPU cannot allocate a snapshot.
    } finally {
      snapshot.dispose();
    }
  }

  static final _pin = Path()
    ..moveTo(0, 0)
    ..cubicTo(-4, -8, -13, -12, -13, -21)
    ..cubicTo(-13, -38, 13, -38, 13, -21)
    ..cubicTo(13, -12, 4, -8, 0, 0)
    ..close();

  void paint(
    Canvas canvas,
    Offset anchor,
    double unit,
    IconData icon,
    Color color,
  ) {
    final picture = _pictures.putIfAbsent((icon, color), () {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      c.drawPath(_pin, Paint()..color = const Color(0xff122019));
      c.drawPath(
        _pin,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final symbolCategory = switch (icon) {
        Icons.ad_units_rounded => '广告牌',
        Icons.landscape_rounded => '地标',
        Icons.pets_rounded => '吉祥物',
        _ => null,
      };
      if (symbolCategory != null) {
        c.save();
        c.translate(0, -21);
        _paintPlaceSymbol(c, symbolCategory, color);
        c.restore();
      } else {
        final glyph = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: 18,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        glyph.paint(c, Offset(-glyph.width / 2, -21 - glyph.height / 2));
        glyph.dispose();
      }
      final picture = recorder.endRecording();
      unawaited(_rasterize((icon, color), picture));
      return picture;
    });
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(unit);
    final image = _images[(icon, color)];
    if (image == null) {
      canvas.drawPicture(picture);
    } else {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _bounds,
        _imagePaint,
      );
    }
    canvas.restore();
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
  }
}
