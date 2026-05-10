import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'news_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static const String _prefKey = 'selected_country_code';

  Future<String>? _ongoingDetection;

  Future<String> getCountryCode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && saved.isNotEmpty) return saved;

    _ongoingDetection ??= _fetchFromDevice().whenComplete(() {
      _ongoingDetection = null;
    });
    return _ongoingDetection!;
  }

  Future<String> _fetchFromDevice() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return _fallback();

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallback();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 10));

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final raw = placemarks.first.isoCountryCode?.toLowerCase() ?? '';
        final code = NewsService.supportedCountries.containsKey(raw)
            ? raw
            : 'pk'; // Default to 'pk' if unsupported
        await saveCountryCode(code);
        return code;
      }
    } catch (e) {
      print('LocationService error: $e');
    }
    return _fallback();
  }

  String _fallback() => 'pk';

  Future<void> saveCountryCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, code);
    NewsService.clearCache();
  }

  Future<void> resetCountry() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    NewsService.clearCache();
  }
}
