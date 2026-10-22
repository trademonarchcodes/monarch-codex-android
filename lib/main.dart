import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:monarch_codex/native_workspaces.dart';

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
  Future<Map<String, dynamic>> investments() async =>
      Map<String, dynamic>.from((await dio.get('investments')).data as Map);
  Future<Map<String, dynamic>> kycStatus() async => Map<String, dynamic>.from((await dio.get('kyc/status')).data as Map);
  Future<Map<String, dynamic>> referrals() async => Map<String, dynamic>.from((await dio.get('referrals')).data as Map);
  Future<void> logout() async { await dio.post('auth/logout'); }
  Future<Map<String, dynamic>> transactions() async => Map<String, dynamic>.from((await dio.get('transactions')).data as Map);
  Future<Map<String, dynamic>> depositOptions() async => Map<String, dynamic>.from((await dio.get('deposit/options')).data as Map);
  Future<Map<String, dynamic>> withdrawalOptions() async => Map<String, dynamic>.from((await dio.get('withdrawal/options')).data as Map);
  Future<Map<String, dynamic>> adminOverview() async => Map<String, dynamic>.from((await dio.get('admin/overview')).data as Map);
  Future<Map<String,dynamic>> adminReviewQueue(String type) async => Map<String,dynamic>.from((await dio.get('admin/reviews/$type')).data as Map);
  Future<Map<String,dynamic>> reviewKyc({required int id,required String status,required String note}) async => Map<String,dynamic>.from((await dio.post('admin/reviews/kyc/$id',data:{'status':status,'note':note})).data as Map);
  Future<Map<String,dynamic>> reviewDeposit({required int id,required String decision,required String note,required bool confirmed}) async => Map<String,dynamic>.from((await dio.post('admin/reviews/deposits/$id',data:{'decision':decision,'note':note,'confirmed':confirmed})).data as Map);
  Future<Map<String,dynamic>> reviewWithdrawal({required int id,required String decision,required String note,required String paymentReference,required bool confirmed}) async => Map<String,dynamic>.from((await dio.post('admin/reviews/withdrawals/$id',data:{'decision':decision,'note':note,'paymentReference':paymentReference,'confirmed':confirmed})).data as Map);
  Future<Map<String,dynamic>> adminAuditEvents() async => Map<String,dynamic>.from((await dio.get('admin/audit-events')).data as Map);
  Future<Map<String,dynamic>> adminAnalytics() async => Map<String,dynamic>.from((await dio.get('admin/analytics')).data as Map);
  Future<Map<String,dynamic>> adminSecurity() async => Map<String,dynamic>.from((await dio.get('admin/security')).data as Map);
  Future<Map<String, dynamic>> submitWithdrawal({required String currency, required String amount, required String bankId, required String note}) async => Map<String, dynamic>.from((await dio.post('withdrawal/requests', data: {'currency': currency, 'amount': amount, 'bank_account_id': bankId, 'member_note': note})).data as Map);

  Future<Map<String,dynamic>> profile() async => Map<String,dynamic>.from((await dio.get('profile')).data['member'] as Map);
  Future<Map<String,dynamic>> saveProfile({required String fullName,required String username,required String email,required String phone}) async =>
    Map<String,dynamic>.from((await dio.put('profile',data:{'fullName':fullName,'username':username,'email':email,'phone':phone})).data['member'] as Map);
  Future<Map<String,dynamic>> uploadProfilePhoto(PlatformFile photo) async {
    final bytes=photo.bytes;
    if(bytes==null||bytes.isEmpty) throw Exception('The selected image could not be read. Please choose it again.');
    if(bytes.length>3*1024*1024) throw Exception('Choose a JPG, PNG or WebP image under 3 MB.');
    final ext=(photo.extension??'').toLowerCase();
    final mime=ext=='jpg'||ext=='jpeg'?'image/jpeg':ext=='png'?'image/png':ext=='webp'?'image/webp':'';
    if(mime.isEmpty) throw Exception('Choose a JPG, PNG or WebP image.');
    return Map<String,dynamic>.from((await dio.post('profile/photo',data:{'mimeType':mime,'imageBase64':base64Encode(bytes)})).data as Map);
  }
  Future<Map<String,dynamic>> notifications() async => Map<String,dynamic>.from((await dio.get('notifications')).data as Map);
  Future<void> markNotificationRead(int id) async { await dio.post('notifications/$id/read'); }
  Future<void> markAllNotificationsRead() async { await dio.post('notifications/read-all'); }
  Future<Map<String,dynamic>> communityPosts() async => Map<String,dynamic>.from((await dio.get('community/posts')).data as Map);
  Future<Map<String,dynamic>> createCommunityPost(String body) async => Map<String,dynamic>.from((await dio.post('community/posts',data:{'body':body,'type':'post'})).data as Map);
  Future<Map<String,dynamic>> communityComments(int postId) async => Map<String,dynamic>.from((await dio.get('community/posts/$postId/comments')).data as Map);
  Future<Map<String,dynamic>> createCommunityComment(int postId,String body) async => Map<String,dynamic>.from((await dio.post('community/posts/$postId/comments',data:{'body':body})).data as Map);
  Future<Map<String,dynamic>> cooperativeStatus() async => Map<String,dynamic>.from((await dio.get('cooperative/status')).data as Map);
  Future<Map<String,dynamic>> submitCooperativeConnection({required String registeredName,required String registeredEmail}) async => Map<String,dynamic>.from((await dio.post('cooperative/connections',data:{'registeredName':registeredName,'registeredEmail':registeredEmail})).data as Map);
  Future<Map<String,dynamic>> socialLinks() async => Map<String,dynamic>.from((await dio.get('social-links')).data as Map);
  Future<Map<String,dynamic>> adminCooperativeConnections() async => Map<String,dynamic>.from((await dio.get('admin/cooperative/connections')).data as Map);
  Future<Map<String,dynamic>> reviewCooperativeConnection({required int id,required String decision,required String note}) async => Map<String,dynamic>.from((await dio.post('admin/cooperative/connections/$id/review',data:{'decision':decision,'note':note})).data as Map);
  Future<Map<String,dynamic>> adminSocialLinks() async => Map<String,dynamic>.from((await dio.get('admin/social-links')).data as Map);
  Future<Map<String,dynamic>> saveAdminSocialLink({required String key,required String label,required String url,required bool active}) async => Map<String,dynamic>.from((await dio.post('admin/social-links',data:{'key':key,'label':label,'url':url,'active':active})).data as Map);
  Future<Map<String,dynamic>> adminPermissions() async => Map<String,dynamic>.from((await dio.get('admin/permissions')).data as Map);
  Future<Map<String,dynamic>> saveAdminPermission({required int adminMemberId,required String category,required String level,required List<String> allowedActions}) async => Map<String,dynamic>.from((await dio.post('admin/permissions',data:{'adminMemberId':adminMemberId,'category':category,'level':level,'allowedActions':allowedActions})).data as Map);
  Future<Map<String,dynamic>> roles() async => Map<String,dynamic>.from((await dio.get('roles')).data as Map);
  Future<Map<String,dynamic>> requestRole({required int roleId,required String message}) async => Map<String,dynamic>.from((await dio.post('roles/request',data:{'roleId':roleId,'message':message})).data as Map);
  Future<Map<String,dynamic>> adminRoles() async => Map<String,dynamic>.from((await dio.get('admin/roles')).data as Map);
  Future<Map<String,dynamic>> saveRole({int? roleId,required String roleName,required String description,required bool isActive}) async => Map<String,dynamic>.from((await dio.post('admin/roles/catalog',data:{'roleId':roleId,'roleName':roleName,'description':description,'isActive':isActive})).data as Map);
  Future<Map<String,dynamic>> reviewRoleRequest({required int requestId,required String decision}) async => Map<String,dynamic>.from((await dio.post('admin/roles/requests/$requestId',data:{'decision':decision})).data as Map);
  Future<Map<String,dynamic>> assignRole({required int memberId,required int roleId,required String action}) async => Map<String,dynamic>.from((await dio.post('admin/roles/assign',data:{'memberId':memberId,'roleId':roleId,'action':action})).data as Map);
  Future<Map<String,dynamic>> requestSovereignPartner({required String companyName,required String message}) async => Map<String,dynamic>.from((await dio.post('sovereign/roles/partner-request',data:{'companyName':companyName,'message':message})).data as Map);

  Future<Map<String, dynamic>> submitDeposit({required String currency, required String amount, required String methodId, required String reference, required String note, required PlatformFile proof}) async {
    final bytes = proof.bytes;
    if (bytes == null || bytes.isEmpty) throw Exception('The selected receipt could not be read. Please choose it again.');
    final form = FormData.fromMap({'currency': currency, 'amount': amount, 'payment_method_id': methodId, 'payment_reference': reference, 'member_note': note, 'payment_proof': MultipartFile.fromBytes(bytes, filename: proof.name)});
    return Map<String, dynamic>.from((await dio.post('deposit/requests', data: form)).data as Map);
  }
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
  bool _isSovereignAdmin(Map<String, dynamic> m) {
    final role = (m['adminRole'] ?? '').toString().trim().toLowerCase().replaceAll(' ', '_');
    return m['isSovereignAdmin'] == true || role == 'sovereign_desk_admin' || role == 'sovereign_admin';
  }
  bool _isAdmin(Map<String, dynamic> m) {
    final role = (m['adminRole'] ?? '').toString().trim().toLowerCase().replaceAll(' ', '_');
    return m['isAdmin'] == true || (role.isNotEmpty && role != 'sovereign_desk_admin' && role != 'sovereign_admin');
  }
  Future<void> signOut() async { try { await widget.api.logout(); } catch (_) {} if (mounted) setState(() => member = null); }
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Monarch Codex', debugShowCheckedModeBanner: false,
    theme: makeTheme(false), darkTheme: makeTheme(true), themeMode: light ? ThemeMode.light : ThemeMode.dark,
    home: busy ? const Scaffold(body: Center(child: CircularProgressIndicator(color: gold))) :
      member == null ? AuthPage(api: widget.api, onSignedIn: signedIn) :
      (_isSovereignAdmin(member!) ? SovereignAdminShell(api: widget.api, member: member!, signOut: signOut, light: light, toggleTheme: () => setState(() => light = !light)) : _isAdmin(member!) ? AdminShell(api: widget.api, member: member!, signOut: signOut, light: light, toggleTheme: () => setState(() => light = !light)) :
      Shell(api: widget.api, member: member!, signOut: signOut, light: light, toggleTheme: () => setState(() => light = !light))),
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
    ))));
  }
  String? requiredField(String? value) => value == null || value.trim().isEmpty ? 'This field is required' : null;
}

class SocialLinksPage extends StatefulWidget {
  const SocialLinksPage({super.key,required this.api,required this.dark});
  final MonarchApi api;final bool dark;
  @override State<SocialLinksPage> createState()=>_SocialLinksPageState();
}
class _SocialLinksPageState extends State<SocialLinksPage>{
  late Future<Map<String,dynamic>> future;String? error;
  @override void initState(){super.initState();future=widget.api.socialLinks();}
  void reload()=>setState(()=>future=widget.api.socialLinks());
  Future<void> open(String raw)async{final uri=Uri.tryParse(raw);if(uri==null||uri.scheme!='https'||uri.host.isEmpty){setState(()=>error='This link is not a valid secure HTTPS address.');return;}try{final ok=await launchUrl(uri,mode:LaunchMode.externalApplication);if(!ok&&mounted)setState(()=>error='Could not open this link. Please try again.');}catch(_){if(mounted)setState(()=>error='Could not open this link. Please try again.');}}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(s.hasError)return ListView(padding:const EdgeInsets.all(20),children:[const Text('Official social links are unavailable right now.'),const SizedBox(height:10),FilledButton(onPressed:reload,child:const Text('Retry'))]);
    final items=(s.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('OFFICIAL MONARCH CODEX CHANNELS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:6),const Text('Open verified official links. Links open outside the app using a secure HTTPS address.',style:TextStyle(color:muted)),
      if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,style:const TextStyle(color:Colors.redAccent))),
      if(items.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No official social links have been published yet.',textAlign:TextAlign.center,style:TextStyle(color:muted))),
      ...items.map((x)=>Card(color:widget.dark?panel:Colors.white,child:ListTile(leading:const Icon(Icons.public,color:gold),title:Text((x['label']??'Official channel').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((x['url']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis),trailing:const Icon(Icons.open_in_new,color:gold),onTap:()=>open((x['url']??'').toString())))),
      OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Refresh official links'))
    ]);
  });
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key,required this.api,required this.dark});
  final MonarchApi api; final bool dark;
  @override State<NotificationsPage> createState()=>_NotificationsPageState();
}
class _NotificationsPageState extends State<NotificationsPage>{
  late Future<Map<String,dynamic>> future; bool busy=false; String? error;
  @override void initState(){super.initState();future=widget.api.notifications();}
  void reload(){setState(()=>future=widget.api.notifications());}
  Future<void> markAll() async {setState(()=>busy=true);try{await widget.api.markAllNotificationsRead();if(mounted){setState(()=>busy=false);reload();}}catch(e){if(mounted)setState(() { busy=false; error='Could not update notifications. Please try again.'; });}}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snapshot){
    if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator(color:gold));
    if(snapshot.hasError)return ListView(padding:const EdgeInsets.all(20),children:[const Text('Notifications are temporarily unavailable.'),const SizedBox(height:12),FilledButton(onPressed:reload,child:const Text('Try again'))]);
    final data=snapshot.data??{};final items=(data['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    return RefreshIndicator(color:gold,onRefresh:()async=>reload(),child:ListView(padding:const EdgeInsets.all(15),children:[
      Row(children:[const Expanded(child:Text('IMPORTANT UPDATES',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1))),Text('${data['unreadCount']??0} unread'),const SizedBox(width:8),IconButton(onPressed:busy?null:markAll,tooltip:'Mark all as read',icon:const Icon(Icons.done_all,color:gold))]),
      if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,style:const TextStyle(color:Colors.redAccent))),
      if(items.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:32),child:Column(children:[Icon(Icons.notifications_none,size:44,color:muted),SizedBox(height:10),Text('You are all caught up.'),SizedBox(height:4),Text('Important account and review updates will appear here.',style:TextStyle(color:muted),textAlign:TextAlign.center)])),
      ...items.map((item){final read=item['readAt']!=null;final id=(item['id'] as num?)?.toInt();return Card(color:widget.dark?panel:Colors.white,child:ListTile(leading:Icon(read?Icons.notifications_none:Icons.notifications_active,color:read?muted:gold),title:Text((item['title']??'Account update').toString(),style:TextStyle(fontWeight:read?FontWeight.w500:FontWeight.w800)),subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Text((item['body']??'').toString()+'\n'+(item['createdAt']??'').toString())),isThreeLine:true,trailing:read?null:IconButton(icon:const Icon(Icons.done,color:gold),tooltip:'Mark as read',onPressed:id==null?null:()async{try{await widget.api.markNotificationRead(id);if(mounted)reload();}catch(_){if(mounted)setState(()=>error='Could not mark this notification as read.');}})));}),
    ]));
  });
}

class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({super.key, required this.api, required this.dark});
  final MonarchApi api;
  final bool dark;
  @override State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  late Future<Map<String, dynamic>> future;
  @override void initState() { super.initState(); future = widget.api.investments(); }
  void reload() => setState(() => future = widget.api.investments());
  String money(dynamic currency, dynamic amount) {
    final value = double.tryParse((amount ?? '0').toString()) ?? 0;
    return '${currency ?? ''} ${value.toStringAsFixed(2)}';
  }
  @override Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
      if (snapshot.hasError) return ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.trending_up, color: gold, size: 42),
        const SizedBox(height: 10),
        const Text('Investment information is temporarily unavailable. Your wallet has not been changed.'),
        const SizedBox(height: 12),
        FilledButton(onPressed: reload, child: const Text('Retry')),
      ]);
      final data = snapshot.data ?? {};
      final packages = (data['packages'] as List? ?? const []).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
      final portfolio = (data['portfolio'] as List? ?? const []).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
      return RefreshIndicator(color: gold, onRefresh: () async { reload(); await future; }, child: ListView(padding: const EdgeInsets.all(15), children: [
        const Text('INVESTMENT OPPORTUNITIES', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 5),
        const Text('Review the currently active packages. Package details are read from Monarch Codex; no projected returns are invented.', style: TextStyle(color: muted)),
        const SizedBox(height: 12),
        if (packages.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No active investment packages are available right now.', textAlign: TextAlign.center))),
        ...packages.map((p) {
          final terms = (p['terms'] ?? '').toString().trim();
          final description = (p['description'] ?? '').toString().trim();
          return Card(color: widget.dark ? panel : Colors.white, child: ExpansionTile(
            leading: const Icon(Icons.workspace_premium, color: gold),
            title: Text((p['name'] ?? 'Investment package').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(money(p['currency'], p['price']) + ' · ' + ((p['durationDays'] == null || p['durationDays'].toString().isEmpty) ? 'Flexible duration' : '${p['durationDays']} days'), style: const TextStyle(color: gold, fontWeight: FontWeight.w800))),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (description.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text(description)),
              if (terms.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: Text('Terms: ' + terms, style: const TextStyle(color: muted)))),
              const SizedBox(height: 8),
              const Align(alignment: Alignment.centerLeft, child: Text('Review the terms before investing. No purchase or wallet change is performed from this view.', style: TextStyle(color: muted, fontSize: 11))),
            ],
          ));
        }),
        const SizedBox(height: 20),
        Row(children: [const Expanded(child: Text('MY PORTFOLIO', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: 1))), IconButton(onPressed: reload, icon: const Icon(Icons.refresh, color: gold), tooltip: 'Refresh investments')]),
        if (portfolio.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Your recorded investments will appear here once you have an investment on your account.', textAlign: TextAlign.center))),
        ...portfolio.map((p) => Card(color: widget.dark ? panel : Colors.white, child: ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined, color: gold),
          title: Text((p['packageName'] ?? 'Investment').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text('Principal: ' + money(p['currency'], p['principalAmount']) + '\nTotal charged: ' + money(p['currency'], p['totalCharged']) + '\nStatus: ' + (p['status'] ?? 'unknown').toString().toUpperCase() + '\nStarted: ' + (p['startsAt'] ?? '—').toString() + ((p['maturesAt'] == null) ? '' : '\nMatures: ' + p['maturesAt'].toString()))),
          isThreeLine: true,
        ))),
      ]));
    },
  );
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key,required this.api,required this.dark});
  final MonarchApi api; final bool dark;
  @override State<CommunityPage> createState()=>_CommunityPageState();
}
class _CommunityPageState extends State<CommunityPage>{
  final composer=TextEditingController();late Future<Map<String,dynamic>> future;bool sending=false;String? message;bool success=false;
  @override void initState(){super.initState();future=widget.api.communityPosts();}
  void reload()=>setState(()=>future=widget.api.communityPosts());
  Future<void> publish()async{final body=composer.text.trim();if(body.isEmpty)return;setState(() { sending=true; message=null; });try{final r=await widget.api.createCommunityPost(body);composer.clear();if(mounted)setState(() { sending=false; message=(r['message']??'Post published.').toString(); success=true; });reload();}catch(e){if(mounted)setState(() { sending=false; message='Could not publish your post. Please try again.'; success=false; });}}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(15),children:[
    const Text('THE MONARCH COMMUNITY',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
    const SizedBox(height:5),const Text('Share an update, ask a question, and connect with members.',style:TextStyle(color:muted)),
    const SizedBox(height:14),Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      TextField(controller:composer,maxLines:4,maxLength:5000,decoration:const InputDecoration(hintText:'What would you like to share?',border:OutlineInputBorder())),
      const SizedBox(height:8),Row(children:[if(message!=null)Expanded(child:Text(message!,style:TextStyle(color:success?Colors.green:Colors.redAccent,fontSize:12))),FilledButton.icon(onPressed:sending?null:publish,icon:const Icon(Icons.send),label:Text(sending?'Posting…':'Publish'))])
    ]))),
    const SizedBox(height:14),Row(children:[const Expanded(child:Text('COMMUNITY FEED',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1))),IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),
    FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snapshot){if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator(color:gold));if(snapshot.hasError)return const Padding(padding:EdgeInsets.all(12),child:Text('The community feed is not available yet. Please try again later.',style:TextStyle(color:muted)));final posts=(snapshot.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();if(posts.isEmpty)return const Padding(padding:EdgeInsets.all(22),child:Text('No posts yet. Be the first to start a conversation.',textAlign:TextAlign.center,style:TextStyle(color:muted)));return Column(children:posts.map((p)=>Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((p['authorName']??'Monarch member').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w800)),const SizedBox(height:7),Text((p['body']??'').toString()),const SizedBox(height:9),Text((p['createdAt']??'').toString(),style:const TextStyle(color:muted,fontSize:10))])))).toList());})
  ]);
}

class OnlineCooperativePage extends StatefulWidget {
  const OnlineCooperativePage({super.key,required this.api,required this.dark});
  final MonarchApi api; final bool dark;
  @override State<OnlineCooperativePage> createState()=>_OnlineCooperativePageState();
}
class _OnlineCooperativePageState extends State<OnlineCooperativePage>{
  final name=TextEditingController(),email=TextEditingController();late Future<Map<String,dynamic>> future;bool sending=false;String? message;bool success=false;
  @override void initState(){super.initState();future=widget.api.cooperativeStatus();}
  void reload()=>setState(()=>future=widget.api.cooperativeStatus());
  Future<void> register()async{setState(()=>sending=true);try{await widget.api.submitCooperativeConnection(registeredName:name.text.trim(),registeredEmail:email.text.trim());if(mounted){setState(() { sending=false; message='Submitted for manual verification. You will be notified after review.'; success=true; });name.clear();email.clear();reload();}}catch(e){if(mounted)setState(() { sending=false; message='Could not submit these details. Check them and try again.'; success=false; });}}
  Future<void> openRegistration()async{final uri=Uri.parse('https://airdrop.myturntech.com/register?ref=53');if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&mounted)setState(()=>message='Could not open the registration page. Please try again.');}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snapshot){
    final items=(snapshot.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    final connected=items.any((x)=>x['status']=='approved');final pending=items.any((x)=>x['status']=='pending');
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('ONLINE COOPERATIVE',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:6),const Text('Register with our referral link, then submit the same name and email for manual verification. We will not ask for your password or OTP.',style:TextStyle(color:muted)),
      const SizedBox(height:14),Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Icon(connected?Icons.verified:pending?Icons.hourglass_top:Icons.link,color:gold),const SizedBox(width:8),Expanded(child:Text(connected?'CONNECTED TO MONARCH CODEX':pending?'VERIFICATION PENDING':'NOT CONNECTED',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:12)))]),
        const SizedBox(height:12),FilledButton.icon(onPressed:openRegistration,icon:const Icon(Icons.open_in_new),label:const Text('Register with Online Cooperative')),
        const SizedBox(height:16),TextField(controller:name,decoration:const InputDecoration(labelText:'Name used to register',border:OutlineInputBorder())),
        const SizedBox(height:10),TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Registration email',border:OutlineInputBorder())),
        const SizedBox(height:12),if(message!=null)Padding(padding:const EdgeInsets.only(bottom:10),child:Text(message!,style:TextStyle(color:success?Colors.green:Colors.redAccent))),
        FilledButton(onPressed:sending||connected||pending?null:register,child:Text(sending?'Submitting…':pending?'Awaiting verification':connected?'Account connected':'Submit for verification')),
      ]))),
      if(snapshot.hasError)const Padding(padding:EdgeInsets.all(10),child:Text('Connection status could not be loaded. Check your connection and refresh.',style:TextStyle(color:muted))),
      if(items.isNotEmpty) ...items.map((x)=>Card(color:widget.dark?panel:Colors.white,child:ListTile(leading:Icon(x['status']=='approved'?Icons.check_circle:x['status']=='pending'?Icons.hourglass_top:Icons.info_outline,color:gold),title:Text((x['status']??'').toString().toUpperCase()),subtitle:Text('Submitted: ${x['createdAt']??'—'}${x['reviewNote']==null?'':'\nReason: ${x['reviewNote']}'}')))),
      const SizedBox(height:10),OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Refresh connection status')),
    ]);
  });
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
  int photoVersion = DateTime.now().millisecondsSinceEpoch;
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
        Expanded(child: special != null ? specialPage(special!, dark) : tab == 0 ? overviewPage(dark) : tab == 1 ? walletPage(dark) : tab == 2 ? InvestmentsPage(api: widget.api, dark: dark) : tab == 5 ? profilePage(dark) : tab == 4 ? CommunityPage(api: widget.api, dark: dark) : featurePage(names[tab], 'Market information', icons[tab], 'Live market quotes are not displayed until a verified quote provider is connected. No placeholder prices are shown as real market data.', dark)),
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
        quick('Online Coop', Icons.link_rounded, () => page('Online Cooperative'), dark),
        quick('Social Links', Icons.public, () => page('Social Links'), dark),
      ]),
      if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: gold))),
      if (error != null) Message(text: error!, success: false),
    ]));
  }

  Widget walletPage(bool dark) {
    final w = data?['wallet'] is Map ? Map<String, dynamic>.from(data!['wallet'] as Map) : <String, dynamic>{};
    return ListView(padding: const EdgeInsets.all(15), children: [
      const Text('Your money, clearly.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6), const Text('Requests and history are managed securely inside this app.', style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 16), balanceCard(number(w['ngn']), number(w['usd']), number(w['rate'])),
      const SizedBox(height: 12),
      tile('Deposit', 'Choose a payment destination and submit your receipt.', Icons.add_card, dark, () => page('Deposit')),
      tile('Withdraw', 'Request a payout to a saved account after KYC approval.', Icons.south_west, dark, () => page('Withdraw')),
      tile('Transactions', 'View recorded activity and request statuses.', Icons.receipt_long, dark, () => page('Transactions')),
    ]);
  }

  Widget profilePage(bool dark) {
    final m = data?['member'] is Map ? Map<String, dynamic>.from(data!['member'] as Map) : widget.member;
    return ProfileEditorPage(api: widget.api, member: m, dark: dark, onUpdated: () { if(mounted) setState(() { photoVersion = DateTime.now().millisecondsSinceEpoch; }); refresh(); });
  }

  Widget specialPage(String p, bool dark) {
    if (p == 'Transactions') return TransactionsPage(api: widget.api, dark: dark);
    if (p == 'Deposit') return DepositPage(api: widget.api, dark: dark, onDone: refresh);
    if (p == 'Withdraw') return WithdrawalPage(api: widget.api, dark: dark, onDone: refresh);
    if (p == 'Notifications') return NotificationsPage(api: widget.api, dark: dark);
    if (p == 'Settings') return ListView(padding: const EdgeInsets.all(15), children: [
      tile(widget.light ? 'Dark appearance' : 'Light appearance', 'Toggle app appearance.', Icons.contrast, dark, widget.toggleTheme),
      tile('Account details', 'Open your existing profile page.', Icons.manage_accounts, dark, () => openSite('/profile')),
      tile('Password recovery', 'Secure password reset.', Icons.lock_reset, dark, () => openSite('/forgot-password')),
    ]);
    if (p == 'Help & Support') return ListView(padding: const EdgeInsets.all(15), children: [
      featurePage(p, 'We are here to help', Icons.support_agent, 'For account access, verification or payment questions, contact official Monarch Codex support.', dark),
      tile('Email support', 'support@monarchcodex.online', Icons.email_outlined, dark, () => launchUrl(Uri.parse('mailto:support@monarchcodex.online'))),
      tile('Open website', 'Visit Monarch Codex online.', Icons.open_in_new, dark, () => openSite('/')),
    ]);
    if (p == 'KYC Verification') return KycStatusPage(api: widget.api, dark: dark);
    if (p == 'Referrals') return ReferralsPage(api: widget.api, dark: dark);
    if (p == 'Online Cooperative') return OnlineCooperativePage(api: widget.api, dark: dark);
    if (p == 'Social Links') return SocialLinksPage(api: widget.api, dark: dark);
    return featurePage(p, 'Monarch Codex', Icons.auto_awesome, 'This section will connect to your existing account backend. Existing records are not changed.', dark);
  }

  Widget bottomNav(bool dark) => Container(
    padding: const EdgeInsets.fromLTRB(2, 7, 2, 5),
    decoration: BoxDecoration(color: dark ? const Color(0xFF111113) : Colors.white, border: Border(top: BorderSide(color: dark ? const Color(0xFF2B2924) : const Color(0xFFE2DED1)))),
    child: Row(children: List.generate(names.length, (i) => Expanded(child: InkWell(
      onTap: () => page(null, i), borderRadius: BorderRadius.circular(11),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: tab == i ? gold.withValues(alpha:.14) : Colors.transparent, borderRadius: BorderRadius.circular(99)), child: Icon(icons[i], size: 18, color: tab == i ? gold : muted)),
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
      Container(width: 37, height: 37, decoration: BoxDecoration(color: gold.withValues(alpha:.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: gold, size: 20)),
      const SizedBox(height: 7), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
    ]),
  ));

  Widget featurePage(String title, String subtitle, IconData icon, String body, bool dark) => ListView(padding: const EdgeInsets.all(15), children: [
    Container(padding: const EdgeInsets.all(20), decoration: card(dark), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 50, height: 50, decoration: BoxDecoration(color: gold.withValues(alpha:.12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: gold, size: 27)),
      const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 13), Text(body, style: const TextStyle(color: muted, fontSize: 13, height: 1.6)),
    ])),
  ]);

  Widget tile(String title, String subtitle, IconData icon, bool dark, VoidCallback action) => Container(
    margin: const EdgeInsets.only(bottom: 10), decoration: card(dark), child: ListTile(
      onTap: action, contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      leading: Container(width: 39, height: 39, decoration: BoxDecoration(color: gold.withValues(alpha:.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: gold, size: 20)),
      title: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: const TextStyle(color: muted, fontSize: 10, height: 1.4))),
      trailing: const Icon(Icons.chevron_right, color: muted, size: 19),
    ),
  );

  BoxDecoration card(bool dark) => BoxDecoration(color: dark ? panel : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: dark ? const Color(0xFF302E29) : const Color(0xFFE4DFD2)));
  Future<void> openSite(String path) async => launchUrl(Uri.parse(site + path), mode: LaunchMode.externalApplication);
}

double number(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;


BoxDecoration mcCard(bool dark) => BoxDecoration(color: dark ? panel : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: dark ? const Color(0xFF302E29) : const Color(0xFFE4DFD2)));

class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({super.key,required this.api,required this.member,required this.dark,required this.onUpdated});
  final MonarchApi api; final Map<String,dynamic> member; final bool dark; final VoidCallback onUpdated;
  @override State<ProfileEditorPage> createState()=>_ProfileEditorPageState();
}
class _ProfileEditorPageState extends State<ProfileEditorPage> {
  final name=TextEditingController(), username=TextEditingController(), email=TextEditingController(), phone=TextEditingController(), requestMessage=TextEditingController();
  Map<String,dynamic> member={}; List<dynamic> roles=[], requests=[]; bool loading=true,saving=false,photoBusy=false,rolesBusy=false; int version=DateTime.now().millisecondsSinceEpoch; String? error,notice;
  @override void initState(){super.initState();member=Map<String,dynamic>.from(widget.member);_setControllers(member);_load();}
  void _setControllers(Map<String,dynamic> m){name.text=(m['fullName']??'').toString();username.text=(m['username']??'').toString();email.text=(m['email']??'').toString();phone.text=(m['phone']??'').toString();}
  Future<void> _load() async {try{final p=await widget.api.profile();if(!mounted)return;setState((){member=p;_setControllers(p);loading=false;});try{final r=await widget.api.roles();if(mounted)setState((){roles=List<dynamic>.from(r['roles']??[]);requests=List<dynamic>.from(r['requests']??[]);});}catch(e){if(mounted)setState(()=>error='Profile editing is available, but role requests need the latest website update. '+_message(e));}}catch(e){if(mounted)setState((){loading=false;error=_message(e);});}}
  String _message(Object e){if(e is DioException){final d=e.response?.data;if(d is Map&&d['message']!=null)return d['message'].toString();}return e.toString().replaceFirst('Exception: ','');}
  Future<void> _save() async {setState((){saving=true;error=null;notice=null;});try{final p=await widget.api.saveProfile(fullName:name.text.trim(),username:username.text.trim(),email:email.text.trim(),phone:phone.text.trim());if(!mounted)return;setState((){member={...member,...p};notice='Your profile details were saved.';saving=false;});widget.onUpdated();}catch(e){if(mounted)setState((){error=_message(e);saving=false;});}}
  Future<void> _photo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      setState(() { photoBusy = true; error = null; notice = null; });
      final uploaded = await widget.api.uploadProfilePhoto(result.files.first);
      if (!mounted) return;
      final photoUrl = (uploaded['profilePhotoUrl'] ?? '/member-avatar-current').toString();
      setState(() {
        version = DateTime.now().millisecondsSinceEpoch;
        member = {...member, 'profilePhotoUrl': photoUrl};
        notice = 'Profile picture updated across your account.';
        photoBusy = false;
      });
      widget.onUpdated();
    } catch (e) {
      if (mounted) setState(() { error = _message(e); photoBusy = false; });
    }
  }
  Future<void> _request(Map role) async {setState((){rolesBusy=true;error=null;notice=null;});try{await widget.api.requestRole(roleId:(role['id'] as num).toInt(),message:requestMessage.text.trim());requestMessage.clear();final r=await widget.api.roles();if(!mounted)return;setState((){roles=List<dynamic>.from(r['roles']??[]);requests=List<dynamic>.from(r['requests']??[]);notice='Role request submitted for administrator review.';rolesBusy=false;});}catch(e){if(mounted)setState((){error=_message(e);rolesBusy=false;});}}
  @override void dispose(){name.dispose();username.dispose();email.dispose();phone.dispose();requestMessage.dispose();super.dispose();}
  @override Widget build(BuildContext context){final dark=widget.dark;final assigned=roles.where((r)=>r is Map&&r['assigned']==true).toList();return ListView(padding:const EdgeInsets.all(15),children:[
    if(error!=null) Message(text:error!,success:false), if(notice!=null) Message(text:notice!,success:true),
    Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:dark?panel:Colors.white,borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFF6D5920))),child:Column(children:[MemberAvatar(api:widget.api,member:member,size:78,radius:24,version:version),const SizedBox(height:10),Text((member['fullName']??'Monarch Member').toString(),textAlign:TextAlign.center,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),Text((member['email']??'').toString(),style:const TextStyle(color:muted,fontSize:12)),const SizedBox(height:10),OutlinedButton.icon(onPressed:photoBusy?null:_photo,icon:photoBusy?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.add_a_photo_outlined),label:Text(photoBusy?'Uploading photo…':'Change profile picture'))])),
    const SizedBox(height:12),Container(padding:const EdgeInsets.all(16),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('PERSONAL DETAILS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),const SizedBox(height:12),TextField(controller:name,decoration:const InputDecoration(labelText:'Full name')),const SizedBox(height:10),TextField(controller:username,decoration:const InputDecoration(labelText:'Username')),const SizedBox(height:10),TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email address')),const SizedBox(height:10),TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone number')),const SizedBox(height:14),FilledButton(onPressed:saving?null:_save,style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,minimumSize:const Size.fromHeight(48)),child:Text(saving?'Saving…':'Save profile details'))])),
    const SizedBox(height:12),Container(padding:const EdgeInsets.all(16),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('YOUR ROLES',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),const SizedBox(height:6),const Text('Roles are assigned only after administrator approval.',style:TextStyle(color:muted,fontSize:12)),if(loading)const Padding(padding:EdgeInsets.all(14),child:Center(child:CircularProgressIndicator(color:gold))),if(!loading&&assigned.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('No roles have been assigned yet.',style:TextStyle(color:muted))),...assigned.map((r)=>ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.verified_user,color:gold),title:Text((r['role_name']??'').toString()),subtitle:Text((r['description']??'').toString(),style:const TextStyle(color:muted,fontSize:12)))),if(!loading)...roles.where((r)=>r is Map&&r['assigned']!=true).map((r)=>Card(color:dark?const Color(0xFF101012):Colors.white,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((r['role_name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),Text((r['description']??'Request approval to access this role.').toString(),style:const TextStyle(color:muted,fontSize:12)),const SizedBox(height:8),TextField(controller:requestMessage,maxLines:2,decoration:const InputDecoration(labelText:'Reason for request (optional)')),Align(alignment:Alignment.centerRight,child:TextButton(onPressed:rolesBusy?null:()=>_request(Map<String,dynamic>.from(r as Map)),child:const Text('Request role')))]))))],)),
    const SizedBox(height:12),Container(padding:const EdgeInsets.all(16),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('ROLE REQUEST HISTORY',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),if(requests.isEmpty)const Text('No requests yet.',style:TextStyle(color:muted)),...requests.map((r)=>ListTile(contentPadding:EdgeInsets.zero,title:Text((r['role_name']??'Role').toString()),subtitle:Text((r['message']??'').toString(),style:const TextStyle(color:muted,fontSize:12)),trailing:Text((r['status']??'').toString().toUpperCase(),style:const TextStyle(color:gold,fontSize:10,fontWeight:FontWeight.w900))))]))
  ]);}
}

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
      if (data == null) return Padding(padding: EdgeInsets.all(widget.size * .14), child: SvgPicture.asset('assets/images/monarch-codex-logo.svg', fit: BoxFit.contain));
      return Image.memory(data, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Padding(padding: EdgeInsets.all(widget.size * .14), child: SvgPicture.asset('assets/images/monarch-codex-logo.svg', fit: BoxFit.contain)));
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
