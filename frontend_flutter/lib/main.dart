library solola_app;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'app.dart';
part 'core/app_section.dart';
part 'core/helpers.dart';
part 'core/route_guard.dart';
part 'firebase/config.dart';
part 'services/api_client.dart';
part 'services/firebase_email_verification_service.dart';
part 'services/pin_crypto.dart';
part 'widgets/solola_logo.dart';
part 'widgets/auth_widgets.dart';
part 'pages/auth_page.dart';
part 'pages/verify_code_page.dart';
part 'pages/verify_email_page.dart';
part 'pages/home_page.dart';
part 'pages/admin_pages.dart';
part 'dialogs/app_dialogs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseEmailVerificationService.initialize();
  runApp(const SololaApp());
}
