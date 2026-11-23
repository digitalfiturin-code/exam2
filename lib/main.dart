import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';

WebViewEnvironment? webViewEnvironment;
bool isWebViewAvailable = true;
String webViewErrorMessage = "";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Penangkal crash global agar aplikasi tidak menutup seketika
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint("Flutter Error Caught: ${details.exceptionAsString()}");
  };

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        fullScreen: true,
        center: true,
        backgroundColor: Color(0xFFF8FAFC),
        skipTaskbar: false, // Set false agar terlihat saat proses loading
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
      );
      
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        try {
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setFullScreen(true);
          await windowManager.setResizable(false);
          await windowManager.setPreventClose(true);
          await windowManager.setAlwaysOnTop(true);
        } catch (e) {
          debugPrint("WindowManager configure error: $e");
        }
      });
    } catch (e) {
      debugPrint("WindowManager Initialization Error: $e");
    }
  }

  // Khusus Windows: Inisialisasi WebView2 Environment secara aman
  if (Platform.isWindows) {
    try {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion == null || availableVersion.isEmpty) {
        isWebViewAvailable = false;
        webViewErrorMessage = "Microsoft Edge WebView2 Runtime belum terpasang di komputer ini.";
      } else {
        webViewEnvironment = await WebViewEnvironment.create();
      }
    } catch (e) {
      debugPrint("WebViewEnvironment Error: $e");
      isWebViewAvailable = false;
      webViewErrorMessage = "Gagal menginisialisasi engine browser: $e\nPastikan Microsoft Edge WebView2 Runtime terpasang.";
    }
  }

  runApp(MaterialApp(
    theme: ThemeData(
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
      ),
      useMaterial3: false,
    ),
    home: const ExamBrowserFinal(),
    debugShowCheckedModeBanner: false,
  ));
}

class ExamBrowserFinal extends StatefulWidget {
  const ExamBrowserFinal({super.key});

  @override
  State<ExamBrowserFinal> createState() => _ExamBrowserFinalState();
}

class _ExamBrowserFinalState extends State<ExamBrowserFinal> with WidgetsBindingObserver, WindowListener {
  InAppWebViewController? webViewController;
  final String customUserAgent = "MSAT-ExamBrowser-V1";
  final String exitPassword = "085086";
  final String schoolName = "SMPN 4 DEPOK";
  
  // === PENGATURAN SUARA ALERT ===
  // Ganti ke `true` jika ingin mengaktifkan suara alert.mp3 (alarm & popup)
  // Ganti ke `false` jika ingin menonaktifkan suara sepenuhnya (mode hening)
  final bool enableAlertAudio = false;

  // === PENGATURAN VOLUME SUARA ALERT (0.1 - 1.0) ===
  final double alertAudioVolume = 0.8;

  // === PENGATURAN KECERAHAN LAYAR (0.1 - 1.0) ===
  final double autoScreenBrightness = 0.35;
  
  final AudioPlayer audioPlayer = AudioPlayer();
  final TextEditingController _urlController = TextEditingController();
  
  bool isUrlSet = true;
  String currentUrl = "https://sites.google.com/guru.smp.belajar.id/asesmenpasmer/home";
  bool isLoading = true;
  bool isError = false;
  double progress = 0;
  String errorMsg = "";

  // Custom Premium Security Variables
  Timer? _securityCheckTimer;
  bool isSecurityViolation = false;
  String securityViolationReason = "";
  
  // Security Layer
  double? initialAspectRatio;
  bool isViolationReported = false;
  final String secureToken = 'TVNBVC1FWEFNLVNFQ1VSRS0yMDI2';

  // Audio State & Debounce Control
  bool _isAudioAlarmPlaying = false;
  StreamSubscription? _audioCompleteSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    
    // Reset audio state saat pemutaran selesai
    _audioCompleteSub = audioPlayer.onPlayerComplete.listen((_) {
      _isAudioAlarmPlaying = false;
    });

    _setupExamEnvironment();
    _checkSavedUrl();
    _startSecurityChecks();
  }

  @override
  void onWindowBlur() {
    if (isUrlSet) {
      if (!Platform.isWindows) {
        _reportViolation("Aplikasi kehilangan fokus (Alt+Tab/Win Key)");
      }
    }
  }

  @override
  void onWindowMinimize() {
    if (isUrlSet) {
      _reportViolation("Aplikasi kehilangan fokus (Alt+Tab/Win Key)");
    }
  }

  Future<void> _checkSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('exam_url');
    setState(() {
      if (saved != null && saved.isNotEmpty) {
        currentUrl = saved;
      } else {
        currentUrl = "https://sites.google.com/guru.smp.belajar.id/asesmenpasmer/home";
      }
      isUrlSet = true;
      isLoading = false;
    });
  }

  Future<void> _saveAndOpenUrl(String url) async {
    if (url.trim().isEmpty) return;
    
    setState(() => isLoading = true);

    // Auto-fix URL format
    String formattedUrl = url.trim();
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      final isLocalIp = RegExp(r'^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.0\.0\.1|localhost)').hasMatch(formattedUrl);
      if (isLocalIp) {
        formattedUrl = 'http://$formattedUrl';
      } else {
        formattedUrl = 'https://$formattedUrl';
      }
    }

    try {
      final Uri parsedUri = Uri.parse(formattedUrl);
      if (!parsedUri.hasAuthority) {
        throw "Format URL tidak valid";
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('exam_url', formattedUrl);
      
      setState(() {
        currentUrl = formattedUrl;
        isUrlSet = true;
        isLoading = true;
        isError = false;
      });

      webViewController?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(formattedUrl),
          headers: {
            'X-MSAT-Auth-Token': secureToken,
          },
        ),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
        isError = true;
        errorMsg = "URL Tidak Valid!";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Format URL tidak valid!'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _resetUrl() async {
    setState(() {
      isLoading = true;
      isError = false;
    });
    webViewController?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(currentUrl),
        headers: {
          'X-MSAT-Auth-Token': secureToken,
        },
      ),
    );
  }

  Future<void> _setupExamEnvironment() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await WakelockPlus.enable();
        await startKioskMode();
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await InAppWebViewController.clearAllCache();

        if (enableAlertAudio) {
          final session = await audio_session.AudioSession.instance;
          await session.configure(const audio_session.AudioSessionConfiguration(
            avAudioSessionCategory: audio_session.AVAudioSessionCategory.playback,
            avAudioSessionCategoryOptions: audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker,
            androidAudioAttributes: audio_session.AndroidAudioAttributes(
              usage: audio_session.AndroidAudioUsage.alarm,
              contentType: audio_session.AndroidAudioContentType.sonification,
            ),
          ));
        }

        // === Kecerahan Otomatis ===
        try {
          await ScreenBrightness.instance.setScreenBrightness(autoScreenBrightness);
        } catch (e) {
          debugPrint("Brightness control error: $e");
        }

        // === Kunci Volume di 40% & Nonaktifkan Tombol Volume (Android) ===
        if (Platform.isAndroid) {
          try {
            const platform = MethodChannel('com.xcoding.exam_browser/security');
            await platform.invokeMethod('setVolume');
          } catch (e) {
            debugPrint("Volume lock error: $e");
          }
        }
      } else {
        // Windows Desktop
        try {
          await WakelockPlus.enable();
        } catch (e) {
          debugPrint("Wakelock error Windows: $e");
        }
      }
    } catch (e) {
      debugPrint("Setup error: $e");
    }
  }

  @override
  void dispose() {
    _securityCheckTimer?.cancel();
    _audioCompleteSub?.cancel();
    _stopViolationAlarm();
    WakelockPlus.disable();
    if (!Platform.isWindows) {
      stopKioskMode();
    }
    audioPlayer.dispose();
    _urlController.dispose();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _checkSplitScreen();
  }

  void _checkSplitScreen() {
    if (!isUrlSet || isViolationReported) return;

    final double currentAspectRatio =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.aspectRatio;

    if (initialAspectRatio == null) {
      initialAspectRatio = currentAspectRatio;
      return;
    }

    // Jika keyboard sedang terbuka (viewInsets.bottom > 0), abaikan pengecekan
    // karena keyboard akan merubah rasio layar secara signifikan.
    if (MediaQuery.of(context).viewInsets.bottom > 0) return;

    // Jika rasio berubah lebih dari 20%, anggap sebagai split screen
    if ((currentAspectRatio - initialAspectRatio!).abs() > 0.20) {
      _reportViolation("Layar terbagi (Split Screen)");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _checkSplitScreen(); // Re-check on resume
      _runSecurityCheck(); // Re-check kiosk mode & security immediately
    }
    if (isUrlSet && (state == AppLifecycleState.paused)) {
      _reportViolation("Aplikasi ditinggalkan (Home/Recent/Alt+Tab)");
    }
  }

  void _playViolationAlarm() async {
    if (!enableAlertAudio || _isAudioAlarmPlaying) return;
    _isAudioAlarmPlaying = true;

    bool playedNatively = false;
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.xcoding.exam_browser/security');
        await platform.invokeMethod('playAlarm');
        playedNatively = true;
      } catch (e) {
        debugPrint("Native playAlarm not available, fallback to AudioPlayer: $e");
        playedNatively = false;
      }
    }

    if (!playedNatively) {
      try {
        await audioPlayer.stop(); // Hentikan audio sebelumnya agar tidak menumpuk
        await audioPlayer.setVolume(alertAudioVolume);
        await audioPlayer.play(AssetSource('alert.mp3'));
      } catch (e) {
        debugPrint("AudioPlayer play error: $e");
        _isAudioAlarmPlaying = false;
      }
    }
  }

  void _stopViolationAlarm() async {
    _isAudioAlarmPlaying = false;
    if (!enableAlertAudio) return;

    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.xcoding.exam_browser/security');
        await platform.invokeMethod('stopAlarm');
      } catch (e) {
        debugPrint("Native stopAlarm error: $e");
      }
    }
    try {
      await audioPlayer.stop();
    } catch (e) {
      debugPrint("AudioPlayer stop error: $e");
    }
  }

  void _reportViolation(String reason) {
    if (isViolationReported) return;
    isViolationReported = true;

    // Play Alert Sound (Tembus mode Silent via Android STREAM_ALARM + AudioPlayer di Windows)
    _playViolationAlarm();

    // 1. Laporan Langsung via HTTP (Paling Ampuh & Anti-Freeze)
    _reportViolationDirect(reason);

    // 2. Laporan via WebView (Jika masih aktif)
    webViewController?.evaluateJavascript(
      source: "if(typeof reportViolation === 'function') { reportViolation('$reason'); }"
    );

    // 3. UI Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("PELANGGARAN: $reason"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
    
    // Reset flag after 5 seconds to allow reporting again if needed (or keep true to block)
    Future.delayed(const Duration(seconds: 5), () => isViolationReported = false);
  }

  Future<void> _reportViolationDirect(String reason) async {
    try {
      final Uri uri = Uri.parse(currentUrl);
      final String baseUrl = "${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 && uri.port != 0 ? ':${uri.port}' : ''}/";
      final String reportUrl = "${baseUrl}student/exam/report_violation_api";
      
      await http.post(
        Uri.parse(reportUrl),
        headers: {
          'X-MSAT-Auth-Token': secureToken,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'reason': reason,
          'url': currentUrl,
        },
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("Direct report failed: $e");
    }
  }

  void _startSecurityChecks() {
    _securityCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      await _runSecurityCheck();
    });
  }

  Future<void> _runSecurityCheck() async {
    if (!isUrlSet) return; // Jalankan pengecekan hanya saat ujian aktif

    // 1. Deteksi Multi-Monitor (Windows)
    if (Platform.isWindows) {
      try {
        List<Display> displays = await ScreenRetriever.instance.getAllDisplays();
        if (displays.length > 1) {
          _triggerSecurityBlocking("Menggunakan Lebih dari Satu Layar (Multi-Monitor)");
          return;
        }
      } catch (e) {
        debugPrint("Error checking displays: $e");
      }
    }

    // 2. Deteksi Native Android via MethodChannel & Kiosk Mode
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.xcoding.exam_browser/security');
        final Map<dynamic, dynamic>? results = await platform.invokeMethod('checkSecurity');
        if (results != null) {
          final bool isDevOptionsEnabled = results['isDevOptionsEnabled'] ?? false;
          final bool isEmulator = results['isEmulator'] ?? false;
          final bool isHeadsetConnected = results['isHeadsetConnected'] ?? false;

          if (isDevOptionsEnabled) {
            _triggerSecurityBlocking("Opsi Pengembang (Developer Options) atau USB Debugging Aktif");
            return;
          }
          if (isEmulator) {
            _triggerSecurityBlocking("Aplikasi Dijalankan di Emulator / Virtual Machine");
            return;
          }
          if (isHeadsetConnected) {
            _triggerSecurityBlocking("Earphone / Headphone (Bluetooth atau Kabel) Terhubung");
            return;
          }
        }
      } catch (e) {
        debugPrint("Android native check failed: $e");
      }

      // 3. PAKSA PENYEMATAN APLIKASI (Strict Kiosk Guard)
      try {
        final mode = await getKioskMode();
        if (mode != KioskMode.enabled) {
          _triggerSecurityBlocking("Penyematan Aplikasi (App Pinning) Wajib Diaktifkan");
          return;
        }
      } catch (e) {
        debugPrint("Kiosk mode check failed: $e");
      }
    }

    // Jika tidak ada pelanggaran, hilangkan overlay blokir dan matikan alarm
    if (isSecurityViolation) {
      _stopViolationAlarm();
      setState(() {
        isSecurityViolation = false;
        securityViolationReason = "";
      });
    }
  }

  void _triggerSecurityBlocking(String reason) {
    if (isSecurityViolation && securityViolationReason == reason) return;

    setState(() {
      isSecurityViolation = true;
      securityViolationReason = reason;
    });

    _reportViolation("Pelanggaran Keamanan: $reason");
  }

  void _showExitDialog({bool isReset = false}) {
    // Mainkan alert.mp3 pada volume yang telah diatur saat dialog keluar muncul (jika audio diaktifkan dan belum bermain)
    if (!isReset && enableAlertAudio && !_isAudioAlarmPlaying) {
      try {
        _isAudioAlarmPlaying = true;
        audioPlayer.stop().then((_) {
          audioPlayer.setVolume(alertAudioVolume);
          audioPlayer.play(AssetSource('alert.mp3'));
        });
      } catch (e) {
        debugPrint("Exit dialog audio error: $e");
        _isAudioAlarmPlaying = false;
      }
    }
    final TextEditingController _passController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 25, spreadRadius: 4)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: isReset ? Colors.amber.withOpacity(0.1) : Colors.indigoAccent.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        isReset ? Icons.settings_backup_restore_rounded : Icons.lock_person_rounded,
                        color: isReset ? Colors.amber : Colors.indigoAccent,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isReset ? 'RESET KONFIGURASI' : 'PASSWORD',
                        style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  children: [
                    Text(
                      isReset ? 'Masukkan PIN untuk mengganti link ujian:' : 'Masukkan PIN untuk menutup aplikasi:',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passController,
                      obscureText: true,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 10),
                      decoration: InputDecoration(
                        hintText: "••••",
                        hintStyle: TextStyle(color: Colors.black.withOpacity(0.1)),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.indigoAccent, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('BATAL', style: TextStyle(color: Colors.black38, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_passController.text == exitPassword) {
                                _stopViolationAlarm();
                                Navigator.pop(context);
                                if (isReset) {
                                  _resetUrl();
                                } else {
                                  if (Platform.isWindows) {
                                    exit(0);
                                  } else {
                                    stopKioskMode().then((_) => SystemNavigator.pop());
                                  }
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PIN Salah!'), backgroundColor: Colors.redAccent),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isReset ? Colors.amber : const Color(0xFF4F46E5),
                              foregroundColor: isReset ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: Text(isReset ? 'RESET' : 'KELUAR', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("Scan QR Link Ujian")),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  Navigator.pop(context);
                  _saveAndOpenUrl(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final double rawTopPadding = MediaQuery.viewPaddingOf(context).top;
    final double topPadding = isMobile ? (rawTopPadding > 24.0 ? rawTopPadding : 24.0) : 0.0;

    if (Platform.isWindows && (!isWebViewAvailable || webViewEnvironment == null)) {
      return _buildWebView2MissingScreen();
    }

    if (isLoading && !isUrlSet) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
      );
    }

    if (!isUrlSet) return _buildSetupScreen(topPadding);
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Tombol back dimatikan total agar siswa tidak terganggu
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: isSecurityViolation
            ? SafeArea(child: _buildSecurityViolationOverlay())
            : SafeArea(
                top: false,
                right: isMobile,
                left: isMobile,
                child: Column(
                  children: [
                    // Top Bar Navigation (Clean Off-White)
                    Container(
                      padding: EdgeInsets.only(
                        top: topPadding > 0 ? topPadding : 8,
                        bottom: 8,
                        left: 16,
                        right: 8, // Sedikit dikurangi agar lebih menempel
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // KELOMPOK KIRI: Logo + Nama Sekolah
                          Expanded(
                            child: Row(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: () => _showExitDialog(),
                                  child: Image.asset('assets/logo.png', height: 24, errorBuilder: (_,__,___) => const Icon(Icons.school, color: Color(0xFF4F46E5), size: 20)),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    schoolName,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // KELOMPOK KANAN: Jam + Tombol
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Digital Clock
                              StreamBuilder(
                                stream: Stream.periodic(const Duration(seconds: 1)),
                                builder: (context, snapshot) {
                                  final now = DateTime.now();
                                  return Text(
                                    "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
                                    style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace'),
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                              // Tombol Kembali Web
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF475569), size: 22),
                                onPressed: () async {
                                  if (await webViewController?.canGoBack() ?? false) {
                                    await webViewController?.goBack();
                                  } else {
                                    _resetUrl();
                                  }
                                },
                                tooltip: 'Kembali',
                              ),
                              // Tombol Home Ujian
                              IconButton(
                                icon: const Icon(Icons.home_rounded, color: Color(0xFF475569), size: 22),
                                onPressed: () => _resetUrl(),
                                tooltip: 'Menu Utama Ujian',
                              ),
                              // Refresh Button
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF475569), size: 22),
                                onPressed: () => webViewController?.reload(),
                                tooltip: 'Refresh Halaman',
                              ),
                              // Exit Button
                              IconButton(
                                icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 24),
                                onPressed: () => _showExitDialog(),
                                tooltip: 'Keluar',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
              if (isLoading || progress < 1.0)
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                ),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      webViewEnvironment: webViewEnvironment,
                      initialUrlRequest: URLRequest(
                        url: WebUri(currentUrl),
                        headers: {
                          'X-MSAT-Auth-Token': secureToken,
                        },
                      ),
                      initialSettings: InAppWebViewSettings(
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true, // Tangkap link target="_blank" dan window.open()
                        javaScriptCanOpenWindowsAutomatically: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        cacheEnabled: true,
                        clearCache: false,
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        transparentBackground: true,
                        disableContextMenu: true, // Matikan klik kanan / inspeksi elemen
                        supportZoom: true, // Izinkan zoom secukupnya jika soal ujian memiliki gambar/tabel kecil
                        builtInZoomControls: false,
                        displayZoomControls: false,
                        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                        allowFileAccess: true,
                        allowContentAccess: true,
                      ),
                      onWebViewCreated: (controller) async {
                        webViewController = controller;
                        try {
                          CookieManager cookieManager = CookieManager.instance();
                          await cookieManager.setCookie(
                            url: WebUri(currentUrl),
                            name: "MSAT_SECURE_TOKEN",
                            value: secureToken,
                            isHttpOnly: false,
                            isSecure: currentUrl.startsWith("https"),
                          );
                        } catch (e) {
                          debugPrint("Failed to set security cookie: $e");
                        }
                      },
                      onCreateWindow: (controller, createWindowAction) async {
                        // Tangkap link yang meminta buka tab/window baru dan muat di layar aplikasi yang sama
                        final url = createWindowAction.request.url;
                        if (url != null) {
                          controller.loadUrl(urlRequest: URLRequest(url: url));
                        }
                        return true;
                      },
                      shouldOverrideUrlLoading: (controller, navigationAction) async {
                        final uri = navigationAction.request.url;
                        if (uri == null) return NavigationActionPolicy.CANCEL;

                        final scheme = uri.scheme.toLowerCase();
                        // Izinkan semua link web HTTP dan HTTPS
                        if (scheme == 'http' || scheme == 'https') {
                          return NavigationActionPolicy.ALLOW;
                        }

                        // Blokir skema luar (intent://, market://, tel:, whatsapp:, dll.)
                        debugPrint("Blocked non-web navigation: $uri");
                        return NavigationActionPolicy.CANCEL;
                      },
                      onReceivedServerTrustAuthRequest: (controller, challenge) async {
                        // Izinkan koneksi SSL self-signed untuk server lokal sekolah
                        return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                      },
                      onLoadStart: (controller, url) {
                        debugPrint("Navigating to: $url");
                        setState(() {
                          isLoading = true;
                          isError = false;
                        });
                      },
                      onProgressChanged: (controller, p) {
                        setState(() {
                          progress = p / 100;
                          if (progress == 1.0) isLoading = false;
                        });
                      },
                      onLoadError: (controller, url, code, message) {
                        debugPrint("onLoadError: $code - $message for $url");
                        setState(() {
                          isError = true;
                          errorMsg = "$message ($code)";
                        });
                      },
                      onReceivedHttpError: (controller, request, errorResponse) {
                        debugPrint("onReceivedHttpError: ${errorResponse.statusCode} ${errorResponse.reasonPhrase}");
                        if ((errorResponse.statusCode ?? 0) >= 400) {
                          setState(() {
                            isError = true;
                            errorMsg = "HTTP ${errorResponse.statusCode}: ${errorResponse.reasonPhrase}";
                          });
                        }
                      },
                      onLoadStop: (controller, url) {
                        // Simpan rasio layar awal untuk deteksi split screen
                        initialAspectRatio ??= WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.aspectRatio;
                      },
                    ),
                    if (isError) _buildErrorView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupScreen(double topPadding) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Stack(
            children: [
              Positioned(
                top: 10 + topPadding,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.power_settings_new_rounded, color: Colors.black38, size: 28),
                  onPressed: _showExitDialog,
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(35),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 25, spreadRadius: 2)
                              ]
                            ),
                            child: Image.asset('assets/logo.png', height: 100, errorBuilder: (_,__,___) => const Icon(Icons.school, size: 100, color: Color(0xFF4F46E5))),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            schoolName,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                        child: const Text("SMART EXAM SOLUTION", style: TextStyle(color: Color(0xFF4F46E5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      ),
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, spreadRadius: 2)
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text("KONFIGURASI UJIAN", style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                            const SizedBox(height: 25),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openScanner,
                                icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
                                label: const Text("SCAN QR CODE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  elevation: 4,
                                  shadowColor: const Color(0xFF4F46E5).withOpacity(0.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 25),
                            Row(
                              children: [
                                const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 15),
                                  child: Text("ATAU", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                                const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                              ],
                            ),
                            const SizedBox(height: 25),
                            TextField(
                              controller: _urlController,
                              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                hintText: "Ketik Link Ujian Manual...",
                                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                prefixIcon: const Icon(Icons.link, color: Color(0xFF64748B)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.send_rounded, color: Color(0xFF4F46E5)),
                                  onPressed: () => _saveAndOpenUrl(_urlController.text),
                                ),
                              ),
                              onSubmitted: (val) => _saveAndOpenUrl(val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 18),
                            SizedBox(width: 10),
                            Text(
                              "Pastikan Internet & Baterai Stabil",
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 80, color: Colors.redAccent),
            const SizedBox(height: 20),
            const Text("Gagal Memuat Halaman", style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                "Periksa koneksi jaringan Anda atau server ujian Anda",
                style: TextStyle(color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
            ),
            if (errorMsg.isNotEmpty && errorMsg != "Gagal memuat halaman ujian.")
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  errorMsg,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  isError = false;
                });
                webViewController?.reload();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Coba Lagi", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _showExitDialog(isReset: true),
              child: const Text("Ganti Link", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityViolationOverlay() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFF8FAFC),
      child: Stack(
        children: [
          // Tombol Keluar dengan PIN Guru di pojok kanan atas
          Positioned(
            top: 15,
            right: 15,
            child: IconButton(
              icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 28),
              onPressed: () => _showExitDialog(),
              tooltip: 'Keluar dengan PIN Guru',
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.redAccent.withOpacity(0.2), width: 2),
                    ),
                    child: const Icon(
                      Icons.gpp_bad_rounded,
                      color: Colors.redAccent,
                      size: 80,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    "BLOKIR KEAMANAN",
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      "TERDETEKSI TINDAKAN KECURANGAN",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, spreadRadius: 2)
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Jenis Pelanggaran:",
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          securityViolationReason,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          securityViolationReason.contains("Penyematan")
                              ? "Ujian dikunci! Klik tombol di bawah dan izinkan penyematan layar untuk melanjutkan ujian."
                              : "Harap lepaskan perangkat tambahan / matikan opsi pengembang untuk melanjutkan ujian!",
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  if (securityViolationReason.contains("Penyematan"))
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (Platform.isAndroid) {
                          await startKioskMode();
                        }
                        await Future.delayed(const Duration(milliseconds: 500));
                        await _runSecurityCheck();
                      },
                      icon: const Icon(Icons.push_pin_rounded, color: Colors.white, size: 22),
                      label: const Text(
                        "SEMATKAN APLIKASI SEKARANG",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _runSecurityCheck(),
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      label: const Text(
                        "PERIKSA ULANG KONDISI",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView2MissingScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 56,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Komponen Browser Diperlukan",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                webViewErrorMessage.isNotEmpty
                    ? webViewErrorMessage
                    : "Aplikasi ExamBrowser membutuhkan 'Microsoft Edge WebView2 Runtime' agar dapat menampilkan halaman ujian di Windows.",
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse("https://go.microsoft.com/fwlink/p/?LinkId=2124703");
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      debugPrint("Launch url error: $e");
                    }
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    "Unduh WebView2 Runtime (Microsoft)",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => exit(0),
                child: const Text(
                  "Tutup Aplikasi",
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
