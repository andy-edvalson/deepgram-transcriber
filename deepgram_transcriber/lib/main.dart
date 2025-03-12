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

// The minimum Android SDK version for using audio is 21
const theSource = 'deepgram_transcriber';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deepgram Transcriber',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const TranscriptionScreen(),
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
  
  // Base Deepgram WebSocket URL for transcription
  final String _baseServerUrl = 
      'wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=16000&language=en-US';
  
  String _tempFilePath = '';

  @override
  void initState() {
    _mRecorder = FlutterSoundRecorder();
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
    
    if (_apiKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Deepgram API key first')),
      );
      return;
    }
    
    setState(() {
      transcribedText = "Starting transcription...";
      _lastReadPosition = 0;
      isRecording = true;
    });
    
    try {
      // Set up WebSocket connection with Deepgram
      final apiKey = _apiKeyController.text;
      _channel = IOWebSocketChannel.connect(
        Uri.parse(_baseServerUrl),
        headers: {'Authorization': 'Token $apiKey'},
      );

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deepgram Transcriber'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Status indicators row
          Padding(
            padding: const EdgeInsets.all(8.0),
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
                    
          // API key input at the bottom
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'Deepgram API Key',
                hintText: 'Paste your API key here',
                border: OutlineInputBorder(),
              ),
              obscureText: true, // Hide API key like a password
            ),
          ),
        ],
      ),
    );
  }
}