import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/constants/role.dart';
import '../data/api/api_client.dart';
import '../views/notifications/notifications_page.dart';
import 'auth_controller.dart';

class PushNotificationService extends GetxController {
  final ApiClient _apiClient = ApiClient();
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  Worker? _authWorker;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;
  bool _registeringToken = false;
  String? _lastRegisteredToken;

  bool get _supportsPush => !kIsWeb
      && (defaultTargetPlatform == TargetPlatform.android
          || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void onInit() {
    super.onInit();
    if (!_supportsPush) return;
    final auth = Get.find<AuthController>();
    _authWorker = everAll([auth.isReady, auth.isAuthed, auth.role], (_) {
      if (auth.isReady.value && auth.isAuthed.value && auth.role.value == Role.student) {
        unawaited(_startForSignedInStudent());
      }
    });
    if (auth.isReady.value && auth.isAuthed.value && auth.role.value == Role.student) {
      unawaited(_startForSignedInStudent());
    }
  }

  Future<void> _startForSignedInStudent() async {
    if (_initialized) {
      await _registerCurrentToken();
      return;
    }
    _initialized = true;
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      _tokenSubscription = _messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });
      _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? 'Thông báo mới';
        final body = message.notification?.body ?? '';
        Get.snackbar(
          title,
          body,
          snackPosition: SnackPosition.TOP,
          onTap: (_) => Get.to<void>(
            () => const NotificationsPage(role: Role.student),
          ),
        );
      });
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) _openMessage(initialMessage);
      await _registerCurrentToken();
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    if (_registeringToken || token == _lastRegisteredToken) return;
    _registeringToken = true;
    try {
      await _apiClient.post('/api/me/fcm-token', data: {'token': token});
      _lastRegisteredToken = token;
    } catch (_) {
      // The next sign-in or token refresh will retry registration.
    } finally {
      _registeringToken = false;
    }
  }

  void _openMessage(RemoteMessage message) {
    if (Get.find<AuthController>().isAuthed.value) {
      Get.to<void>(() => const NotificationsPage(role: Role.student));
    }
  }

  /// Best effort server cleanup before the auth token is cleared on logout.
  Future<void> unregisterCurrentDevice() async {
    if (!_supportsPush) return;
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _apiClient.post(
        '/api/me/fcm-token/unregister',
        data: {'token': token},
      );
      _lastRegisteredToken = null;
    } catch (_) {
      // Inactive tokens are pruned by the server when FCM rejects them.
    }
  }

  @override
  void onClose() {
    _authWorker?.dispose();
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _openedSubscription?.cancel();
    super.onClose();
  }
}
