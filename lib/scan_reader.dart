import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe_tap_and_pay/payment_page.dart';
import 'package:http/http.dart' as http;
import 'package:mek_stripe_terminal/mek_stripe_terminal.dart';
import 'package:permission_handler/permission_handler.dart';

class ScanPage extends StatefulWidget {
  @override
  _ScanPageState createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool isScanning = false;
  String scanStatus = "Scan readers";
  Terminal? _terminal;
  Location? _selectedLocation;
  List<Reader> _readers = [];
  Reader? _reader;

  static const bool _isSimulated = true; //if testing >> true otherwise false

  //Tap & Pay
  StreamSubscription? _onConnectionStatusChangeSub;

  var _connectionStatus = ConnectionStatus.notConnected;

  StreamSubscription? _onPaymentStatusChangeSub;

  PaymentStatus _paymentStatus = PaymentStatus.notReady;

  StreamSubscription? _onUnexpectedReaderDisconnectSub;

  StreamSubscription? _discoverReaderSub;

  void _startDiscoverReaders(Terminal terminal) {
    isScanning = true;
    _readers = [];
    final discoverReaderStream =
        terminal.discoverReaders(const LocalMobileDiscoveryConfiguration(
      isSimulated: _isSimulated,
    ));
    setState(() {
      _discoverReaderSub = discoverReaderStream.listen((readers) {
        scanStatus = "Tap on Any To connect ";
        setState(() => _readers = readers);
      }, onDone: () {
        setState(() {
          _discoverReaderSub = null;
          _readers = const [];
        });
      });
    });
  }

  void _stopDiscoverReaders() {
    unawaited(_discoverReaderSub?.cancel());
    setState(() {
      _discoverReaderSub = null;
      isScanning = false;
      scanStatus = "Scan readers";
      _readers = const [];
    });
  }

  Future<void> _connectReader(Terminal terminal, Reader reader) async {
    await _tryConnectReader(terminal, reader).then((value) {
      final connectedReader = value;
      if (connectedReader == null) {
        throw Exception("Error connecting to reader ! Please try again");
      }
      _reader = connectedReader;
    });
  }

  Future<Reader?> _tryConnectReader(Terminal terminal, Reader reader) async {
    String? getLocationId() {
      final locationId = _selectedLocation?.id ?? reader.locationId;
      if (locationId == null) throw AssertionError('Missing location');

      return locationId;
    }

    final locationId = getLocationId();

    return await terminal.connectMobileReader(
      reader,
      locationId: locationId!,
    );
  }

  Future<void> _fetchLocations() async {
    final locations = await _terminal!.listLocations();
    _selectedLocation = locations.first;
    print(_selectedLocation);
    if (_selectedLocation == null) {
      throw AssertionError(
          'Please create location on stripe dashboard to proceed further!');
    }
  }

  Future<void> requestPermissions() async {
    final permissions = [
      Permission.locationWhenInUse,
      Permission.bluetooth,
      if (Platform.isAndroid) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ],
    ];

    for (final permission in permissions) {
      final result = await permission.request();
      if (result == PermissionStatus.denied ||
          result == PermissionStatus.permanentlyDenied) return;
    }
  }

  Future<void> _initTerminal() async {
    await requestPermissions();
    await initTerminal();
    await _fetchLocations();
  }

  Future<String> getConnectionToken() async {
    http.Response response = await http.post(
      Uri.parse("https://api.stripe.com/v1/terminal/connection_tokens"),
      headers: {
        'Authorization': 'Bearer ${dotenv.env['STRIPE_SECRET']}',
        'Content-Type': 'application/x-www-form-urlencoded'
      },
    );
    Map jsonResponse = json.decode(response.body);
    print(jsonResponse);
    if (jsonResponse['secret'] != null) {
      return jsonResponse['secret'];
    } else {
      return "";
    }
  }

  Future<void> initTerminal() async {
    final connectionToken = await getConnectionToken();
    final terminal = await Terminal.getInstance(
      shouldPrintLogs: false,
      fetchToken: () async {
        return connectionToken;
      },
    );
    _terminal = terminal;
    showSnackBar("Initialized Stripe Terminal");

    _onConnectionStatusChangeSub =
        terminal.onConnectionStatusChange.listen((status) {
      print('Connection Status Changed: ${status.name}');
      _connectionStatus = status;
      scanStatus = _connectionStatus.name;
    });
    _onUnexpectedReaderDisconnectSub =
        terminal.onUnexpectedReaderDisconnect.listen((reader) {
      print('Reader Unexpected Disconnected: ${reader.label}');
    });
    _onPaymentStatusChangeSub = terminal.onPaymentStatusChange.listen((status) {
      print('Payment Status Changed: ${status.name}');
      _paymentStatus = status;
    });
    if (_terminal == null) {
      print('Please try again later!');
    }
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showSnackBar("Wait initializing Stripe Terminal");
    });

    _initTerminal();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              scanStatus,
              style: const TextStyle(fontSize: 24, color: Colors.teal),
            ),
            if (_readers.isNotEmpty)
              ..._readers.map((reader) => TextButton(
                    onPressed: () async {
                      await _connectReader(_terminal!, reader).then((v) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => PaymentPage(
                                    terminal: _terminal!,
                                  )),
                        );
                      });
                    },
                    child: Text(
                      reader.serialNumber,
                      style: const TextStyle(fontSize: 20, color: Colors.grey),
                    ),
                  )),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          isScanning
              ? _stopDiscoverReaders()
              : _startDiscoverReaders(_terminal!);
        },
        label: Text(isScanning ? 'Stop Scanning' : 'Scan Reader'),
        icon: Icon(isScanning ? Icons.stop : Icons.scanner),
        backgroundColor: Colors.teal,
        elevation: 5,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
