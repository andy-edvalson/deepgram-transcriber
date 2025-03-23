import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_logger.dart';
import 'api_keys.dart';
import 'auth/auth_service.dart';
import 'screens/tenant_selection_screen.dart';
import 'services/deepgram_service.dart';

// The minimum Android SDK version for using audio is 21
const theSource = 'deepgram_transcriber';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthService _authService = AuthService();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _authService.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      logger.error('Failed to initialize app', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deepgram Transcriber',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: _isInitialized
          ? ValueListenableBuilder<bool>(
              valueListenable: _authService.authStateNotifier,
              builder: (context, isAuthenticated, _) {
                return isAuthenticated
                    ? const TranscriptionScreen()
                    : const TenantSelectionScreen();
              },
            )
          : const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
    );
  }
}

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  String transcribedText = "Transcription will appear here...";
  String _pendingTranscript = "";
  int _lastReadPosition = 0;
  bool _wakelockEnabled = false;

  final List<String> _finalTranscripts = [];
  final TextEditingController _apiKeyController = TextEditingController();
  bool isRecording = false;

  // Flutter Sound recorder variables
  FlutterSoundRecorder? _mRecorder;
  bool _mRecorderIsInited = false;
  IOWebSocketChannel? _channel;
  
  String _tempFilePath = '';

  @override
  void initState() {
    _mRecorder = FlutterSoundRecorder();
    _apiKeyController.text = deepgramApiKey;
    openTheRecorder().then((value) {
      setState(() {
        _mRecorderIsInited = true;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _mRecorder!.closeRecorder();
    _mRecorder = null;
    super.dispose();
  }

  Future<void> openTheRecorder() async {
    try {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        throw RecordingPermissionException('Microphone permission not granted');
      }

      await _mRecorder!.openRecorder();
      
      // Get temp file path
      var tempDir = await getTemporaryDirectory();
      _tempFilePath = '${tempDir.path}/temp_audio.pcm';
    } catch (e) {
      setState(() {
        transcribedText = "Error initializing recorder: $e";
      });
    }
  }

  void _updateTranscriptionDisplay() {
    // Combine finalized transcripts with the current pending one
    String displayText = "";
    
    // Add all finalized transcripts
    if (_finalTranscripts.isNotEmpty) {
      displayText = _finalTranscripts.join(" ");
    }
    
    // Add pending transcript if it exists
    if (_pendingTranscript.isNotEmpty) {
      if (displayText.isNotEmpty) {
        displayText += " ";
      }
      displayText += "[$_pendingTranscript]"; // Show pending transcript in brackets
    }
    
    // Update UI
    transcribedText = displayText.isEmpty 
        ? "Transcription will appear here..." 
        : displayText;
  }

  void _clearTranscriptions() {
    setState(() {
      _finalTranscripts.clear();
      _pendingTranscript = "";
      transcribedText = "Transcription will appear here...";
    });
  }

  Future<void> _startRecording() async {
    if (!_mRecorderIsInited) {
      setState(() {
        transcribedText = "Recorder not initialized";
      });
      return;
    }
    
    setState(() {
      transcribedText = "Fetching Deepgram token...";
    });
    
    // Get Deepgram token from the authenticated API
    final deepgramService = DeepgramService();
    final tokenResult = await deepgramService.getToken();
    
    if (tokenResult == null) {
      setState(() {
        transcribedText = "Failed to get Deepgram token. Please check your authentication.";
      });
      return;
    }
    
    setState(() {
      transcribedText = "Starting transcription...";
      _lastReadPosition = 0;
      isRecording = true;
      
      // Update the API key field with the token for reference
      _apiKeyController.text = tokenResult.token;
    });
    
    try {
      // Set up WebSocket connection with Deepgram using the token from the API
      final apiKey = tokenResult.token;
      
      // Check if the token response includes a URL field
      // This is important for self-hosted Deepgram instances
      String wsUrl;

      // TOOD: This should work when connecting to a working self-hosted Deepgram instance
      // if (tokenResult.url.isNotEmpty) {
      //   // Use the URL from the token response, converting from HTTPS to WSS
      //   wsUrl = tokenResult.url.replaceFirst('https://', 'wss://');
      //   logger.info('Using custom Deepgram URL from token: $wsUrl');
      // } else {
      //   // Fall back to the direct Deepgram SaaS URL
      //   wsUrl = 'wss://api.deepgram.com';
      //   logger.info('Using default Deepgram SaaS URL: $wsUrl');
      // }

      wsUrl = 'wss://api.deepgram.com';
      logger.info('Using default Deepgram SaaS URL: $wsUrl');
      
      // Append the WebSocket path and parameters
      final fullUrl = '$wsUrl/v1/listen?encoding=linear16&sample_rate=16000&language=en-US';
      
      logger.info('Connecting to Deepgram WebSocket: $fullUrl');
      
      // The Deepgram WebSocket API uses a different authentication method than our backend
      // It requires a Token authentication in the headers, not a session cookie
      logger.info('Using Deepgram token: ${apiKey.substring(0, 5)}... for WebSocket authentication');
      
      final headers = {'Authorization': 'Token $apiKey'};
      logger.info('WebSocket headers: $headers');
      
      try {
        _channel = IOWebSocketChannel.connect(
          Uri.parse(fullUrl),
          headers: headers,
        );
        
        logger.info('WebSocket connection established');
      } catch (e) {
        logger.error('Error connecting to WebSocket: $e');
        setState(() {
          transcribedText = "Failed to connect to Deepgram: $e";
          isRecording = false;
        });
        return;
      }

      try {
        WakelockPlus.enable();
        _wakelockEnabled = true;
        logger.info("Keep screen on enabled during recording");
      } catch (e) {
        logger.error("Failed to keep screen on", error: e);
        // Continue anyway - this is not critical
      }
      
      // Listen for transcription results
      _channel!.stream.listen(
        (dynamic message) {
          logger.info('Received message: $message');
          try {
            final parsedJson = jsonDecode(message);
            // Extract transcript from Deepgram response
            if (parsedJson['channel'] != null && 
                parsedJson['channel']['alternatives'] != null && 
                parsedJson['channel']['alternatives'].isNotEmpty) {

              final alternative = parsedJson['channel']['alternatives'][0];
              final transcript = alternative['transcript'] ?? '';
              final isFinal = parsedJson['is_final'] ?? false;

              logger.debug('Transcript: "$transcript", is_final: $isFinal');

              setState(() {
                if (isFinal) {
                  // This is a finalized transcript block
                  if (transcript.isNotEmpty) {
                    // Add to our list of final transcripts
                    _finalTranscripts.add(transcript);
                    logger.info('Added final transcript: "$transcript"');
                    
                    // Reset pending transcript since this block is complete
                    _pendingTranscript = "";
                  }
                } else {
                  // This is an interim result (not finalized)
                  _pendingTranscript = transcript;
                  logger.debug('Updated pending transcript: "$_pendingTranscript"');
                }
                
                // Update display text - combine final transcripts with current pending one
                _updateTranscriptionDisplay();
              });
            }
          } catch (e) {
            logger.warning('Error parsing message: $message, error: $e');
          }
        },
        onError: (error) {
          logger.error("WebSocket error", error: error, stackTrace: StackTrace.current);
          setState(() {
            _finalTranscripts.add("Error: $error");
            _updateTranscriptionDisplay();
            isRecording = false;
          });
          _stopRecording();
        },
        onDone: () {
          // WebSocket closed
          if (isRecording) {
            logger.info("WebSocket connection closed unexpectedly");
            setState(() {
              _finalTranscripts.add("Connection closed unexpectedly");
              _updateTranscriptionDisplay();
              isRecording = false;
            });
          }
        },
      );
      
      // Start recording to file
      await _mRecorder!.startRecorder(
        toFile: _tempFilePath,
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 16000,
      );
      
      // Setup a periodic timer to read and send PCM data
      Timer.periodic(const Duration(milliseconds: 300), (timer) async {
        if (!isRecording) {
          timer.cancel();
          return;
        }
        
        try {
          final file = File(_tempFilePath);
          if (await file.exists()) {
            final fileSize = await file.length();
            
            // Only process if there's new data
            if (fileSize > _lastReadPosition) {
              // Open file for reading from the last position
              final raf = await file.open(mode: FileMode.read);
              try {
                // Seek to where we left off
                await raf.setPosition(_lastReadPosition);
                
                // Read only the new data
                final newDataSize = fileSize - _lastReadPosition;
                final bytes = await raf.read(newDataSize);
                
                // Update the last read position
                _lastReadPosition = fileSize;
                
                if (bytes.isNotEmpty && _channel != null) {
                  logger.debug("Sending ${bytes.length} new bytes to Deepgram");
                  _channel!.sink.add(bytes);
                }
              } finally {
                await raf.close();
              }
            }
          }
        } catch (e) {
          logger.error('Error reading audio file', error: e);
        }
      });

      
    } catch (e) {
      setState(() {
        transcribedText += "\nFailed to start recording: $e";
        isRecording = false;
      });
    }
  }
  
  Future<void> _stopRecording() async {
    if (!isRecording) return;
    _wakelockEnabled = false;

    try {
      WakelockPlus.disable();
      logger.info("Screen can turn off normally now");
    } catch (e) {
      logger.error("Failed to reset screen timeout", error: e);
    }
    
    _lastReadPosition = 0;
    try {
      // Stop recording
      if (_mRecorder != null && _mRecorder!.isRecording) {
        await _mRecorder!.stopRecorder();
      }
      
      // Close WebSocket
      _channel?.sink.close();
      _channel = null;
      
      setState(() {
        transcribedText += "\n--- Transcription ended ---";
        isRecording = false;
      });
      
      // Clean up temporary file
      if (File(_tempFilePath).existsSync()) {
        try {
          await File(_tempFilePath).delete();
        } catch (e) {
          logger.warning('Error deleting temp file: $e');
        }
      }
      
    } catch (e) {
      setState(() {
        transcribedText += "\nError stopping recording: $e";
        isRecording = false;
      });
    }
  }
  
  void _toggleRecording() {
    if (isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deepgram Transcriber'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              authService.logout();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged out successfully')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Tenant info
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    const Icon(Icons.domain, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Tenant: ${authService.currentTenant ?? "Unknown"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Authenticated',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Status indicators row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Recorder status (left aligned)
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _mRecorderIsInited ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_mRecorderIsInited 
                      ? 'Recorder ready' 
                      : 'Initializing recorder...',
                      style: TextStyle(
                        color: _mRecorderIsInited ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
                
                // Screen on indicator (right aligned)
                Row(
                  children: [
                    Icon(
                      Icons.stay_current_portrait,
                      color: _wakelockEnabled ? Colors.amber : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _wakelockEnabled 
                          ? 'Screen will stay on' 
                          : 'Screen will time out normally',
                      style: TextStyle(
                        color: _wakelockEnabled ? Colors.amber : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Transcription display area
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: SingleChildScrollView(
                child: Text(
                  transcribedText,
                  style: const TextStyle(fontSize: 16.0),
                ),
              ),
            ),
          ),
          
          // Control buttons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _mRecorderIsInited ? _toggleRecording : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecording ? Colors.red : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                  ),
                  child: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _clearTranscriptions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                  ),
                  child: const Text('Clear Text'),
                ),
              ],
            ),
          ),
                    
          // Token display at the bottom
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _apiKeyController,
              readOnly: true, // Make it read-only since we get the token from the API
              decoration: const InputDecoration(
                labelText: 'Deepgram Token (Auto-fetched)',
                hintText: 'Token will be fetched automatically when recording starts',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true, // Hide token like a password
            ),
          ),
        ],
      ),
    );
  }
}
