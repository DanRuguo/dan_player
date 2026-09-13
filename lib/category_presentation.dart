enum CategoryCoverShape { circle, rounded }

enum CategoryTileSize {
  small(1, 1),
  wide(2, 1),
  tall(1, 2),
  large(2, 2);

  const CategoryTileSize(this.columns, this.rows);
  final int columns;
  final int rows;
}

enum CategorySort { standard, name, count, custom }

class CategoryPresentation {
  const CategoryPresentation(
      {this.shape = CategoryCoverShape.circle,
      this.showTitle = true,
      this.showDetails = false,
      this.sizes = const {},
      this.orders = const {},
      this.layouts = const {},
      this.sort = CategorySort.standard,
      this.descending = false,
      this.autoFill = true,
      this.categories = const {}});

  /// Legacy shared settings remain the initial defaults for each category.
  final Map<String, CategoryPresentation> categories;
  CategoryPresentation forCategory(String kind) => categories[kind] ?? this;
  CategoryPresentation withCategory(String kind, CategoryPresentation value) =>
      copyWith(categories: {
        ...categories,
        kind: value.copyWith(categories: const {})
      });

  final CategoryCoverShape shape;
  final bool showTitle;
  final bool showDetails;
  final Map<String, CategoryTileSize> sizes;
  final Map<String, List<String>> orders;

  /// Last full-view cell origins: [columnCount, x, y], keyed by category ID.
  final Map<String, List<int>> layouts;
  final CategorySort sort;
  final bool descending;
  final bool autoFill;

  factory CategoryPresentation.fromMap(Object? value) {
    final map = value is Map ? value : const {};
    return CategoryPresentation(
      shape: map['shape'] == 'rounded'
          ? CategoryCoverShape.rounded
          : CategoryCoverShape.circle,
      showTitle: map['showTitle'] is bool ? map['showTitle'] : true,
      showDetails: map['showDetails'] is bool ? map['showDetails'] : false,
      sizes: {
        if (map['sizes'] is Map)
          for (final entry in (map['sizes'] as Map).entries)
            if (entry.key is String)
              entry.key: CategoryTileSize.values
                      .where((s) => s.name == entry.value)
                      .firstOrNull ??
                  CategoryTileSize.small,
      },
      orders: {
        if (map['orders'] is Map)
          for (final entry in (map['orders'] as Map).entries)
            if (entry.key is String && entry.value is List)
              entry.key:
                  (entry.value as List).whereType<String>().toSet().toList(),
      },
      layouts: {
        if (map['layouts'] is Map)
          for (final entry in (map['layouts'] as Map).entries)
            if (entry.key is String &&
                entry.value is List &&
                (entry.value as List).length == 3 &&
                (entry.value as List)
                    .every((v) => v is int && v >= 0 && v < 100000))
              entry.key: (entry.value as List).cast<int>(),
      },
      sort:
          CategorySort.values.where((s) => s.name == map['sort']).firstOrNull ??
              CategorySort.standard,
      descending: map['descending'] == true,
      autoFill: map['autoFill'] != false,
      categories: {
        if (map['categories'] is Map)
          for (final entry in (map['categories'] as Map).entries)
            if (entry.key is String && entry.value is Map)
              entry.key: CategoryPresentation.fromMap(
                  Map.of(entry.value as Map)..remove('categories')),
      },
    );
  }
  Map<String, Object> toMap() => {
        'shape': shape.name,
        'showTitle': showTitle,
        'showDetails': showDetails,
        'sizes': sizes.map((key, value) => MapEntry(key, value.name)),
        'orders': orders,
        'layouts': layouts,
        'sort': sort.name,
        'descending': descending,
        'autoFill': autoFill,
        if (categories.isNotEmpty)
          'categories':
              categories.map((key, value) => MapEntry(key, value.toMap())),
      };
  CategoryPresentation copyWith(
          {CategoryCoverShape? shape,
          bool? showTitle,
          bool? showDetails,
          Map<String, CategoryTileSize>? sizes,
          Map<String, List<String>>? orders,
          Map<String, List<int>>? layouts,
          CategorySort? sort,
          bool? descending,
          bool? autoFill,
          Map<String, CategoryPresentation>? categories}) =>
      CategoryPresentation(
          shape: shape ?? this.shape,
          showTitle: showTitle ?? this.showTitle,
          showDetails: showDetails ?? this.showDetails,
          sizes: sizes ?? this.sizes,
          orders: orders ?? this.orders,
          layouts: layouts ?? this.layouts,
          sort: sort ?? this.sort,
          descending: descending ?? this.descending,
          autoFill: autoFill ?? this.autoFill,
          categories: categories ?? this.categories);
}
