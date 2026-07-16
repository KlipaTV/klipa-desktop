class Programme {
  const Programme({
    required this.sourceId,
    required this.guideId,
    required this.title,
    required this.startUtc,
    required this.endUtc,
    this.description,
  });

  final String sourceId;
  final String guideId;
  final String title;
  final DateTime startUtc;
  final DateTime endUtc;
  final String? description;
}
