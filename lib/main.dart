import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:monarch_codex/native_workspaces.dart';
import 'package:monarch_codex/app_updater.dart';

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

String apiErrorMessage(Object error, {String fallback = 'The request could not be completed. Please try again.'}) {
  if (error is! DioException) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? fallback : text;
  }
  final response = error.response;
  final status = response?.statusCode;
  final data = response?.data;
  if (data is Map) {
    for (final key in const ['message', 'error_description', 'error']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty &&
          !const ['internal_server_error', 'request_failed'].contains(value.trim().toLowerCase())) {
        return value.trim();
      }
    }
    final details = data['details'] ?? data['errors'];
    if (details is List && details.isNotEmpty) {
      final first = details.first;
      if (first is Map && first['message'] is String) return first['message'].toString();
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }
  }
  if (status == 400 || status == 422) return 'Some information is missing or invalid. Review the fields and try again.';
  if (status == 401) return 'Your session has expired. Sign in again, then retry.';
  if (status == 403) return 'Your account does not have permission for this action. Contact the Super Admin if you believe this is incorrect.';
  if (status == 404) return 'This service was not found. The website backend may need to be updated.';
  if (status == 429) return 'Too many requests were sent. Wait a moment before retrying.';
  if (status != null && status >= 500) return 'The server could not complete this request (HTTP $status). Please retry; if it continues, the backend logs need checking.';
  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout) return 'The server took too long to respond. Check your connection and retry.';
  if (error.type == DioExceptionType.connectionError) return 'Could not connect to monarchcodex.online. Check your internet connection.';
  if (error.type == DioExceptionType.cancel) return 'This request was cancelled. Retry if you still need it.';
  if (error.type == DioExceptionType.badResponse) return 'The server returned an unexpected response. Please retry.';
  if (error.type == DioExceptionType.badCertificate) return 'A secure connection could not be established. Please try again later.';
  return fallback;
}

class MonarchApi {
  MonarchApi(CookieJar jar) : dio = Dio(BaseOptions(
    baseUrl: '$apiRoot/',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  )) {
    dio.interceptors.add(CookieManager(jar));
    // Log only request metadata; never log headers, cookies, tokens or request bodies.
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final requestId = 'mc-${DateTime.now().microsecondsSinceEpoch}';
        options.extra['monarchRequestId'] = requestId;
        options.headers['X-Request-ID'] = requestId;
        if (kDebugMode) {
          debugPrint('API ${options.method} ${options.uri.path} requestId=$requestId');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          debugPrint('API ${response.requestOptions.method} ${response.requestOptions.uri.path} '
              'status=${response.statusCode} requestId=${response.requestOptions.extra['monarchRequestId']}');
        }
        handler.next(response);
      },
      onError: (error, handler) {
        if (kDebugMode) {
          debugPrint('API ${error.requestOptions.method} ${error.requestOptions.uri.path} '
              'status=${error.response?.statusCode ?? 'network'} '
              'type=${error.type.name} requestId=${error.requestOptions.extra['monarchRequestId']}');
        }
        handler.next(error);
      },
    ));
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
  Future<Map<String,dynamic>> purchaseInvestment({required int packageId,required String idempotencyKey}) async =>
      Map<String,dynamic>.from((await dio.post('investments/$packageId/purchase',data:{'idempotencyKey':idempotencyKey})).data as Map);
  Future<Map<String, dynamic>> kycStatus() async => Map<String, dynamic>.from((await dio.get('kyc/status')).data as Map);
  Future<Map<String, dynamic>> referrals() async => Map<String, dynamic>.from((await dio.get('referrals')).data as Map);
  Future<Map<String,dynamic>> academy() async => Map<String,dynamic>.from((await dio.get('academy')).data as Map);
  Future<Map<String,dynamic>> purchaseAcademyAccess() async => Map<String,dynamic>.from((await dio.post('academy/access/purchase')).data as Map);
  Future<Map<String,dynamic>> replayAcademyLesson({required int lessonId,required String idempotencyKey}) async => Map<String,dynamic>.from((await dio.post('academy/lessons/$lessonId/replay',data:{'idempotencyKey':idempotencyKey})).data as Map);
  Future<Map<String,dynamic>> watchAcademyLesson(int lessonId) async => Map<String,dynamic>.from((await dio.post('academy/lessons/$lessonId/watch')).data as Map);
  Future<Map<String,dynamic>> completeAcademyLesson(int lessonId) async => Map<String,dynamic>.from((await dio.post('academy/lessons/$lessonId/complete')).data as Map);

  Future<void> logout() async { await dio.post('auth/logout'); }
  Future<Map<String, dynamic>> walletBalances() async => Map<String, dynamic>.from((await dio.get('wallet/balances')).data as Map);
  Future<Map<String, dynamic>> walletRecipient(String uid) async => Map<String, dynamic>.from((await dio.get('wallet/recipient/${Uri.encodeComponent(uid)}')).data as Map);
  Future<Map<String, dynamic>> transferWallet({required String recipientUid,required String currency,required String amount,required String idempotencyKey}) async =>
      Map<String, dynamic>.from((await dio.post('wallet/transfer',data:{'recipientUid':recipientUid,'currency':currency,'amount':amount,'idempotencyKey':idempotencyKey})).data as Map);
  Future<Map<String, dynamic>> transactions() async => Map<String, dynamic>.from((await dio.get('transactions')).data as Map);
  Future<Map<String, dynamic>> depositOptions() async => Map<String, dynamic>.from((await dio.get('deposit/options')).data as Map);
  Future<Map<String, dynamic>> withdrawalOptions() async => Map<String, dynamic>.from((await dio.get('withdrawal/options')).data as Map);
  Future<Map<String, dynamic>> adminOverview() async => Map<String, dynamic>.from((await dio.get('admin/overview')).data as Map);
  Future<Map<String,dynamic>> adminMembers({String q=''}) async => Map<String,dynamic>.from((await dio.get('admin/members',queryParameters:{'q':q})).data as Map);
  Future<Map<String,dynamic>> adminMember(int id) async => Map<String,dynamic>.from((await dio.get('admin/members/$id')).data as Map);
  Future<void> setMemberBlocked(int id,bool blocked) async { await dio.post('admin/members/$id/status',data:{'blocked':blocked}); }
  Future<void> deleteMember(int id) async { await dio.delete('admin/members/$id'); }
  Future<Map<String,dynamic>> adminReviewQueue(String type) async => Map<String,dynamic>.from((await dio.get('admin/reviews/$type')).data as Map);
  Future<Map<String,dynamic>> reviewKyc({required int id,required String status,required String note}) async => Map<String,dynamic>.from((await dio.post('admin/reviews/kyc/$id',data:{'status':status,'note':note})).data as Map);
  Future<Map<String,dynamic>> reviewDeposit({required int id,required String decision,required String note,required bool confirmed}) async => Map<String,dynamic>.from((await dio.post('admin/reviews/deposits/$id',data:{'decision':decision,'note':note,'confirmed':confirmed})).data as Map);
  Future<Map<String,dynamic>> reviewWithdrawal({required int id,required String decision,required String note,required String paymentReference,required bool confirmed}) async => Map<String,dynamic>.from((await dio.post('admin/reviews/withdrawals/$id',data:{'decision':decision,'note':note,'paymentReference':paymentReference,'confirmed':confirmed})).data as Map);
  Future<Map<String,dynamic>> adminAuditEvents() async => Map<String,dynamic>.from((await dio.get('admin/audit-events')).data as Map);
  Future<Map<String,dynamic>> adminAnalytics() async => Map<String,dynamic>.from((await dio.get('admin/analytics')).data as Map);
  Future<Map<String,dynamic>> adminSecurity() async => Map<String,dynamic>.from((await dio.get('admin/security')).data as Map);

  Future<Map<String,dynamic>> adminAcademy() async => Map<String,dynamic>.from((await dio.get('admin/academy')).data as Map);
  Future<Map<String,dynamic>> createAcademyCategory({required String name,required String description,required int sortOrder}) async => Map<String,dynamic>.from((await dio.post('admin/academy/categories',data:{'name':name,'description':description,'sortOrder':sortOrder})).data as Map);
  Future<Map<String,dynamic>> toggleAcademyCategory(int id) async => Map<String,dynamic>.from((await dio.post('admin/academy/categories/$id/toggle')).data as Map);
  Future<Map<String,dynamic>> createAcademyLesson({required String title,required String description,required String content,required String videoUrl,required String accessLevel,required String status,required int sortOrder,int? categoryId}) async => Map<String,dynamic>.from((await dio.post('admin/academy/lessons',data:{'title':title,'description':description,'content':content,'videoUrl':videoUrl,'accessLevel':accessLevel,'status':status,'sortOrder':sortOrder,'categoryId':categoryId})).data as Map);
  Future<Map<String,dynamic>> placeAcademyLesson({required int id,int? categoryId,required int sortOrder}) async => Map<String,dynamic>.from((await dio.post('admin/academy/lessons/$id/placement',data:{'categoryId':categoryId,'sortOrder':sortOrder})).data as Map);
  Future<Map<String,dynamic>> setAcademyLessonStatus(int id,String status) async => Map<String,dynamic>.from((await dio.post('admin/academy/lessons/$id/status',data:{'status':status})).data as Map);
  Future<Map<String,dynamic>> grantAcademyAccess({required String memberUid,required String reason}) async => Map<String,dynamic>.from((await dio.post('admin/academy/access',data:{'memberUid':memberUid,'reason':reason})).data as Map);
  Future<Map<String,dynamic>> revokeAcademyAccess({required String memberUid}) async => Map<String,dynamic>.from((await dio.post('admin/academy/access/revoke',data:{'memberUid':memberUid})).data as Map);
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
  Future<void> deleteCommunityPost(int postId) async { await dio.delete('community/posts/$postId'); }
  Future<void> deleteCommunityComment(int postId,int commentId) async { await dio.delete('community/posts/$postId/comments/$commentId'); }
  Future<Map<String,dynamic>> communityPosts() async => Map<String,dynamic>.from((await dio.get('community/posts')).data as Map);
  Future<Map<String,dynamic>> createCommunityPost(String body) async => Map<String,dynamic>.from((await dio.post('community/posts',data:{'body':body,'type':'post'})).data as Map);
  Future<void> presenceHeartbeat() async { await dio.post('presence/heartbeat'); }
  Future<Map<String,dynamic>> presenceSettings() async => Map<String,dynamic>.from((await dio.get('presence/settings')).data as Map);
  Future<Map<String,dynamic>> savePresenceSettings(bool showStatus) async => Map<String,dynamic>.from((await dio.put('presence/settings',data:{'showStatus':showStatus})).data as Map);
  Future<Map<String,dynamic>> submitFeedback({required String category,required String title,required String description,PlatformFile? image}) async {
    final fields=<String,dynamic>{'category':category,'title':title,'description':description};
    if(image!=null){final bytes=image.bytes;if(bytes==null||bytes.isEmpty)throw Exception('The selected image could not be read.');if(bytes.length>5*1024*1024)throw Exception('Choose an image smaller than 5 MB.');final ext=(image.extension??'').toLowerCase();final mime=ext=='jpg'||ext=='jpeg'?'image/jpeg':ext=='png'?'image/png':ext=='webp'?'image/webp':'';if(mime.isEmpty)throw Exception('Choose a JPG, PNG or WebP image.');fields['image']=MultipartFile.fromBytes(bytes,filename:image.name,contentType:DioMediaType.parse(mime));}
    return Map<String,dynamic>.from((await dio.post('feedback',data:FormData.fromMap(fields))).data as Map);
  }
  Future<Map<String,dynamic>> feedbackList() async => Map<String,dynamic>.from((await dio.get('feedback')).data as Map);
  Future<Uint8List> communityImage(int id) async {final r=await dio.get<List<int>>('community/posts/$id/image',options:Options(responseType:ResponseType.bytes));return Uint8List.fromList(r.data??const <int>[]);}
  Future<Map<String,dynamic>> createCommunityPostWithImage(String body,PlatformFile? image) async {
    if(image==null)return createCommunityPost(body);final bytes=image.bytes;if(bytes==null||bytes.isEmpty)throw Exception('The selected image could not be read.');if(bytes.length>5*1024*1024)throw Exception('Choose an image smaller than 5 MB.');final ext=(image.extension??'').toLowerCase();final mime=ext=='jpg'||ext=='jpeg'?'image/jpeg':ext=='png'?'image/png':ext=='webp'?'image/webp':'';if(mime.isEmpty)throw Exception('Choose a JPG, PNG or WebP image.');
    return Map<String,dynamic>.from((await dio.post('community/posts/media',data:FormData.fromMap({'body':body,'type':'post','image':MultipartFile.fromBytes(bytes,filename:image.name,contentType:DioMediaType.parse(mime))}))).data as Map);
  }
  Future<Map<String,dynamic>> communityComments(int postId) async => Map<String,dynamic>.from((await dio.get('community/posts/$postId/comments')).data as Map);
  Future<Map<String,dynamic>> createCommunityComment(int postId,String body) async => Map<String,dynamic>.from((await dio.post('community/posts/$postId/comments',data:{'body':body})).data as Map);
  Future<Map<String,dynamic>> cooperativeStatus() async => Map<String,dynamic>.from((await dio.get('cooperative/status')).data as Map);
  Future<Map<String,dynamic>> submitCooperativeConnection({required String registeredName,required String registeredEmail}) async => Map<String,dynamic>.from((await dio.post('cooperative/connections',data:{'registeredName':registeredName,'registeredEmail':registeredEmail})).data as Map);
  Future<Map<String,dynamic>> socialLinks() async => Map<String,dynamic>.from((await dio.get('social-links')).data as Map);
  Future<Map<String,dynamic>> adminCooperativeConnections() async => Map<String,dynamic>.from((await dio.get('admin/cooperative/connections')).data as Map);
  Future<Map<String,dynamic>> reviewCooperativeConnection({required int id,required String decision,required String note}) async => Map<String,dynamic>.from((await dio.post('admin/cooperative/connections/$id/review',data:{'decision':decision,'note':note})).data as Map);
  Future<Map<String,dynamic>> adminSocialLinks() async => Map<String,dynamic>.from((await dio.get('admin/social-links')).data as Map);
  Future<Map<String,dynamic>> adminFeedback() async => Map<String,dynamic>.from((await dio.get('admin/feedback')).data as Map);
  Future<Map<String,dynamic>> reviewAdminFeedback({required int id,required String status,required String note}) async => Map<String,dynamic>.from((await dio.post('admin/feedback/$id/review',data:{'status':status,'note':note})).data as Map);
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

  Future<Map<String,dynamic>> sovereignDeskSection(String section) async =>
      Map<String,dynamic>.from((await dio.get('sovereign/$section')).data as Map);
  Future<Map<String,dynamic>> sovereignDeskCreate(String section,Map<String,dynamic> data) async =>
      Map<String,dynamic>.from((await dio.post('sovereign/$section',data:data)).data as Map);
  Future<Map<String,dynamic>> sovereignDeskUpdate(String path,Map<String,dynamic> data) async =>
      Map<String,dynamic>.from((await dio.post('sovereign/$path',data:data)).data as Map);

  Future<Map<String,dynamic>> telegramAdminChats() async =>
      Map<String,dynamic>.from((await dio.get('telegram/admin-chats')).data as Map);
  Future<Map<String,dynamic>> telegramAdminMembers(String chatId) async =>
      Map<String,dynamic>.from((await dio.get('telegram/admin-chat-members',queryParameters:{'chat_id':chatId})).data as Map);
  Future<Map<String,dynamic>> telegramAdminAssignment({required String chatId,required String operatorUserId,required String action}) async =>
      Map<String,dynamic>.from((await dio.post('telegram/admin-chat-assignment',data:{'chat_id':chatId,'operator_user_id':operatorUserId,'action':action})).data as Map);
  Future<Map<String,dynamic>> telegramAdminAction(Map<String,dynamic> data) async =>
      Map<String,dynamic>.from((await dio.post('telegram/admin-action',data:data)).data as Map);


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

class WalletTransferPage extends StatefulWidget {
  const WalletTransferPage({super.key, required this.api, required this.dark, required this.onDone});
  final MonarchApi api;
  final bool dark;
  final VoidCallback onDone;
  @override State<WalletTransferPage> createState() => _WalletTransferPageState();
}

class _WalletTransferPageState extends State<WalletTransferPage> {
  final uidController = TextEditingController();
  final amountController = TextEditingController();
  Map<String,dynamic>? recipient;
  Map<String,dynamic>? balances;
  String currency = 'NGN';
  String? error, success, pendingKey;
  bool busy = false, looking = false;

  @override void initState() { super.initState(); refreshBalances(); }
  @override void dispose() { uidController.dispose(); amountController.dispose(); super.dispose(); }

  String newKey() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2,'0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }

  String messageFrom(Object e) {
    if (e is DioException && e.response?.data is Map) {
      final value = (e.response!.data as Map)['message'];
      if (value != null) return value.toString();
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> refreshBalances() async {
    try {
      final value = await widget.api.walletBalances();
      if (mounted) setState(() => balances = value);
    } catch (_) { if (mounted) setState(() => balances = null); }
  }

  Future<void> lookupRecipient() async {
    final uid = uidController.text.trim().toUpperCase();
    uidController.value = uidController.value.copyWith(text: uid, selection: TextSelection.collapsed(offset: uid.length));
    if (!RegExp(r'^MONARCH\d{6}$').hasMatch(uid)) {
      setState(() { recipient = null; error = 'Enter a valid UID, for example MONARCH123456.'; success = null; });
      return;
    }
    setState(() { looking = true; error = null; success = null; recipient = null; });
    try {
      final value = await widget.api.walletRecipient(uid);
      if (mounted) setState(() { recipient = value; looking = false; });
    } catch (e) {
      if (mounted) setState(() { looking = false; error = messageFrom(e); recipient = null; });
    }
  }

  Future<void> sendTransfer() async {
    if (busy) return;
    final uid = uidController.text.trim().toUpperCase();
    if (recipient == null || (recipient!['uid'] ?? '').toString().toUpperCase() != uid) {
      await lookupRecipient();
      if (!mounted || recipient == null) return;
    }
    final amount = amountController.text.trim();
    final value = double.tryParse(amount);
    if (!RegExp(r'^(?:0|[1-9]\d{0,11})(?:\.\d{1,8})?$').hasMatch(amount) || value == null || !value.isFinite || value <= 0) {
      setState(() { error = 'Enter a valid amount greater than zero.'; success = null; });
      return;
    }
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Confirm wallet transfer'),
      content: Text('Send $currency ${value.toStringAsFixed(2)} to ${recipient!['name']} (${recipient!['uid']})? Transfers may not be reversible after completion.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm transfer')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = null; success = null; pendingKey ??= newKey(); });
    try {
      final result = await widget.api.transferWallet(recipientUid: uid, currency: currency, amount: amount, idempotencyKey: pendingKey!);
      if (!mounted) return;
      setState(() { success = '${result['message'] ?? 'Transfer completed.'} Reference: ${result['reference'] ?? ''}'; pendingKey = null; amountController.clear(); });
      await refreshBalances();
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() { error = messageFrom(e); });
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override Widget build(BuildContext context) {
    final dark = widget.dark;
    final textColor = dark ? Colors.white : const Color(0xFF191919);
    final cardColor = dark ? panel : Colors.white;
    final borderColor = dark ? const Color(0xFF3C3423) : const Color(0xFFE8D9A9);
    final ngn = double.tryParse((balances?['ngn'] ?? '0').toString()) ?? 0;
    final usd = double.tryParse((balances?['usd'] ?? '0').toString()) ?? 0;
    InputDecoration decoration(String label, String hint) => InputDecoration(labelText: label, hintText: hint, filled: true, fillColor: dark ? const Color(0xFF101012) : const Color(0xFFFAF8F1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: gold, width: 1.5)));
    return ListView(padding: const EdgeInsets.all(15), children: [
      const Text('Send funds to another Monarch', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      const Text('Transfer wallet funds using a member’s Monarch UID. The recipient and amount are verified before the transfer is submitted.', style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Card(color: cardColor, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('NGN available', style: TextStyle(color: muted, fontSize: 11)), const SizedBox(height: 7), Text('₦${ngn.toStringAsFixed(2)}', style: TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.w900))])))),
        const SizedBox(width: 9),
        Expanded(child: Card(color: cardColor, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('USD available', style: TextStyle(color: muted, fontSize: 11)), const SizedBox(height: 7), Text(r'$' + usd.toStringAsFixed(2), style: TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.w900))])))),
      ]),
      Card(color: cardColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: borderColor)), child: Padding(padding: const EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: uidController, textCapitalization: TextCapitalization.characters, textInputAction: TextInputAction.done, onSubmitted: (_) => lookupRecipient(), decoration: decoration('Recipient Monarch UID', 'MONARCH123456')),
        const SizedBox(height: 8),
        if (looking) const LinearProgressIndicator(color: gold, minHeight: 2),
        if (recipient != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [const Icon(Icons.verified_user_outlined, color: Colors.green), const SizedBox(width: 8), Expanded(child: Text('${recipient!['name']} · ${recipient!['uid']}', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)))])),
        OutlinedButton.icon(onPressed: looking ? null : lookupRecipient, icon: const Icon(Icons.person_search_outlined), label: const Text('Verify recipient')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: currency, decoration: decoration('Wallet currency', 'Choose currency'), items: const [DropdownMenuItem(value: 'NGN', child: Text('Nigerian naira (NGN)')), DropdownMenuItem(value: 'USD', child: Text('US dollars (USD)'))], onChanged: busy ? null : (v) => setState(() => currency = v ?? 'NGN')),
        const SizedBox(height: 12),
        TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: decoration('Amount to send', '0.00')),
        const SizedBox(height: 14),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: const TextStyle(color: Color(0xFFFF8F80), fontSize: 12))),
        if (success != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(success!, style: const TextStyle(color: Color(0xFF38B878), fontSize: 12))),
        FilledButton.icon(onPressed: busy ? null : sendTransfer, icon: busy ? const SizedBox(width: 17,height: 17,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.swap_horiz_rounded), label: Text(busy ? 'Processing securely…' : 'Confirm and send'), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 14))),
        const SizedBox(height: 8),
        Text('Transfers must use the same currency on both wallets. Check the UID carefully and never share your password or one-time code.', style: TextStyle(color: muted, fontSize: 11, height: 1.45)),
      ]))),
    ]);
  }
}

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
  bool purchasing=false;
  @override void initState() { super.initState(); future = widget.api.investments(); }
  void reload() => setState(() => future = widget.api.investments());
  String money(dynamic currency, dynamic amount) {
    final value = double.tryParse((amount ?? '0').toString()) ?? 0;
    return '${currency ?? ''} ${value.toStringAsFixed(2)}';
  }
  String idempotencyKey(){
    final random=math.Random.secure();
    final bytes=List<int>.generate(16,(_)=>random.nextInt(256));
    bytes[6]=(bytes[6]&0x0f)|0x40;
    bytes[8]=(bytes[8]&0x3f)|0x80;
    final hex=bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }
  Future<void> buy(Map<String,dynamic> p) async {
    if(purchasing)return;
    final price=double.tryParse((p['price']??'0').toString())??0;
    final currency=(p['currency']??'').toString();
    final id=(p['id'] as num?)?.toInt();
    if(id==null||id<=0){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('This investment package is unavailable. Refresh and try again.')));
      return;
    }
    // One tap sends a single idempotent purchase request. The server is the
    // authority for package price, fees, KYC, wallet balance and activation.
    setState(()=>purchasing=true);
    try{
      final result=await widget.api.purchaseInvestment(packageId:id,idempotencyKey:idempotencyKey());
      if(!mounted)return;
      final investment=result['investment'] is Map?Map<String,dynamic>.from(result['investment'] as Map):<String,dynamic>{};
      final total=(investment['totalCharged']??price).toString();
      final message=(result['message']??'Investment purchase recorded successfully.').toString();
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Row(children:[Icon(Icons.check_circle,color:gold,size:28),SizedBox(width:8),Expanded(child:Text('Investment successful'))]),
        content:SingleChildScrollView(child:Text('$message\n\nReference: ${investment['reference']??'—'}\nPackage: ${investment['packageName']??p['name']??'—'}\nAmount charged: ${money(investment['currency']??currency,total)}\nStatus: ${(investment['status']??'active').toString().toUpperCase()}')),
        actions:[FilledButton(onPressed:()=>Navigator.pop(ctx),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('DONE'))],
      ));
      reload();
    }catch(e){
      if(!mounted)return;
      var message='Purchase could not be completed. The server did not confirm a successful transaction.';
      if(e is DioException){final data=e.response?.data;if(data is Map&&data['message']!=null)message=data['message'].toString();}
      else message=e.toString().replaceFirst('Exception: ','');
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Row(children:[Icon(Icons.error_outline,color:Colors.redAccent,size:26),SizedBox(width:8),Expanded(child:Text('Purchase not completed'))]),
        content:Text(message),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('OK'))],
      ));
    }finally{if(mounted)setState(()=>purchasing=false);}
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
        const Text('Review active packages and purchase securely inside the app. Availability, fees, KYC and wallet balances are verified by the database-backed API.', style: TextStyle(color: muted)),
        const SizedBox(height: 12),
        if (packages.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No active investment packages are available right now.', textAlign: TextAlign.center))),
        ...packages.map((p) {
          final terms = (p['terms'] ?? '').toString().trim();
          final description = (p['description'] ?? '').toString().trim();
          final price=double.tryParse((p['price']??'0').toString())??0;
          final fee=price*0.01;
          return Card(color: widget.dark ? panel : Colors.white, child: ExpansionTile(
            leading: const Icon(Icons.workspace_premium, color: gold),
            title: Text((p['name'] ?? 'Investment package').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(money(p['currency'], p['price']) + ' · ' + ((p['durationDays'] == null || p['durationDays'].toString().isEmpty) ? 'Flexible duration' : '${p['durationDays']} days'), style: const TextStyle(color: gold, fontWeight: FontWeight.w800))),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (description.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text(description)),
              if (terms.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: Text('Terms: ' + terms, style: const TextStyle(color: muted)))),
              const SizedBox(height: 8),
              Text('Service fee (1%): '+money(p['currency'],fee),style:const TextStyle(color:muted,fontSize:12)),
              Text('Total wallet debit before currency conversion: '+money(p['currency'],price+fee),style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: purchasing ? null : () => buy(p),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(purchasing?'PROCESSING…':'BUY IN APP'),
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink, minimumSize: const Size.fromHeight(48)),
              )),
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


class AcademyPage extends StatefulWidget {
  const AcademyPage({super.key, required this.api, required this.dark});
  final MonarchApi api;
  final bool dark;
  @override State<AcademyPage> createState() => _AcademyPageState();
}
class _AcademyPageState extends State<AcademyPage> {
  late Future<Map<String,dynamic>> future;
  final Set<int> opened = <int>{};
  final Set<int> busy = <int>{};
  String? message;
  bool success = true;
  @override void initState(){super.initState();future=widget.api.academy();}
  void reload(){setState(()=>future=widget.api.academy());}
  String academyKey(){final r=math.Random.secure();final b=List<int>.generate(16,(_)=>r.nextInt(256));b[6]=(b[6]&0x0f)|0x40;b[8]=(b[8]&0x3f)|0x80;final h=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();return h.substring(0,8)+'-'+h.substring(8,12)+'-'+h.substring(12,16)+'-'+h.substring(16,20)+'-'+h.substring(20);}

  Future<void> act(int id,Future<Map<String,dynamic>> Function() action,{bool watch=false,bool complete=false})async{
    if(busy.contains(id))return;setState(()=>busy.add(id));
    try{final r=await action();if(watch){final u=Uri.tryParse((r['videoUrl']??'').toString());if(u==null||!u.hasScheme)throw Exception('Video link unavailable');await launchUrl(u,mode:LaunchMode.externalApplication);opened.add(id);}if(complete)opened.remove(id);
      if(mounted){setState(() { message=(r['message']??(complete?'Lesson completed.':watch?'Video opened.':'Payment successful.')).toString(); success=true; });reload();}
    }catch(e){if(mounted)setState(() { message=e.toString(); success=false; });}finally{if(mounted)setState(()=>busy.remove(id));}
  }
  List<Widget> _academyLessonWidgets(List<Map<String,dynamic>> lessons) {
    final widgets=<Widget>[];
    String? previousCategory;
    for(final l in lessons){
      final category=(l['categoryName']??'Unassigned').toString().trim().isEmpty?'Unassigned':(l['categoryName']??'Unassigned').toString();
      if(category!=previousCategory){
        widgets.add(Padding(
          padding: EdgeInsets.only(top:widgets.isEmpty?18:22,bottom:2),
          child:Row(children:[
            Container(width:4,height:24,decoration:BoxDecoration(color:gold,borderRadius:BorderRadius.circular(4))),
            const SizedBox(width:9),
            Expanded(child:Text(category.toUpperCase(),style:const TextStyle(color:gold,fontSize:13,fontWeight:FontWeight.w900,letterSpacing:1.1))),
          ]),
        ));
        previousCategory=category;
      }
      final id=(l['id'] as num).toInt();
      final done=l['completed']==true,can=l['canOpen']==true,fee=l['requiresReplayFee']==true,ready=l['replayReady']==true,wait=busy.contains(id);
      widgets.add(Container(margin:const EdgeInsets.only(top:10),padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:widget.dark?panel:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:widget.dark?const Color(0xFF393326):const Color(0xFFE0D7BC))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Container(width:36,height:36,alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xFF30250C),borderRadius:BorderRadius.circular(10)),child:Text((l['order']??'').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w900))),const SizedBox(width:10),Expanded(child:Text((l['title']??'Lesson').toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16))),if(done)const Icon(Icons.check_circle,color:Color(0xFF4CAF80))]),
        if((l['categoryName']??'').toString().isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Align(alignment:Alignment.centerLeft,child:Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:const Color(0xFF30250C),borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFF6D5920))),child:Text(l['categoryName'].toString(),style:const TextStyle(color:gold,fontSize:11,fontWeight:FontWeight.w800))))),
        if((l['description']??'').toString().isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(l['description'].toString(),style:const TextStyle(color:muted))),
        const SizedBox(height:8),Text(done?(fee?'Previous video · \$2 replay fee':ready?'Replay paid · ready to open':'Lesson completed'):can?'Current lesson':'Finish the current lesson in this category first',style:const TextStyle(color:gold,fontWeight:FontWeight.w800,fontSize:12)),
        const SizedBox(height:9),Wrap(spacing:8,runSpacing:8,children:[
          if(can&&done&&fee)FilledButton(onPressed:wait?null:()=>act(id,()=>widget.api.replayAcademyLesson(lessonId:id,idempotencyKey:academyKey())),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:Text(wait?'Processing…':'Pay \$2 to replay')),
          if(can&&(!done||ready))OutlinedButton.icon(onPressed:wait?null:()=>act(id,()=>widget.api.watchAcademyLesson(id),watch:true),icon:const Icon(Icons.play_arrow),label:Text(wait?'Opening…':'Watch video')),
          if(can&&!done&&opened.contains(id))FilledButton(onPressed:wait?null:()=>act(id,()=>widget.api.completeAcademyLesson(id),complete:true),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Mark video finished'))
        ])
      ])));
    }
    return widgets;
  }

  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snap){
    if(snap.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator(color:gold));
    if(snap.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Monarch Codex Academy',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),Message(text:'Academy could not load. Check your connection and retry.',success:false),FilledButton(onPressed:reload,child:const Text('Retry'))]);
    final d=snap.data??<String,dynamic>{};final full=d['fullAccess']==true;final lessons=(d['lessons'] as List? ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return RefreshIndicator(color:gold,onRefresh:()async{reload();},child:ListView(padding:const EdgeInsets.all(15),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),border:Border.all(color:const Color(0xFF6D5920)),gradient:const LinearGradient(colors:[Color(0xFF30250C),Color(0xFF151411),Color(0xFF101012)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('MONARCH CODEX ACADEMY',style:TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:11,letterSpacing:1.2)),const SizedBox(height:10),
        const Text('Learn. Practice. Build your kingdom.',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:Colors.white)),const SizedBox(height:8),
        const Text('Finish the current video before moving forward. Every replay of a completed video costs \$2.',style:TextStyle(color:Colors.white70,height:1.5)),const SizedBox(height:12),
        Text(full?'FULL ACADEMY ACCESS ACTIVE':'FULL ACADEMY ACCESS · \$10',style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),
        if(!full)Padding(padding:const EdgeInsets.only(top:10),child:FilledButton(onPressed:busy.contains(-1)?null:()=>act(-1,()=>widget.api.purchaseAcademyAccess()),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:Text(busy.contains(-1)?'Processing…':'Unlock full Academy · \$10')))
      ])),
      if(message!=null)Padding(padding:const EdgeInsets.only(top:10),child:Message(text:message!,success:success)),
      if(lessons.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('Lessons are being prepared.',style:TextStyle(color:muted))),
      ..._academyLessonWidgets(lessons)
    ]));
  });
}

class SovereignRequestPage extends StatefulWidget {
  const SovereignRequestPage({super.key, required this.api, required this.dark, required this.uid, required this.initialType});
  final MonarchApi api;
  final bool dark;
  final String uid;
  final String initialType;
  @override State<SovereignRequestPage> createState() => _SovereignRequestPageState();
}

class _SovereignRequestPageState extends State<SovereignRequestPage> {
  late String kind;
  final details = TextEditingController();
  bool sending = false;

  @override void initState() { super.initState(); kind = widget.initialType; }
  @override void dispose() { details.dispose(); super.dispose(); }

  Future<void> sendRequest() async {
    if (sending) return;
    setState(() => sending = true);
    final isFree = kind == 'Free Signals';
    final subject = isFree ? 'Free Signals Access Request' : 'Sovereign Desk Services Request';
    final body = 'Monarch Codex UID: ${widget.uid.isEmpty ? 'Not available' : widget.uid}\nRequest type: $kind\n\nMember message:\n${details.text.trim().isEmpty ? 'Please advise me on eligibility and next steps.' : details.text.trim()}\n\nPlease confirm eligibility, any applicable access requirements, and the request status.';
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@monarchcodex.online',
      queryParameters: {'subject': 'Monarch Codex — $subject', 'body': body},
    );
    try {
      final opened = await launchUrl(uri);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(opened ? 'Your email app is opening. Send the message there to submit your request.' : 'Could not open an email app. Please contact support@monarchcodex.online.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open an email app. Please contact support@monarchcodex.online.')));
    } finally { if (mounted) setState(() => sending = false); }
  }

  @override Widget build(BuildContext context) {
    if (widget.initialType == 'Sovereign Desk') return _buildHub();
    if (widget.initialType == 'Signal Access' || widget.initialType == 'Watchlist' || widget.initialType == 'Trading Guidance') return _buildNativeDataScreen();
    if (widget.initialType == 'Free Signal Slots & Countdown') return _buildSlotsScreen();
    if (widget.initialType == 'Premium Access') return _buildPremiumScreen();
    if (widget.initialType == 'Chat with Sovereign Desk Admin') return _buildChatScreen();
    if (widget.initialType == 'Other Services') return _buildOtherServicesScreen();
    return _buildRequestForm();
  }
  Widget _nativeHero(String title,String subtitle,IconData icon)=>Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:widget.dark?panel:Colors.white,borderRadius:BorderRadius.circular(22),border:Border.all(color:gold.withValues(alpha:.5))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:gold.withValues(alpha:.15),borderRadius:BorderRadius.circular(15)),child:Icon(icon,color:gold,size:30)),const SizedBox(height:15),Text(title,style:const TextStyle(color:gold,fontSize:22,fontWeight:FontWeight.w900,letterSpacing:.5)),const SizedBox(height:7),Text(subtitle,style:const TextStyle(color:muted,fontSize:13,height:1.5)),const SizedBox(height:12),Text('MONARCH UID: '+(widget.uid.isEmpty?'Unavailable':widget.uid),style:const TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:11))]));
  Widget _nativeCard(String title,String body,IconData icon)=>Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:widget.dark?panel:Colors.white,borderRadius:BorderRadius.circular(17),border:Border.all(color:gold.withValues(alpha:.23))),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:gold,size:25),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:14)),const SizedBox(height:5),Text(body,style:const TextStyle(color:muted,fontSize:12,height:1.45))]))]));
  Future<Map<String,dynamic>> _loadNativeSection(String section)=>api.sovereignDeskSection(section);
  Widget _buildNativeDataScreen(){
    final title=widget.initialType=='Watchlist'?'YOUR WATCHLIST':widget.initialType=='Trading Guidance'?'TRADING GUIDANCE':'TRADING SIGNALS';
    final icon=widget.initialType=='Watchlist'?Icons.visibility_outlined:widget.initialType=='Trading Guidance'?Icons.school_outlined:Icons.candlestick_chart_rounded;
    final section=widget.initialType=='Watchlist'?'watchlist':widget.initialType=='Trading Guidance'?'guidance':'signals';
    return FutureBuilder<Map<String,dynamic>>(future:_loadNativeSection(section),builder:(context,s){
      final raw=s.data?['items']??s.data?['signals']??s.data?['lessons']??s.data?['records'];final items=raw is List?raw.whereType<Map>().toList():const [];
      return ListView(padding:const EdgeInsets.all(15),children:[
        _nativeHero(title,widget.initialType=='Watchlist'?'Review instruments and notes provided by the desk.':widget.initialType=='Trading Guidance'?'Learning notes and guidance published by the team.':'Published signal details delivered from the service API.',icon),
        const SizedBox(height:18),Row(children:[const Expanded(child:Text('LATEST UPDATES',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1,fontSize:12))),IconButton(onPressed:()=>setState((){}),icon:const Icon(Icons.refresh_rounded,color:gold))]),
        if(s.connectionState==ConnectionState.waiting)const Padding(padding:EdgeInsets.all(25),child:Center(child:CircularProgressIndicator(color:gold))),
        if(s.hasError)_nativeCard('Could not load live data','Check your connection and tap refresh. The screen is native; data is requested through the service API.',Icons.cloud_off_outlined),
        if(s.connectionState==ConnectionState.done&&!s.hasError&&items.isEmpty)_nativeCard('Nothing available yet','The service returned no published items. No sample signals or fake prices are shown.',Icons.inbox_outlined),
        ...items.map((item){final x=Map<String,dynamic>.from(item);final heading=(x['title']??x['asset_pair']??x['instrument']??x['symbol']??x['name']??'Desk update').toString();final status=(x['direction']??x['status']??x['type']??'Update').toString();final body=(x['explanation']??x['notes']??x['description']??'Details supplied by the service.').toString();return _nativeCard(heading,status+'\\n'+body,icon);}),
        const Text('Trading involves risk. Signals and guidance do not guarantee profits.',style:TextStyle(color:muted,fontSize:11,height:1.5))
      ]);
    });
  }
  Widget _buildSlotsScreen()=>ListView(padding:const EdgeInsets.all(15),children:[_nativeHero('FREE SIGNAL SLOTS','Availability is shown only when confirmed by the server.',Icons.timer_outlined),const SizedBox(height:18),FutureBuilder<Map<String,dynamic>>(future:_loadNativeSection('access'),builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator(color:gold));if(s.hasError)return _nativeCard('Availability unavailable','Could not retrieve current availability. Check your connection.',Icons.cloud_off_outlined);final d=s.data??{};return _nativeCard('Server-reported availability',(d['slots_remaining']??d['remaining_slots']??d['message']??'No confirmed slot count or countdown was returned.').toString(),Icons.hourglass_empty_rounded);}),_nativeCard('No invented countdowns','This screen will not guess remaining places, deadlines or eligibility.',Icons.verified_user_outlined),FilledButton.icon(onPressed:()=>setState((){}),icon:const Icon(Icons.refresh_rounded),label:const Text('Refresh availability'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink))]);
  Widget _buildPremiumScreen()=>ListView(padding:const EdgeInsets.all(15),children:[_nativeHero('PREMIUM SIGNALS','Premium access details and approval guidance.',Icons.workspace_premium_outlined),const SizedBox(height:18),_nativeCard('Confirm current pricing','No subscription price is invented here. Ask the team to confirm official plans and eligibility before paying.',Icons.receipt_long_outlined),_nativeCard('Risk reminder','Signals do not guarantee profits. Use official access instructions.',Icons.shield_outlined),_buildRequestForm()]);
  Widget _buildChatScreen()=>ListView(padding:const EdgeInsets.all(15),children:[_nativeHero('SOVEREIGN DESK SUPPORT','A dedicated native support composer for your question.',Icons.forum_outlined),const SizedBox(height:18),_nativeCard('Member support','Your UID is included in the support handoff. The current app does not have a verified member-chat endpoint, so it will not pretend messages were delivered in-app.',Icons.support_agent_rounded),_buildRequestForm()]);
  Widget _buildOtherServicesScreen()=>ListView(padding:const EdgeInsets.all(15),children:[_nativeHero('OTHER SERVICES','Request mentorship, learning support or information about other Sovereign Desk services.',Icons.grid_view_rounded),const SizedBox(height:18),_nativeCard('Mentorship','Ask about learning support and current availability.',Icons.school_outlined),_nativeCard('Trading guidance','Ask about trading concepts and risk management.',Icons.lightbulb_outline_rounded),_nativeCard('Access and eligibility','Request official approval steps and applicable fees.',Icons.verified_user_outlined),_buildRequestForm()]);

  Widget _buildHub() {
    final dark = widget.dark;
    Widget shortcut(String title, String subtitle, IconData icon, VoidCallback onTap) => Card(
      color: dark ? panel : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: BorderSide(color: gold.withValues(alpha: .25))),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: gold.withValues(alpha: .13), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: gold, size: 25)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: muted, fontSize: 11, height: 1.35)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: gold),
          ]),
        ),
      ),
    );
    void openRequest(String type) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SovereignNativeSectionPage(type: type, dark: dark, uid: widget.uid)));
    return ListView(padding: const EdgeInsets.all(15), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: dark ? panel : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: gold.withValues(alpha: .55))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: gold.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.support_agent_rounded, color: gold, size: 29)),
          const SizedBox(height: 15),
          const Text('SOVEREIGN DESK', style: TextStyle(color: gold, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: .5)),
          const SizedBox(height: 8),
          const Text('Your home for trading signals, access, market tools and support.', style: TextStyle(color: muted, height: 1.5)),
          const SizedBox(height: 15),
          const Text('YOUR MONARCH UID', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 4),
          SelectableText(widget.uid.isEmpty ? 'UID unavailable' : widget.uid, style: const TextStyle(color: gold, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 18),
      const Text('QUICK ACCESS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 11)),
      const SizedBox(height: 8),
      shortcut('Trading Signals', 'Browse signals and their entry, stop-loss and target details.', Icons.candlestick_chart_rounded, () => openRequest('Signal Access')),
      shortcut('Free Signals', 'Request free access and check eligibility with the team.', Icons.campaign_outlined, () => openRequest('Free Signals')),
      shortcut('Premium Signals', 'Ask about paid access and current subscription options.', Icons.workspace_premium_outlined, () => openRequest('Premium Access')),
      shortcut('Free Signal Slots & Countdown', 'Check eligibility and confirm current availability.', Icons.timer_outlined, () => openRequest('Free Signal Slots')),
      shortcut('Chat with Sovereign Desk Admin', 'Open the dedicated native support screen.', Icons.forum_outlined, () => openRequest('Admin Chat')),
      shortcut('Watchlist', 'Review instruments and notes from the desk.', Icons.visibility_outlined, () => openRequest('Watchlist')),
      shortcut('Trading Guidance & Academy', 'Continue learning through available tutorials and guidance.', Icons.school_outlined, () => openRequest('Trading Guidance')),
      shortcut('Other Sovereign Desk Services', 'Ask about mentorship and other available services.', Icons.grid_view_rounded, () => openRequest('Other Services')),
      const SizedBox(height: 8),
      const Text('Trading involves risk. Signals and guidance do not guarantee profits. Paid access and availability must be confirmed by the team.', style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
    ]);
  }

  Widget _buildRequestForm() {
    final dark = widget.dark;
    final isFree = kind == 'Free Signals';
    final title = isFree ? 'FREE SIGNALS' : 'SOVEREIGN DESK';
    final description = isFree
      ? 'Request a review for free signals access. Eligibility and any referral reward must be confirmed by the team before access is granted.'
      : 'Request Sovereign Desk services, signal access, mentorship, or trading guidance. Any paid access or approval requirements will be confirmed by the team.';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: dark ? panel : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: gold.withValues(alpha:.55))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: gold.withValues(alpha:.15), borderRadius: BorderRadius.circular(14)), child: Icon(isFree ? Icons.campaign_outlined : Icons.support_agent_rounded, color: gold, size: 28)),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(color: gold, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: .5)),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(fontSize: 13, height: 1.5, color: muted)),
        const SizedBox(height: 14),
        Text('YOUR MONARCH UID', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900, color: dark ? muted : Colors.black54)),
        const SizedBox(height: 4),
        SelectableText(widget.uid.isEmpty ? 'UID will be included if available' : widget.uid, style: const TextStyle(color: gold, fontWeight: FontWeight.w900)),
      ])),
      const SizedBox(height: 18),
      const Text('CHOOSE A REQUEST', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _requestChoice('Free Signals', Icons.campaign_outlined, dark)),
        const SizedBox(width: 10),
        Expanded(child: _requestChoice('Sovereign Desk', Icons.support_agent_rounded, dark)),
      ]),
      const SizedBox(height: 18),
      const Text('MESSAGE TO THE TEAM (OPTIONAL)', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      TextField(controller: details, maxLines: 4, maxLength: 1000, decoration: InputDecoration(hintText: 'Tell us what access or service you are requesting…', filled: true, fillColor: dark ? panel : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: gold.withValues(alpha:.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: gold.withValues(alpha:.25))))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: sending ? null : sendRequest, icon: const Icon(Icons.send_rounded), label: Text(sending ? 'Opening…' : 'Send request to the team'), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 15)))),
      const SizedBox(height: 12),
      const Text('Submitting a request does not guarantee approval or profits. Trading involves risk. Your email app must send the message for the request to reach support.', style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
    ]);
  }

  Widget _requestChoice(String value, IconData icon, bool dark) {
    final selected = kind == value;
    return InkWell(onTap: () => setState(() => kind = value), borderRadius: BorderRadius.circular(14), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: selected ? gold.withValues(alpha:.14) : (dark ? panel : Colors.white), borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? gold : (dark ? Colors.white12 : Colors.black12))), child: Column(children: [
      Icon(icon, color: selected ? gold : muted, size: 24),
      const SizedBox(height: 7),
      Text(value, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: selected ? gold : (dark ? Colors.white : ink))),
    ])));
  }
}


class SovereignNativeSectionPage extends StatefulWidget {
  const SovereignNativeSectionPage({super.key, required this.type, required this.dark, required this.uid});
  final String type; final bool dark; final String uid;
  @override State<SovereignNativeSectionPage> createState()=>_SovereignNativeSectionPageState();
}
class _SovereignNativeSectionPageState extends State<SovereignNativeSectionPage> {
  final message=TextEditingController();
  final saved=<String>['BTC/USD','EUR/USD','XAU/USD'];
  String? status; bool busy=false;
  @override void dispose(){message.dispose();super.dispose();}
  IconData get icon {switch(widget.type){case 'Signal Access':return Icons.candlestick_chart_rounded;case 'Free Signals':return Icons.campaign_rounded;case 'Premium Access':return Icons.workspace_premium_rounded;case 'Free Signal Slots':return Icons.timer_rounded;case 'Admin Chat':return Icons.forum_rounded;case 'Watchlist':return Icons.visibility_rounded;case 'Trading Guidance':return Icons.school_rounded;default:return Icons.grid_view_rounded;}}
  String get title {switch(widget.type){case 'Signal Access':return 'TRADING SIGNALS';case 'Free Signals':return 'FREE SIGNALS';case 'Premium Access':return 'PREMIUM SIGNALS';case 'Free Signal Slots':return 'FREE SIGNAL SLOTS';case 'Admin Chat':return 'SOVEREIGN DESK CHAT';case 'Watchlist':return 'YOUR WATCHLIST';case 'Trading Guidance':return 'TRADING GUIDANCE';default:return 'MORE SERVICES';}}
  String get description {switch(widget.type){case 'Signal Access':return 'Live signal records are not displayed unless a verified feed is available. No entries or targets are fabricated.';case 'Free Signals':return 'Request a review for free signal access. Eligibility and request status must be confirmed by the team.';case 'Premium Access':return 'Ask about current premium access. No price or performance promise is assumed.';case 'Free Signal Slots':return 'Current slot counts and countdowns require verified live data; this screen will not invent availability.';case 'Admin Chat':return 'Send a message to the Sovereign Desk team with your Monarch UID.';case 'Watchlist':return 'Manage instruments you want to follow. This native list is session-only until persistent storage is added.';case 'Trading Guidance':return 'Learn risk management, position sizing, market structure and trading psychology.';default:return 'Choose a service and contact the team for current availability and eligibility.';}}
  Future<void> contact() async {if(busy)return;setState(()=>busy=true);final uri=Uri(scheme:'mailto',path:'support@monarchcodex.online',queryParameters:{'subject':'Monarch Codex — '+title,'body':'Monarch UID: '+(widget.uid.isEmpty?'Unavailable':widget.uid)+'\\nSection: '+widget.type+'\\n\\n'+message.text.trim()});try{final ok=await launchUrl(uri);if(mounted)setState(()=>status=ok?'Email app opened. Send the message there to contact the team.':'No email app available. Contact support@monarchcodex.online.');}catch(_){if(mounted)setState(()=>status='No email app available. Contact support@monarchcodex.online.');}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context){final dark=widget.dark;final card=dark?panel:Colors.white;final fg=dark?Colors.white:ink;return ListView(padding:const EdgeInsets.all(16),children:[
    Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(23),border:Border.all(color:gold.withValues(alpha:.65)),gradient:LinearGradient(colors:dark?const [Color(0xFF30250C),Color(0xFF151518),Color(0xFF09090B)]:const [Color(0xFFFFF4CC),Colors.white,Color(0xFFF4EFE0)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(width:54,height:54,decoration:BoxDecoration(color:gold.withValues(alpha:.17),borderRadius:BorderRadius.circular(15)),child:Icon(icon,color:gold,size:30)),const SizedBox(height:15),Text(title,style:const TextStyle(color:gold,fontSize:22,fontWeight:FontWeight.w900,letterSpacing:.5)),const SizedBox(height:8),Text(description,style:TextStyle(color:dark?Colors.white70:Colors.black54,height:1.5,fontSize:13)),const SizedBox(height:14),Text('MONARCH UID  •  '+(widget.uid.isEmpty?'Unavailable':widget.uid),style:const TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:11))])),
    const SizedBox(height:16),
    if(widget.type=='Signal Access') _info(card,fg,Icons.cloud_off_rounded,'LIVE FEED STATUS','No live signal data is shown here yet. This avoids displaying invented trading instructions.'),
    if(widget.type=='Free Signal Slots') _info(card,fg,Icons.verified_user_outlined,'ELIGIBILITY','Ask the team to confirm your eligibility and current slot availability.'),
    if(widget.type=='Premium Access') _info(card,fg,Icons.lock_outline_rounded,'ACCESS STATUS','Any applicable price and approval requirements must be confirmed by the Sovereign Desk.'),
    if(widget.type=='Trading Guidance') ...[_info(card,fg,Icons.shield_outlined,'MANAGE RISK','Set your maximum loss before entering a trade. Never treat signals as guaranteed outcomes.'),_info(card,fg,Icons.school_outlined,'ACADEMY','Open Academy from the main app navigation for lessons available to your account.')],
    if (widget.type == 'Watchlist') ...[
      Text('SAVED INSTRUMENTS', style: TextStyle(color: fg, fontWeight: FontWeight.w900, letterSpacing: 1)),
      const SizedBox(height: 8),
      ...saved.map((symbol) => Card(
        color: card,
        child: ListTile(
          leading: const Icon(Icons.show_chart, color: gold),
          title: Text(symbol, style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
          subtitle: const Text('Price feed not connected on this screen', style: TextStyle(color: muted, fontSize: 11)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => setState(() { saved.remove(symbol); }),
          ),
        ),
      )),
      OutlinedButton.icon(
        onPressed: () async {
          final controller = TextEditingController();
          final value = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Add instrument'),
              content: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'e.g. GBP/USD'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim().toUpperCase()), child: const Text('Add')),
              ],
            ),
          );
          if (value != null && value.isNotEmpty && !saved.contains(value)) {
            setState(() => saved.add(value));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add instrument'),
      ),
    ],
    if(widget.type!='Watchlist') ...[const SizedBox(height:8),Text('MESSAGE THE TEAM',style:TextStyle(color:fg,fontWeight:FontWeight.w900,letterSpacing:1)),const SizedBox(height:8),TextField(controller:message,maxLines:3,maxLength:1000,decoration:InputDecoration(hintText:'Add details (optional)',filled:true,fillColor:card,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)))),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy?null:contact,icon:const Icon(Icons.support_agent_rounded),label:Text(busy?'Opening…':'Contact Sovereign Desk'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,padding:const EdgeInsets.symmetric(vertical:15))))],
    if(status!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(status!,style:const TextStyle(color:muted,fontSize:12))),const SizedBox(height:12),const Text('Trading involves risk. Signals and education do not guarantee profits.',style:TextStyle(color:muted,fontSize:11,height:1.5))
  ]);}
  Widget _info(Color card,Color fg,IconData icon,String title,String body)=>Card(color:card,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:BorderSide(color:gold.withValues(alpha:.2))),child:Padding(padding:const EdgeInsets.all(15),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:gold,size:24),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:TextStyle(color:fg,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(body,style:const TextStyle(color:muted,fontSize:12,height:1.5))]))])));
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key,required this.api,required this.dark});
  final MonarchApi api; final bool dark;
  @override State<CommunityPage> createState()=>_CommunityPageState();
}
class _CommunityPageState extends State<CommunityPage>{
  final composer=TextEditingController();late Future<Map<String,dynamic>> future;bool sending=false;String? message;bool success=false;PlatformFile? image;
  @override void initState(){super.initState();future=widget.api.communityPosts();}
  void reload()=>setState(()=>future=widget.api.communityPosts());
  Future<void> chooseImage()async{final r=await FilePicker.platform.pickFiles(type:FileType.image,withData:true);if(r!=null&&r.files.isNotEmpty&&mounted)setState(()=>image=r.files.first);}
  Future<void> deletePost(int id)async{
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Delete this post?'),content:const Text('Your post will be removed from the community feed.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('Delete'))]));
    if(confirmed!=true)return;
    try{await widget.api.deleteCommunityPost(id);if(mounted){reload();ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Your post was deleted.')));}}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not delete the post. Please try again.')));}
  }
  Future<void> publish()async{if(sending)return;final body=composer.text.trim();if(body.isEmpty){setState((){message='Write something before publishing.';success=false;});return;}setState((){sending=true;message=null;});try{final r=await widget.api.createCommunityPostWithImage(body,image);composer.clear();if(mounted)setState((){sending=false;image=null;message=(r['message']??'Post published.').toString();success=true;});reload();}catch(e){if(mounted)setState((){sending=false;message=apiErrorMessage(e,fallback:'Could not publish your post. Check the connection and image format.');success=false;});}}
  String presenceLabel(Map<String,dynamic> p){if(p['authorOnline']==true||p['authorOnline']==1)return 'Online now';final raw=p['authorLastSeen'];if(raw==null)return 'Status unavailable';final dt=DateTime.tryParse(raw.toString());if(dt==null)return 'Last seen recently';final d=DateTime.now().difference(dt.toLocal());if(d.inMinutes<1)return 'Last seen just now';if(d.inMinutes<60)return 'Last seen '+d.inMinutes.toString()+'m ago';if(d.inHours<24)return 'Last seen '+d.inHours.toString()+'h ago';return 'Last seen '+d.inDays.toString()+'d ago';}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(15),children:[
    const Text('THE MONARCH COMMUNITY',style:TextStyle(color:gold,fontSize:18,fontWeight:FontWeight.w900,letterSpacing:0.6)),
    const SizedBox(height:6),const Text('Share updates, ask questions, and connect with members. Images are optional.',style:TextStyle(color:muted,fontSize:13,height:1.35)),
    const SizedBox(height:14),Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      TextField(controller:composer,maxLines:4,maxLength:5000,style:const TextStyle(fontSize:14,height:1.35),decoration:const InputDecoration(hintText:'What would you like to share?',hintMaxLines:2,border:OutlineInputBorder(),contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:12))),
      if(image!=null)Padding(padding:const EdgeInsets.only(top:4),child:Text('Attached: '+image!.name,style:const TextStyle(color:muted,fontSize:11),maxLines:2,overflow:TextOverflow.ellipsis)),
      const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:sending?null:chooseImage,icon:const Icon(Icons.image_outlined),label:const Text('Add image')),FilledButton.icon(onPressed:sending?null:publish,icon:sending?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:ink)):const Icon(Icons.send),label:Text(sending?'Posting…':'Publish'))]),
      if(message!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(message!,style:TextStyle(color:success?Colors.green:Colors.redAccent,fontSize:12))),
      TextButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>FeedbackPage(api:widget.api,dark:widget.dark))),icon:const Icon(Icons.feedback_outlined),label:const Text('Feedback & Suggestions'))
    ]))),
    const SizedBox(height:14),Row(children:[const Expanded(child:Text('COMMUNITY FEED',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1))),IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),
    FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snapshot){
      if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator(color:gold));
      if(snapshot.hasError)return Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(apiErrorMessage(snapshot.error!,fallback:'The community feed is not available. Check your connection and retry.'),style:const TextStyle(color:muted,fontSize:13,height:1.35)),const SizedBox(height:8),Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Retry')))]));
      final posts=(snapshot.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
      if(posts.isEmpty)return const Padding(padding:EdgeInsets.all(22),child:Text('No posts yet. Be the first to start a conversation.',textAlign:TextAlign.center,style:TextStyle(color:muted)));
      return Column(children:posts.map((p)=>Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.account_circle_outlined,color:gold,size:20),const SizedBox(width:7),Expanded(child:Text((p['authorName']??'Monarch member').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w800))),Container(width:7,height:7,decoration:BoxDecoration(color:(p['authorOnline']==true||p['authorOnline']==1)?Colors.green:muted,shape:BoxShape.circle)),const SizedBox(width:5),Flexible(child:Text(presenceLabel(p),style:const TextStyle(color:muted,fontSize:10),overflow:TextOverflow.ellipsis))]),
        const SizedBox(height:7),Text((p['body']??'').toString()),
        if(p['hasImage']==true||p['hasImage']==1)Padding(padding:const EdgeInsets.only(top:10),child:FutureBuilder<Uint8List>(future:widget.api.communityImage((p['id'] as num).toInt()),builder:(context,s)=>s.hasData?ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.memory(s.data!,fit:BoxFit.cover)):s.hasError?const SizedBox.shrink():const SizedBox(height:90,child:Center(child:CircularProgressIndicator(strokeWidth:2,color:gold))))),
        const SizedBox(height:9),Row(children:[Expanded(child:Text((p['createdAt']??'').toString(),style:const TextStyle(color:muted,fontSize:10))),if(p['isMine']==true||p['isMine']==1)IconButton(onPressed:()=>deletePost((p['id'] as num).toInt()),tooltip:'Delete your post',icon:const Icon(Icons.delete_outline,color:Colors.redAccent,size:20))]),
        Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(_)=>CommunityCommentsDialog(api:widget.api,postId:(p['id'] as num).toInt(),dark:widget.dark)),icon:const Icon(Icons.mode_comment_outlined,color:gold,size:18),label:Text('Comments (${p['commentCount']??0})'))),
      ])))).toList());
    })
  ]);
}

class CommunityCommentsDialog extends StatefulWidget {
  const CommunityCommentsDialog({super.key,required this.api,required this.postId,required this.dark});
  final MonarchApi api;final int postId;final bool dark;
  @override State<CommunityCommentsDialog> createState()=>_CommunityCommentsDialogState();
}
class _CommunityCommentsDialogState extends State<CommunityCommentsDialog>{
  final controller=TextEditingController();late Future<Map<String,dynamic>> future;bool sending=false;String? error;
  @override void initState(){super.initState();future=widget.api.communityComments(widget.postId);}
  @override void dispose(){controller.dispose();super.dispose();}
  void reload()=>setState(()=>future=widget.api.communityComments(widget.postId));
  String presence(Map<String,dynamic> p){if(p['authorOnline']==true||p['authorOnline']==1)return 'Online now';final raw=p['authorLastSeen'];if(raw==null)return 'Offline';final dt=DateTime.tryParse(raw.toString());if(dt==null)return 'Offline';final minutes=DateTime.now().difference(dt.toLocal()).inMinutes;return minutes<1?'Last seen just now':minutes<60?'Last seen ${minutes}m ago':'Offline';}
  Future<void> deleteComment(int id)async{
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Delete this comment?'),content:const Text('Your comment will be removed from the discussion.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('Delete'))]));
    if(confirmed!=true)return;
    try{await widget.api.deleteCommunityComment(widget.postId,id);reload();}
    catch(_){if(mounted)setState(()=>error='Could not delete your comment. Please try again.');}
  }
  Future<void> send()async{final body=controller.text.trim();if(body.isEmpty||sending)return;setState(()=>sending=true);try{await widget.api.createCommunityComment(widget.postId,body);controller.clear();if(mounted)setState(()=>error=null);reload();}catch(e){if(mounted)setState(()=>error='Could not post your comment. Check your connection and try again.');}finally{if(mounted)setState(()=>sending=false);}}
  @override Widget build(BuildContext context)=>AlertDialog(
    title:const Text('Community comments'),
    content:SizedBox(width:480,height:420,child:Column(mainAxisSize:MainAxisSize.min,children:[
      Flexible(child:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Padding(padding:EdgeInsets.all(20),child:CircularProgressIndicator(color:gold));if(s.hasError)return Column(children:[const Text('Comments could not be loaded.'),TextButton(onPressed:reload,child:const Text('Retry'))]);final items=(s.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();if(items.isEmpty)return const Padding(padding:EdgeInsets.all(12),child:Text('Be the first to comment.'));return ListView(shrinkWrap:true,children:items.map((c)=>ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.account_circle_outlined,color:gold),title:Row(children:[Expanded(child:Text((c['authorName']??'Member').toString(),style:const TextStyle(fontWeight:FontWeight.w800))),Text(presence(c),style:const TextStyle(fontSize:10,color:muted))]),subtitle:Text((c['body']??'').toString()),trailing:(c['isMine']==true||c['isMine']==1)?IconButton(tooltip:'Delete your comment',icon:const Icon(Icons.delete_outline,color:Colors.redAccent,size:19),onPressed:()=>deleteComment((c['id'] as num).toInt())):null)).toList());})),
      const SizedBox(height:8),TextField(controller:controller,maxLength:2000,maxLines:2,decoration:const InputDecoration(hintText:'Write a comment…',border:OutlineInputBorder())),
      if(error!=null)Align(alignment:Alignment.centerLeft,child:Text(error!,style:const TextStyle(color:Colors.redAccent,fontSize:12)))
    ])),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close')),FilledButton(onPressed:sending?null:send,style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:Text(sending?'Posting…':'Comment'))],
  );
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key,required this.api,required this.dark});
  final MonarchApi api;final bool dark;
  @override State<FeedbackPage> createState()=>_FeedbackPageState();
}
class _FeedbackPageState extends State<FeedbackPage>{
  final title=TextEditingController(),description=TextEditingController();String category='feature_request';PlatformFile? image;bool sending=false;String? message;bool success=false;late Future<Map<String,dynamic>> future;
  @override void initState(){super.initState();future=widget.api.feedbackList();}
  @override void dispose(){title.dispose();description.dispose();super.dispose();}
  void reload()=>setState(()=>future=widget.api.feedbackList());
  Future<void> chooseImage()async{final r=await FilePicker.platform.pickFiles(type:FileType.image,withData:true);if(r!=null&&r.files.isNotEmpty&&mounted)setState(()=>image=r.files.first);}
  Future<void> submit()async{if(title.text.trim().length<3||description.text.trim().length<5){setState(()=>message='Please add a clear title and description.');return;}setState(()=>sending=true);try{await widget.api.submitFeedback(category:category,title:title.text.trim(),description:description.text.trim(),image:image);if(mounted){setState((){sending=false;message='Thank you. Your feedback has been received.';success=true;image=null;});title.clear();description.clear();reload();}}catch(_){if(mounted)setState((){sending=false;message='Could not submit feedback. Check your connection and image size.';success=false;});}}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(15),children:[
    const Text('FEEDBACK & SUGGESTIONS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),const SizedBox(height:6),const Text('Tell us what should be added, improved, or fixed. Images are optional.',style:TextStyle(color:muted)),
    const SizedBox(height:12),Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(labelText:'Feedback category',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'feature_request',child:Text('Feature request')),DropdownMenuItem(value:'bug_report',child:Text('Something is broken')),DropdownMenuItem(value:'improvement',child:Text('Improvement')),DropdownMenuItem(value:'other',child:Text('Other feedback'))],onChanged:sending?null:(v)=>setState(()=>category=v??'other')),
      const SizedBox(height:10),TextField(controller:title,maxLength:160,decoration:const InputDecoration(labelText:'Title',border:OutlineInputBorder())),
      const SizedBox(height:10),TextField(controller:description,maxLines:5,maxLength:5000,decoration:const InputDecoration(labelText:'Describe your idea or problem',border:OutlineInputBorder())),
      OutlinedButton.icon(onPressed:sending?null:chooseImage,icon:const Icon(Icons.image_outlined),label:Text(image==null?'Attach image (optional)':image!.name)),
      if(image!=null)TextButton(onPressed:()=>setState(()=>image=null),child:const Text('Remove image')),
      if(message!=null)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(message!,style:TextStyle(color:success?Colors.green:Colors.redAccent))),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:sending?null:submit,child:Text(sending?'Submitting…':'Submit feedback')))
    ]))),
    const SizedBox(height:18),const Text('YOUR FEEDBACK HISTORY',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1)),
    FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Padding(padding:EdgeInsets.all(12),child:Center(child:CircularProgressIndicator(color:gold)));if(s.hasError)return const Text('Could not load feedback history.',style:TextStyle(color:muted));final items=(s.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();if(items.isEmpty)return const Padding(padding:EdgeInsets.all(16),child:Text('Your submitted feedback will appear here.',style:TextStyle(color:muted)));return Column(children:items.map((x)=>Card(color:widget.dark?panel:Colors.white,child:ListTile(isThreeLine:true,leading:const Icon(Icons.feedback_outlined,color:gold),title:Text((x['title']??'Feedback').toString()),subtitle:Text((x['category']??'').toString().replaceAll('_',' ')+' · '+(x['status']??'received').toString().replaceAll('_',' ')+(x['adminNote']==null?'':'\nAdmin note: '+x['adminNote'].toString())),trailing:(x['hasImage']==true||x['hasImage']==1)?const Icon(Icons.image,color:gold):null))).toList());})
  ]);
}

class PresencePrivacyPage extends StatefulWidget {
  const PresencePrivacyPage({super.key,required this.api,required this.dark});
  final MonarchApi api;final bool dark;
  @override State<PresencePrivacyPage> createState()=>_PresencePrivacyPageState();
}
class _PresencePrivacyPageState extends State<PresencePrivacyPage>{
  late Future<Map<String,dynamic>> future;bool busy=false;String? message;
  @override void initState(){super.initState();future=widget.api.presenceSettings();}
  Future<void> save(bool value)async{setState(()=>busy=true);try{await widget.api.savePresenceSettings(value);if(mounted)setState((){busy=false;message=value?'Online status is visible to members.':'Online status and last seen are hidden.';future=widget.api.presenceSettings();});}catch(_){if(mounted)setState((){busy=false;message='Could not update privacy settings.';});}}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator(color:gold));final visible=s.data?['showStatus']!=false;return ListView(padding:const EdgeInsets.all(16),children:[const Text('ONLINE STATUS PRIVACY',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),const SizedBox(height:8),const Text('When enabled, members can see whether you are online and when you were last active. Status expires automatically when activity stops.',style:TextStyle(color:muted)),const SizedBox(height:14),SwitchListTile(value:visible,onChanged:busy?null:save,activeColor:gold,title:const Text('Show online status and last seen'),subtitle:const Text('You can change this setting at any time.'),tileColor:widget.dark?panel:Colors.white),if(message!=null)Padding(padding:const EdgeInsets.all(12),child:Text(message!,style:const TextStyle(color:gold)))]);});
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
  Future<void> openLogin()async{final uri=Uri.parse('https://airdrop.myturntech.com/login');if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&mounted)setState(()=>message='Could not open the login page. Please try again.');}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snapshot){
    final items=(snapshot.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    final connected=items.any((x)=>x['status']=='approved');final pending=items.any((x)=>x['status']=='pending');
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('ONLINE COOPERATIVE',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:6),Text(connected?'Your Online Cooperative account is connected. You can now log in to your existing account.':'Register with our referral link, then submit the same name and email for manual verification. We will not ask for your password or OTP.',style:const TextStyle(color:muted)),
      const SizedBox(height:14),Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Icon(connected?Icons.verified:pending?Icons.hourglass_top:Icons.link,color:gold),const SizedBox(width:8),Expanded(child:Text(connected?'CONNECTED TO MONARCH CODEX':pending?'VERIFICATION PENDING':'NOT CONNECTED',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:12)))]),
        const SizedBox(height:12),
        if(connected) FilledButton.icon(onPressed:openLogin,icon:const Icon(Icons.login),label:const Text('Login to Online Cooperative')),
        if(!connected) ...[
          FilledButton.icon(onPressed:openRegistration,icon:const Icon(Icons.open_in_new),label:const Text('Register with Online Cooperative')),
          const SizedBox(height:16),TextField(controller:name,decoration:const InputDecoration(labelText:'Name used to register',border:OutlineInputBorder())),
          const SizedBox(height:10),TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Registration email',border:OutlineInputBorder())),
          const SizedBox(height:12),if(message!=null)Padding(padding:const EdgeInsets.only(bottom:10),child:Text(message!,style:TextStyle(color:success?Colors.green:Colors.redAccent))),
          FilledButton(onPressed:sending||pending?null:register,child:Text(sending?'Submitting…':pending?'Awaiting verification':'Submit for verification')),
        ],
        if(connected&&message!=null) Padding(padding:const EdgeInsets.only(top:12),child:Text(message!,style:TextStyle(color:success?Colors.green:Colors.redAccent))),
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
  bool menu = false, loading = true, balanceInUsd = false;
  String? special, error;
  Map<String, dynamic>? data;
  static const names = ['Overview', 'Wallet', 'Invest', 'Market', 'Community', 'Profile'];
  static const icons = [Icons.grid_view_rounded, Icons.account_balance_wallet_rounded, Icons.trending_up_rounded, Icons.show_chart_rounded, Icons.groups_rounded, Icons.person_rounded];
  Timer? presenceTimer;
  Timer? indicatorTimer;
  int communityUnread = 0;
  int notificationUnread = 0;
  List<Map<String, dynamic>> _notificationItems = [];
  bool updateAvailable = false;
  @override void initState() {
    super.initState();
    refresh();
    _refreshIndicators();
    _checkForAppUpdate(notify: true);
    widget.api.presenceHeartbeat().catchError((_){});
    presenceTimer=Timer.periodic(const Duration(seconds:45),(_)=>widget.api.presenceHeartbeat().catchError((_){}));
    indicatorTimer=Timer.periodic(const Duration(seconds:60),(_) { _refreshIndicators(); _checkForAppUpdate(notify: true); });
  }
  @override void dispose(){presenceTimer?.cancel();indicatorTimer?.cancel();super.dispose();}
  Future<File> _communityMarkerFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/community_last_seen_post_id.txt');
  }
  Future<void> _refreshIndicators() async {
    try {
      final notificationData = await widget.api.notifications();
      final postsData = await widget.api.communityPosts();
      final items = (notificationData['items'] as List? ?? const []).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
      final unreadItems = items.where((item) => item['readAt'] == null).toList();
      final posts = (postsData['items'] as List? ?? const []).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
      final ids = posts.map((p) => int.tryParse((p['id'] ?? '').toString()) ?? 0).where((id) => id > 0).toList();
      final latestId = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
      final marker = await _communityMarkerFile();
      int? lastSeen;
      if (await marker.exists()) lastSeen = int.tryParse((await marker.readAsString()).trim());
      if (lastSeen == null || (tab == 4 && special == null)) {
        lastSeen = latestId;
        await marker.writeAsString('$latestId', flush: true);
      }
      final newPosts = ids.where((id) => id > lastSeen!).length;
      if (!mounted) return;
      setState(() {
        _notificationItems = items;
        notificationUnread = unreadItems.length;
        communityUnread = newPosts;
      });
    } catch (_) {
      // Keep the last known indicators when the service is temporarily unavailable.
    }
  }
  Future<void> _markCommunitySeen() async {
    try {
      final data = await widget.api.communityPosts();
      final posts = (data['items'] as List? ?? const []).whereType<Map>().toList();
      final ids = posts.map((p) => int.tryParse((p['id'] ?? '').toString()) ?? 0).where((id) => id > 0).toList();
      final latestId = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
      final marker = await _communityMarkerFile();
      await marker.writeAsString('$latestId', flush: true);
      if (mounted) setState(() => communityUnread = 0);
    } catch (_) {}
  }
  int _categoryUnread(String category) => _notificationItems.where((item) {
    if (item['readAt'] != null) return false;
    final type = (item['type'] ?? '').toString().toLowerCase();
    switch (category) {
      case 'wallet': return type.contains('deposit') || type.contains('withdraw') || type.contains('transaction') || type.contains('wallet');
      case 'invest': return type.contains('invest');
      case 'market': return type.contains('market');
      case 'profile': return type.contains('kyc') || type.contains('role') || type.contains('profile');
      case 'community': return type.contains('community');
      default: return false;
    }
  }).length;
  int _sectionUnreadCount(int index) {
    switch (index) {
      case 1: return _categoryUnread('wallet');
      case 2: return _categoryUnread('invest');
      case 3: return _categoryUnread('market');
      case 4: return communityUnread + _categoryUnread('community');
      case 5: return _categoryUnread('profile');
      default: return 0;
    }
  }
  Widget _countBadge(Widget child, int count, {double size = 16}) => Stack(clipBehavior: Clip.none, children: [
    child,
    if (count > 0) Positioned(right: -5, top: -5, child: Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(99), border: Border.all(color: ink, width: 1)),
      child: Text(count > 99 ? '99+' : '$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 8, height: 1.2, fontWeight: FontWeight.w900)),
    )),
  ]);
  bool _isNewerVersion(String candidate, String installed) {
    List<int> parts(String value) {
      final pieces = value.split('+');
      final version = pieces.first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      while (version.length < 3) { version.add(0); }
      version.add(pieces.length > 1 ? int.tryParse(pieces[1]) ?? 0 : 0);
      return version;
    }
    final a = parts(candidate), b = parts(installed);
    for (var i = 0; i < 4; i++) { if (a[i] != b[i]) return a[i] > b[i]; }
    return false;
  }
  Future<void> _checkForAppUpdate({bool notify = false}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: const {'Accept': 'application/json'},
      )).get<dynamic>('https://monarchcodex.online/api/mobile/app-update/latest');
      if (response.data is! Map) return;
      final release = Map<String, dynamic>.from(response.data as Map);
      final version = (release['version'] ?? '').toString().trim();
      final apkUri = Uri.tryParse((release['apkUrl'] ?? '').toString());
      final checksumUri = Uri.tryParse((release['checksumUrl'] ?? '').toString());
      if (version.isEmpty || apkUri == null || checksumUri == null ||
          apkUri.scheme != 'https' || checksumUri.scheme != 'https' ||
          apkUri.host != 'monarchcodex.online' || checksumUri.host != 'monarchcodex.online') return;
      final newer = _isNewerVersion(version, info.version + '+' + info.buildNumber);
      final newlyAvailable = newer && !updateAvailable;
      if (mounted) setState(() => updateAvailable = newer);
      if (notify && newlyAvailable && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Monarch Codex update ' + version + ' is available.'),
            action: SnackBarAction(label: 'UPDATE', onPressed: _openUpdater),
            duration: const Duration(seconds: 8),
          ));
        });
      }
    } catch (_) {
      // A failed check must not block sign-in or dashboard access.
    }
  }
  Future<void> _openUpdater() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppUpdaterPage()));
    if (mounted) _checkForAppUpdate();
  }
  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
    try { final result = await widget.api.overview(); if (mounted) setState(() { data = result; loading = false; }); }
    catch (e) { if (mounted) setState(() { loading = false; error = e is DioException && e.response?.data is Map ? ((e.response!.data as Map)['message']?.toString() ?? 'Could not load account data.') : 'Could not load account data.'; }); }
  }
  void page(String? value, [int? index]) {
    setState(() { special = value; if (index != null) tab = index; menu = false; });
    if (index == 4) _markCommunitySeen();
  }
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = special ?? names[tab];
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (menu) { setState(() => menu = false); return; }
        if (special != null) { setState(() => special = null); return; }
        if (tab != 0) { setState(() => tab = 0); return; }
        confirmAppExit(context);
      },
      child: Scaffold(body: SafeArea(child: Stack(clipBehavior: Clip.hardEdge, children: [
      Positioned.fill(child: AnimatedPadding(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, padding: EdgeInsets.only(left: menu ? 214 : 0), child: SizedBox(width: MediaQuery.sizeOf(context).width, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Row(children: [
          IconButton(onPressed: () => setState(() => menu = !menu), icon: Icon(menu ? Icons.close : Icons.menu, color: gold)),
          SvgPicture.asset('assets/images/monarch-codex-logo.svg', width: 40, height: 40),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .8)),
            Row(children: [Expanded(child: Text((widget.member['uid'] ?? 'MONARCH').toString(), style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w900))), IconButton(visualDensity: VisualDensity.compact, tooltip: 'Copy Monarch UID', onPressed: () { Clipboard.setData(ClipboardData(text: (widget.member['uid'] ?? '').toString())); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monarch UID copied'))); }, icon: const Icon(Icons.copy, size: 14, color: gold))]),
          ])),
          IconButton(onPressed: _openUpdater, tooltip: updateAvailable ? 'Update available — tap to install' : 'Check for app updates', icon: _countBadge(const Icon(Icons.system_update_alt_rounded, color: gold), updateAvailable ? 1 : 0)),
          IconButton(onPressed: () => page('Notifications'), tooltip: notificationUnread > 0 ? '$notificationUnread unread notifications' : 'Notifications', icon: _countBadge(const Icon(Icons.notifications_none_rounded, color: gold), notificationUnread)),
        ])),
        Expanded(child: special != null ? specialPage(special!, dark) : tab == 0 ? overviewPage(dark) : tab == 1 ? walletPage(dark) : tab == 2 ? InvestmentsPage(api: widget.api, dark: dark) : tab == 5 ? profilePage(dark) : tab == 3 ? LiveMarketsPage(api: widget.api, dark: dark) : tab == 4 ? CommunityPage(api: widget.api, dark: dark) : featurePage(names[tab], 'Market information', icons[tab], 'Market information is temporarily unavailable.', dark)),
        if (special == null) bottomNav(dark),
      ])))),
      if (menu) Positioned(left: 0, top: 0, bottom: 0, width: 214, child: sidebar(dark)),
    ]))));
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
        quick('Transactions', Icons.receipt_long_rounded, () => page('Transactions'), dark),
        quick('Wallet Transfer', Icons.swap_horiz_rounded, () => page('Wallet Transfer'), dark),
        quick('Invest', Icons.trending_up, () => page(null, 2), dark),
        quick('Market', Icons.show_chart, () => page(null, 3), dark),
        quick('Feeds', Icons.newspaper_rounded, () => page(null, 3), dark),
        quick('Community', Icons.groups_outlined, () => page(null, 4), dark),
        quick('Notifications', Icons.notifications_none_rounded, () => page('Notifications'), dark),
        quick('Announcements', Icons.campaign_outlined, () => page('Notifications'), dark),
        quick('Verify KYC', Icons.shield_outlined, () => page('KYC Verification'), dark),
        quick('Referrals', Icons.share_outlined, () => page('Referrals'), dark),
        quick('Roles & Requests', Icons.badge_outlined, () => page(null, 5), dark),
        quick('Online Coop', Icons.link_rounded, () => page('Online Cooperative'), dark),
        quick('Social Links', Icons.public, () => page('Social Links'), dark),
        quick('Feedback', Icons.feedback_outlined, () => page('Feedback & Suggestions'), dark),
        quick('Academy', Icons.school_outlined, () => page('Academy'), dark),
        quick('Sovereign Desk', Icons.support_agent_rounded, () => page('Sovereign Desk'), dark),
        quick('Help & Support', Icons.help_outline_rounded, () => page('Help & Support'), dark),
        quick('App Updates', Icons.system_update_alt_rounded, _openUpdater, dark),
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
      tile('Wallet Transfer', 'Send funds securely to another member using their Monarch UID.', Icons.swap_horiz_rounded, dark, () => page('Wallet Transfer')),
      tile('Monarch Codex Academy', 'Continue lessons, unlock full access, or pay \$2 to replay a previous video.', Icons.school_outlined, dark, () => page('Academy')),
    ]);
  }

  Widget profilePage(bool dark) {
    final m = data?['member'] is Map ? Map<String, dynamic>.from(data!['member'] as Map) : widget.member;
    return ProfileEditorPage(api: widget.api, member: m, dark: dark, onUpdated: () { if(mounted) setState(() { photoVersion = DateTime.now().millisecondsSinceEpoch; }); refresh(); });
  }

  Widget specialPage(String p, bool dark) {
    if (p == 'Wallet Transfer') return WalletTransferPage(api: widget.api, dark: dark, onDone: refresh);
    if (p == 'Academy') return AcademyPage(api: widget.api, dark: dark);
    if (p == 'Free Signals' || p == 'Sovereign Desk') return SovereignRequestPage(api: widget.api, dark: dark, uid: (widget.member['uid'] ?? widget.member['monarch_uid'] ?? '').toString(), initialType: p);
    if (p == 'Transactions') return TransactionsPage(api: widget.api, dark: dark);
    if (p == 'Deposit') return DepositPage(api: widget.api, dark: dark, onDone: refresh);
    if (p == 'Withdraw') return WithdrawalPage(api: widget.api, dark: dark, onDone: refresh);
    if (p == 'Notifications') return NotificationsPage(api: widget.api, dark: dark);
    if (p == 'Settings') return ListView(padding: const EdgeInsets.all(15), children: [
      tile(widget.light ? 'Dark appearance' : 'Light appearance', 'Toggle app appearance.', Icons.contrast, dark, widget.toggleTheme),
      tile('Account details', 'Edit your account details inside the app.', Icons.manage_accounts, dark, () => page(null, 5)),
      tile('Password recovery', 'Open secure password recovery instructions.', Icons.lock_reset, dark, () => page('Password Recovery')),
      tile('Online status privacy', 'Choose whether members can see your online and last-seen status.', Icons.visibility_outlined, dark, () => page('Presence Privacy')),
    ]);
    if (p == 'Help & Support') return ListView(padding: const EdgeInsets.all(15), children: [
      featurePage(p, 'How can we help you?', Icons.support_agent, 'Choose the topic that matches your question. For your safety, never share your password, PIN, or one-time verification code with anyone.', dark),
      tile('Contact official support', 'Email support@monarchcodex.online. Include your Monarch UID and a short description; never include your password or OTP.', Icons.email_outlined, dark, () => launchUrl(Uri.parse('mailto:support@monarchcodex.online?subject=Monarch%20Codex%20Member%20Support'))),
      tile('Account access & password recovery', 'Get help signing in or securely reset your password.', Icons.lock_reset, dark, () => page('Password Recovery')),
      tile('KYC & account verification', 'Check your verification status or open the KYC section.', Icons.verified_user_outlined, dark, () => page('KYC Verification')),
      tile('Deposits & withdrawals', 'Find payment instructions or check your request status.', Icons.account_balance_wallet_outlined, dark, () => page(null, 1)),
      tile('Investments & market', 'Open your investment plans, portfolio, and market information.', Icons.trending_up, dark, () => page(null, 2)),
      tile('Referrals & Monarch UID', 'Get help sharing your referral details and connecting with members.', Icons.share_outlined, dark, () => page('Referrals')),
      tile('Online Cooperative connection', 'Get help with connecting your account or understanding a pending Cooperative verification. Cooperative participation is separate from Monarch Codex services.', Icons.handshake_outlined, dark, () => page('Online Cooperative')),
      tile('Sovereign Desk signals & access', 'Ask about signal access, membership eligibility, or trading guidance. Signals and market activity carry risk and do not guarantee profits.', Icons.insights_outlined, dark, () => launchUrl(Uri.parse('mailto:support@monarchcodex.online?subject=Monarch%20Codex%20Sovereign%20Desk%20Support'))),
      tile('Community & social links', 'Open the member community or official Monarch Codex channels.', Icons.groups_outlined, dark, () => page(null, 4)),
      tile('Report a problem / send feedback', 'Submit a bug report, suggestion, or improvement and track its status.', Icons.feedback_outlined, dark, () => page('Feedback & Suggestions')),
      tile('Visit website in browser', 'Open Monarch Codex online in your external browser.', Icons.open_in_new, dark, () => openSite('/')),
    ]);
    if (p == 'Password Recovery') return PasswordRecoveryPage(dark: dark);
    if (p == 'KYC Verification') return KycStatusPage(api: widget.api, dark: dark);
    if (p == 'Referrals') return ReferralsPage(api: widget.api, dark: dark);
    if (p == 'Online Cooperative') return OnlineCooperativePage(api: widget.api, dark: dark);
    if (p == 'Social Links') return SocialLinksPage(api: widget.api, dark: dark);
    if (p == 'Feedback & Suggestions') return FeedbackPage(api: widget.api, dark: dark);
    if (p == 'Presence Privacy') return PresencePrivacyPage(api: widget.api, dark: dark);
    return featurePage(p, 'Monarch Codex', Icons.auto_awesome, 'This section will connect to your existing account backend. Existing records are not changed.', dark);
  }

  Widget bottomNav(bool dark) => Container(
    padding: const EdgeInsets.fromLTRB(2, 7, 2, 5),
    decoration: BoxDecoration(color: dark ? const Color(0xFF111113) : Colors.white, border: Border(top: BorderSide(color: dark ? const Color(0xFF2B2924) : const Color(0xFFE2DED1)))),
    child: Row(children: List.generate(names.length, (i) => Expanded(child: InkWell(
      onTap: () => page(null, i), borderRadius: BorderRadius.circular(11),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: tab == i ? gold.withValues(alpha:.14) : Colors.transparent, borderRadius: BorderRadius.circular(99)), child: _countBadge(Icon(icons[i], size: 18, color: tab == i ? gold : muted), _sectionUnreadCount(i), size: 15)),
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
      sideItem('Invest', Icons.trending_up, () => page(null, 2), dark), sideItem('Market & Feeds', Icons.show_chart, () => page(null, 3), dark),
      sideItem('Community', Icons.groups_outlined, () => page(null, 4), dark), sideItem('Profile & Roles', Icons.person_outline, () => page(null, 5), dark),
      const Divider(color: Color(0xFF39352A)), sideItem('Academy', Icons.school_outlined, () => page('Academy'), dark),
      sideItem('Sovereign Desk', Icons.support_agent_rounded, () => page('Sovereign Desk'), dark),
      sideItem('Transactions', Icons.receipt_long_rounded, () => page('Transactions'), dark),
      sideItem('Wallet Transfer', Icons.swap_horiz_rounded, () => page('Wallet Transfer'), dark),
      sideItem('Online Cooperative', Icons.link_rounded, () => page('Online Cooperative'), dark),
      sideItem('KYC Verification', Icons.verified_user_outlined, () => page('KYC Verification'), dark),
      sideItem('Referrals', Icons.share_outlined, () => page('Referrals'), dark), sideItem('Settings', Icons.settings_outlined, () => page('Settings'), dark),
      sideItem('Notifications', Icons.notifications_none_rounded, () => page('Notifications'), dark),
      sideItem('App updates', Icons.system_update_alt_rounded, _openUpdater, dark),
      sideItem('Help & Support', Icons.support_agent, () => page('Help & Support'), dark),
    ])),
    TextButton.icon(onPressed: widget.signOut, icon: const Icon(Icons.logout, size: 17), label: const Text('Sign out'), style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8D85))),
  ])));

  Widget avatar(Map<String, dynamic> member, double size, double radius) =>
      MemberAvatar(api: widget.api, member: member, size: size, radius: radius, version: photoVersion);

  Widget sideItem(String label, IconData icon, VoidCallback action, bool dark) {
    final count = label == 'Community' ? communityUnread + _categoryUnread('community')
        : label == 'Wallet' ? _categoryUnread('wallet')
        : label == 'Invest' ? _categoryUnread('invest')
        : label == 'Market' ? _categoryUnread('market')
        : label == 'Profile' ? _categoryUnread('profile')
        : label == 'Notifications' ? notificationUnread
        : label == 'App updates' && updateAvailable ? 1 : 0;
    return ListTile(
      dense: true, visualDensity: const VisualDensity(vertical: -2), minLeadingWidth: 18, horizontalTitleGap: 7,
      leading: _countBadge(Icon(icon, color: gold, size: 18), count, size: 15),
      title: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), onTap: action,
    );
  }

  Widget balanceCard(double ngn, double usd, double rate) {
    final canConvert = rate > 0;
    final shownValue = balanceInUsd ? usd : ngn; // API values are already combined totals; do not convert them a second time.
    final shownCurrency = balanceInUsd ? 'USD' : 'NGN';
    final shownSymbol = balanceInUsd ? 'USD ' : '₦';
    return Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF6D5920)),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF28200D), Color(0xFF151411), Color(0xFF101012)]),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 22, offset: Offset(0, 9))],
    ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.account_balance_wallet_outlined, color: gold, size: 18), SizedBox(width: 8), Expanded(child: Text('TOTAL WALLET BALANCE', style: TextStyle(color: Color(0xFFD6CBA8), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)))]),
      const SizedBox(height: 12),
      Text((balanceInUsd && !canConvert) ? 'FX unavailable' : shownSymbol + shownValue.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7)),
      const SizedBox(height: 4),
      Text('Combined wallet value · ' + shownCurrency, style: const TextStyle(color: Color(0xFFE0C96D), fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('₦ Naira'), selected: !balanceInUsd, onSelected: (_) { setState(() => balanceInUsd = false); }),
        ChoiceChip(label: const Text('USD Dollars'), selected: balanceInUsd, onSelected: (_) { setState(() => balanceInUsd = true); }),
      ]),
      if (!canConvert) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Exchange-rate reference unavailable. Currency conversion is paused until a rate is available.', style: TextStyle(color: muted, fontSize: 10))),
      const SizedBox(height: 8),
      const Text('Display conversion only. Your actual NGN and USD account balances are unchanged.', style: TextStyle(color: muted, fontSize: 10)),
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


class LiveMarketsPage extends StatefulWidget {
  const LiveMarketsPage({super.key, required this.api, required this.dark});
  final MonarchApi api;
  final bool dark;
  @override State<LiveMarketsPage> createState() => _LiveMarketsPageState();
}

class _LiveMarketsPageState extends State<LiveMarketsPage> {
  late Future<Map<String, dynamic>> future;
  Timer? refreshTimer;
  @override void initState() {
    super.initState();
    future = _load();
    refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) reload(); });
  }
  @override void dispose() { refreshTimer?.cancel(); super.dispose(); }
  Future<Map<String, dynamic>> _load() async {
    final response = await widget.api.dio.get<dynamic>('$site/api/live-markets/crypto?convert=USD', options: Options(headers: const {'Accept': 'application/json'}));
    if (response.data is! Map) throw Exception('The market provider returned an invalid response.');
    return Map<String, dynamic>.from(response.data as Map);
  }
  void reload() => setState(() => future = _load());
  @override Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(color: gold));
      if (snapshot.hasError) return ListView(padding: const EdgeInsets.all(18), children: [
        const Icon(Icons.show_chart, color: gold, size: 44),
        const Text('Live market quotes are temporarily unavailable.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('No placeholder prices are shown. Check your connection and retry.', style: TextStyle(color: muted)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]);
      final data = snapshot.data ?? <String, dynamic>{};
      final coins = (data['coins'] as List? ?? const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      final updated = (data['updatedAt'] ?? '').toString();
      return RefreshIndicator(color: gold, onRefresh: () async { reload(); await future; }, child: ListView(padding: const EdgeInsets.all(15), children: [
        const Text('LIVE MARKET QUOTES', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 6),
        const Text('Crypto prices and 24-hour movement from the Monarch Codex market feed.', style: TextStyle(color: muted, fontSize: 12)),
        if (updated.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 7, bottom: 10), child: Text('Last updated: ' + updated, style: const TextStyle(color: muted, fontSize: 10))),
        if (coins.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No quotes are available right now. Refresh shortly.'))),
        ...coins.take(60).map((coin) {
          final quote = coin['quote'] is Map ? Map<String, dynamic>.from(coin['quote'] as Map) : <String, dynamic>{};
          final usd = quote['USD'] is Map ? Map<String, dynamic>.from(quote['USD'] as Map) : quote;
          final price = number(usd['price']);
          final change = double.tryParse((usd['percent_change_24h'] ?? '').toString());
          final symbol = (coin['symbol'] ?? '').toString();
          return Card(color: widget.dark ? panel : Colors.white, child: ListTile(
            leading: Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: gold.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Text(symbol.isEmpty ? 'COIN' : symbol.substring(0, symbol.length > 4 ? 4 : symbol.length), style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w900))),
            title: Text((coin['name'] ?? symbol).toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(symbol + (change == null ? '' : ' · 24h ' + (change >= 0 ? '+' : '') + change.toStringAsFixed(2) + '%'), style: TextStyle(color: change == null ? muted : change >= 0 ? Colors.green : Colors.redAccent, fontSize: 11)),
            trailing: Text(price > 0 ? 'USD ' + price.toStringAsFixed(price < 1 ? 6 : 2) : '—', style: const TextStyle(color: gold, fontWeight: FontWeight.w900)),
          ));
        }),
        const SizedBox(height: 8),
        const Text('Market data can be delayed or unavailable. Quotes are educational only, not financial advice or guaranteed execution prices.', style: TextStyle(color: muted, fontSize: 10)),
        OutlinedButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('Refresh quotes')),
      ]));
    },
  );
}

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


class PasswordRecoveryPage extends StatelessWidget {
  const PasswordRecoveryPage({super.key, required this.dark});
  final bool dark;
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Container(padding: const EdgeInsets.all(18), decoration: mcCard(dark), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.lock_reset, color: gold, size: 38),
      const SizedBox(height: 12),
      const Text('PASSWORD RECOVERY', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('For account security, use the official password recovery page. Enter only your registered email and follow the instructions sent to your inbox. Never share your password or verification code.', style: TextStyle(color: muted, height: 1.5)),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: () => launchUrl(Uri.parse('$site/forgot-password'), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new), label: const Text('OPEN SECURE RECOVERY'),
        style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink),
      )),
      const SizedBox(height: 8),
      const Text('This opens the official recovery page because password-reset tokens must be handled by the secure account service.', style: TextStyle(color: muted, fontSize: 11)),
    ])),
  ]);
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