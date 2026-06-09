import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart' as nats;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NATS Flutter Web Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFA855F7),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class LogEntry {
  final DateTime timestamp;
  final String message;
  final String type; // 'info', 'success', 'error', 'received', 'system'

  LogEntry(this.message, this.type) : timestamp = DateTime.now();
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  nats.Client _client = nats.Client();
  nats.Status _currentStatus = nats.Status.disconnected;
  StreamSubscription<nats.Status>? _statusSubscription;

  final Map<String, nats.Subscription> _activeSubs = {};
  final Map<String, StreamSubscription> _activeStreams = {};
  final List<LogEntry> _logs = [
    LogEntry('Console initialized. Waiting for NATS Connection...', 'system')
  ];

  final TextEditingController _urlController =
      TextEditingController(text: 'ws://localhost:8080');
  final TextEditingController _subSubjectController =
      TextEditingController(text: 'demo.wasm');
  final TextEditingController _pubSubjectController =
      TextEditingController(text: 'demo.wasm');
  final TextEditingController _payloadController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isConnecting = false;

  void _setupStatusSubscription() {
    _statusSubscription?.cancel();
    _statusSubscription = _client.statusStream.listen((status) {
      setState(() {
        _currentStatus = status;
        _isConnecting = status == nats.Status.connecting ||
            status == nats.Status.reconnecting ||
            status == nats.Status.tlsHandshake ||
            status == nats.Status.infoHandshake;
        
        _addLog(
          'NATS status: ${status.name.toUpperCase()}',
          _getStatusLogType(status),
        );

        if (status == nats.Status.disconnected || status == nats.Status.closed) {
          _activeSubs.clear();
          for (var stream in _activeStreams.values) {
            stream.cancel();
          }
          _activeStreams.clear();
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _setupStatusSubscription();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _client.close();
    _urlController.dispose();
    _subSubjectController.dispose();
    _pubSubjectController.dispose();
    _payloadController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getStatusLogType(nats.Status status) {
    switch (status) {
      case nats.Status.connected:
        return 'success';
      case nats.Status.disconnected:
      case nats.Status.closed:
        return 'system';
      default:
        return 'info';
    }
  }

  void _addLog(String message, String type) {
    setState(() {
      _logs.add(LogEntry(message, type));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'success':
        return const Color(0xFF10B981);
      case 'error':
        return const Color(0xFFEF4444);
      case 'received':
        return const Color(0xFFFBBF24);
      case 'info':
        return const Color(0xFF60A5FA);
      case 'system':
      default:
        return const Color(0xFF94A3B8);
    }
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _addLog('Error: Connection URL cannot be empty.', 'error');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      // 1. Clean up the previous client cleanly
      try {
        _client.close();
      } catch (_) {
        // Ignore initialization error
      }

      // 2. Instantiate a fresh client
      _client = nats.Client();
      _setupStatusSubscription();

      final uri = Uri.parse(url);
      _addLog('Attempting to connect to NATS WebSocket Gateway: $uri', 'info');
      await _client.connect(uri, retry: true, retryCount: 3);
    } catch (e) {
      _addLog('Failed to connect: $e', 'error');
      try {
        _client.close();
      } catch (_) {}
      setState(() {
        _isConnecting = false;
      });
    }
  }

  void _disconnect() {
    _addLog('Closing NATS connection...', 'info');
    _client.close();
  }

  void _subscribe() {
    final subject = _subSubjectController.text.trim();
    if (subject.isEmpty) {
      _addLog('Error: Subscription subject cannot be empty.', 'error');
      return;
    }

    if (_activeSubs.containsKey(subject)) {
      _addLog('Already subscribed to subject: "$subject"', 'error');
      return;
    }

    try {
      final sub = _client.sub(subject);
      _activeSubs[subject] = sub;

      final streamSub = sub.stream.listen((msg) {
        _addLog('Received on "$subject": ${msg.string}', 'received');
      });
      _activeStreams[subject] = streamSub;

      setState(() {});
      _addLog('Subscribed to subject: "$subject"', 'success');
    } catch (e) {
      _addLog('Subscription failed: $e', 'error');
    }
  }

  void _unsubscribe(String subject) {
    final sub = _activeSubs.remove(subject);
    final streamSub = _activeStreams.remove(subject);

    streamSub?.cancel();
    sub?.close();

    setState(() {});
    _addLog('Unsubscribed from subject: "$subject"', 'info');
  }

  Future<void> _publish() async {
    final subject = _pubSubjectController.text.trim();
    final payload = _payloadController.text;

    if (subject.isEmpty) {
      _addLog('Error: Publish subject cannot be empty.', 'error');
      return;
    }

    _addLog('Publishing message to subject "$subject"...', 'info');
    try {
      final success = await _client.pubString(subject, payload);
      if (success) {
        _addLog('Published message successfully!', 'success');
      } else {
        _addLog('Publish failed or queued (not connected).', 'error');
      }
    } catch (e) {
      _addLog('Publish encountered error: $e', 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    final isConnected = _currentStatus == nats.Status.connected;

    return Scaffold(
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFA855F7).withOpacity(0.12),
              ),
            ),
          ),

          // Main Layout
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Center(
                        child: Column(
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Colors.white, Color(0xFFA855F7), Color(0xFF6366F1)],
                              ).createShader(bounds),
                              child: const Text(
                                'NATS Flutter Web Dashboard',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'A full-featured NATS Client running over WebSocket connections.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF6366F1).withOpacity(0.3),
                                ),
                              ),
                              child: const Text(
                                'Flutter Web Live Demo',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF818CF8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Column or Row layout depending on screen size
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  _buildConnectionCard(isConnected),
                                  const SizedBox(height: 20),
                                  _buildSubscriptionCard(isConnected),
                                  const SizedBox(height: 20),
                                  _buildPublisherCard(isConnected),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 5,
                              child: _buildConsoleCard(),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _buildConnectionCard(isConnected),
                            const SizedBox(height: 20),
                            _buildSubscriptionCard(isConnected),
                            const SizedBox(height: 20),
                            _buildPublisherCard(isConnected),
                            const SizedBox(height: 20),
                            _buildConsoleCard(),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Glassmorphic Box ---
  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x3B1E293B), // Glassmorphism container
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1Fffffff), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }

  // --- Connection Settings ---
  Widget _buildConnectionCard(bool isConnected) {
    Color statusColor;
    switch (_currentStatus) {
      case nats.Status.connected:
        statusColor = const Color(0xFF10B981);
        break;
      case nats.Status.disconnected:
      case nats.Status.closed:
        statusColor = const Color(0xFFEF4444);
        break;
      default:
        statusColor = const Color(0xFFA855F7);
    }

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Connection Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentStatus.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 32, color: Color(0x1AFFFFFF)),
          const Text(
            'NATS WEBSOCKET GATEWAY URL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'ws://localhost:8080',
              fillColor: const Color(0xFF0F172A).withOpacity(0.6),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x1Fffffff)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x1Fffffff)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isConnected || _isConnecting ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF475569),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: isConnected ? _disconnect : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFCA5A5),
                    side: BorderSide(
                      color: isConnected
                          ? const Color(0xFFEF4444).withOpacity(0.4)
                          : const Color(0x1Fffffff),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Subscription Manager ---
  Widget _buildSubscriptionCard(bool isConnected) {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Subscription Manager',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 32, color: Color(0x1AFFFFFF)),
          const Text(
            'SUBJECT TO SUBSCRIBE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subSubjectController,
                  enabled: isConnected,
                  decoration: InputDecoration(
                    hintText: 'demo.wasm',
                    fillColor: const Color(0xFF0F172A).withOpacity(0.6),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0x1Fffffff)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0x1Fffffff)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: isConnected ? _subscribe : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0x1Affffff),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF475569).withOpacity(0.2),
                  disabledForegroundColor: const Color(0xFF94A3B8).withOpacity(0.5),
                  side: BorderSide(
                    color: isConnected ? const Color(0x1Fffffff) : Colors.transparent,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Subscribe', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'ACTIVE SUBSCRIPTIONS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          if (_activeSubs.isEmpty)
            const Text(
              'No active subscriptions.',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Color(0xFF64748B),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activeSubs.keys.map((sub) {
                return Chip(
                  label: Text(sub),
                  backgroundColor: const Color(0x1Affffff),
                  side: const BorderSide(color: Color(0x1Fffffff)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onDeleted: () => _unsubscribe(sub),
                  deleteIconColor: const Color(0xFFEF4444),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // --- Publisher ---
  Widget _buildPublisherCard(bool isConnected) {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Publisher',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 32, color: Color(0x1AFFFFFF)),
          const Text(
            'PUBLISH SUBJECT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pubSubjectController,
            enabled: isConnected,
            decoration: InputDecoration(
              hintText: 'demo.wasm',
              fillColor: const Color(0xFF0F172A).withOpacity(0.6),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x1Fffffff)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x1Fffffff)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'MESSAGE PAYLOAD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _payloadController,
            enabled: isConnected,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter message text...',
              fillColor: const Color(0xFF0F172A).withOpacity(0.6),
              filled: true,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x1Fffffff)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x1Fffffff)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isConnected ? _publish : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF475569),
                disabledForegroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Publish Message', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // --- Live Connection Logs & Messages ---
  Widget _buildConsoleCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x3B1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1Fffffff), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      height: 680,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Connection Logs & Messages',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _logs.clear();
                    _addLog('Console cleared.', 'system');
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF94A3B8),
                  backgroundColor: const Color(0x0Fffffff),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Clear Console', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const Divider(height: 32, color: Color(0x1AFFFFFF)),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F1E).withOpacity(0.7),
                border: Border.all(color: const Color(0x1Fffffff)),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(16),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final timeStr =
                      '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
                  final displayColor = _getLogColor(log.type);

                  if (log.type == 'received') {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                          left: BorderSide(color: Color(0xFFFBBF24), width: 3),
                        ),
                      ),
                      child: Text(
                        '[$timeStr] ${log.message}',
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12.5,
                          color: Color(0xFFFBBF24),
                          height: 1.4,
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      '[$timeStr] ${log.message}',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12.5,
                        color: displayColor,
                        height: 1.4,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
