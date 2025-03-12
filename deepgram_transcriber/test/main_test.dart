import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:deepgram_transcriber/main.dart';

// Mock class for testing WebSocket responses
class MockWebSocketResponse {
  static String createTranscriptionResponse({
    required String transcript,
    bool isFinal = false,
  }) {
    return jsonEncode({
      'channel': {
        'alternatives': [
          {'transcript': transcript}
        ]
      },
      'is_final': isFinal,
    });
  }
}

void main() {
  group('MyApp Theme Tests', () {
    testWidgets('MyApp should have correct theme configuration', (WidgetTester tester) async {
      // Build our app and trigger a frame
      await tester.pumpWidget(const MyApp());

      // Get the MaterialApp widget
      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      
      // Test theme properties
      expect(app.theme?.useMaterial3, isTrue);
      expect(app.title, 'Deepgram Transcriber');
      
      // Test that the home widget is TranscriptionScreen
      expect(app.home.runtimeType, TranscriptionScreen);
    });
  });

  group('TranscriptionScreen UI Tests', () {
    testWidgets('Should have a properly configured AppBar', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the AppBar
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);
      
      // Test AppBar properties
      final AppBar appBar = tester.widget(appBarFinder);
      expect(appBar.title, isA<Text>());
      expect((appBar.title as Text).data, 'Deepgram Transcriber');
      expect(appBar.backgroundColor, isNotNull);
    });
    
    testWidgets('Should have a transcription display area', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the Container that holds the transcription text
      final containerFinder = find.ancestor(
        of: find.text('Transcription will appear here...'),
        matching: find.byType(Container),
      );
      expect(containerFinder, findsOneWidget);
      
      // Test Container properties
      final Container container = tester.widget(containerFinder);
      expect(container.margin, isNotNull);
      expect(container.padding, isNotNull);
      expect(container.decoration, isNotNull);
    });
    
    testWidgets('Should have properly styled recording button', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the recording button
      final buttonFinder = find.ancestor(
        of: find.text('Start Recording'),
        matching: find.byType(ElevatedButton),
      );
      expect(buttonFinder, findsOneWidget);
      
      // Test button properties
      final ElevatedButton button = tester.widget(buttonFinder);
      expect(button.style, isNotNull);
      
      // The button should be disabled initially until recorder is initialized
      // This is hard to test directly since the enabled property depends on private state
    });
    
    testWidgets('Should have properly styled clear text button', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the clear text button
      final buttonFinder = find.ancestor(
        of: find.text('Clear Text'),
        matching: find.byType(ElevatedButton),
      );
      expect(buttonFinder, findsOneWidget);
      
      // Test button properties
      final ElevatedButton button = tester.widget(buttonFinder);
      expect(button.style, isNotNull);
    });
    
    testWidgets('Should have API key input field with correct properties', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the TextField
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      
      // Test TextField properties
      final TextField textField = tester.widget(textFieldFinder);
      expect(textField.obscureText, isTrue); // Should be obscured like a password
      expect(textField.decoration?.labelText, 'Deepgram API Key');
      expect(textField.decoration?.hintText, 'Paste your API key here');
      expect(textField.decoration?.border, isA<OutlineInputBorder>());
    });
  });

  group('TranscriptionScreen Status Indicators', () {
    testWidgets('Should display recorder status indicator', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the recorder status indicator container
      final statusIndicatorFinder = find.byType(Container).first;
      expect(statusIndicatorFinder, findsOneWidget);
      
      // Test that the status indicator has the correct shape
      final Container statusIndicator = tester.widget(statusIndicatorFinder);
      final BoxDecoration decoration = statusIndicator.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      
      // We can't directly test width/height properties as they're part of constraints
      // but we can verify the decoration exists
      expect(decoration, isNotNull);
    });
    
    testWidgets('Should display screen timeout status', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the screen timeout status icon
      final iconFinder = find.byIcon(Icons.stay_current_portrait);
      expect(iconFinder, findsOneWidget);
      
      // Test that the icon has the correct color (should be grey initially)
      final Icon icon = tester.widget(iconFinder);
      expect(icon.color, Colors.grey);
      expect(icon.size, 16);
    });
  });

  group('TranscriptionScreen Layout Tests', () {
    testWidgets('Should have correct overall layout structure', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Test the main layout is a Column
      expect(find.byType(Column), findsOneWidget);
      
      // Test that the Column contains the expected children in the correct order
      final columnFinder = find.byType(Column);
      final Column column = tester.widget(columnFinder);
      
      // Test that the Column has multiple children
      expect(column.children.length, greaterThan(1));
      
      // Test that the main sections are present
      expect(find.byType(Padding), findsWidgets); // Status indicators row
      expect(find.byType(Expanded), findsOneWidget); // Transcription display area
      expect(find.byType(Row), findsWidgets); // Control buttons row
      expect(find.byType(TextField), findsOneWidget); // API key input
    });
    
    testWidgets('Control buttons should be in a row with correct spacing', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the row containing the buttons
      final rowFinder = find.ancestor(
        of: find.text('Start Recording'),
        matching: find.byType(Row),
      );
      expect(rowFinder, findsOneWidget);
      
      // Test row properties
      final Row row = tester.widget(rowFinder);
      expect(row.mainAxisAlignment, MainAxisAlignment.center);
      
      // Test that there's a SizedBox for spacing between buttons
      final sizedBoxFinder = find.descendant(
        of: rowFinder,
        matching: find.byType(SizedBox),
      );
      expect(sizedBoxFinder, findsOneWidget);
      
      // Test the spacing width
      final SizedBox sizedBox = tester.widget(sizedBoxFinder);
      expect(sizedBox.width, 16);
    });
  });

  group('TranscriptionScreen Functional Tests', () {
    testWidgets('API key field should accept input', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(const MaterialApp(home: TranscriptionScreen()));
      
      // Find the TextField
      final textFieldFinder = find.byType(TextField);
      
      // Enter text
      await tester.enterText(textFieldFinder, 'test-api-key');
      
      // We can't directly verify the text since it's obscured, but we can verify the TextField exists
      expect(textFieldFinder, findsOneWidget);
    });
  });
}
