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
      title: 'NATS Flutter Demo Dashboard',
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

  // JetStream context
  nats.JetStream? _js;

  // JetStream Message Replay states
  bool _jsStreamInitialized = false;
  bool _jsConsumerInitialized = false;
  List<nats.Message> _jsReplayedMessages = [];
  final TextEditingController _jsStreamController =
      TextEditingController(text: 'demo-stream');
  final TextEditingController _jsStreamSubjectController =
      TextEditingController(text: 'demo.flutter.>');

  // JetStream Publisher states
  final TextEditingController _jsPubSubjectController =
      TextEditingController(text: 'demo.flutter.alerts');
  final TextEditingController _jsPubMsgIdController = TextEditingController();
  final TextEditingController _jsPubPayloadController =
      TextEditingController(text: 'JetStream alert payload!');

  // JetStream Consumer states
  final TextEditingController _jsConsumerController =
      TextEditingController(text: 'demo-consumer');
  final TextEditingController _jsBatchController =
      TextEditingController(text: '5');
  String _jsDeliverPolicy = 'all'; // 'all', 'last', 'new'

  // Key-Value Store states
  nats.KeyValue? _kv;
  bool _kvInitialized = false;
  StreamSubscription<nats.KeyValueEntry?>? _kvWatchSubscription;
  final TextEditingController _kvBucketController =
      TextEditingController(text: 'example_settings');
  final TextEditingController _kvKeyController =
      TextEditingController(text: 'config.theme');
  final TextEditingController _kvValueController =
      TextEditingController(text: 'dark-mode');

  // Object Store states
  nats.ObjectStore? _os;
  bool _osInitialized = false;
  List<nats.ObjectInfo> _osFiles = [];
  final TextEditingController _osBucketController =
      TextEditingController(text: 'example_files');
  final TextEditingController _osFilenameController =
      TextEditingController(text: 'hello.txt');
  final TextEditingController _osPayloadController =
      TextEditingController(text: 'Hello from Flutter Object Store!');

  final Map<String, nats.Subscription> _activeSubs = {};
  final Map<String, StreamSubscription> _activeStreams = {};
  final List<LogEntry> _logs = [
    LogEntry('Console initialized. Waiting for NATS Connection...', 'system')
  ];

  final TextEditingController _urlController =
      TextEditingController(text: 'ws://localhost:8080');
  final TextEditingController _subSubjectController =
      TextEditingController(text: 'demo.flutter');
  final TextEditingController _pubSubjectController =
      TextEditingController(text: 'demo.flutter');
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

          // Reset JetStream objects
          _js = null;
          _kv = null;
          _kvInitialized = false;
          _kvWatchSubscription?.cancel();
          _kvWatchSubscription = null;
          _os = null;
          _osInitialized = false;
          _osFiles.clear();

          // Reset JetStream Tab states
          _jsStreamInitialized = false;
          _jsConsumerInitialized = false;
          _jsReplayedMessages.clear();
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
    _kvWatchSubscription?.cancel();
    _client.close().catchError((_) {});
    _urlController.dispose();
    _subSubjectController.dispose();
    _pubSubjectController.dispose();
    _payloadController.dispose();
    _kvBucketController.dispose();
    _kvKeyController.dispose();
    _kvValueController.dispose();
    _osBucketController.dispose();
    _osFilenameController.dispose();
    _osPayloadController.dispose();
    _jsStreamController.dispose();
    _jsStreamSubjectController.dispose();
    _jsPubSubjectController.dispose();
    _jsPubMsgIdController.dispose();
    _jsPubPayloadController.dispose();
    _jsConsumerController.dispose();
    _jsBatchController.dispose();
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
      try {
        await _client.close();
      } catch (_) {}

      _client = nats.Client();
      _setupStatusSubscription();

      final uri = Uri.parse(url);
      _addLog('Attempting to connect to NATS WebSocket Gateway: $uri', 'info');
      await _client.connect(uri, retry: true, retryCount: 3);

      _js = _client.jetStream();
    } catch (e) {
      _addLog('Failed to connect: $e', 'error');
      try {
        await _client.close();
      } catch (_) {}
      setState(() {
        _isConnecting = false;
      });
    }
  }

  void _disconnect() {
    _addLog('Closing NATS connection...', 'info');
    _client.close().catchError((_) {});
  }

  // --- JetStream Stream & Message Replay Operations ---
  Future<void> _createJsStream() async {
    if (_js == null) return;
    final name = _jsStreamController.text.trim();
    final subject = _jsStreamSubjectController.text.trim();
    if (name.isEmpty || subject.isEmpty) {
      _addLog('Error: Stream name and subject filter cannot be empty.', 'error');
      return;
    }
    _addLog('Creating stream "$name" for subject filter "$subject"...', 'info');
    try {
      final config = nats.StreamConfig(
        name: name,
        subjects: [subject],
        storage: 'memory',
      );
      final ok = await _js!.addStream(config);
      setState(() {
        _jsStreamInitialized = ok;
      });
      _addLog('Stream "$name" created successfully: $ok', 'success');
    } catch (e) {
      _addLog('Failed to create stream: $e', 'error');
    }
  }

  Future<void> _publishJs() async {
    if (_js == null) return;
    final subject = _jsPubSubjectController.text.trim();
    final payload = _jsPubPayloadController.text;
    final msgId = _jsPubMsgIdController.text.trim();
    if (subject.isEmpty) {
      _addLog('Error: JetStream publish subject cannot be empty.', 'error');
      return;
    }
    _addLog('Publishing message to JetStream subject "$subject"...', 'info');
    try {
      final opts = msgId.isNotEmpty ? nats.PubOpts(msgId: msgId) : null;
      final ack = await _js!.publishString(subject, payload, opts: opts);
      _addLog('PubAck -> Stream: ${ack.stream}, Sequence: ${ack.sequence}, Duplicate: ${ack.duplicate}', 'success');
    } catch (e) {
      _addLog('JetStream publish failed: $e', 'error');
    }
  }

  Future<void> _createJsConsumer() async {
    if (_js == null) return;
    final stream = _jsStreamController.text.trim();
    final consumerName = _jsConsumerController.text.trim();
    if (stream.isEmpty || consumerName.isEmpty) {
      _addLog('Error: Stream name and consumer name cannot be empty.', 'error');
      return;
    }
    _addLog('Creating pull consumer "$consumerName" on stream "$stream" with deliver policy "$_jsDeliverPolicy"...', 'info');
    try {
      final config = nats.ConsumerConfig(
        durable: consumerName,
        ackPolicy: 'explicit',
        deliverPolicy: _jsDeliverPolicy,
      );
      final ok = await _js!.addConsumer(stream, config);
      setState(() {
        _jsConsumerInitialized = ok;
      });
      _addLog('Pull consumer "$consumerName" created successfully: $ok', 'success');
    } catch (e) {
      _addLog('Failed to create pull consumer: $e', 'error');
    }
  }

  Future<void> _pullJsMessages() async {
    if (_js == null) return;
    final stream = _jsStreamController.text.trim();
    final consumerName = _jsConsumerController.text.trim();
    final batchStr = _jsBatchController.text.trim();
    final batch = int.tryParse(batchStr) ?? 5;
    if (stream.isEmpty || consumerName.isEmpty) {
      _addLog('Error: Stream name and consumer name cannot be empty.', 'error');
      return;
    }
    _addLog('Pulling batch of up to $batch messages from consumer "$consumerName"...', 'info');
    try {
      final msgs = await _js!.pull(stream, consumerName, batch: batch, timeout: const Duration(seconds: 2));
      setState(() {
        _jsReplayedMessages = msgs;
      });
      _addLog('Replayed ${msgs.length} message(s) from JetStream.', 'success');
      for (var i = 0; i < msgs.length; i++) {
        final m = msgs[i];
        _addLog('Replayed [$i] Seq: ${m.streamSequence} Subj: ${m.subject} Data: "${m.string}"', 'received');
        m.ack(); // Acknowledge to NATS
      }
    } catch (e) {
      _addLog('Failed to pull messages: $e', 'error');
    }
  }

  // --- Key-Value Store Operations ---
  Future<void> _initKv() async {
    if (_js == null) return;
    final bucket = _kvBucketController.text.trim();
    if (bucket.isEmpty) {
      _addLog('Error: KV Bucket name cannot be empty.', 'error');
      return;
    }
    _addLog('Initializing Key-Value bucket "$bucket"...', 'info');
    try {
      final config = nats.KeyValueConfig(bucket: bucket, storage: 'memory');
      _kv = await _js!.keyValue(bucket, create: true, config: config);
      setState(() {
        _kvInitialized = true;
      });
      _addLog('Key-Value bucket "$bucket" active.', 'success');
    } catch (e) {
      _addLog('Failed to initialize KV bucket: $e', 'error');
    }
  }

  Future<void> _putKv() async {
    if (_kv == null) return;
    final key = _kvKeyController.text.trim();
    final value = _kvValueController.text;
    if (key.isEmpty) {
      _addLog('Error: KV Key cannot be empty.', 'error');
      return;
    }
    try {
      final revision = await _kv!.putString(key, value);
      _addLog('Put "$key" -> value: "$value" (Revision: $revision)', 'success');
    } catch (e) {
      _addLog('KV Put failed: $e', 'error');
    }
  }

  Future<void> _getKv() async {
    if (_kv == null) return;
    final key = _kvKeyController.text.trim();
    if (key.isEmpty) {
      _addLog('Error: KV Key cannot be empty.', 'error');
      return;
    }
    try {
      final entry = await _kv!.get(key);
      if (entry != null) {
        _addLog('Get "$key" -> value: "${entry.string}" (Revision: ${entry.revision})', 'success');
      } else {
        _addLog('Get "$key" -> Key not found', 'info');
      }
    } catch (e) {
      _addLog('KV Get failed: $e', 'error');
    }
  }

  Future<void> _deleteKv() async {
    if (_kv == null) return;
    final key = _kvKeyController.text.trim();
    if (key.isEmpty) {
      _addLog('Error: KV Key cannot be empty.', 'error');
      return;
    }
    try {
      final ok = await _kv!.delete(key);
      _addLog('Delete "$key" -> Success: $ok', 'success');
    } catch (e) {
      _addLog('KV Delete failed: $e', 'error');
    }
  }

  Future<void> _purgeKv() async {
    if (_kv == null) return;
    final key = _kvKeyController.text.trim();
    if (key.isEmpty) {
      _addLog('Error: KV Key cannot be empty.', 'error');
      return;
    }
    try {
      final ok = await _kv!.purge(key);
      _addLog('Purge "$key" -> Success: $ok', 'success');
    } catch (e) {
      _addLog('KV Purge failed: $e', 'error');
    }
  }

  void _watchKv() {
    if (_kv == null) return;
    final key = _kvKeyController.text.trim();
    if (key.isEmpty) {
      _addLog('Error: KV Key to watch cannot be empty.', 'error');
      return;
    }
    _addLog('Watching Key pattern: "$key"', 'info');
    _kvWatchSubscription?.cancel();
    try {
      final watchStream = _kv!.watch(key: key, includeHistory: true);
      _kvWatchSubscription = watchStream.listen((entry) {
        if (entry != null) {
          _addLog('Watch Update -> key: ${entry.key}, value: "${entry.string}", revision: ${entry.revision}', 'received');
        } else {
          _addLog('Watch Update -> key: "$key" was DELETED or PURGED.', 'info');
        }
      });
    } catch (e) {
      _addLog('KV Watch failed: $e', 'error');
    }
  }

  // --- Object Store Operations ---
  Future<void> _initOs() async {
    if (_js == null) return;
    final bucket = _osBucketController.text.trim();
    if (bucket.isEmpty) {
      _addLog('Error: Object Store Bucket name cannot be empty.', 'error');
      return;
    }
    _addLog('Initializing Object Store bucket "$bucket"...', 'info');
    try {
      final config = nats.ObjectStoreConfig(bucket: bucket, storage: 'memory');
      _os = await _js!.objectStore(bucket, create: true, config: config);
      setState(() {
        _osInitialized = true;
      });
      _addLog('Object Store bucket "$bucket" active.', 'success');
      await _refreshOsFiles();
    } catch (e) {
      _addLog('Failed to initialize Object Store bucket: $e', 'error');
    }
  }

  Future<void> _putOsFile() async {
    if (_os == null) return;
    final name = _osFilenameController.text.trim();
    final content = _osPayloadController.text;
    if (name.isEmpty) {
      _addLog('Error: Filename cannot be empty.', 'error');
      return;
    }
    try {
      final info = await _os!.putString(name, content, description: 'Uploaded via Dashboard');
      _addLog('Stored "$name" (${info.size} bytes, ${info.chunks} chunks, digest: ${info.digest})', 'success');
      await _refreshOsFiles();
    } catch (e) {
      _addLog('Object Store upload failed: $e', 'error');
    }
  }

  Future<void> _getOsFile() async {
    if (_os == null) return;
    final name = _osFilenameController.text.trim();
    if (name.isEmpty) {
      _addLog('Error: Filename cannot be empty.', 'error');
      return;
    }
    try {
      final content = await _os!.getString(name);
      if (content != null) {
        _addLog('Downloaded "$name" content:\n$content', 'success');
      } else {
        _addLog('Downloaded "$name" -> Content is null or file not found', 'info');
      }
    } catch (e) {
      _addLog('Object Store download failed: $e', 'error');
    }
  }

  Future<void> _deleteOsFile(String name) async {
    if (_os == null) return;
    try {
      final ok = await _os!.delete(name);
      _addLog('Deleted file "$name" -> Success: $ok', 'success');
      await _refreshOsFiles();
    } catch (e) {
      _addLog('Object Store file deletion failed: $e', 'error');
    }
  }

  Future<void> _refreshOsFiles() async {
    if (_os == null) return;
    try {
      final list = await _os!.list();
      setState(() {
        _osFiles = list;
      });
      _addLog('Listed ${list.length} file(s) in Object Store.', 'info');
    } catch (e) {
      _addLog('Listing Object Store files failed: $e', 'error');
    }
  }

  // --- Pub/Sub Operations ---
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
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
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
                color: const Color(0xFFA855F7).withValues(alpha: 0.12),
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
                                'NATS Flutter Demo Dashboard',
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
                              'A full-featured NATS Client running over WebSocket or TCP connections supporting JetStream.',
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
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Text(
                                'Flutter Multi-Platform Live Demo',
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
                              flex: 5,
                              child: Column(
                                children: [
                                  _buildConnectionCard(isConnected),
                                  const SizedBox(height: 20),
                                  _buildTabsCard(isConnected),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 4,
                              child: _buildConsoleCard(),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _buildConnectionCard(isConnected),
                            const SizedBox(height: 20),
                            _buildTabsCard(isConnected),
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
        color: const Color(0x3B1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1Fffffff), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
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
                          color: statusColor.withValues(alpha: 0.6),
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
              fillColor: const Color(0xFF0F172A).withValues(alpha: 0.6),
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
                          ? const Color(0xFFEF4444).withValues(alpha: 0.4)
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

  // --- Tabbed Area for Pub/Sub, JetStream, KV, and Object Store ---
  Widget _buildTabsCard(bool isConnected) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            indicatorColor: const Color(0xFF6366F1),
            labelColor: const Color(0xFF818CF8),
            unselectedLabelColor: const Color(0xFF94A3B8),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'Pub / Sub'),
              Tab(text: 'JetStream'),
              Tab(text: 'Key-Value'),
              Tab(text: 'Object Store'),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 820,
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(), // Prevent swipe to make text input smooth
              children: [
                _buildPubSubTab(isConnected),
                _buildJetStreamTab(isConnected),
                _buildKeyValueTab(isConnected),
                _buildObjectStoreTab(isConnected),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 1: Pub/Sub ---
  Widget _buildPubSubTab(bool isConnected) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSubscriptionSubCard(isConnected),
          const SizedBox(height: 16),
          _buildPublisherSubCard(isConnected),
        ],
      ),
    );
  }

  Widget _buildSubscriptionSubCard(bool isConnected) {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Subscription Manager',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 24, color: Color(0x1AFFFFFF)),
          const Text(
            'SUBJECT TO SUBSCRIBE',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subSubjectController,
                  enabled: isConnected,
                  decoration: _buildInputDecoration('e.g. demo.flutter'),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: isConnected ? _subscribe : null,
                style: _buildSubButtonStyle(isConnected),
                child: const Text('Subscribe'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'ACTIVE SUBSCRIPTIONS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),
          if (_activeSubs.isEmpty)
            const Text(
              'No active subscriptions.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
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
                  onDeleted: () => _unsubscribe(sub),
                  deleteIconColor: const Color(0xFFEF4444),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPublisherSubCard(bool isConnected) {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Publisher',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 24, color: Color(0x1AFFFFFF)),
          const Text(
            'PUBLISH SUBJECT',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pubSubjectController,
            enabled: isConnected,
            decoration: _buildInputDecoration('e.g. demo.flutter'),
          ),
          const SizedBox(height: 12),
          const Text(
            'MESSAGE PAYLOAD',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _payloadController,
            enabled: isConnected,
            maxLines: 3,
            decoration: _buildInputDecoration('Enter message text...'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isConnected ? _publish : null,
              style: _buildPrimaryButtonStyle(),
              child: const Text('Publish Message'),
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 2: JetStream ---
  Widget _buildJetStreamTab(bool isConnected) {
    final isJsActive = isConnected && _js != null;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Stream Config
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Stream Configuration',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _jsStreamInitialized
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _jsStreamInitialized ? 'ACTIVE' : 'NOT INITIALIZED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _jsStreamInitialized
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                const Text(
                  'STREAM NAME',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jsStreamController,
                  enabled: isJsActive,
                  decoration: _buildInputDecoration('demo-stream'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'SUBJECT FILTER',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _jsStreamSubjectController,
                        enabled: isJsActive,
                        decoration: _buildInputDecoration('demo.flutter.>'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: isJsActive ? _createJsStream : null,
                      style: _buildSubButtonStyle(isJsActive),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // JetStream Pub
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Publish to JetStream (with PubAck)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                const Text(
                  'SUBJECT',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jsPubSubjectController,
                  enabled: isJsActive,
                  decoration: _buildInputDecoration('demo.flutter.alerts'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'MSG-ID (FOR DEDUPLICATION)',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jsPubMsgIdController,
                  enabled: isJsActive,
                  decoration: _buildInputDecoration('Optional Msg-ID'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PAYLOAD',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jsPubPayloadController,
                  enabled: isJsActive,
                  decoration: _buildInputDecoration('Payload text...'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isJsActive ? _publishJs : null,
                    style: _buildPrimaryButtonStyle(),
                    child: const Text('Publish String to Stream'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Consumer & Replay
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pull Consumer & Message Replay',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _jsConsumerInitialized
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _jsConsumerInitialized ? 'CONSUMER ACTIVE' : 'NO CONSUMER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _jsConsumerInitialized
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                const Text(
                  'CONSUMER DURABLE NAME',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jsConsumerController,
                  enabled: isJsActive,
                  decoration: _buildInputDecoration('demo-consumer'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DELIVER POLICY',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _jsDeliverPolicy,
                            dropdownColor: const Color(0xFF1E293B),
                            decoration: InputDecoration(
                              fillColor: const Color(0xFF0F172A).withValues(alpha: 0.6),
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Messages')),
                              DropdownMenuItem(value: 'last', child: Text('Last Message')),
                              DropdownMenuItem(value: 'new', child: Text('New Messages')),
                            ],
                            onChanged: isJsActive
                                ? (val) {
                                    setState(() {
                                      _jsDeliverPolicy = val!;
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BATCH SIZE',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _jsBatchController,
                            enabled: isJsActive,
                            decoration: _buildInputDecoration('5'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isJsActive ? _createJsConsumer : null,
                        style: _buildActionButtonStyle(const Color(0xFF6366F1)),
                        child: const Text('Create Consumer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isJsActive && _jsConsumerInitialized ? _pullJsMessages : null,
                        style: _buildActionButtonStyle(const Color(0xFF10B981)),
                        child: const Text('Pull & Replay'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'REPLAYED MESSAGES',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                if (_jsReplayedMessages.isEmpty)
                  const Text(
                    'No messages replayed yet. Pull a batch to display.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _jsReplayedMessages.length,
                    itemBuilder: (context, index) {
                      final msg = _jsReplayedMessages[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x1Affffff),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x0Fffffff)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Subject: ${msg.subject}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF818CF8)),
                                ),
                                Text(
                                  'Seq: ${msg.streamSequence}',
                                  style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              msg.string,
                              style: const TextStyle(fontSize: 12.5, color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 3: Key-Value Store ---
  Widget _buildKeyValueTab(bool isConnected) {
    final isKvActive = isConnected && _kvInitialized;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Bucket Bind Card
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'KV Bucket Configuration',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isKvActive ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isKvActive ? 'ACTIVE' : 'NOT INITIALIZED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isKvActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                const Text(
                  'KV BUCKET NAME',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _kvBucketController,
                        enabled: isConnected,
                        decoration: _buildInputDecoration('e.g. app_settings'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: isConnected ? _initKv : null,
                      style: _buildSubButtonStyle(isConnected),
                      child: const Text('Create/Bind'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Operations Card
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Key-Value Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                const Text(
                  'KEY',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _kvKeyController,
                  enabled: isKvActive,
                  decoration: _buildInputDecoration('config.theme'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'VALUE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _kvValueController,
                  enabled: isKvActive,
                  decoration: _buildInputDecoration('dark-mode'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton(
                      onPressed: isKvActive ? _putKv : null,
                      style: _buildActionButtonStyle(const Color(0xFF6366F1)),
                      child: const Text('Put Value'),
                    ),
                    ElevatedButton(
                      onPressed: isKvActive ? _getKv : null,
                      style: _buildActionButtonStyle(const Color(0xFF10B981)),
                      child: const Text('Get Value'),
                    ),
                    ElevatedButton(
                      onPressed: isKvActive ? _deleteKv : null,
                      style: _buildActionButtonStyle(const Color(0xFFFBBF24)),
                      child: const Text('Delete'),
                    ),
                    ElevatedButton(
                      onPressed: isKvActive ? _purgeKv : null,
                      style: _buildActionButtonStyle(const Color(0xFFEF4444)),
                      child: const Text('Purge'),
                    ),
                    ElevatedButton(
                      onPressed: isKvActive ? _watchKv : null,
                      style: _buildActionButtonStyle(const Color(0xFFFA55F7)),
                      child: const Text('Watch Key'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 4: Object Store ---
  Widget _buildObjectStoreTab(bool isConnected) {
    final isOsActive = isConnected && _osInitialized;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Bucket Bind Card
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Object Store Configuration',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOsActive ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOsActive ? 'ACTIVE' : 'NOT INITIALIZED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isOsActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                const Text(
                  'OBJECT BUCKET NAME',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _osBucketController,
                        enabled: isConnected,
                        decoration: _buildInputDecoration('e.g. app_files'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: isConnected ? _initOs : null,
                      style: _buildSubButtonStyle(isConnected),
                      child: const Text('Create/Bind'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // File uploads
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upload / Download Files',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                const Text(
                  'FILENAME',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _osFilenameController,
                  enabled: isOsActive,
                  decoration: _buildInputDecoration('hello.txt'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'FILE CONTENT',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _osPayloadController,
                  enabled: isOsActive,
                  maxLines: 2,
                  decoration: _buildInputDecoration('file content...'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isOsActive ? _putOsFile : null,
                        style: _buildActionButtonStyle(const Color(0xFF6366F1)),
                        child: const Text('Upload String File'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isOsActive ? _getOsFile : null,
                        style: _buildActionButtonStyle(const Color(0xFF10B981)),
                        child: const Text('Download/Print File'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // File list display
          _buildGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Bucket Files',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: isOsActive ? _refreshOsFiles : null,
                      color: const Color(0xFF818CF8),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0x1AFFFFFF)),
                if (!isOsActive)
                  const Text(
                    'Bind Object Store bucket to list files.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                  )
                else if (_osFiles.isEmpty)
                  const Text(
                    'No files in bucket.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _osFiles.length,
                    itemBuilder: (context, index) {
                      final file = _osFiles[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x1Affffff),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x0Fffffff)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Size: ${file.size}B | Chunks: ${file.chunks}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: const Color(0xFFEF4444),
                              onPressed: () => _deleteOsFile(file.name),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Input styling helper ---
  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      fillColor: const Color(0xFF0F172A).withValues(alpha: 0.6),
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
    );
  }

  // --- Buttons Style Helpers ---
  ButtonStyle _buildSubButtonStyle(bool isConnected) {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0x1Affffff),
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFF475569).withValues(alpha: 0.2),
      disabledForegroundColor: const Color(0xFF94A3B8).withValues(alpha: 0.5),
      side: BorderSide(
        color: isConnected ? const Color(0x1Fffffff) : Colors.transparent,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  ButtonStyle _buildPrimaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF6366F1),
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFF475569),
      disabledForegroundColor: const Color(0xFF94A3B8),
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  ButtonStyle _buildActionButtonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color.withValues(alpha: 0.15),
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
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
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      height: 820,
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
                color: const Color(0xFF0A0F1E).withValues(alpha: 0.7),
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
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.08),
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
