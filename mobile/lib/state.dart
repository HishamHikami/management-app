import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';

/// The organization's server. Override for testing with
/// `flutter run --dart-define=SERVER=https://other.example.com`.
const kServer = String.fromEnvironment(
  'SERVER',
  defaultValue: 'https://ksa-riyadh.halacreative.com',
);

/// Something to open after tapping a notification.
class OpenTarget {
  const OpenTarget(this.kind, this.id);
  final String kind; // task, announcement, meeting
  final int id;
}

/// App-wide state: who is logged in, their roles, the organization's committees
/// and people, unread counts, and a "something changed" signal so open screens refresh.
class AppState extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  ApiClient? api;
  Json? boot;
  Json counts = const {};
  bool loading = true;
  int dataVersion = 0; // bumps after any change; screens reload on it
  OpenTarget? openTarget;
  String server = kServer;
  String orgName = 'Karnataka Riyadh Unit';
  String shortName = 'KSA Riyadh Unit';
  final messages = GlobalKey<ScaffoldMessengerState>();
  Timer? _poll;
  String? _pushToken;
  bool _pushReady = false;
  bool _pushStarted = false;
  bool _listening = false;
  bool _handlers = false;

  // ---- who am I
  Json get me => (boot?['me'] as Json?) ?? const {};
  int get meId => (me['id'] as int?) ?? 0;
  bool get isAdmin => me['is_admin'] == true;
  bool get isCore => me['is_core'] == true;
  bool get canLead => me['can_lead'] == true;
  bool get canManagePeople => me['can_manage_people'] == true;
  Set<int> get headedIds =>
      ((me['headed_ids'] as List?) ?? []).cast<int>().toSet();
  Set<int> get leadableIds =>
      ((boot?['leadable_ids'] as List?) ?? []).cast<int>().toSet();
  bool canManageCommittee(int id) => isCore || headedIds.contains(id);

  List<Json> get committees =>
      ((boot?['committees'] as List?) ?? []).cast<Json>();
  List<Json> get leadableCommittees =>
      committees.where((c) => leadableIds.contains(c['id'])).toList();
  List<Json> get members => ((boot?['members'] as List?) ?? []).cast<Json>();
  Json? committee(int? id) =>
      committees.where((c) => c['id'] == id).firstOrNull;
  List<Json> choice(String key) =>
      (((boot?['choices'] as Json?)?[key] as List?) ?? []).cast<Json>();

  int count(String key) => (counts[key] as int?) ?? 0;

  // ---- lifecycle
  Future<void> init() async {
    server = await _storage.read(key: 'server') ?? kServer;
    final token = await _storage.read(key: 'token');
    _loadConfig();
    if (token != null) {
      api = ApiClient(baseUrl: server, token: token);
      try {
        await _bootstrap();
      } on ApiException catch (e) {
        if (e.unauthorized) {
          api = null;
          await _storage.delete(key: 'token');
        }
        // offline: keep the token; screens show the error and retry
      }
    }
    loading = false;
    notifyListeners();
    if (api != null) _afterLogin();
  }

  Future<void> _loadConfig() async {
    try {
      final c = await ApiClient(baseUrl: server).get('config');
      orgName = (c['org_name'] as String?) ?? orgName;
      shortName = (c['short_name'] as String?) ?? shortName;
      notifyListeners();
      final fb = c['firebase'];
      if (fb is Map && api != null) await _initPush(fb.cast<String, dynamic>());
      if (fb is Map) _firebase = fb.cast<String, dynamic>();
    } catch (_) {}
  }

  Json? _firebase;

  Future<void> _bootstrap() async {
    boot = await api!.get('bootstrap');
    counts = (boot!['counts'] as Json?) ?? const {};
    orgName = (boot!['org_name'] as String?) ?? orgName;
    shortName = (boot!['short_name'] as String?) ?? shortName;
  }

  void _afterLogin() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(minutes: 2), (_) => refreshCounts());
    if (_firebase != null) {
      _initPush(_firebase!);
    } else {
      _loadConfig();
    }
  }

  Future<void> setServer(String input) async {
    server = ApiClient.normalizeServer(input.isEmpty ? kServer : input);
    await _storage.write(key: 'server', value: server);
    _firebase = null;
    _loadConfig();
    notifyListeners();
  }

  Future<void> _signedIn(String token) async {
    final client = ApiClient(baseUrl: server, token: token);
    api = client;
    try {
      await _bootstrap();
    } catch (e) {
      api = null;
      rethrow;
    }
    await _storage.write(key: 'token', value: token);
    notifyListeners();
    _afterLogin();
  }

  Future<void> login(String identifier, String password) async {
    final r = await ApiClient(baseUrl: server).post('auth/login', {
      'identifier': identifier,
      'password': password,
      'device': 'Android app',
    });
    await _signedIn(r['token'] as String);
  }

  Future<Json> checkInvite(String code) =>
      ApiClient(baseUrl: server).post('auth/invite/check', {'code': code});

  Future<void> acceptInvite(String code, String password) async {
    final r = await ApiClient(baseUrl: server).post('auth/invite/accept', {
      'code': code,
      'password': password,
      'device': 'Android app',
    });
    await _signedIn(r['token'] as String);
  }

  Future<void> logout() async {
    _poll?.cancel();
    try {
      if (_pushToken != null) {
        await api?.post('devices', {'token': _pushToken, 'remove': true});
      }
      await api?.post('auth/logout');
    } catch (_) {}
    if (_pushReady) {
      try {
        await FirebaseMessaging.instance.unregister();
      } catch (_) {}
    }
    _pushToken = null;
    _pushStarted = false;
    api = null;
    boot = null;
    counts = const {};
    await _storage.delete(key: 'token');
    notifyListeners();
  }

  Future<void> refreshBoot() async {
    if (api == null) return;
    try {
      await _bootstrap();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshCounts() async {
    if (api == null) return;
    try {
      counts = await api!.get('counts');
      notifyListeners();
    } catch (_) {}
  }

  void setCounts(Object? c) {
    if (c is Json) {
      counts = c;
      notifyListeners();
    }
  }

  /// Call after any change: open screens reload, badges refresh.
  void changed({bool boot = false}) {
    dataVersion++;
    notifyListeners();
    refreshCounts();
    if (boot) refreshBoot();
  }

  void handleSessionExpired(BuildContext context) {
    _poll?.cancel();
    api = null;
    _storage.delete(key: 'token');
    notifyListeners();
  }

  void open(OpenTarget t) {
    openTarget = t;
    notifyListeners();
  }

  OpenTarget? takeOpenTarget() {
    final t = openTarget;
    openTarget = null;
    return t;
  }

  // ---- push notifications (Firebase, configured on the server) --------------
  Future<void> _initPush(Json fb) async {
    if (api == null || _pushStarted) return;
    _pushStarted = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: fb['apiKey'] as String,
            appId: fb['appId'] as String,
            messagingSenderId: fb['messagingSenderId'] as String,
            projectId: fb['projectId'] as String,
          ),
        );
      }
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      _pushReady = true;
      if (!_listening) {
        _listening = true;
        // Fires once registered, and again whenever Firebase rotates the token.
        fm.onRegistered.listen(_registerToken);
      }
      await fm.register();
      if (_handlers) return;
      _handlers = true;
      FirebaseMessaging.onMessage.listen((m) {
        changed();
        final n = m.notification;
        if (n != null) {
          messages.currentState?.showSnackBar(
            SnackBar(
              content: Text(n.title ?? 'New update'),
              behavior: SnackBarBehavior.floating,
              action: _targetOf(m) == null
                  ? null
                  : SnackBarAction(
                      label: 'Open',
                      onPressed: () => open(_targetOf(m)!),
                    ),
            ),
          );
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final t = _targetOf(m);
        if (t != null) open(t);
        changed();
      });
      final first = await fm.getInitialMessage();
      if (first != null && _targetOf(first) != null) open(_targetOf(first)!);
    } catch (_) {
      // Push is optional: the in-app inbox still works.
    }
  }

  Future<void> _registerToken(String token) async {
    if (api == null) return;
    _pushToken = token;
    try {
      await api?.post('devices', {'token': token});
    } catch (_) {}
  }

  OpenTarget? _targetOf(RemoteMessage m) {
    final id = int.tryParse('${m.data['id'] ?? ''}');
    final kind = m.data['kind'] as String?;
    if (id == null || kind == null) return null;
    return OpenTarget(kind, id);
  }
}

/// Makes AppState available to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget
              as AppScope)
          .notifier!;
}
