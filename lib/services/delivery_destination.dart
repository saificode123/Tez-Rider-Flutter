/// Confirmation is an explicit customer action, never a device-location default.
class DeliveryDestination {
  double? latitude, longitude;
  String? source;
  bool get confirmed => source != null;
  void confirm(double lat, double lng, String method) {
    if (!lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        !const ['my_location', 'map_pin'].contains(method)) {
      throw ArgumentError('Invalid delivery destination');
    }
    latitude = lat;
    longitude = lng;
    source = method;
  }

  Map<String, dynamic> get provenance => {
    'destination_confirmed': confirmed,
    'destination_source': source,
  };
}
