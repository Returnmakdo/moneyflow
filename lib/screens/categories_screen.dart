import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../utils/nav_back.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  CategoriesData? _cats;
  Object? _error;
  // 'expense' | 'income' — 화면 상단 탭으로 전환.
  String _type = 'expense';

  late final Listenable _apiListenable = Listenable.merge([
    Api.instance.majorsVersion,
    Api.instance.categoriesVersion,
  ]);
  bool _reloadScheduled = false;

  @override
  void initState() {
    super.initState();
    _apiListenable.addListener(_onApiChanged);
    _reload();
  }

  @override
  void dispose() {
    _apiListenable.removeListener(_onApiChanged);
    super.dispose();
  }

  void _onApiChanged() {
    if (_reloadScheduled || !mounted) return;
    _reloadScheduled = true;
    scheduleMicrotask(() {
      _reloadScheduled = false;
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    try {
      final c = await Api.instance.listCategories(type: _type);
      if (!mounted) return;
      setState(() {
        _cats = c;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String initial = '',
    String confirmText = '확인',
  }) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('취소',
                style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(confirmText,
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return r == null || r.isEmpty ? null : r;
  }

  Future<void> _addMajor() async {
    final name = await _promptText(
      title: _type == 'income' ? '수입 카테고리 추가' : '지출 카테고리 추가',
      label: _type == 'income' ? '예: 부업, 환급' : '예: 식비/카페',
      confirmText: '추가',
    );
    if (name == null) return;
    try {
      await Api.instance.createMajor(name, type: _type);
      if (!mounted) return;
      showToast(context, '추가했어요');
      _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _renameMajor(String major, String newName) async {
    final v = newName.trim();
    if (v.isEmpty || v == major) return;
    try {
      await Api.instance.renameMajor(major, v);
      if (!mounted) return;
      showToast(context, '수정했어요');
      _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _deleteMajor(String major) async {
    final ok = await confirmDialog(
      context,
      title: '카테고리 삭제',
      message: '"$major"을 삭제할까요?\n'
          '이 카테고리를 쓰는 거래가 있으면 삭제할 수 없어요. '
          '태그와 예산 설정도 함께 삭제됩니다.',
      confirmText: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.deleteMajor(major);
      if (!mounted) return;
      showToast(context, '삭제했어요');
      _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _addSub(String major) async {
    final name = await _promptText(
        title: '태그 추가', label: '새 태그', confirmText: '추가');
    if (name == null) return;
    try {
      await Api.instance.createCategory(major, name);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _renameSub(Category s) async {
    final v = await _promptText(
      title: '태그 이름 변경',
      label: '태그 이름',
      initial: s.sub,
      confirmText: '저장',
    );
    if (v == null || v == s.sub) return;
    try {
      await Api.instance.renameCategory(s.id, v);
      if (!mounted) return;
      showToast(context, '수정했어요');
      _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _deleteSub(Category s) async {
    final ok = await confirmDialog(
      context,
      title: '태그 삭제',
      message: '"${s.sub}"을 삭제할까요? 이 태그를 쓰는 거래가 있으면 삭제할 수 없어요.',
      confirmText: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.deleteCategory(s.id);
      if (!mounted) return;
      showToast(context, '삭제했어요');
      _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text2),
          onPressed: () => goBackOr(context, '/settings'),
        ),
        title: Text(
          '카테고리 관리',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_categories',
        onPressed: _addMajor,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_type == 'income' ? '수입 카테고리 추가' : '카테고리 추가'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _typeTabs(),
            ),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _typeTabs() {
    Widget tab(String value, String label) {
      final selected = _type == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_type == value) return;
            setState(() {
              _type = value;
              _cats = null;
            });
            _reload();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? (value == 'income'
                      ? AppColors.incomeBg
                      : AppColors.surface)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? (value == 'income'
                          ? AppColors.incomeText
                          : AppColors.text)
                      : AppColors.text3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          tab('expense', '지출'),
          tab('income', '수입'),
        ],
      ),
    );
  }

  Widget _content() {
    return Builder(
      builder: (context) {
        if (_cats == null) {
          if (_error != null) {
            return Center(child: Text(errorMessage(_error!)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              for (var i = 0; i < 5; i++) ...[
                AppCard(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonLine(width: 80, height: 16),
                      SizedBox(height: 14),
                      Skeleton(height: 28, radius: 99),
                      SizedBox(height: 14),
                      Skeleton(width: 110, height: 36, radius: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        }
        final cats = _cats!;
        if (cats.majors.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _type == 'income'
                    ? '수입 카테고리가 아직 없어요.\n월급, 이자 같은 항목을 추가해보세요.'
                    : '카테고리가 아직 없어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.text3,
                  height: 1.6,
                ),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            for (final m in cats.majors)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MajorCard(
                  key: ValueKey(m),
                  major: m,
                  subs: cats.byMajor[m] ?? const [],
                  onAddSub: () => _addSub(m),
                  onRenameSub: _renameSub,
                  onDeleteSub: _deleteSub,
                  onRename: (v) => _renameMajor(m, v),
                  onDelete: () => _deleteMajor(m),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MajorCard extends StatefulWidget {
  const _MajorCard({
    super.key,
    required this.major,
    required this.subs,
    required this.onAddSub,
    required this.onRenameSub,
    required this.onDeleteSub,
    required this.onRename,
    required this.onDelete,
  });
  final String major;
  final List<Category> subs;
  final VoidCallback onAddSub;
  final ValueChanged<Category> onRenameSub;
  final ValueChanged<Category> onDeleteSub;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  State<_MajorCard> createState() => _MajorCardState();
}

class _MajorCardState extends State<_MajorCard> {
  bool _editing = false;
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.major);
  }

  @override
  void didUpdateWidget(covariant _MajorCard old) {
    super.didUpdateWidget(old);
    if (old.major != widget.major && !_editing) {
      _ctrl.text = widget.major;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _ctrl.selection = TextSelection(
          baseOffset: 0, extentOffset: _ctrl.text.length);
    });
  }

  void _commit() {
    if (!_editing) return;
    final v = _ctrl.text.trim();
    setState(() => _editing = false);
    if (v.isEmpty || v == widget.major) {
      _ctrl.text = widget.major;
      return;
    }
    widget.onRename(v);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _editing
                    ? TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        onSubmitted: (_) => _commit(),
                        onTapOutside: (_) => _commit(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      )
                    : InkWell(
                        onTap: _startEdit,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Text(widget.major,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              )),
                        ),
                      ),
              ),
              IconButton(
                onPressed: widget.onDelete,
                tooltip: '삭제',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline,
                    color: AppColors.text3, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.subs.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in widget.subs)
                  _SubChip(
                    sub: s,
                    onRename: () => widget.onRenameSub(s),
                    onDelete: () => widget.onDeleteSub(s),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onAddSub,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('태그 추가'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primaryWeak, width: 1.5),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubChip extends StatelessWidget {
  const _SubChip({
    required this.sub,
    required this.onRename,
    required this.onDelete,
  });
  final Category sub;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryWeak,
      borderRadius: BorderRadius.circular(99),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onRename,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(99),
              bottomLeft: Radius.circular(99),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Text(sub.sub,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryStrong,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ),
          InkWell(
            onTap: onDelete,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(99),
              bottomRight: Radius.circular(99),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(2, 6, 8, 6),
              child: Icon(Icons.close,
                  size: 14, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
