import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// App-wide state: session, the signed-in user, and the wedding being worked on.
class AppState extends ChangeNotifier {
  AppState(this.api);

  final Api api;
  Map<String, dynamic>? user;
  List<dynamic> weddings = [];
  Map<String, dynamic>? summary; // GET /weddings/:id
  String locale = 'en';
  Map<String, dynamic>? planner; // GET /planner: {planner, role, studioActive, teamLimit}
  /// What the person is doing right now: their own wedding, or planner work. Switch from the profile menu.
  String workspace = 'couple';
  bool ready = false;

  /// Invite link opened before sign-in (web panel #join=...); accepted after sign-in.
  String? pendingJoinToken;
  String? pendingTeamToken;

  String? get weddingId => summary?['wedding']?['id'] as String?;
  Map<String, dynamic> get wedding => (summary?['wedding'] as Map<String, dynamic>?) ?? {};
  bool get isAdvanced => wedding['mode'] == 'advanced';
  bool get isPaid => summary?['plan']?['plan'] == 'pass';
  String get role => summary?['role'] as String? ?? 'view';
  bool get canEditAll => role == 'owner' || role == 'edit_all';
  bool get canEditGuests => canEditAll || role == 'edit_guests';
  bool get isStaff => user?['staff_role'] != null;
  bool get isPlanner => planner != null;
  bool get inPlannerWorkspace => isPlanner && workspace == 'planner';

  Future<void> init({String? sessionFromUrl, String? joinFromUrl, String? teamFromUrl}) async {
    pendingTeamToken = teamFromUrl;
    final prefs = await SharedPreferences.getInstance();
    locale = prefs.getString('locale') ?? 'en';
    pendingJoinToken = joinFromUrl;
    api.token = sessionFromUrl ?? prefs.getString('token');
    if (sessionFromUrl != null) await prefs.setString('token', sessionFromUrl);
    if (api.token != null) {
      try {
        await _afterSignIn();
      } on ApiException catch (e) {
        if (e.status == 401) await signOut(callServer: false);
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> setSession(String token) async {
    api.token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await _afterSignIn();
    notifyListeners();
  }

  Future<void> _afterSignIn() async {
    user = (await api.get('/me'))['user'] as Map<String, dynamic>;
    if (pendingJoinToken != null) {
      try {
        await api.post('/invites/$pendingJoinToken/accept');
      } catch (_) {}
      pendingJoinToken = null;
    }
    if (pendingTeamToken != null) {
      try {
        await api.post('/planner-invites/$pendingTeamToken/accept');
      } catch (_) {}
      pendingTeamToken = null;
    }
    await loadPlanner();
    await loadWeddings();
    final prefs = await SharedPreferences.getInstance();
    workspace = prefs.getString('workspace') ?? (isPlanner ? 'planner' : 'couple');
    if (inPlannerWorkspace) return; // planners land on their dashboard
    final last = prefs.getString('wedding');
    final ids = weddings.map((w) => w['id']).toList();
    final pick = ids.contains(last) ? last : (ids.isNotEmpty ? ids.first as String : null);
    if (pick != null) await openWedding(pick);
  }

  Future<void> loadPlanner() async {
    try {
      planner = await api.get('/planner');
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
      planner = null;
    }
  }

  Future<void> setWorkspace(String w) async {
    workspace = w;
    summary = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workspace', w);
    if (w == 'couple') {
      await loadWeddings();
      final own = weddings.where((x) => x['role'] == 'owner').toList();
      if (own.isNotEmpty) await openWedding(own.first['id'] as String);
    }
    notifyListeners();
  }

  /// Back from a client wedding to the planner dashboard.
  void closeWedding() {
    summary = null;
    notifyListeners();
  }

  Future<void> becamePlanner() async {
    await loadPlanner();
    await setWorkspace('planner');
  }

  Future<void> loadWeddings() async {
    weddings = (await api.get('/weddings'))['weddings'] as List<dynamic>;
  }

  Future<void> openWedding(String id) async {
    summary = await api.get('/weddings/$id');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wedding', id);
    notifyListeners();
  }

  Future<void> refresh() async {
    if (weddingId == null) return;
    summary = await api.get('/weddings/$weddingId');
    notifyListeners();
  }

  void setSummary(Map<String, dynamic> s) {
    summary = s;
    notifyListeners();
  }

  Future<void> createdWedding(Map<String, dynamic> s) async {
    summary = s;
    await loadWeddings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wedding', s['wedding']['id'] as String);
    notifyListeners();
  }

  Future<void> setLocale(String l) async {
    locale = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', l);
    if (user != null) {
      try {
        await api.patch('/me', {'locale': l});
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> signOut({bool callServer = true}) async {
    if (callServer) {
      try {
        await api.post('/auth/logout');
      } catch (_) {}
    }
    api.token = null;
    user = null;
    summary = null;
    planner = null;
    workspace = 'couple';
    weddings = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('wedding');
    notifyListeners();
  }
}
