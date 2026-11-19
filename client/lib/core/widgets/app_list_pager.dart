import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../l10n/app_lang.dart';

const int kListPageSize = 10;

class PageWindow<T> {
  const PageWindow({
    required this.items,
    required this.page,
    required this.total,
    required this.pageSize,
  });

  final List<T> items;
  final int page;
  final int total;
  final int pageSize;

  int get totalPages =>
      total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);

  static PageWindow<T> slice<T>(
    List<T> all,
    int page, {
    int pageSize = kListPageSize,
  }) {
    final total = all.length;
    final pages = total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
    final safe = page < 1 ? 1 : (page > pages ? pages : page);
    if (total == 0) {
      return PageWindow<T>(
        items: <T>[],
        page: 1,
        total: 0,
        pageSize: pageSize,
      );
    }
    final start = (safe - 1) * pageSize;
    var end = start + pageSize;
    if (end > total) end = total;
    return PageWindow<T>(
      items: all.sublist(start, end),
      page: safe,
      total: total,
      pageSize: pageSize,
    );
  }
}

class AppListPager extends StatelessWidget {
  const AppListPager({
    super.key,
    required this.page,
    required this.total,
    required this.onPage,
    this.pageSize = kListPageSize,
  });

  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (total <= pageSize) return const SizedBox.shrink();
    final pages = (total + pageSize - 1) ~/ pageSize;
    final safe = page < 1 ? 1 : (page > pages ? pages : page);
    final start = (safe - 1) * pageSize + 1;
    final end = safe * pageSize > total ? total : safe * pageSize;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;
    final fg = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              trf('showingRange', {
                'start': '$start',
                'end': '$end',
                'total': '$total',
              }),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text),
            ),
          ),
          IconButton(
            tooltip: tr('previousPage'),
            onPressed: safe > 1 ? () => onPage(safe - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: fg,
          ),
          Text(
            '$safe / $pages',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg),
          ),
          IconButton(
            tooltip: tr('nextPage'),
            onPressed: safe < pages ? () => onPage(safe + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: fg,
          ),
        ],
      ),
    );
  }
}

/// Scrollable list that shows [pageSize] rows and a pager when there are more.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding,
    this.pageSize = kListPageSize,
    this.physics,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final EdgeInsetsGeometry? padding;
  final int pageSize;
  final ScrollPhysics? physics;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  int _page = 1;

  @override
  void didUpdateWidget(covariant PagedListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pages = widget.items.isEmpty
        ? 1
        : ((widget.items.length + widget.pageSize - 1) ~/ widget.pageSize);
    if (_page > pages) _page = pages;
  }

  @override
  Widget build(BuildContext context) {
    final window = PageWindow.slice(widget.items, _page, pageSize: widget.pageSize);
    final showPager = window.total > widget.pageSize;
    final count = window.items.length + (showPager ? 1 : 0);

    Widget row(BuildContext context, int index) {
      if (index >= window.items.length) {
        return AppListPager(
          page: window.page,
          total: window.total,
          pageSize: widget.pageSize,
          onPage: (p) => setState(() => _page = p),
        );
      }
      return widget.itemBuilder(context, window.items[index], index);
    }

    if (widget.separatorBuilder != null) {
      return ListView.separated(
        physics: widget.physics,
        padding: widget.padding,
        itemCount: count,
        separatorBuilder: widget.separatorBuilder!,
        itemBuilder: row,
      );
    }
    return ListView.builder(
      physics: widget.physics,
      padding: widget.padding,
      itemCount: count,
      itemBuilder: row,
    );
  }
}
