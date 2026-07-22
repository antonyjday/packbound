/// One address/place suggestion from PlacesService.autocomplete - just
/// enough to show in a suggestions list and, once picked, resolve to a
/// [RouteStop] via PlacesService.resolvePlace(placeId).
class PlaceSuggestion {
  final String placeId;
  final String primaryText;
  final String? secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    this.secondaryText,
  });
}
