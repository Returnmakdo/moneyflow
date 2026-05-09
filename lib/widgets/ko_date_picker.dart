import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// 년/월만 선택하는 다이얼로그. YYYY-MM 문자열 반환. 헤더 월 스위처에서 사용.
Future<String?> showKoMonthPicker({
  required BuildContext context,
  required String initialYm, // 'YYYY-MM'
  int firstYear = 2000,
  int lastYear = 2100,
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _KoMonthPickerDialog(
      initialYm: initialYm,
      firstYear: firstYear,
      lastYear: lastYear,
    ),
  );
}

/// 한국어 날짜 선택 다이얼로그. 상단에 년/월 dropdown으로 빠르게 이동할 수
/// 있고, 화살표로 월 단위 nav도 가능. 일 grid에서 선택 → 확인.
Future<DateTime?> showKoDatePicker({
  required BuildContext context,
  required DateTime initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _KoDatePickerDialog(
      initial: initial,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
    ),
  );
}

class _KoMonthPickerDialog extends StatefulWidget {
  const _KoMonthPickerDialog({
    required this.initialYm,
    required this.firstYear,
    required this.lastYear,
  });
  final String initialYm;
  final int firstYear;
  final int lastYear;

  @override
  State<_KoMonthPickerDialog> createState() => _KoMonthPickerDialogState();
}

class _KoMonthPickerDialogState extends State<_KoMonthPickerDialog> {
  late int _viewYear;
  late int _initialYear;
  late int _initialMonth;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialYm.split('-');
    _initialYear = int.parse(parts[0]);
    _initialMonth = int.parse(parts[1]);
    _viewYear = _initialYear;
  }

  void _shiftYear(int delta) {
    final next = _viewYear + delta;
    if (next < widget.firstYear || next > widget.lastYear) return;
    setState(() => _viewYear = next);
  }

  void _confirm(int month) {
    final ym = '$_viewYear-${month.toString().padLeft(2, '0')}';
    Navigator.of(context).pop(ym);
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = _viewYear > widget.firstYear;
    final canNext = _viewYear < widget.lastYear;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('월 선택',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    )),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close,
                      size: 20, color: AppColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _YearNavBtn(
                  icon: Icons.chevron_left,
                  enabled: canPrev,
                  onTap: () => _shiftYear(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$_viewYear년',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ),
                _YearNavBtn(
                  icon: Icons.chevron_right,
                  enabled: canNext,
                  onTap: () => _shiftYear(1),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthCell(
                    month: m,
                    selected: _viewYear == _initialYear &&
                        m == _initialMonth,
                    onTap: () => _confirm(m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _YearNavBtn extends StatelessWidget {
  const _YearNavBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? AppColors.text2 : AppColors.text4,
          ),
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.month,
    required this.selected,
    required this.onTap,
  });
  final int month;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface2,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Center(
          child: Text(
            '$month월',
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? Colors.white : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _KoDatePickerDialog extends StatefulWidget {
  const _KoDatePickerDialog({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });
  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_KoDatePickerDialog> createState() => _KoDatePickerDialogState();
}

class _KoDatePickerDialogState extends State<_KoDatePickerDialog> {
  late int _year;
  late int _month;
  late int _day;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
    _month = widget.initial.month;
    _day = widget.initial.day;
  }

  void _shiftMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    if (y < widget.firstDate.year || y > widget.lastDate.year) return;
    setState(() {
      _year = y;
      _month = m;
      final maxDay = DateTime(y, m + 1, 0).day;
      if (_day > maxDay) _day = maxDay;
    });
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final selDay = _day > daysInMonth ? daysInMonth : _day;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('날짜 선택',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    )),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close,
                      size: 20, color: AppColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: AppDropdown<int>(
                    value: _year,
                    items: [
                      for (var y = widget.lastDate.year;
                          y >= widget.firstDate.year;
                          y--)
                        AppDropdownItem(value: y, label: '$y년'),
                    ],
                    onChanged: (v) => setState(() => _year = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: AppDropdown<int>(
                    value: _month,
                    items: [
                      for (var m = 1; m <= 12; m++)
                        AppDropdownItem(value: m, label: '$m월'),
                    ],
                    onChanged: (v) => setState(() => _month = v),
                  ),
                ),
                const SizedBox(width: 6),
                _NavBtn(
                  icon: Icons.chevron_left,
                  onTap: () => _shiftMonth(-1),
                ),
                const SizedBox(width: 4),
                _NavBtn(
                  icon: Icons.chevron_right,
                  onTap: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DayGrid(
              year: _year,
              month: _month,
              selectedDay: selDay,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onSelected: (d) => setState(() => _day = d),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('취소',
                        style: TextStyle(
                          color: AppColors.text2,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      DateTime(_year, _month, selDay),
                    ),
                    child: const Text('확인'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 36,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: AppColors.text2),
        ),
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.year,
    required this.month,
    required this.selectedDay,
    required this.onSelected,
    this.firstDate,
    this.lastDate,
  });
  final int year;
  final int month;
  final int selectedDay;
  final ValueChanged<int> onSelected;
  final DateTime? firstDate;
  final DateTime? lastDate;

  bool _enabled(int day) {
    final d = DateTime(year, month, day);
    if (firstDate != null && d.isBefore(DateTime(
          firstDate!.year, firstDate!.month, firstDate!.day))) {
      return false;
    }
    if (lastDate != null && d.isAfter(DateTime(
          lastDate!.year, lastDate!.month, lastDate!.day))) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // 0=Sun
    final daysInMonth = DateTime(year, month + 1, 0).day;
    const labels = ['일', '월', '화', '수', '목', '금', '토'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: i == 0
                            ? AppColors.danger
                            : (i == 6
                                ? AppColors.primary
                                : AppColors.text3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: [
            for (var i = 0; i < firstWeekday; i++)
              const SizedBox.shrink(),
            for (var d = 1; d <= daysInMonth; d++)
              _DayCell(
                day: d,
                weekday: (firstWeekday + d - 1) % 7,
                selected: d == selectedDay,
                enabled: _enabled(d),
                onTap: _enabled(d) ? () => onSelected(d) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.weekday,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final int day;
  final int weekday; // 0=Sun
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color color;
    if (selected) {
      color = Colors.white;
    } else if (!enabled) {
      color = AppColors.text4;
    } else {
      color = weekday == 0
          ? AppColors.danger
          : (weekday == 6 ? AppColors.primary : AppColors.text);
    }
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
