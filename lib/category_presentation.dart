enum CategoryCoverShape { circle, rounded }

class CategoryPresentation {
  const CategoryPresentation(
      {this.shape = CategoryCoverShape.circle,
      this.showTitle = true,
      this.showDetails = false});

  final CategoryCoverShape shape;
  final bool showTitle;
  final bool showDetails;

  factory CategoryPresentation.fromMap(Object? value) {
    final map = value is Map ? value : const {};
    return CategoryPresentation(
      shape: map['shape'] == 'rounded'
          ? CategoryCoverShape.rounded
          : CategoryCoverShape.circle,
      showTitle: map['showTitle'] is bool ? map['showTitle'] : true,
      showDetails: map['showDetails'] is bool ? map['showDetails'] : false,
    );
  }
  Map<String, Object> toMap() =>
      {'shape': shape.name, 'showTitle': showTitle, 'showDetails': showDetails};
  CategoryPresentation copyWith(
          {CategoryCoverShape? shape, bool? showTitle, bool? showDetails}) =>
      CategoryPresentation(
          shape: shape ?? this.shape,
          showTitle: showTitle ?? this.showTitle,
          showDetails: showDetails ?? this.showDetails);
}
