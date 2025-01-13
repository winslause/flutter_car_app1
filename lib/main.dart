import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MapAlertScreen(),
    );
  }
}

class MapAlertScreen extends StatefulWidget {
  @override
  _MapAlertScreenState createState() => _MapAlertScreenState();
}

class _MapAlertScreenState extends State<MapAlertScreen> {
  final MapController _mapController = MapController();
  final LatLng initialCoordinates = LatLng(-1.103788, 37.012681);

  List<LatLng> potholeCoordinates = [];
  List<LatLng> bumpCoordinates = [];
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  String _selectedType = 'pothole';
  Position? _currentPosition;
  late StreamSubscription<Position> _positionStream;
  double? nearestDistance;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    Future.delayed(Duration.zero, () => _loadCoordinates());
  }

  @override
  void dispose() {
    _positionStream.cancel();
    super.dispose();
  }

  void _initializeLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position? position) {
      if (position != null) {
        _currentPosition = position;
        _checkProximity();
        _updateMapPosition();
        setState(() {});
      }
    });
  }

  void _checkProximity() {
    if (_currentPosition == null) return;
    double distanceToNearestPothole = _findNearestDistance(potholeCoordinates);
    double distanceToNearestBump = _findNearestDistance(bumpCoordinates);
    double nearestDistance = min(distanceToNearestPothole, distanceToNearestBump);

    setState(() {
      this.nearestDistance = nearestDistance <= 10 ? nearestDistance : null;
    });
  }

  void _updateMapPosition() {
    if (_currentPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 16.0);
      });
    }
  }

  double _findNearestDistance(List<LatLng> coordinates) {
    if (coordinates.isEmpty || _currentPosition == null) return double.infinity;
    return coordinates.map((coord) {
      return Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        coord.latitude,
        coord.longitude,
      );
    }).reduce(min);
  }

  void _zoomToCoordinates() {
    if (potholeCoordinates.isNotEmpty) {
      _mapController.move(potholeCoordinates.first, 18.0);
    } else if (bumpCoordinates.isNotEmpty) {
      _mapController.move(bumpCoordinates.first, 18.0);
    } else {
      _mapController.move(initialCoordinates, 18.0);
    }
  }

  void _addManualMarker() async {
    double? latitude = double.tryParse(_latitudeController.text);
    double? longitude = double.tryParse(_longitudeController.text);

    if (latitude != null && longitude != null) {
      setState(() {
        if (_selectedType == 'pothole') {
          potholeCoordinates.add(LatLng(latitude, longitude));
        } else {
          bumpCoordinates.add(LatLng(latitude, longitude));
        }
        _latitudeController.clear();
        _longitudeController.clear();
      });
      await _sendCoordinateToServer(latitude, longitude, _selectedType);
    }
  }

  Future<void> _sendCoordinateToServer(double latitude, double longitude, String type) async {
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:5000/coordinates'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'type': type,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
      if (response.statusCode == 200) {
        print("Coordinate added to server");
      } else {
        print("Failed to add coordinate to server");
      }
    } catch (e) {
      print("Error sending data to server: $e");
    }
  }

  Future<void> _loadCoordinates() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:5000/coordinates'));
      if (response.statusCode == 200) {
        List<dynamic> jsonData = jsonDecode(response.body);
        setState(() {
          potholeCoordinates = jsonData
              .where((json) => json['type'] == 'pothole')
              .map((json) => LatLng(double.parse(json['latitude']), double.parse(json['longitude'])))
              .toList();
          bumpCoordinates = jsonData
              .where((json) => json['type'] == 'bump')
              .map((json) => LatLng(double.parse(json['latitude']), double.parse(json['longitude'])))
              .toList();
        });
        print('Coordinates loaded: Potholes: ${potholeCoordinates.length}, Bumps: ${bumpCoordinates.length}');
      } else {
        print('Failed to load coordinates. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading coordinates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Building MapAlertScreen with ${potholeCoordinates.length} potholes and ${bumpCoordinates.length} bumps');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pothole and Bump Detection App'),
        actions: [
          IconButton(
            icon: Icon(Icons.zoom_in),
            onPressed: _zoomToCoordinates,
          ),
        ],
      ),
      body: Row(
        children: [
          // Map Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.5 - 32,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: KeyedSubtree(
                  key: ValueKey(potholeCoordinates.length + bumpCoordinates.length),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _currentPosition != null ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) : initialCoordinates,
                      initialZoom: 14.0,
                      initialRotation: 10.0,
                      maxZoom: 20.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: 'potbump_detection_app',
                      ),
                      MarkerLayer(
                        markers: [
                          ...potholeCoordinates.map((coord) => Marker(
                            point: coord,
                            width: 50,
                            height: 50,
                            child: Container(
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.warning,
                                color: Colors.orange,
                                size: 40,
                              ),
                            ),
                          )).toList(),
                          ...bumpCoordinates.map((coord) => Marker(
                            point: coord,
                            width: 50,
                            height: 50,
                            child: Container(
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.warning,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                          )).toList(),
                          if (_currentPosition != null) Marker(
                            point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            width: 80,
                            height: 80,
                            child: Container(
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.blue,
                                size: 40,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            'OpenStreetMap contributors',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Alerts/Status and Manual Input Section
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black12.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      spreadRadius: 2,
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(child: Center(child: AlertStatusDisplay(distance: nearestDistance))),
                    
                    // Card for Manual Coordinate Input with Dropdown
                    Card(
                      margin: EdgeInsets.all(8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('ADD SPOT',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            DropdownButton<String>(
                              value: _selectedType,
                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedType = newValue!;
                                });
                              },
                              items: <String>['pothole', 'bump'].map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                            ),
                            TextField(
                              controller: _latitudeController,
                              decoration: InputDecoration(labelText: 'Latitude'),
                            ),
                            TextField(
                              controller: _longitudeController,
                              decoration: InputDecoration(labelText: 'Longitude'),
                            ),
                            ElevatedButton(
                              onPressed: _addManualMarker,
                              child: Text('Add Marker'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AlertStatusDisplay extends StatelessWidget {
  final double? distance;

  const AlertStatusDisplay({Key? key, this.distance}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (distance != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "${distance!.toStringAsFixed(1)}m rem",
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          distance != null ? "Pothole or Bump Ahead!!" : "No Alerts",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: distance != null ? Colors.red : Colors.grey,
          ),
        ),
        // ... other widgets ...
      ],
    );
  }
}