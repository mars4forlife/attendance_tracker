import 'package:geolocator/geolocator.dart';
import '../utils/constants.dart';

class LocationService {
  static Future<bool> isInUniversityZone() async {
    try {
      // Проверяем, включена ли геолокация
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      // Проверяем разрешения
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }

      if (permission == LocationPermission.deniedForever) return false;

      // Получаем текущую позицию
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Считаем расстояние до университета
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        AppConstants.universityLat,
        AppConstants.universityLng,
      );

      return distance <= AppConstants.attendanceRadiusMeters;
    } catch (e) {
      print("Ошибка определения локации: $e");
      return false;
    }
  }
}
