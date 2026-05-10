import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/news_service.dart';

class LocationProvider extends ChangeNotifier {
  final LocationService _locationService = LocationService();

  String _countryCode = 'pk';
  String get countryCode => _countryCode;

  String _selectedLanguage = 'ur'; // default for 'pk'
  String get selectedLanguage => _selectedLanguage;

  Future<void> loadCountry() async {
    _countryCode = await _locationService.getCountryCode();
    _selectedLanguage = NewsService.getDefaultLanguageForCountry(_countryCode);
    notifyListeners();
  }

  Future<void> changeCountry(String code) async {
    _countryCode = code;
    // Reset language to the country's default whenever country changes
    _selectedLanguage = NewsService.getDefaultLanguageForCountry(code);
    await _locationService.saveCountryCode(code);
    notifyListeners();
  }

  Future<void> detectLocation() async {
    await _locationService.resetCountry();
    _countryCode = await _locationService.getCountryCode();
    _selectedLanguage = NewsService.getDefaultLanguageForCountry(_countryCode);
    notifyListeners();
  }

  /// Call this when the user picks a language on Home or Profile.
  void changeLanguage(String langCode) {
    _selectedLanguage = langCode;
    notifyListeners();
  }
}
