class Place {
  final String displayName;
  final String? shortName;
  final double lat;
  final double lon;
  final String? type;
  final String? address;

  Place({
    required this.displayName,
    this.shortName,
    required this.lat,
    required this.lon,
    this.type,
    this.address,
  });

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'shortName': shortName,
        'lat': lat,
        'lon': lon,
        'type': type,
        'address': address,
      };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        displayName: json['displayName'] as String,
        shortName: json['shortName'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        type: json['type'] as String?,
        address: json['address'] as String?,
      );

  factory Place.fromPhoton(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>;
    final geom = feature['geometry'] as Map<String, dynamic>;
    final coords = geom['coordinates'] as List;

    final name = props['name'] as String? ?? '';
    final street = props['street'] as String? ?? '';
    final city = props['city'] as String? ?? '';
    final state = props['state'] as String? ?? '';

    final parts = <String>[];
    if (name.isNotEmpty) parts.add(name);
    if (street.isNotEmpty && street != name) parts.add(street);
    if (city.isNotEmpty && city != name && city != street) parts.add(city);
    if (state.isNotEmpty) parts.add(state);

    return Place(
      displayName: parts.join(', '),
      shortName: name.isNotEmpty ? name : street,
      lat: (coords[1] as num).toDouble(),
      lon: (coords[0] as num).toDouble(),
      type: props['type'] as String?,
      address: parts.join(', '),
    );
  }
}