import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

const gold = Color(0xFFF3CF3C);
const ink = Color(0xFF09090B);
const panel = Color(0xFF151518);
const muted = Color(0xFFAAA7AF);
const site = 'https://monarchcodex.online';
const apiRoot = 'https://monarchcodex.online/api/mobile';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final jar = PersistCookieJar(storage: FileStorage(dir.path + '/.monarch-cookies/'));
  runApp(MonarchApp(api: MonarchApi(jar)));
}

class MonarchApi {
  MonarchApi(CookieJar jar) : dio = Dio(BaseOptions(
    baseUrl: '$apiRoot/',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  )) {
    dio.interceptors.add(CookieManager(jar));
  }
  final Dio dio;
  Future<Map<String, dynamic>?> me() async {
    try { return Map<String, dynamic>.from((await dio.get('auth/me')).data['member'] as Map); }
    on DioException catch (e) { if (e.response?.statusCode == 401) return null; rethrow; }
  }
  Future<Map<String, dynamic>> login(String identity, String password) async =>
      Map<String, dynamic>.from((await dio.post('auth/login', data: {'identity': identity, 'password': password})).data['member'] as Map);
  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from((await dio.post('auth/register', data: data)).data as Map);
  Future<Map<String, dynamic>> overview() async =>
      Map<String, dynamic>.from((await dio.get('overview')).data as Map);
  Future<void> logout() async { await dio.post('auth/logout'); }
}

ThemeData makeTheme(bool dark) => ThemeData(
  useMaterial3: true,
  brightness: dark ? Brightness.dark : Brightness.light,
  scaffoldBackgroundColor: dark ? ink : const Color(0xFFF6F4ED),
  colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: dark ? Brightness.dark : Brightness.light, primary: gold, surface: dark ? panel : Colors.white, onPrimary: ink),
  inputDecorationTheme: InputDecorationTheme(
    filled: true, fillColor: dark ? const Color(0xFF101012) : Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: gold, width: 1.5)),
  ),
);

class MonarchApp extends StatefulWidget {
  const MonarchApp({super.key, required this.api});
  final MonarchApi api;
  @override State<MonarchApp> createState() => _MonarchAppState();
}
class _MonarchAppState extends State<MonarchApp> {
  Map<String, dynamic>? member;
  bool busy = true, light = false;
  @override void initState() { super.initState(); widget.api.me().then((v) { if (mounted) setState(() { member = v; busy = false; }); }).catchError((_) { if (mounted) setState(() => busy = false); }); }
  void signedIn(Map<String, dynamic> m) => setState(() => member = m);
  Future<void> signOut() async { try { await widget.api.logout(); } catch (_) {} if (mounted) setState(() => member = null); }
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Monarch Codex', debugShowCheckedModeBanner: false,
    theme: makeTheme(false), darkTheme: makeTheme(true), themeMode: light ? ThemeMode.light : ThemeMode.dark,
    home: busy ? const Scaffold(body: Center(child: CircularProgressIndicator(color: gold))) :
      member == null ? AuthPage(api: widget.api, onSignedIn: signedIn) :
      Shell(api: widget.api, member: member!, signOut: signOut, light: light, toggleTheme: () => setState(() => light = !light)),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.api, required this.onSignedIn});
  final MonarchApi api;
  final ValueChanged<Map<String, dynamic>> onSignedIn;
  @override State<AuthPage> createState() => _AuthPageState();
}
class _AuthPageState extends State<AuthPage> {
  final keyForm = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController(), phone = TextEditingController(), username = TextEditingController(), password = TextEditingController(), confirm = TextEditingController(), referral = TextEditingController();
  bool register = false, accepted = false, busy = false, reveal = false;
  String error = '', notice = '';
  @override void dispose() { name.dispose(); email.dispose(); phone.dispose(); username.dispose(); password.dispose(); confirm.dispose(); referral.dispose(); super.dispose(); }
  String problem(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (e.response?.statusCode == 404) return 'The mobile service is not deployed yet.';
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) return 'Connection failed. Check your internet and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    if (!keyForm.currentState!.validate()) return;
    if (register && !accepted) { setState(() => error = 'Accept the Terms & Conditions and Privacy Policy to continue.'); return; }
    setState(() { busy = true; error = ''; notice = ''; });
    try {
      if (register) {
        final result = await widget.api.register({
          'fullName': name.text.trim(), 'email': email.text.trim(), 'phoneCountryCode': '+234',
          'phone': phone.text.trim(), 'username': username.text.trim(), 'password': password.text,
          'confirmPassword': confirm.text, 'referralCode': referral.text.trim(), 'acceptPolicies': accepted,
        });
        setState(() { notice = (result['message'] ?? 'Account created.').toString() + ' Monarch ID: ' + (result['uid'] ?? 'created').toString(); register = false; email.text = email.text.trim(); password.clear(); confirm.clear(); });
      } else {
        widget.onSignedIn(await widget.api.login(email.text.trim(), password.text));
      }
    } catch (e) { if (mounted) setState(() => error = problem(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Form(key: keyForm, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: SvgPicture.asset('assets/images/monarch-codex-logo.svg', height: 118)),
        const SizedBox(height: 12),
        Text('BUILD WEALTH.\nBUILD A KINGDOM.', textAlign: TextAlign.center, style: TextStyle(color: dark ? Colors.white : ink, fontSize: 29, height: 1.03, fontWeight: FontWeight.w900, letterSpacing: -1)),
        const SizedBox(height: 9),
        Text(register ? 'Become a Monarch.' : 'Welcome back, Monarch.', textAlign: TextAlign.center, style: const TextStyle(color: muted)),
        const SizedBox(height: 22),
        if (notice.isNotEmpty) Message(text: notice, success: true),
        if (error.isNotEmpty) Message(text: error, success: false),
        if (register) ...[
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: requiredField),
          const SizedBox(height: 10),
          TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email address'), keyboardType: TextInputType.emailAddress, validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email'),
          const SizedBox(height: 10),
          TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone number', prefixText: '+234 '), keyboardType: TextInputType.phone, validator: requiredField),
          const SizedBox(height: 10),
          TextFormField(controller: username, decoration: const InputDecoration(labelText: 'Username', helperText: '6–30 letters, numbers or underscores'), validator: (v) => v != null && RegExp(r'^[A-Za-z0-9_]{6,30}$').hasMatch(v) ? null : 'Use 6–30 letters, numbers or underscores'),
          const SizedBox(height: 10),
          TextFormField(controller: referral, decoration: const InputDecoration(labelText: 'Referral ID (optional)')),
          const SizedBox(height: 10),
        ] else
          TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email or username'), validator: requiredField),
        const SizedBox(height: 10),
        TextFormField(controller: password, obscureText: !reveal, decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(onPressed: () => setState(() => reveal = !reveal), icon: Icon(reveal ? Icons.visibility_off : Icons.visibility))), validator: (v) {
          if (v == null || v.isEmpty) return 'Enter your password';
          if (register && (v.length < 12 || !RegExp(r'[A-Z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v) || !RegExp(r'[^A-Za-z0-9\s]').hasMatch(v))) return 'Use 12+ characters, a capital, a number and a symbol';
          return null;
        }),
        if (register) ...[
          const SizedBox(height: 10),
          TextFormField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password'), validator: (v) => v == password.text ? null : 'Passwords do not match'),
          CheckboxListTile(value: accepted, onChanged: (v) => setState(() => accepted = v ?? false), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: gold, title: const Text('I agree to the Terms & Conditions and Privacy Policy.', style: TextStyle(color: muted, fontSize: 12))),
        ],
        const SizedBox(height: 18),
        FilledButton(onPressed: busy ? null : submit, style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink, minimumSize: const Size.fromHeight(52)), child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: ink)) : Text(register ? 'CREATE MY ACCOUNT' : 'SIGN IN', style: const TextStyle(fontWeight: FontWeight.w900))),
        TextButton(onPressed: busy ? null : () => setState(() { register = !register; error = ''; notice = ''; }), child: Text(register ? 'Already a Monarch? Sign in' : 'New here? Become a Monarch', style: const TextStyle(color: gold, fontWeight: FontWeight.w800))),
        if (!register) TextButton(onPressed: () => launchUrl(Uri.parse(site + '/forgot-password'), mode: LaunchMode.externalApplication), child: const Text('Forgot password?', style: TextStyle(color: muted))),
      ]))),
    )));
  }
  String? requiredField(String? value) => value == null || value.trim().isEmpty ? 'This field is required' : null;
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.member, required this.signOut, required this.light, required this.toggleTheme});
  final MonarchApi api;
  final Map<String, dynamic> member;
  final Future<void> Function() signOut;
  final bool light;
  final VoidCallback toggleTheme;
  @override State<Shell> createState() => _ShellState();
}
class _ShellState extends State<Shell> {
  int tab = 0;
  final int photoVersion = DateTime.now().millisecondsSinceEpoch;
  bool menu = false, loading = true;
  String? special, error;
  Map<String, dynamic>? data;
  static const names = ['Overview', 'Wallet', 'Invest', 'Market', 'Community', 'Profile'];
  static const icons = [Icons.grid_view_rounded, Icons.account_balance_wallet_rounded, Icons.trending_up_rounded, Icons.show_chart_rounded, Icons.groups_rounded, Icons.person_rounded];
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
    try { final result = await widget.api.overview(); if (mounted) setState(() { data = result; loading = false; }); }
    catch (e) { if (mounted) setState(() { loading = false; error = e is DioException && e.response?.data is Map ? ((e.response!.data as Map)['message']?.toString() ?? 'Could not load account data.') : 'Could not load account data.'; }); }
  }
  void page(String? value, [int? index]) => setState(() { special = value; if (index != null) tab = index; menu = false; });
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = special ?? names[tab];
    return Scaffold(body: SafeArea(child: Stack(clipBehavior: Clip.hardEdge, children: [
      Positioned.fill(child: AnimatedPadding(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, padding: EdgeInsets.only(left: menu ? 214 : 0), child: SizedBox(width: MediaQuery.sizeOf(context).width, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Row(children: [
          IconButton(onPressed: () => setState(() => menu = !menu), icon: Icon(menu ? Icons.close : Icons.menu, color: gold)),
          SvgPicture.asset('assets/images/monarch-codex-logo.svg', width: 40, height: 40),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .8)),
            Text((widget.member['uid'] ?? 'MONARCH').toString(), style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w900)),
          ])),
          IconButton(onPressed: () => page('Notifications'), icon: const Icon(Icons.notifications_none_rounded, color: gold)),
        ])),
        Expanded(child: special != null ? specialPage(special!, dark) : tab == 0 ? overviewPage(dark) : tab == 1 ? walletPage(dark) : tab == 5 ? profilePage(dark) : featurePage(names[tab], tab == 2 ? 'Investment packages and recorded purchases' : tab == 3 ? 'Market information' : 'Grow with the Monarch community', icons[tab], tab == 2 ? 'Your investment records will appear here when the mobile investment API is connected. No returns are invented.' : tab == 3 ? 'Live market feeds are being connected. No placeholder prices are displayed.' : 'Sovereign Desk and community access will respect your existing member permissions.', dark)),
        if (special == null) bottomNav(dark),
      ])))),
      if (menu) Positioned(left: 0, top: 0, bottom: 0, width: 214, child: sidebar(dark)),
    ])));
  }

  Widget overviewPage(bool dark) {
    final wallet = data?['wallet'] is Map ? Map<String, dynamic>.from(data!['wallet'] as Map) : <String, dynamic>{};
    final member = data?['member'] is Map ? Map<String, dynamic>.from(data!['member'] as Map) : widget.member;
    final kyc = (data?['kycStatus'] ?? 'not_submitted').toString().replaceAll('_', ' ');
    return RefreshIndicator(color: gold, onRefresh: refresh, child: ListView(padding: const EdgeInsets.fromLTRB(15, 3, 15, 20), children: [
      Text('Your kingdom starts here.', style: TextStyle(color: dark ? Colors.white : ink, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -.7)),
      const SizedBox(height: 5),
      const Text('BUILD WEALTH. BUILD A KINGDOM.', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
      const SizedBox(height: 16),
      balanceCard(number(wallet['ngn']), number(wallet['usd']), number(wallet['rate'])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: stat('VERIFICATION', kyc.toUpperCase(), Icons.verified_user_outlined, dark)),
        const SizedBox(width: 9),
        Expanded(child: stat('REFERRALS', (data?['referralCount'] ?? 0).toString(), Icons.people_outline, dark)),
      ]),
      const SizedBox(height: 9),
      Row(children: [
        Expanded(child: stat('NOTIFICATIONS', (data?['unreadNotifications'] ?? 0).toString(), Icons.notifications_none, dark)),
        const SizedBox(width: 9),
        Expanded(child: stat('YOUR MONARCH ID', (member['uid'] ?? '—').toString(), Icons.badge_outlined, dark)),
      ]),
      const SizedBox(height: 20),
      Row(children: [Container(width: 4, height: 18, decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(4))), const SizedBox(width: 8), const Text('QUICK ACCESS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1))]),
      const SizedBox(height: 10),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, mainAxisSpacing: 9, crossAxisSpacing: 9, childAspectRatio: 1.03, children: [
        quick('Wallet', Icons.account_balance_wallet_outlined, () => page(null, 1), dark),
        quick('Invest', Icons.trending_up, () => page(null, 2), dark),
        quick('Market', Icons.show_chart, () => page(null, 3), dark),
        quick('Community', Icons.groups_outlined, () => page(null, 4), dark),
        quick('Verify KYC', Icons.shield_outlined, () => page('KYC Verification'), dark),
        quick('Referrals', Icons.share_outlined, () => page('Referrals'), dark),
      ]),
      if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: gold))),
      if (error != null) Message(text: error!, success: false),
    ]));
  }

  Widget walletPage(bool dark) {
    final w = data?['wallet'] is Map ? Map<String, dynamic>.from(data!['wallet'] as Map) : <String, dynamic>{};
    return ListView(padding: const EdgeInsets.all(15), children: [
      const Text('Your money, clearly.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6), const Text('Balances are read from your existing member account.', style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 16), balanceCard(number(w['ngn']), number(w['usd']), number(w['rate'])),
      const SizedBox(height: 12),
      tile('Deposit', 'Submit a deposit request and payment proof.', Icons.add_card, dark, () => openSite('/deposit')),
      tile('Withdraw', 'Subject to approved KYC and account checks.', Icons.south_west, dark, () => openSite('/withdraw')),
      tile('Transactions', 'Review your recorded activity.', Icons.receipt_long, dark, () => openSite('/transactions')),
      const Message(text: 'Financial actions open the secure website for now. Native money movement will be connected only after its API preserves review and duplicate-credit safeguards.', success: true),
    ]);
  }

  Widget profilePage(bool dark) {
    final m = data?['member'] is Map ? Map<String, dynamic>.from(data!['member'] as Map) : widget.member;
    return ListView(padding: const EdgeInsets.all(15), children: [
      Container(padding: const EdgeInsets.all(20), decoration: card(dark), child: Column(children: [
        avatar(m, 76, 24),
        const SizedBox(height: 10), Text((m['fullName'] ?? 'Monarch Member').toString(), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
        const SizedBox(height: 4), Text((m['email'] ?? '').toString(), style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 10), Text((m['uid'] ?? 'MONARCH').toString(), style: const TextStyle(color: gold, fontWeight: FontWeight.w900)),
      ])),
      const SizedBox(height: 12),
      tile('KYC Verification', 'Review identity verification status.', Icons.verified_user_outlined, dark, () => page('KYC Verification')),
      tile('Referrals', 'Personal link and referral count.', Icons.share_outlined, dark, () => page('Referrals')),
      tile('Settings', 'Appearance and account preferences.', Icons.settings_outlined, dark, () => page('Settings')),
      tile('Help & Support', 'Contact official support.', Icons.support_agent, dark, () => page('Help & Support')),
      tile(widget.light ? 'Switch to dark mode' : 'Switch to light mode', 'Change app appearance.', Icons.contrast, dark, widget.toggleTheme),
      OutlinedButton.icon(onPressed: widget.signOut, icon: const Icon(Icons.logout, color: Color(0xFFFF8D85)), label: const Text('Sign out'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
    ]);
  }

  Widget specialPage(String p, bool dark) {
    if (p == 'Notifications') return ListView(padding: const EdgeInsets.all(15), children: [\n      featurePage(p, 'Your account updates', Icons.notifications_none_rounded, 'Unread notifications: ' + (data?['unreadNotifications'] ?? 0).toString() + '. Open the secure member dashboard to read and manage the full notification list.', dark),\n      tile('Open notifications', 'View your complete notification centre.', Icons.open_in_new, dark, () => openSite('/dashboard')),\n      tile('Refresh account status', 'Reload your latest overview and unread count.', Icons.refresh, dark, refresh),\n    ]);\n    if (p == 'Settings') return ListView(padding: const EdgeInsets.all(15), children: [
      tile(widget.light ? 'Dark appearance' : 'Light appearance', 'Toggle app appearance.', Icons.contrast, dark, widget.toggleTheme),
      tile('Account details', 'Open your existing profile page.', Icons.manage_accounts, dark, () => openSite('/profile')),
      tile('Password recovery', 'Secure password reset.', Icons.lock_reset, dark, () => openSite('/forgot-password')),
    ]);
    if (p == 'Help & Support') return ListView(padding: const EdgeInsets.all(15), children: [
      featurePage(p, 'We are here to help', Icons.support_agent, 'For account access, verification or payment questions, contact official Monarch Codex support.', dark),
      tile('Email support', 'support@monarchcodex.online', Icons.email_outlined, dark, () => launchUrl(Uri.parse('mailto:support@monarchcodex.online'))),
      tile('Open website', 'Visit Monarch Codex online.', Icons.open_in_new, dark, () => openSite('/')),
    ]);
    if (p == 'KYC Verification') return ListView(padding: const EdgeInsets.all(15), children: [
      featurePage(p, 'Protect your account', Icons.verified_user_outlined, 'Current status: ' + (data?['kycStatus'] ?? 'not_submitted').toString().toUpperCase() + '. Approval is required before restricted financial actions.', dark),
      tile('Continue on secure website', 'Open the existing verification workflow.', Icons.open_in_new, dark, () => openSite('/kyc')),
    ]);
    if (p == 'Referrals') return ListView(padding: const EdgeInsets.all(15), children: [
      featurePage(p, 'Invite people to join', Icons.share_outlined, 'Recorded referrals: ' + (data?['referralCount'] ?? 0).toString(), dark),
      SelectableText((data?['referralLink'] ?? (site + '/register?ref=' + (widget.member['uid'] ?? ''))).toString(), style: const TextStyle(color: gold, fontWeight: FontWeight.w800)),
      tile('Open referral dashboard', 'View your full referral details.', Icons.open_in_new, dark, () => openSite('/referrals')),
    ]);
    return featurePage(p, 'Monarch Codex', Icons.auto_awesome, 'This section will connect to your existing account backend. Existing records are not changed.', dark);
  }

  Widget bottomNav(bool dark) => Container(
    padding: const EdgeInsets.fromLTRB(2, 7, 2, 5),
    decoration: BoxDecoration(color: dark ? const Color(0xFF111113) : Colors.white, border: Border(top: BorderSide(color: dark ? const Color(0xFF2B2924) : const Color(0xFFE2DED1)))),
    child: Row(children: List.generate(names.length, (i) => Expanded(child: InkWell(
      onTap: () => page(null, i), borderRadius: BorderRadius.circular(11),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: tab == i ? gold.withOpacity(.14) : Colors.transparent, borderRadius: BorderRadius.circular(99)), child: Icon(icons[i], size: 18, color: tab == i ? gold : muted)),
        const SizedBox(height: 3), Text(names[i], maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 8.5, fontWeight: tab == i ? FontWeight.w900 : FontWeight.w600, color: tab == i ? gold : muted)),
      ])),
    )))),
  );

  Widget sidebar(bool dark) => Material(color: dark ? const Color(0xFF121214) : Colors.white, child: SafeArea(child: Column(children: [
    const SizedBox(height: 10), SvgPicture.asset('assets/images/monarch-codex-logo.svg', width: 112, height: 90),
    Padding(padding: const EdgeInsets.all(11), child: Container(width: double.infinity, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: dark ? const Color(0xFF211C0D) : const Color(0xFFFFF7DA), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFF6D5920))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: avatar(data?['member'] is Map ? Map<String, dynamic>.from(data!['member'] as Map) : widget.member, 48, 16)),
      const SizedBox(height: 8),
      Text((widget.member['fullName'] ?? 'Monarch Member').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4), Text((widget.member['uid'] ?? 'MONARCH').toString(), style: const TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.w900)),
    ]))),
    const Padding(padding: EdgeInsets.fromLTRB(14, 2, 10, 7), child: Align(alignment: Alignment.centerLeft, child: Text('MEMBER MENU', style: TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)))),
    Expanded(child: ListView(children: [
      sideItem('Overview', Icons.grid_view, () => page(null, 0), dark), sideItem('Wallet', Icons.account_balance_wallet_outlined, () => page(null, 1), dark),
      sideItem('Invest', Icons.trending_up, () => page(null, 2), dark), sideItem('Market', Icons.show_chart, () => page(null, 3), dark),
      sideItem('Community', Icons.groups_outlined, () => page(null, 4), dark), sideItem('Profile', Icons.person_outline, () => page(null, 5), dark),
      const Divider(color: Color(0xFF39352A)), sideItem('KYC Verification', Icons.verified_user_outlined, () => page('KYC Verification'), dark),
      sideItem('Referrals', Icons.share_outlined, () => page('Referrals'), dark), sideItem('Settings', Icons.settings_outlined, () => page('Settings'), dark),
      sideItem('Help & Support', Icons.support_agent, () => page('Help & Support'), dark),
    ])),
    TextButton.icon(onPressed: widget.signOut, icon: const Icon(Icons.logout, size: 17), label: const Text('Sign out'), style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8D85))),
  ])));

  Widget avatar(Map<String, dynamic> member, double size, double radius) =>
      MemberAvatar(api: widget.api, member: member, size: size, radius: radius, version: photoVersion);

  Widget sideItem(String label, IconData icon, VoidCallback action, bool dark) => ListTile(
    dense: true, visualDensity: const VisualDensity(vertical: -2), minLeadingWidth: 18, horizontalTitleGap: 7,
    leading: Icon(icon, color: gold, size: 18), title: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), onTap: action,
  );

  Widget balanceCard(double ngn, double usd, double rate) {
    final totalUsd = rate > 0 ? usd + ngn / rate : usd;
    return Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF6D5920)),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF28200D), Color(0xFF151411), Color(0xFF101012)]),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 22, offset: Offset(0, 9))],
    ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.account_balance_wallet_outlined, color: gold, size: 18), SizedBox(width: 8), Expanded(child: Text('TOTAL WALLET BALANCE', style: TextStyle(color: Color(0xFFD6CBA8), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))), Text('NGN + USD', style: TextStyle(color: gold, fontSize: 9, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 13), Text('₦' + ngn.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7)),
      const SizedBox(height: 4), Text('\$' + usd.toStringAsFixed(2) + ' USD', style: const TextStyle(color: Color(0xFFE0C96D), fontSize: 14, fontWeight: FontWeight.w800)),
      const SizedBox(height: 13), Container(height: 1, color: const Color(0xFF4A3D1B)), const SizedBox(height: 10),
      Row(children: [const Expanded(child: Text('Estimated combined value in USD', style: TextStyle(color: muted, fontSize: 10)),), Text(rate > 0 ? '\$' + totalUsd.toStringAsFixed(2) : 'FX unavailable', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))]),
      if (rate <= 0) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Exchange-rate reference unavailable; no conversion is estimated.', style: TextStyle(color: muted, fontSize: 10))),
    ]));
  }

  Widget stat(String title, String value, IconData icon, bool dark) => Container(
    constraints: const BoxConstraints(minHeight: 98), padding: const EdgeInsets.all(12), decoration: card(dark),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: gold, size: 18), const SizedBox(height: 11), Text(title, style: const TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .4)),
      const SizedBox(height: 4), Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
    ]),
  );

  Widget quick(String label, IconData icon, VoidCallback action, bool dark) => InkWell(onTap: action, borderRadius: BorderRadius.circular(14), child: Container(
    decoration: card(dark), padding: const EdgeInsets.all(8), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 37, height: 37, decoration: BoxDecoration(color: gold.withOpacity(.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: gold, size: 20)),
      const SizedBox(height: 7), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
    ]),
  ));

  Widget featurePage(String title, String subtitle, IconData icon, String body, bool dark) => ListView(padding: const EdgeInsets.all(15), children: [
    Container(padding: const EdgeInsets.all(20), decoration: card(dark), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 50, height: 50, decoration: BoxDecoration(color: gold.withOpacity(.12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: gold, size: 27)),
      const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 13), Text(body, style: const TextStyle(color: muted, fontSize: 13, height: 1.6)),
    ]),
  ]);

  Widget tile(String title, String subtitle, IconData icon, bool dark, VoidCallback action) => Container(
    margin: const EdgeInsets.only(bottom: 10), decoration: card(dark), child: ListTile(
      onTap: action, contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      leading: Container(width: 39, height: 39, decoration: BoxDecoration(color: gold.withOpacity(.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: gold, size: 20)),
      title: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: const TextStyle(color: muted, fontSize: 10, height: 1.4))),
      trailing: const Icon(Icons.chevron_right, color: muted, size: 19),
    ),
  );

  BoxDecoration card(bool dark) => BoxDecoration(color: dark ? panel : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: dark ? const Color(0xFF302E29) : const Color(0xFFE4DFD2)));
  Future<void> openSite(String path) async => launchUrl(Uri.parse(site + path), mode: LaunchMode.externalApplication);
}

double number(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

class MemberAvatar extends StatefulWidget {
  const MemberAvatar({super.key, required this.api, required this.member, required this.size, required this.radius, required this.version});
  final MonarchApi api;
  final Map<String, dynamic> member;
  final double size, radius;
  final int version;
  @override State<MemberAvatar> createState() => _MemberAvatarState();
}
class _MemberAvatarState extends State<MemberAvatar> {
  Future<Uint8List?>? bytes;
  @override void initState() { super.initState(); bytes = load(); }
  @override void didUpdateWidget(covariant MemberAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member['profilePhotoUrl'] != widget.member['profilePhotoUrl'] || oldWidget.version != widget.version) bytes = load();
  }
  Future<Uint8List?> load() async {
    final raw = (widget.member['profilePhotoUrl'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final url = (raw.startsWith('http://') || raw.startsWith('https://') ? raw : site + (raw.startsWith('/') ? raw : '/$raw')) + (raw.contains('?') ? '&' : '?') + 'v=${widget.version}';
    try {
      final response = await widget.api.dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } catch (_) { return null; }
  }
  @override Widget build(BuildContext context) => Container(
    width: widget.size, height: widget.size,
    decoration: BoxDecoration(color: const Color(0xFF2A220F), borderRadius: BorderRadius.circular(widget.radius), border: Border.all(color: const Color(0xFF705A20))),
    clipBehavior: Clip.antiAlias,
    child: FutureBuilder<Uint8List?>(future: bytes, builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) return Icon(Icons.person, color: gold, size: widget.size * .52);
      return Image.memory(data, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person, color: gold, size: widget.size * .52));
    }),
  );
}

class Message extends StatelessWidget {
  const Message({super.key, required this.text, required this.success});
  final String text;
  final bool success;
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: success ? const Color(0xFF17291F) : const Color(0xFF321B1A), border: Border.all(color: success ? const Color(0xFF2F6647) : const Color(0xFF7B403B)), borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: TextStyle(color: success ? const Color(0xFFB9F3CE) : const Color(0xFFFFC7C1), fontSize: 12, height: 1.45)),
  );
}
