import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';


void main() {
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
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
          ),
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

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Check if we already have all permissions
    bool locationGranted = await Permission.location.isGranted;
    bool photosGranted = await Permission.photos.isGranted;
    
    // Android 13+ uses photos/videos/audio. Older versions use storage.
    // To be safe, we check both storage and photos.
    bool storageGranted = await Permission.storage.isGranted;

    if (locationGranted && (photosGranted || storageGranted)) {
      _navigateToPdf();
    } else {
      setState(() {
        _isChecking = false;
      });
    }
  }

  void _navigateToPdf() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PdfViewerScreen()),
    );
  }

  Future<void> _requestLocationPermission() async {
    // Custom Layout (Dialog) for GPS
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin GPS (Lokasi)'),
        content: const Text(
            'Aplikasi ini membutuhkan akses GPS Anda untuk menyesuaikan rekomendasi lokal. Harap izinkan akses lokasi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    await Permission.location.request();
  }

  Future<void> _requestGalleryPermission() async {
    // Custom Layout (Dialog) for Gallery
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin Galeri'),
        content: const Text(
            'Aplikasi ini membutuhkan akses ke Galeri Anda untuk menyimpan kutipan atau gambar dari buku. Harap izinkan akses galeri.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    await Permission.photos.request();
  }

  Future<void> _requestStoragePermission() async {
    // Custom Layout (Dialog) for Storage Data
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin Data HP'),
        content: const Text(
            'Aplikasi ini membutuhkan akses penyimpanan untuk menyimpan file PDF secara lokal agar dapat dibaca offline. Harap izinkan akses penyimpanan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    await Permission.storage.request();
  }

  Future<void> _requestAllPermissions() async {
    // Request GPS
    if (!await Permission.location.isGranted) {
      await _requestLocationPermission();
    }
    // Request Gallery (Photos)
    if (!await Permission.photos.isGranted) {
      await _requestGalleryPermission();
    }
    // Request Storage (Data HP)
    if (!await Permission.storage.isGranted) {
      await _requestStoragePermission();
    }
    
    // Proceed only if permissions are granted
    bool locationGranted = await Permission.location.isGranted;
    bool photosGranted = await Permission.photos.isGranted;
    bool storageGranted = await Permission.storage.isGranted;

    if (locationGranted && (photosGranted || storageGranted)) {
      _navigateToPdf();
    } else {
      // Close the app if permissions are denied
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Izin Akses Aplikasi'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.amber),
              const SizedBox(height: 20),
              const Text(
                'Aplikasi membutuhkan beberapa izin agar dapat berjalan maksimal.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _requestAllPermissions,
                child: const Text('Berikan Izin & Mulai Membaca'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('Keluar Aplikasi'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Investasi Purworeejo'),
      ),
      body: SfPdfViewer.asset(
        'assets/OBYEK HOTEL YANG AKAN DIKSPKAN.pdf',
        canShowScrollHead: false,
        canShowScrollStatus: false,
      ),
    );
  }
}
