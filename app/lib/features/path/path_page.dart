import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../design/chapter_theme.dart';
import '../../design/motion.dart';
import '../auth/session.dart';
import '../status/api_status_indicator.dart';
import 'learning_path.dart';
import 'path_providers.dart';

class PathPage extends ConsumerWidget {
  const PathPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session is! Ready) return const Scaffold(body: SizedBox.shrink());
    final path = ref.watch(learningPathProvider(session.user.uid));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              key: const Key('path-top-bar'),
              color: const Color(0xFFF2BE82),
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '学習パス',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (path.value case final value?) ...[
                          _ProgressStat(
                            key: const Key('path-xp'),
                            icon: Icons.star_rounded,
                            label: '${value.progress.xp} XP',
                          ),
                          _ProgressStat(
                            key: const Key('path-streak'),
                            icon: Icons.local_fire_department_outlined,
                            label: '${value.progress.streakDays} 日連続',
                          ),
                        ],
                        const ApiStatusIndicator(),
                      ],
                    ),
                  ),
                  const MotionSettingsButton(),
                  PopupMenuButton<void>(
                    key: const Key('path-menu'),
                    tooltip: 'プロフィールと設定',
                    icon: const Icon(Icons.account_circle_outlined),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          '${session.profile.displayName}（${session.profile.grade.label}）',
                        ),
                      ),
                      PopupMenuItem(
                        key: const Key('path-sign-out'),
                        onTap: () => ref.read(authRepositoryProvider).signOut(),
                        child: const Text('ログアウト'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (path) {
                AsyncData(:final value) => LearningPathView(
                  key: ValueKey(session.user.uid),
                  path: value,
                  displayName: session.profile.displayName,
                ),
                AsyncError() => _PathMessage(
                  icon: Icons.cloud_off_rounded,
                  title: '学習パスを読みこめませんでした',
                  detail: '通信を確認して、もう一度試してね。',
                  action: FilledButton(
                    onPressed: () => refreshLearningPath(ref),
                    child: const Text('もう一度試す'),
                  ),
                  key: const Key('path-error'),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Unit paging is presentation-only; progress and locking remain server-driven.
class LearningPathView extends ConsumerStatefulWidget {
  const LearningPathView({
    super.key,
    required this.path,
    required this.displayName,
  });
  final LearningPath path;
  final String displayName;
  @override
  ConsumerState<LearningPathView> createState() => _LearningPathViewState();
}

class _LearningPathViewState extends ConsumerState<LearningPathView> {
  late final PageController _pages;
  late int _index;
  final Map<String, String> _selectedLessons = {};
  @override
  void initState() {
    super.initState();
    final next = widget.path.nextLessonId;
    final initial = widget.path.units.indexWhere(
      (u) => u.lessons.any((l) => l.lesson.id == next),
    );
    _index = initial < 0 ? 0 : initial;
    _pages = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant LearningPathView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.path.units.length && widget.path.units.isNotEmpty) {
      _index = widget.path.units.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
      });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index < 0 || index >= widget.path.units.length) return;
    if (reduceMotion(context, ref)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  PathLesson? _selected(PathUnit unit) {
    if (unit.lessons.isEmpty) return null;
    final id = _selectedLessons[unit.unit.id];
    return unit.lessons.firstWhere(
      (l) => l.lesson.id == id,
      orElse: () => unit.lessons.firstWhere(
        (l) => l.lesson.id == widget.path.nextLessonId,
        orElse: () => unit.lessons.first,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    if (path.units.isEmpty) {
      return const _PathMessage(
        key: Key('path-empty'),
        icon: Icons.auto_stories_outlined,
        title: '学びの準備をしています',
        detail: 'まだレッスンがありません。もうすぐ届くので待っていてね',
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < path.units.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Semantics(
                      selected: i == _index,
                      child: TextButton(
                        key: Key('unit-tab-${path.units[i].unit.id}'),
                        onPressed: () => _go(i),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(72, 48),
                          shape: const RoundedRectangleBorder(),
                          side: i == _index
                              ? BorderSide(color: ChapterPalette.ink, width: 2)
                              : BorderSide.none,
                          backgroundColor: i == _index
                              ? ChapterPalette.forUnit(path.units[i].unit.id)
                                    .wash
                              : null,
                          foregroundColor: ChapterPalette.ink,
                        ),
                        child: Text('Unit ${path.units[i].unit.order}'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: PageView.builder(
            key: const Key('unit-pager'),
            controller: _pages,
            allowImplicitScrolling: false,
            itemCount: path.units.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final unit = path.units[index];
              final palette = ChapterPalette.forUnit(unit.unit.id);
              return TickerMode(
                enabled: index == _index,
                child: ChapterScope(
                  palette: palette,
                  child: _UnitPage(
                    key: Key('unit-${unit.unit.id}'),
                    unit: unit,
                    displayName: widget.displayName,
                    selected: _selected(unit),
                    nextLessonId: path.nextLessonId,
                    active: index == _index,
                    onSelect: (item) => setState(
                      () => _selectedLessons[unit.unit.id] = item.lesson.id,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              IconButton(
                key: const Key('unit-previous'),
                tooltip: '前のユニット',
                onPressed: _index > 0 ? () => _go(_index - 1) : null,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  '${_index + 1} / ${path.units.length} ユニット',
                  key: const Key('unit-position'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ChapterPalette.muted),
                ),
              ),
              IconButton(
                key: const Key('unit-next'),
                tooltip: '次のユニット',
                onPressed: _index < path.units.length - 1
                    ? () => _go(_index + 1)
                    : null,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnitPage extends ConsumerWidget {
  const _UnitPage({
    super.key,
    required this.unit,
    required this.selected,
    required this.nextLessonId,
    required this.active,
    required this.onSelect,
    required this.displayName,
  });
  final String displayName;
  final PathUnit unit;
  final PathLesson? selected;
  final String? nextLessonId;
  final bool active;
  final ValueChanged<PathLesson> onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ChapterPalette.of(context);
    final completed = unit.lessons
        .where((l) => l.status == LessonStatus.completed)
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final list = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'レッスン',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final item in unit.lessons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LessonRow(
                  item: item,
                  selected: item.lesson.id == selected?.lesson.id,
                  isNext: item.lesson.id == nextLessonId,
                  onTap: () => onSelect(item),
                ),
              ),
          ],
        );
        final detail = selected == null
            ? const _PathMessage(
                icon: Icons.auto_stories_outlined,
                title: 'もうすぐ、はじまるよ',
                detail: 'このユニットのレッスンは準備中です',
              )
            : TweenAnimationBuilder<double>(
                key: ValueKey(selected!.lesson.id),
                tween: Tween(
                  begin: reduceMotion(context, ref) ? 1 : .65,
                  end: 1,
                ),
                duration: reduceMotion(context, ref)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: _LessonDetail(item: selected!),
              );
        return SingleChildScrollView(
          key: Key('unit-scroll-${unit.unit.id}'),
          padding: EdgeInsets.fromLTRB(wide ? 40 : 24, 8, wide ? 40 : 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'こんにちは、$displayName さん！',
                    style: const TextStyle(color: ChapterPalette.muted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${unit.unit.order}'.padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: wide ? 96 : 64,
                          height: 1,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              palette.label,
                              style: TextStyle(color: palette.accent),
                            ),
                            Text(
                              unit.unit.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontSize: wide ? 44 : 30,
                                    fontWeight: FontWeight.w400,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(unit.unit.description),
                          ],
                        ),
                      ),
                      if (wide) ...[
                        const SizedBox(width: 24),
                        Transform.rotate(
                          angle: -.10,
                          child: AmbientMotif(
                            palette: palette,
                            size: 100,
                            active: active,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: unit.lessons.isEmpty
                              ? 0
                              : completed / unit.lessons.length,
                          minHeight: 3,
                          semanticsLabel:
                              'ユニットの進捗 $completed / ${unit.lessons.length} レッスン完了',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text('$completed / ${unit.lessons.length}'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: list),
                        const SizedBox(width: 28),
                        Expanded(flex: 6, child: detail),
                      ],
                    )
                  else ...[
                    list,
                    const SizedBox(height: 16),
                    detail,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.item,
    required this.selected,
    required this.isNext,
    required this.onTap,
  });
  final PathLesson item;
  final bool selected;
  final bool isNext;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final palette = ChapterPalette.of(context);
    final icon = switch (item.status) {
      LessonStatus.completed => Icons.check_rounded,
      LessonStatus.unlocked => Icons.play_arrow_rounded,
      LessonStatus.locked => Icons.lock_outline_rounded,
    };
    return Semantics(
      label:
          '${isNext ? 'ここから！ ' : ''}${item.lesson.title}（${_statusLabel(item.status)}）',
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      selected: selected,
      child: Material(
        color: selected ? palette.wash : ChapterPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          side: BorderSide(
            color: selected ? palette.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          key: Key('lesson-${item.lesson.id}-${item.status.name}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Text(
                      '${item.lesson.order}'.padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 26,
                        height: 1,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(icon, color: palette.accent, size: 16),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.lesson.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isNext ? 'ここから！' : _statusLabel(item.status),
                        key: isNext ? const Key('path-next') : null,
                        style: TextStyle(color: palette.accent, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: palette.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(LessonStatus status) => switch (status) {
  LessonStatus.completed => 'クリア済み',
  LessonStatus.unlocked => '挑戦できます',
  LessonStatus.locked => 'まだロックされています',
};

class _LessonDetail extends StatelessWidget {
  const _LessonDetail({required this.item});
  final PathLesson item;
  @override
  Widget build(BuildContext context) {
    final lesson = item.lesson;
    final palette = ChapterPalette.of(context);
    final locked = item.status == LessonStatus.locked;
    return Container(
      key: Key('lesson-detail-${lesson.id}'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ChapterPalette.surface,
        border: Border.all(color: const Color(0xFFE6D8CD)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(36),
          bottomLeft: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'レッスン ${lesson.order}',
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(lesson.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(lesson.intro?.text ?? '短い問題に挑戦しながら、AIへの理解を深めよう。'),
          const SizedBox(height: 20),
          Text(
            '${lesson.exerciseIds.length} 問  ／  ${_statusLabel(item.status)}',
            style: const TextStyle(color: ChapterPalette.muted),
          ),
          const SizedBox(height: 24),
          if (locked) ...[
            const Text('前のレッスンをクリアするとひらきます'),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            key: const Key('path-start-lesson'),
            onPressed: locked
                ? null
                : () => context.push(Routes.lesson(lesson.id)),
            icon: Icon(
              locked ? Icons.lock_outline_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              locked
                  ? 'まだロックされています'
                  : item.status == LessonStatus.completed
                  ? 'もう一度学ぶ'
                  : 'レッスンをはじめる',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20, color: ChapterPalette.primary),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

class _PathMessage extends StatelessWidget {
  const _PathMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: ChapterPalette.primary),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(detail, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}
