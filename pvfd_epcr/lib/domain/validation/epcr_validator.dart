class EpcrValidator {
  const EpcrValidator();
  String? forestGps({
    required bool forestLand,
    required String gpsCoordinates,
  }) => forestLand && gpsCoordinates.trim().isEmpty
      ? 'GPS Coordinates are required when Forest Land is checked.'
      : null;
}
