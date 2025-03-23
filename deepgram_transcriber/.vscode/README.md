# VSCode Flutter Debugging Setup

This directory contains configuration files for debugging the Flutter app in VSCode.

## Files

- `launch.json`: Defines the debug configurations for VSCode
- `settings.json`: Contains VSCode settings specific to this project
- `tasks.json`: Defines custom tasks that can be run from VSCode

## Debugging in VSCode

To debug the app in VSCode instead of Xcode:

1. Make sure you have the Flutter and Dart extensions installed in VSCode
2. Open the Command Palette (Cmd+Shift+P) and type "Flutter: Select Device"
3. Select the device you want to debug on
4. Click on the "Run and Debug" icon in the sidebar (or press F5)
5. Select "Flutter" from the dropdown menu at the top of the sidebar
6. Click the play button to start debugging

## Troubleshooting

If VSCode still opens Xcode instead of debugging within VSCode:

1. Close Xcode if it's open
2. Restart VSCode
3. Make sure you're using the "Flutter" debug configuration (not "Flutter: Attach to Device")
4. Try running the "Flutter: Clean" task from the Command Palette before debugging
5. Check that the Flutter SDK path in settings.json is correct for your system

## Custom Tasks

You can run the following tasks from the Command Palette (Cmd+Shift+P):

- **Flutter: Run**: Runs the app in debug mode
- **Flutter: Clean**: Cleans the build directory
- **Flutter: Build iOS**: Builds the iOS app without code signing
- **Flutter: Build APK**: Builds an Android APK
