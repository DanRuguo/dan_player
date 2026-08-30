enum SortDirection {
  ascending,
  descending;

  String get label => this == ascending ? '升序' : '降序';
}
