import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:monarch_codex/main.dart' hide Card, TextStyle;
import 'package:monarch_codex/app_updater.dart';

Future<void> confirmAppExit(BuildContext context) async {
  final shouldExit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Exit Monarch Codex?'),
      content: const Text('Would you like to close the app?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Stay'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink),
          child: const Text('Exit'),
        ),
      ],
    ),
  );
  if (shouldExit == true) await SystemNavigator.pop();
}

String _workspaceError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (error.response?.statusCode == 401) return 'Your session expired. Sign in again.';
  }
  return 'We could not complete this request. Check your connection and try again. No wallet balance was changed.';
}

class AdminFeedbackPage extends StatefulWidget {
  const AdminFeedbackPage({super.key, required this.api, required this.dark});
  final MonarchApi api;
  final bool dark;

  @override
  State<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends State<AdminFeedbackPage> {
  late Future<Map<String, dynamic>> future;
  final Map<int, TextEditingController> notes = {};
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    future = widget.api.adminFeedback();
  }

  @override
  void dispose() {
    for (final controller in notes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void reload() {
    setState(() {
      future = widget.api.adminFeedback();
    });
  }

  Future<void> review(Map<String, dynamic> item, String status) async {
    final id = (item['id'] as num).toInt();
    setState(() => busy = true);
    try {
      final controller = notes.putIfAbsent(
        id,
        () => TextEditingController(text: (item['adminNote'] ?? '').toString()),
      );
      await widget.api.reviewAdminFeedback(
        id: id,
        status: status,
        note: controller.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        busy = false;
        message = 'Feedback status updated.';
        future = widget.api.adminFeedback();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        message = 'Could not update feedback. Check your permissions and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: gold));
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Member feedback could not be loaded.'),
              FilledButton(onPressed: reload, child: const Text('Retry')),
            ],
          );
        }

        final rawItems = snapshot.data?['items'] as List? ?? const [];
        final items = rawItems
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();

        return ListView(
          padding: const EdgeInsets.all(15),
          children: [
            const Text(
              'MEMBER FEEDBACK',
              style: TextStyle(
                color: gold,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Review member suggestions, bug reports and improvement requests in one queue. Update each item’s status and leave a clear note; members receive a notification and can track the decision in their feedback history.',
              style: TextStyle(color: muted),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(message!, style: const TextStyle(color: gold)),
              ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Text(
                  'No feedback has been submitted yet.',
                  style: TextStyle(color: muted),
                ),
              ),
            for (final entry in items) _feedbackCard(entry),
          ],
        );
      },
    );
  }

  Widget _feedbackCard(Map<String, dynamic> item) {
    final id = (item['id'] as num).toInt();
    final controller = notes.putIfAbsent(
      id,
      () => TextEditingController(text: (item['adminNote'] ?? '').toString()),
    );
    final category = (item['category'] ?? 'other').toString().replaceAll('_', ' ');
    final status = (item['status'] ?? 'received').toString().replaceAll('_', ' ');

    return Card(
      color: widget.dark ? panel : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (item['title'] ?? 'Feedback').toString(),
              style: const TextStyle(color: gold, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              (item['memberName'] ?? 'Member').toString() + ' · ' + category,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Text((item['description'] ?? '').toString()),
            const SizedBox(height: 8),
            Text('Status: ' + status, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextField(
              controller: controller,
              maxLines: 2,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Update for member / reason',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => review(item, 'under_review'),
                  child: const Text('Review'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => review(item, 'planned'),
                  child: const Text('Plan'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => review(item, 'in_progress'),
                  child: const Text('In progress'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => review(item, 'implemented'),
                  child: const Text('Implemented'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => review(item, 'declined'),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.api, required this.member, required this.signOut, required this.light, required this.toggleTheme});
  final MonarchApi api;
  final Map<String,dynamic> member;
  final Future<void> Function() signOut;
  final bool light;
  final VoidCallback toggleTheme;
  @override State<AdminShell> createState()=>_AdminShellState();
}

class _AdminShellState extends State<AdminShell>{
  late Future<Map<String,dynamic>> data;
  int selected=0;
  int unreadNotifications=0;
  bool updateAvailable=false;
  bool drawerBusy=false;
  Timer? indicatorTimer;
  final GlobalKey<ScaffoldState> scaffoldKey=GlobalKey<ScaffoldState>();
  @override void initState(){
    super.initState();
    data=widget.api.adminOverview();
    _refreshIndicators();
    indicatorTimer=Timer.periodic(const Duration(seconds:60),(_)=>_refreshIndicators());
  }
  @override void dispose(){indicatorTimer?.cancel();super.dispose();}
  void reload()=>setState(()=>data=widget.api.adminOverview());
  bool _newerVersion(String candidate,String installed){
    List<int> parts(String value){final p=value.split('+');final v=p.first.split('.').map((x)=>int.tryParse(x)??0).toList();while(v.length<3){v.add(0);}v.add(p.length>1?int.tryParse(p[1])??0:0);return v;}
    final a=parts(candidate),b=parts(installed);
    for(var i=0;i<4;i++){if(a[i]!=b[i])return a[i]>b[i];}
    return false;
  }
  Future<void> _refreshIndicators() async {
    try{
      final result=await widget.api.notifications();
      final items=(result['items'] as List? ?? const []).whereType<Map>().toList();
      final unread=items.where((item)=>item['readAt']==null).length;
      if(mounted)setState(()=>unreadNotifications=unread);
    }catch(_){}
    try{
      final info=await PackageInfo.fromPlatform();
      final response=await Dio(BaseOptions(connectTimeout:const Duration(seconds:10),receiveTimeout:const Duration(seconds:15),headers:const {'Accept':'application/json'})).get<dynamic>('https://monarchcodex.online/api/mobile/app-update/latest');
      if(response.data is! Map)return;
      final release=Map<String,dynamic>.from(response.data as Map);
      final version=(release['version']??'').toString();
      final newer=_newerVersion(version,info.version+'+'+info.buildNumber);
      final newlyAvailable=newer&&!updateAvailable;
      if(mounted)setState(()=>updateAvailable=newer);
      if(newlyAvailable&&mounted)WidgetsBinding.instance.addPostFrameCallback((_){
        if(!mounted)return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text('Monarch Codex update '+version+' is available.'),
          action:SnackBarAction(label:'UPDATE',onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const AppUpdaterPage()))),
          duration:const Duration(seconds:8),
        ));
      });
    }catch(_){}
  }
  Widget _indicatorBadge(Widget child,int count,{double size=16})=>Stack(clipBehavior:Clip.none,children:[
    child,
    if(count>0)Positioned(right:-5,top:-5,child:Container(
      constraints:BoxConstraints(minWidth:size,minHeight:size),
      padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),
      decoration:BoxDecoration(color:const Color(0xFFE5484D),borderRadius:BorderRadius.circular(99),border:Border.all(color:ink,width:1)),
      child:Text(count>99?'99+':'$count',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:8,height:1.2,fontWeight:FontWeight.w900)),
    )),
  ]);

  Future<void> openSection(int index) async {
    if(index==0){scaffoldKey.currentState?.closeDrawer();setState(()=>selected=0);reload();return;}
    if(index==4){scaffoldKey.currentState?.closeDrawer();await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>RoleManagerPage(api:widget.api,dark:Theme.of(context).brightness==Brightness.dark)));if(mounted)setState(()=>selected=0);return;}
     if(index==13){scaffoldKey.currentState?.closeDrawer();await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminMembersPage(api:widget.api,dark:Theme.of(context).brightness==Brightness.dark)));if(mounted)setState(()=>selected=0);return;}
    scaffoldKey.currentState?.closeDrawer();
    setState(()=>selected=index);
    final dark=Theme.of(context).brightness==Brightness.dark;
    Widget? page;
    if(index>=1&&index<=3)page=AdminReviewQueuePage(api:widget.api,type:const ['kyc','deposits','withdrawals'][index-1],dark:dark);
    if(index==5)page=AdminDataPage(api:widget.api,kind:'audit',dark:dark);
    if(index==6)page=AdminDataPage(api:widget.api,kind:'analytics',dark:dark);
    if(index==7)page=AdminDataPage(api:widget.api,kind:'security',dark:dark);
    if(index==8){scaffoldKey.currentState?.closeDrawer();await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>AdminAppSettingsPage(dark:Theme.of(context).brightness==Brightness.dark,light:widget.light,toggleTheme:widget.toggleTheme)));if(mounted)setState(()=>selected=0);return;}
    if(index==9)page=AdminPermissionsPage(api:widget.api,dark:dark,currentMemberId:(widget.member['id'] as num?)?.toInt()??(widget.member['memberId'] as num?)?.toInt()??-1);
    if(index==10)page=AdminCooperativePage(api:widget.api,dark:dark);
    if(index==11)page=AdminSocialLinksPage(api:widget.api,dark:dark);
    if(index==12)page=AdminFeedbackPage(api:widget.api,dark:dark);
    if(index==14)page=NotificationsPage(api:widget.api,dark:dark);
     if(index==15)page=AdminHelpSupportPage(dark:dark);
    if(index==16)page=CommunityPage(api:widget.api,dark:dark);
    if(page!=null)await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>page!));
    if(mounted)setState(()=>selected=0);
  }

  Widget _navItem(int index,IconData icon,String title) {
    final active=selected==index;
    return Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:2),child:Material(
      color:active?const Color(0xFF39301D):Colors.transparent,
      borderRadius:BorderRadius.circular(12),
      child:ListTile(
        dense:true,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
        leading:Icon(icon,color:active?gold:muted,size:21),
        title:Text(title,style:TextStyle(color:active?gold:null,fontSize:12,fontWeight:active?FontWeight.w900:FontWeight.w600)),
        trailing:FutureBuilder<Map<String,dynamic>>(future:data,builder:(context,snapshot){
          final d=snapshot.data??<String,dynamic>{};
          final count=index==1?number(d['pendingKyc']).round():index==2?number(d['pendingDeposits']).round():index==3?number(d['pendingWithdrawals']).round():index==14?unreadNotifications:0;
          if(count==0&&!active)return const SizedBox.shrink();
          return Row(mainAxisSize:MainAxisSize.min,children:[
            if(count>0)Container(
              constraints:const BoxConstraints(minWidth:18,minHeight:18),
              padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
              decoration:BoxDecoration(color:const Color(0xFFE5484D),borderRadius:BorderRadius.circular(99)),
              child:Text(count>99?'99+':'$count',style:const TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w900)),
            ),
            if(active)Container(margin:const EdgeInsets.only(left:6),width:3,height:22,decoration:BoxDecoration(color:gold,borderRadius:BorderRadius.circular(4))),
          ]);
        }),
        onTap:()=>openSection(index),
      ),
    ));
  }

  @override Widget build(BuildContext context){
    final dark=Theme.of(context).brightness==Brightness.dark;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (scaffoldKey.currentState?.isDrawerOpen == true) {
          scaffoldKey.currentState?.closeDrawer();
          return;
        }
        if (selected != 0) {
          setState(() => selected = 0);
          reload();
          return;
        }
        confirmAppExit(context);
      },
      child: Scaffold(
      key:scaffoldKey,
      drawer:Drawer(
        backgroundColor:dark?const Color(0xFF10110F):const Color(0xFFF6F4ED),
        width:MediaQuery.of(context).size.width*0.82,
        child:SafeArea(child:Column(children:[
          Padding(padding:const EdgeInsets.fromLTRB(18,18,18,16),child:Row(children:[
            Container(width:44,height:44,padding:const EdgeInsets.all(5),decoration:BoxDecoration(color:const Color(0xFF292319),borderRadius:BorderRadius.circular(13),border:Border.all(color:const Color(0xFF554628))),child:SvgPicture.asset('assets/images/monarch-codex-logo.svg')),
            const SizedBox(width:11),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('MONARCH CODEX',style:TextStyle(color:gold,fontSize:13,fontWeight:FontWeight.w900,letterSpacing:1)),
              SizedBox(height:3),Text('ADMIN CONTROL CENTRE',style:TextStyle(color:muted,fontSize:9,fontWeight:FontWeight.w800,letterSpacing:1)),
            ])),
          ])),
          Divider(color:dark?const Color(0xFF4C4029):const Color(0xFFE4DFD2),height:1),
          Padding(padding:const EdgeInsets.fromLTRB(20,16,20,7),child:Align(alignment:Alignment.centerLeft,child:Text('WORKSPACE',style:TextStyle(color:muted,fontSize:9,fontWeight:FontWeight.w900,letterSpacing:1.3)))),
          Expanded(child:ListView(padding:EdgeInsets.zero,children:[
            _navItem(0,Icons.dashboard_outlined,'Overview'),
            _navItem(1,Icons.verified_user_outlined,'KYC verification'),
            _navItem(2,Icons.receipt_long_outlined,'Deposits'),
            _navItem(3,Icons.payments_outlined,'Withdrawals'),
            _navItem(4,Icons.groups_outlined,'Members & roles'),
             _navItem(13,Icons.manage_accounts_outlined,'Manage Members'),
            _navItem(5,Icons.history_outlined,'Audit history'),
            _navItem(6,Icons.query_stats_outlined,'Analytics'),
            _navItem(7,Icons.shield_outlined,'Security centre'),
            _navItem(8,Icons.settings_outlined,'App settings'),
            if((widget.member['adminRole']??'').toString()=='super_admin') _navItem(9,Icons.admin_panel_settings_outlined,'Admin permissions'),
            if((widget.member['adminRole']??'').toString()=='super_admin') _navItem(10,Icons.link_outlined,'Online Cooperative'),
            if((widget.member['adminRole']??'').toString()=='super_admin') _navItem(11,Icons.public,'Social links'),
            if(['super_admin','main_admin'].contains((widget.member['adminRole']??'').toString())) _navItem(12,Icons.feedback_outlined,'Member feedback'),
            _navItem(14,Icons.notifications_none_rounded,'Notifications'),
             _navItem(15,Icons.support_agent,'Help & Support'),
             _navItem(16,Icons.forum_outlined,'Community'),
          ])),
          Divider(color:dark?const Color(0xFF4C4029):const Color(0xFFE4DFD2),height:1),
          ListTile(leading:const Icon(Icons.contrast,color:gold),title:const Text('Appearance',style:TextStyle(fontSize:12)),trailing:Text(widget.light?'Light':'Dark',style:const TextStyle(color:muted,fontSize:11)),onTap:(){scaffoldKey.currentState?.closeDrawer();widget.toggleTheme();}),
          ListTile(leading:const Icon(Icons.logout,color:Color(0xFFD8A29A)),title:const Text('Sign out',style:TextStyle(color:Color(0xFFD8A29A),fontSize:12)),onTap:widget.signOut),
          const SizedBox(height:8),
        ])),
      ),
      appBar:AppBar(
        title:Row(children:[SvgPicture.asset('assets/images/monarch-codex-logo.svg',width:32,height:32),const SizedBox(width:8),const Expanded(child:Text('ADMIN CONTROL CENTRE',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900)))]),
        actions:[IconButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const AppUpdaterPage())),icon:_indicatorBadge(const Icon(Icons.system_update_alt,color:gold),updateAvailable?1:0),tooltip:updateAvailable?'Update available':'Check for app updates'),IconButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>NotificationsPage(api:widget.api,dark:dark))),icon:_indicatorBadge(const Icon(Icons.notifications_none_rounded,color:gold),unreadNotifications),tooltip:unreadNotifications>0?'$unreadNotifications unread notifications':'Notifications'),IconButton(onPressed:widget.toggleTheme,icon:const Icon(Icons.contrast,color:gold),tooltip:'Toggle appearance'),IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold),tooltip:'Refresh overview')],
      ),
      body:FutureBuilder<Map<String,dynamic>>(future:data,builder:(context,snap){
        if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
        if(snap.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Icon(Icons.admin_panel_settings_outlined,color:gold,size:48),const Text('Admin dashboard could not load',style:TextStyle(fontSize:21,fontWeight:FontWeight.w900)),Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:reload,child:const Text('Retry'))]);
        final d=snap.data??{};
        return ListView(padding:const EdgeInsets.all(16),children:[
          Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),border:Border.all(color:const Color(0xFF6D5920)),gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF30250C),Color(0xFF151411),Color(0xFF101012)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('MONARCH CODEX · OPERATIONS',style:TextStyle(color:gold,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.2)),const SizedBox(height:10),
            const Text('Administrator overview',style:TextStyle(color:Colors.white,fontSize:25,fontWeight:FontWeight.w900)),const SizedBox(height:7),
            Text('Signed in as '+(widget.member['fullName']??'Administrator').toString(),style:const TextStyle(color:muted,fontSize:12)),const SizedBox(height:12),
            Text('ROLE  '+(d['role']??widget.member['adminRole']??'ADMIN').toString().replaceAll('_',' ').toUpperCase(),style:const TextStyle(color:gold,fontSize:11,fontWeight:FontWeight.w900)),
          ])),
          const SizedBox(height:15),
          GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:1.3,children:[
            _stat('TOTAL MEMBERS',d['members'],Icons.groups_outlined,dark),_stat('PENDING KYC',d['pendingKyc'],Icons.verified_user_outlined,dark),
            _stat('PENDING DEPOSITS',d['pendingDeposits'],Icons.receipt_long,dark),_stat('WITHDRAWAL QUEUE',d['pendingWithdrawals'],Icons.payments_outlined,dark),
          ]),
          const SizedBox(height:14),
          Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:dark?panel:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:dark?const Color(0xFF302E29):const Color(0xFFE4DFD2))),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('SECURITY & FINANCIAL CONTROL',style:TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:11)),SizedBox(height:8),
            Text('Financial requests must be reviewed through authorized server workflows. The app does not directly change wallet balances.',style:TextStyle(color:muted,fontSize:12,height:1.5)),
          ])),
          const SizedBox(height:14),
          Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:dark?panel:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:dark?const Color(0xFF302E29):const Color(0xFFE4DFD2))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('REVIEW & APPROVAL',style:TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:11)),const SizedBox(height:7),
            const Text('Choose a review queue from the sidebar. The secure review portal may request a fresh sign-in.',style:TextStyle(color:muted,fontSize:12,height:1.5)),const SizedBox(height:12),
            SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>openSection(1),icon:const Icon(Icons.verified_user_outlined),label:const Text('Review KYC applications'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,minimumSize:const Size.fromHeight(46)))),
            const SizedBox(height:8),
            SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>openSection(2),icon:const Icon(Icons.receipt_long),label:const Text('Review deposits'),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(44)))),
            const SizedBox(height:8),
            SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>openSection(3),icon:const Icon(Icons.payments_outlined),label:const Text('Review withdrawals'),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(44)))),
          ])),
          const SizedBox(height:12),FilledButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>RoleManagerPage(api:widget.api,dark:dark))),icon:const Icon(Icons.manage_accounts_outlined),label:const Text('Manage member roles'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,minimumSize:const Size.fromHeight(48))),
          const SizedBox(height:12),OutlinedButton.icon(onPressed:widget.signOut,icon:const Icon(Icons.logout),label:const Text('Sign out of administrator account')),
        ]);
      }),
      bottomNavigationBar: NavigationBar(
        selectedIndex: const [0, 13, 1, 2, 14].contains(selected) ? const [0, 13, 1, 2, 14].indexOf(selected) : 0,
        backgroundColor: dark ? const Color(0xFF101012) : Colors.white,
        indicatorColor: gold.withValues(alpha: .18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => openSection(const [0, 13, 1, 2, 14][index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard, color: gold), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups, color: gold), label: 'Members'),
          NavigationDestination(icon: Icon(Icons.verified_user_outlined), selectedIcon: Icon(Icons.verified_user, color: gold), label: 'KYC'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long, color: gold), label: 'Deposits'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications, color: gold), label: 'Alerts'),
        ],
      ),
    ));
  }
  Widget _stat(String label,dynamic value,IconData icon,bool dark)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:dark?panel:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:dark?const Color(0xFF302E29):const Color(0xFFE4DFD2))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:gold,size:20),const SizedBox(height:10),Text((value??'—').toString(),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:3),Text(label,style:const TextStyle(color:muted,fontSize:9,fontWeight:FontWeight.w900))]));
}


class AdminReviewQueuePage extends StatefulWidget {
  const AdminReviewQueuePage({super.key,required this.api,required this.type,required this.dark});
  final MonarchApi api;final String type;final bool dark;
  @override State<AdminReviewQueuePage> createState()=>_AdminReviewQueuePageState();
}
class _AdminReviewQueuePageState extends State<AdminReviewQueuePage>{
 late Future<Map<String,dynamic>> future;final Map<int,TextEditingController> notes={};final Set<int> busy={};
 @override void initState(){super.initState();future=widget.api.adminReviewQueue(widget.type);}
 @override void dispose(){for(final c in notes.values){c.dispose();}super.dispose();}
 void reload()=>setState(()=>future=widget.api.adminReviewQueue(widget.type));
 TextEditingController note(int id)=>notes.putIfAbsent(id,()=>TextEditingController());
 Future<void> act(Map<String,dynamic> row,String decision)async{
  final id=int.tryParse(row['id'].toString());if(id==null)return;final memo=note(id).text.trim();
  if(decision!='approved'&&memo.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Add a reason or instructions first.')));return;}
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Confirm action'),content:Text('Confirm '+decision+' request #'+id.toString()+' '+(row['currency']??'').toString()+' '+(row['amount']??'').toString()+'.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Confirm'))]));
  if(ok!=true||!mounted)return;String ref='';
  if(widget.type=='withdrawals'&&decision=='paid'){final c=TextEditingController();ref=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Transfer reference'),content:TextField(controller:c,decoration:const InputDecoration(labelText:'Actual completed transfer reference')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Continue'))]))??'';c.dispose();if(ref.isEmpty)return;}
  setState(()=>busy.add(id));try{
   if(widget.type=='kyc')await widget.api.reviewKyc(id:id,status:decision,note:memo);
   else if(widget.type=='deposits')await widget.api.reviewDeposit(id:id,decision:decision,note:memo,confirmed:true);
   else await widget.api.reviewWithdrawal(id:id,decision:decision,note:memo,paymentReference:ref,confirmed:true);
   if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Server confirmed the review decision.')));reload();}
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_workspaceError(e))));}finally{if(mounted)setState(()=>busy.remove(id));}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.type=='kyc'?'KYC verification':widget.type=='deposits'?'Deposit reviews':'Withdrawal reviews'),actions:[IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),body:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snap){
  if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
  if(snap.hasError)return ListView(padding:const EdgeInsets.all(16),children:[Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:reload,child:const Text('Retry'))]);
  final rows=(snap.data?['items'] as List? ?? []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
  if(rows.isEmpty)return const Center(child:Text('No review requests found.',style:TextStyle(color:muted)));
  return ListView(padding:const EdgeInsets.all(14),children:[Text(rows.length.toString()+' requests',style:const TextStyle(color:muted)),const SizedBox(height:8),...rows.map((r){
   final id=int.tryParse((r['id']??'0').toString())??0;final status=(r['status']??'').toString();final pending=status=='pending';final person=(r['legal_full_name']??r['full_name']??r['username']??'Member').toString();final dest=r['payoutDestination'];
   return Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Expanded(child:Text(person,style:const TextStyle(fontWeight:FontWeight.w900))),Text(status.toUpperCase(),style:const TextStyle(color:gold,fontSize:10,fontWeight:FontWeight.w900))]),
    Text('Request #'+id.toString()+' · '+(r['created_at']??r['submitted_at']??'').toString(),style:const TextStyle(color:muted,fontSize:10)),
    if(widget.type!='kyc')Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Text((r['currency']??'').toString()+' '+(r['amount']??'').toString(),style:const TextStyle(color:gold,fontSize:20,fontWeight:FontWeight.w900))),
    ...['contact_email','document_type','document_issuer_country','payment_label','payment_reference','reviewer_note'].where((k)=>r[k]!=null&&r[k].toString().isNotEmpty).map((k)=>Text(k.replaceAll('_',' ')+': '+r[k].toString(),style:const TextStyle(color:muted,fontSize:11))),
    if(dest is Map)Text('Payout: '+(dest['bankName']??'').toString()+' · '+(dest['accountName']??'').toString()+' · '+(dest['accountNumber']??'').toString(),style:const TextStyle(color:muted,fontSize:11)),
    if(pending||(widget.type=='withdrawals'&&status=='approved'))...[
     TextField(controller:note(id),maxLines:2,decoration:const InputDecoration(labelText:'Review note / rejection reason')),
     Wrap(spacing:7,runSpacing:7,children:[
      if(widget.type=='kyc')FilledButton(onPressed:busy.contains(id)?null:()=>act(r,'approved'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Approve verified connection')),
      if(widget.type=='kyc')OutlinedButton(onPressed:busy.contains(id)?null:()=>act(r,'needs_resubmission'),child:const Text('Request resubmission')),
      if(widget.type=='deposits')FilledButton(onPressed:busy.contains(id)?null:()=>act(r,'approved'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Approve & credit')),
      if(widget.type=='withdrawals'&&status=='pending')FilledButton(onPressed:busy.contains(id)?null:()=>act(r,'approved'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Approve payout')),
      if(widget.type=='withdrawals'&&status=='approved')FilledButton(onPressed:busy.contains(id)?null:()=>act(r,'paid'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Record paid')),
      OutlinedButton(onPressed:busy.contains(id)?null:()=>act(r,'rejected'),child:const Text('Reject')),
      if(busy.contains(id))const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:gold)),
     ]),
    ]
   ])));
  })]);
 }));
}

class AdminMembersPage extends StatefulWidget {
 const AdminMembersPage({super.key,required this.api,required this.dark});
 final MonarchApi api; final bool dark;
 @override State<AdminMembersPage> createState()=>_AdminMembersPageState();
}
class _AdminMembersPageState extends State<AdminMembersPage>{
 late Future<Map<String,dynamic>> future; final search=TextEditingController(); String? notice; bool busy=false;
 @override void initState(){super.initState();future=widget.api.adminMembers();}
 @override void dispose(){search.dispose();super.dispose();}
 void reload()=>setState(()=>future=widget.api.adminMembers(q:search.text.trim()));
 String err(Object e){
  if(e is DioException){
   final response=e.response;
   final data=response?.data;
   if(data is Map){final message=data['message'];if(message is String&&message.trim().isNotEmpty)return message;}
   final status=response?.statusCode;
   if(status!=null)return 'Manage Members request failed (HTTP $status). Refresh and try again. If this continues, the server administrator must check the mobile API logs and required database migrations.';
   if(e.type==DioExceptionType.connectionError||e.type==DioExceptionType.connectionTimeout||e.type==DioExceptionType.receiveTimeout)return 'Could not reach the Monarch Codex server. Check your internet connection and try again.';
  }
  return 'Could not load Manage Members. Please retry.';
 }
 Future<void> toggle(Map<String,dynamic> m,bool blocked)async{final id=(m['id'] as num).toInt();setState(()=>busy=true);try{await widget.api.setMemberBlocked(id,blocked);if(mounted)setState(()=>notice=blocked?'Member blocked.':'Member unblocked.');reload();}catch(e){if(mounted)setState(()=>notice=err(e));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> remove(Map<String,dynamic> m)async{final id=(m['id'] as num).toInt();final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete member?'),content:Text('Permanently delete '+(m['fullName']??m['username']??'this member').toString()+'? This cannot be undone.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('Delete permanently'))]));if(ok!=true)return;setState(()=>busy=true);try{await widget.api.deleteMember(id);if(mounted)setState(()=>notice='Member deleted.');reload();}catch(e){if(mounted)setState(()=>notice=err(e));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> details(Map<String,dynamic> m)async{final id=(m['id'] as num).toInt();showDialog(context:context,builder:(_)=>const Center(child:CircularProgressIndicator(color:gold)));try{final d=await widget.api.adminMember(id);if(!mounted)return;Navigator.of(context,rootNavigator:true).pop();final x=Map<String,dynamic>.from(d['member'] as Map);final wallets=(d['wallets'] as List? ??[]).whereType<Map>().toList();final kyc=(d['kyc'] as List? ??[]).whereType<Map>().toList();showDialog(context:context,builder:(c)=>AlertDialog(title:Text((x['fullName']??'Member').toString()),content:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[for(final k in ['id','uid','username','email','phone','createdAt','emailVerifiedAt','isBlocked'])Padding(padding:const EdgeInsets.only(bottom:6),child:Text(k+': '+(x[k]??'—').toString())),const Divider(),const Text('Wallets',style:TextStyle(fontWeight:FontWeight.bold)),for(final w in wallets)Text((w['currency']??'').toString()+': '+(w['balance']??'0').toString()),const SizedBox(height:8),const Text('Recent KYC',style:TextStyle(fontWeight:FontWeight.bold)),for(final k in kyc)Text((k['status']??'').toString()+' · '+(k['submittedAt']??'').toString())])),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close'))]));}catch(e){if(mounted){Navigator.of(context,rootNavigator:true).pop();ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(err(e))));}}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('MANAGE MEMBERS'),actions:[IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),body:Column(children:[Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(controller:search,onSubmitted:(_)=>reload(),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search name, email, username or UID',border:OutlineInputBorder()))),IconButton(onPressed:reload,icon:const Icon(Icons.search,color:gold))])),if(notice!=null)Padding(padding:const EdgeInsets.all(8),child:Text(notice!,style:const TextStyle(color:gold))),Expanded(child:FutureBuilder<Map<String,dynamic>>(future:future,builder:(c,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));if(s.hasError)return ListView(padding:const EdgeInsets.all(16),children:[Text(err(s.error!)),FilledButton(onPressed:reload,child:const Text('Retry'))]);final rows=(s.data?['items'] as List? ??[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();if(rows.isEmpty)return const Center(child:Text('No members found.'));return ListView.builder(itemCount:rows.length,itemBuilder:(c,i){final m=rows[i];final blocked=m['isBlocked']==true||m['isBlocked']==1;return Card(color:widget.dark?panel:Colors.white,child:ListTile(leading:CircleAvatar(backgroundColor:blocked?Colors.red.withOpacity(.15):const Color(0x332E2716),child:Icon(blocked?Icons.block:Icons.person,color:blocked?Colors.red:gold)),title:Text((m['fullName']??m['username']??'Member').toString()),subtitle:Text((m['email']??'').toString()+'\nUID: '+(m['uid']??'—').toString()+' · '+(blocked?'Blocked':'Active')),isThreeLine:true,onTap:()=>details(m),trailing:PopupMenuButton<String>(enabled:!busy,itemBuilder:(_)=>[const PopupMenuItem(value:'details',child:Text('View details')),PopupMenuItem(value:'block',child:Text(blocked?'Unblock member':'Block member')),const PopupMenuItem(value:'delete',child:Text('Delete member'))],onSelected:(v){if(v=='details')details(m);if(v=='block')toggle(m,!blocked);if(v=='delete')remove(m);},icon:const Icon(Icons.more_vert,color:gold))));});}))]));
}

class AdminAppSettingsPage extends StatelessWidget {
  const AdminAppSettingsPage({super.key, required this.dark, required this.light, required this.toggleTheme});
  final bool dark;
  final bool light;
  final VoidCallback toggleTheme;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('APP SETTINGS')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF6D5920)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF30250C), Color(0xFF151411), Color(0xFF101012)],
          ),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('MONARCH CODEX', style: TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          SizedBox(height: 8),
          Text('Your app, your workspace.', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('Manage the Android app experience here without opening the website dashboard.', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 14),
      Card(color: dark ? panel : Colors.white, child: SwitchListTile(
        value: light,
        activeThumbColor: gold,
        secondary: const Icon(Icons.contrast, color: gold),
        title: const Text('Light appearance', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Use white, light gold and black across the app.'),
        onChanged: (_) => toggleTheme(),
      )),
      Card(color: dark ? panel : Colors.white, child: ListTile(
        leading: const Icon(Icons.system_update_alt, color: gold),
        title: const Text('App updates', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Check for the latest official Monarch Codex APK.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppUpdaterPage())),
      )),
      Card(color: dark ? panel : Colors.white, child: ListTile(
        leading: const Icon(Icons.support_agent, color: gold),
        title: const Text('Administrator support', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Contact support@monarchcodex.online for app or access issues.'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => launchUrl(Uri.parse('mailto:support@monarchcodex.online?subject=Monarch%20Codex%20Admin%20App%20Support')),
      )),
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: mcCard(dark),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.shield_outlined, color: gold),
          SizedBox(width: 10),
          Expanded(child: Text('Security: role permissions and financial actions remain enforced by the server. Appearance settings do not grant additional access.', style: TextStyle(color: muted, fontSize: 12, height: 1.5))),
        ]),
      ),
    ]),
  );
}

class AdminHelpSupportPage extends StatelessWidget {
  const AdminHelpSupportPage({super.key,required this.dark});
  final bool dark;
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('ADMIN HELP & SUPPORT')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFF6D5920)),gradient:const LinearGradient(colors:[Color(0xFF30250C),Color(0xFF151411),Color(0xFF101012)])),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(Icons.support_agent,color:gold,size:30),SizedBox(height:8),
        Text('Administrator support',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),
        SizedBox(height:6),Text('Help for member management, verification queues, notifications and app updates.',style:TextStyle(color:Colors.white70,fontSize:12,height:1.5))
      ])),
      const SizedBox(height:12),
      Card(color:dark?panel:Colors.white,child:const ListTile(leading:Icon(Icons.people_alt_outlined,color:gold),title:Text('Manage Members errors'),subtitle:Text('Refresh once and note the HTTP status/message. Never share passwords, session cookies or private KYC files.'))),
      Card(color:dark?panel:Colors.white,child:const ListTile(leading:Icon(Icons.verified_user_outlined,color:gold),title:Text('Review queues'),subtitle:Text('Confirm evidence before financial approvals. Keep rejection reasons factual and record sensitive actions through authorized workflows.'))),
      Card(color:dark?panel:Colors.white,child:ListTile(leading:const Icon(Icons.email_outlined,color:gold),title:const Text('Contact technical support'),subtitle:const Text('support@monarchcodex.online'),onTap:()=>launchUrl(Uri.parse('mailto:support@monarchcodex.online?subject=Monarch%20Codex%20Admin%20Support'))))
    ]));
}

class AdminDataPage extends StatefulWidget{
 const AdminDataPage({super.key,required this.api,required this.kind,required this.dark});
 final MonarchApi api;final String kind;final bool dark;
 @override State<AdminDataPage> createState()=>_AdminDataPageState();
}
class _AdminDataPageState extends State<AdminDataPage>{
 late Future<Map<String,dynamic>> future;
 @override void initState(){super.initState();future=load();}
 Future<Map<String,dynamic>> load()=>widget.kind=='audit'?widget.api.adminAuditEvents():widget.kind=='analytics'?widget.api.adminAnalytics():widget.api.adminSecurity();
 void reload()=>setState(()=>future=load());
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.kind=='audit'?'Audit history':widget.kind=='analytics'?'Analytics':'Security centre'),actions:[IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),body:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snap){
  if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
  if(snap.hasError)return ListView(padding:const EdgeInsets.all(16),children:[Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:reload,child:const Text('Retry'))]);
  final d=snap.data??{};final widgets=<Widget>[];
  Widget metric(String label,dynamic value)=>Card(color:widget.dark?panel:Colors.white,child:ListTile(title:Text(label,style:const TextStyle(color:muted,fontSize:11)),subtitle:Text(value==null?'—':value.toString(),style:const TextStyle(color:gold,fontSize:21,fontWeight:FontWeight.w900))));
  if(widget.kind=='analytics'){
   final k=d['kyc'] is Map?Map<String,dynamic>.from(d['kyc']):<String,dynamic>{};final dep=d['deposits'] is Map?Map<String,dynamic>.from(d['deposits']):<String,dynamic>{};final w=d['withdrawals'] is Map?Map<String,dynamic>.from(d['withdrawals']):<String,dynamic>{};
   widgets.addAll([metric('Total members',d['members']),metric('KYC total',k['total']),metric('KYC pending',k['pending']),metric('KYC approved',k['approved']),metric('Deposits pending',dep['pending']),metric('Approved deposit volume',dep['approvedAmount']),metric('Withdrawals pending',w['pending']),metric('Completed payout volume',w['paidAmount'])]);
  }else if(widget.kind=='audit'){
   final rows=(d['events'] as List? ?? []).whereType<Map>().toList();widgets.add(Text(rows.length.toString()+' recent audit events',style:const TextStyle(color:muted)));
   for(final e in rows){widgets.add(Card(color:widget.dark?panel:Colors.white,child:ListTile(title:Text((e['action']??'Action').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),subtitle:Text((e['target_type']??'').toString()+' #'+(e['target_id']??'').toString()+' · '+(e['username']??'').toString()+' · '+(e['created_at']??'').toString()))));}
  }else{
   final admins=(d['admins'] as List? ?? []).whereType<Map>().toList();final events=(d['securityEvents'] as List? ?? []).whereType<Map>().toList();final session=d['session'] is Map?Map<String,dynamic>.from(d['session']):<String,dynamic>{};
   widgets.addAll([metric('Authenticated session',session['authenticated']==true?'Verified':'Unknown'),metric('Fresh re-authentication',session['reauthenticationAvailable']==true?'Available':'Not exposed by backend'),metric('Financial second confirmation',session['secondConfirmationRequired']==true?'Required':'Unknown'),const Text('Administrator accounts',style:TextStyle(fontWeight:FontWeight.w900,fontSize:16))]);
   for(final a in admins){widgets.add(ListTile(leading:const Icon(Icons.shield_outlined,color:gold),title:Text((a['full_name']??a['username']??'Admin').toString()),subtitle:Text((a['role']??'').toString()+' · '+(a['is_active']==1?'Active':'Inactive'))));}
   widgets.add(const Text('Security events',style:TextStyle(fontWeight:FontWeight.w900,fontSize:16)));
   for(final e in events){widgets.add(ListTile(leading:const Icon(Icons.event_note,color:gold),title:Text((e['action']??'Event').toString()),subtitle:Text((e['target_type']??'').toString()+' · '+(e['created_at']??'').toString())));}
  }
  return ListView(padding:const EdgeInsets.all(14),children:widgets);
 }));
}


class RoleManagerPage extends StatefulWidget {
 const RoleManagerPage({super.key,required this.api,required this.dark}); final MonarchApi api; final bool dark;
 @override State<RoleManagerPage> createState()=>_RoleManagerPageState();
}
class _RoleManagerPageState extends State<RoleManagerPage>{
 late Future<Map<String,dynamic>> future; final roleName=TextEditingController(),roleDescription=TextEditingController(); String? error,notice; bool saving=false;
 @override void initState(){super.initState();future=widget.api.adminRoles();}
 void reload()=>setState(()=>future=widget.api.adminRoles());
 String msg(Object e){if(e is DioException&&e.response?.data is Map)return ((e.response!.data as Map)['message']??'Request failed').toString();return e.toString().replaceFirst('Exception: ','');}
 Future<void> save({int? id,String? name,String? description,bool active=true})async{setState(()=>saving=true);try{await widget.api.saveRole(roleId:id,roleName:name??roleName.text.trim(),description:description??roleDescription.text.trim(),isActive:active);roleName.clear();roleDescription.clear();if(mounted)setState(()=>notice='Role options saved.');reload();}catch(e){if(mounted)setState(()=>error=msg(e));}finally{if(mounted)setState(()=>saving=false);}}
 Future<void> review(int id,String decision)async{try{await widget.api.reviewRoleRequest(requestId:id,decision:decision);if(mounted)setState(()=>notice='Request reviewed.');reload();}catch(e){if(mounted)setState(()=>error=msg(e));}}
 Future<void> assign(int memberId,int roleId,String action)async{try{await widget.api.assignRole(memberId:memberId,roleId:roleId,action:action);if(mounted)setState(()=>notice=action=='assign'?'Role assigned.':'Role removed.');reload();}catch(e){if(mounted)setState(()=>error=msg(e));}}
 @override void dispose(){roleName.dispose();roleDescription.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('MEMBER ROLE MANAGEMENT'),actions:[IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),body:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snap){
 if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
 if(snap.hasError)return ListView(padding:const EdgeInsets.all(16),children:[Message(text:msg(snap.error!),success:false),FilledButton(onPressed:reload,child:const Text('Retry'))]);
 final d=snap.data??{};final roles=List<Map<String,dynamic>>.from((d['roles'] as List? ??[]).map((x)=>Map<String,dynamic>.from(x as Map)));final requests=List<Map<String,dynamic>>.from((d['requests'] as List? ??[]).map((x)=>Map<String,dynamic>.from(x as Map)));final members=List<Map<String,dynamic>>.from((d['members'] as List? ??[]).map((x)=>Map<String,dynamic>.from(x as Map)));final assignments=List<Map<String,dynamic>>.from((d['assignments'] as List? ??[]).map((x)=>Map<String,dynamic>.from(x as Map)));final dark=widget.dark;
 return ListView(padding:const EdgeInsets.all(15),children:[
 if(error!=null)Message(text:error!,success:false),if(notice!=null)Message(text:notice!,success:true),
 Container(padding:const EdgeInsets.all(16),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('ADD ROLE OPTION',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:10),TextField(controller:roleName,decoration:const InputDecoration(labelText:'Role name')),const SizedBox(height:10),TextField(controller:roleDescription,maxLines:2,decoration:const InputDecoration(labelText:'Description')),const SizedBox(height:12),FilledButton(onPressed:saving?null:()=>save(),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:Text(saving?'Saving…':'Add role'))])),
 const SizedBox(height:14),Text('ROLE CATALOGUE ('+roles.length.toString()+')',style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:8),
 ...roles.map((r)=>_roleCard(r,dark)),
 const SizedBox(height:14),Text('PENDING REQUESTS ('+requests.length.toString()+')',style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:8),
 if(requests.isEmpty)const Message(text:'No pending role requests.',success:true),
 ...requests.map((r)=>Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(14),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((r['full_name']??'Member').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),Text((r['email']??'').toString(),style:const TextStyle(color:muted,fontSize:12)),const SizedBox(height:6),Text('Requested: '+(r['role_name']??'').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w800)),Text((r['message']??'').toString(),style:const TextStyle(color:muted,fontSize:12)),const SizedBox(height:10),Row(children:[Expanded(child:FilledButton(onPressed:()=>review((r['id'] as num).toInt(),'approve'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Approve'))),const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()=>review((r['id'] as num).toInt(),'reject'),child:const Text('Reject')))])]))),
 const SizedBox(height:14),Text('MANUAL ASSIGNMENT ('+members.length.toString()+' newest members)',style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:8),
 ...members.map((m)=>_memberAssign(m,roles,assignments,dark))
 ]);}));
 Widget _roleCard(Map<String,dynamic> r,bool dark){final name=TextEditingController(text:(r['role_name']??'').toString()),desc=TextEditingController(text:(r['description']??'').toString());bool active=r['is_active']==1||r['is_active']==true;return Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(12),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Role name')),const SizedBox(height:8),TextField(controller:desc,decoration:const InputDecoration(labelText:'Description')),StatefulBuilder(builder:(context,setLocal)=>SwitchListTile(contentPadding:EdgeInsets.zero,value:active,onChanged:(v)=>setLocal(()=>active=v),title:const Text('Available for requests'))),Text('Assigned: '+(r['assigned_count']??0).toString(),style:const TextStyle(color:muted,fontSize:11)),FilledButton(onPressed:()=>save(id:(r['id'] as num).toInt(),name:name.text.trim(),description:desc.text.trim(),active:active),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Save role changes'))]));}
 Widget _memberAssign(Map<String,dynamic> m,List<Map<String,dynamic>> roles,List<Map<String,dynamic>> assignments,bool dark){final active=roles.where((r)=>r['is_active']==1||r['is_active']==true).toList();final memberId=(m['id'] as num).toInt();final owned=assignments.where((a)=>(a['member_id'] as num).toInt()==memberId).toList();int? selected=active.isEmpty?null:(active.first['id'] as num).toInt();return Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(12),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((m['full_name']??'Member').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),Text((m['email']??'').toString(),style:const TextStyle(color:muted,fontSize:11)),if(owned.isNotEmpty)...owned.map((a)=>ListTile(dense:true,contentPadding:EdgeInsets.zero,title:Text((a['role_name']??'Role').toString()),trailing:IconButton(onPressed:()=>assign(memberId,(a['role_id'] as num).toInt(),'remove'),icon:const Icon(Icons.remove_circle_outline,color:Color(0xFFFF8D85)),tooltip:'Remove role'))),StatefulBuilder(builder:(context,setLocal)=>Row(children:[Expanded(child:DropdownButton<int>(isExpanded:true,value:selected,items:active.map((r)=>DropdownMenuItem<int>(value:(r['id'] as num).toInt(),child:Text((r['role_name']??'').toString(),overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setLocal(()=>selected=v))),IconButton(onPressed:selected==null?null:()=>assign(memberId,selected!,'assign'),icon:const Icon(Icons.add_circle,color:gold),tooltip:'Assign role')]))]));}
}

class SovereignAdminShell extends StatefulWidget {
  const SovereignAdminShell({super.key, required this.api, required this.member, required this.signOut, required this.light, required this.toggleTheme});
  final MonarchApi api;
  final Map<String, dynamic> member;
  final Future<void> Function() signOut;
  final bool light;
  final VoidCallback toggleTheme;
  @override
  State<SovereignAdminShell> createState() => _SovereignAdminShellState();
}

class _SovereignAdminShellState extends State<SovereignAdminShell> {
  final company = TextEditingController(text: 'Sovereign Desk');
  final message = TextEditingController(text: 'Request Partner role for the Sovereign Desk company.');
  bool busy = false;
  String? error, notice;
  int selectedDestination = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const List<Map<String, dynamic>> deskDestinations = [
    {'title': 'Overview', 'route': '/sovereign-admin', 'icon': Icons.dashboard_outlined},
    {'title': 'Trading signals', 'route': '/sovereign-admin/signals', 'icon': Icons.show_chart},
    {'title': 'Guidance & learning', 'route': '/sovereign-admin/guidance', 'icon': Icons.school_outlined},
    {'title': 'Access requests', 'route': '/sovereign-admin/access', 'icon': Icons.verified_user_outlined},
    {'title': 'Signal access', 'route': '/sovereign-admin/signal-access', 'icon': Icons.key_outlined},
    {'title': 'Member conversations', 'route': '/sovereign-admin/chat', 'icon': Icons.forum_outlined},
    {'title': 'Announcements', 'route': '/sovereign-admin/announcements', 'icon': Icons.campaign_outlined},
    {'title': 'Homepage events', 'route': '/sovereign-admin/events', 'icon': Icons.event_outlined},
    {'title': 'Trade watchlist', 'route': '/sovereign-admin/watchlist', 'icon': Icons.bookmark_border},
    {'title': 'Governance', 'route': '/sovereign-admin/governance', 'icon': Icons.gavel_outlined},
    {'title': 'Activity log', 'route': '/sovereign-admin/activity', 'icon': Icons.history},
    {'title': 'Telegram groups & channels', 'route': '/sovereign-admin/telegram', 'icon': Icons.send_rounded},
    {'title': 'Live markets', 'route': '/market-movers.html', 'icon': Icons.public},
  ];

  @override
  void dispose() {
    company.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> requestPartner() async {
    setState(() => busy = true);
    try {
      await widget.api.requestSovereignPartner(companyName: company.text.trim(), message: message.text.trim());
      if (mounted) setState(() => notice = 'Partner request submitted for review.');
    } catch (e) {
      if (mounted) setState(() => error = e is DioException && e.response?.data is Map
          ? ((e.response!.data as Map)['message'] ?? 'Request failed').toString()
          : e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openDeskSection(String route, {int? destination}) async {
    if (destination != null && mounted) setState(() => selectedDestination = destination);
    _scaffoldKey.currentState?.closeDrawer();
    const sections = <String,String>{
      '/sovereign-admin':'overview','/sovereign-admin/signals':'signals',
      '/sovereign-admin/guidance':'guidance','/sovereign-admin/mentorship':'guidance',
      '/sovereign-admin/access':'access','/sovereign-admin/signal-access':'signal-access',
      '/sovereign-admin/chat':'chat','/sovereign-admin/announcements':'announcements',
      '/sovereign-admin/events':'events','/sovereign-admin/watchlist':'watchlist',
      '/sovereign-admin/governance':'governance','/sovereign-admin/activity':'activity',
      '/sovereign-admin/telegram':'telegram',
      '/market-movers.html':'markets',
    };
    final section=sections[route]??'overview';
    final title=deskDestinations.firstWhere((x)=>x['route']==route,orElse:()=>{'title':'Sovereign Desk'})['title'] as String;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => section == 'telegram'
          ? TelegramAdminPage(api: widget.api, member: widget.member)
          : SovereignDeskSectionPage(api: widget.api, section: section, title: title),
    ));
    if(mounted)setState(()=>selectedDestination=0);
  }

  void showMoreDestinations() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF101012) : Colors.white,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text('SOVEREIGN DESK TOOLS', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
            for (var i = 1; i < deskDestinations.length; i++)
              ListTile(
                leading: Icon(deskDestinations[i]['icon'] as IconData, color: gold),
                title: Text(deskDestinations[i]['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openDeskSection(deskDestinations[i]['route'] as String, destination: i);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _hero(bool dark) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFF6D5920)),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF30250C), Color(0xFF151411), Color(0xFF101012)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 44, height: 44, padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: const Color(0xFF292319), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6D5920))),
            child: SvgPicture.asset('assets/images/monarch-codex-logo.svg'),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('SOVEREIGN DESK', style: TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.3))),
        ]),
        const SizedBox(height: 18),
        const Text('Command centre', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
        const SizedBox(height: 8),
        Text('Signed in as ' + (widget.member['fullName'] ?? 'Sovereign Desk administrator').toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 12),
        const Text('Signals, access and community operations in a workspace separate from Monarch Codex financial administration.', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
      ],
    ),
  );

  Widget _quickAction({required String title, required String subtitle, required IconData icon, required VoidCallback onTap}) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: gold.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: gold),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 11, height: 1.35)),
          ])),
          const Icon(Icons.chevron_right, color: gold),
        ]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) confirmAppExit(context);
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          leading: Builder(builder: (context) => IconButton(
            tooltip: 'Open Sovereign Desk navigation',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded, color: gold),
          )),
          title: Row(children: [
            SvgPicture.asset('assets/images/monarch-codex-logo.svg', width: 32, height: 32),
            const SizedBox(width: 8),
            const Expanded(child: Text('SOVEREIGN DESK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
          ]),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppUpdaterPage())),
              icon: const Icon(Icons.system_update_alt, color: gold),
              tooltip: 'Check for app updates',
            ),
            IconButton(onPressed: widget.toggleTheme, icon: const Icon(Icons.contrast, color: gold), tooltip: 'Toggle appearance'),
          ],
        ),
        drawer: Drawer(
          backgroundColor: dark ? const Color(0xFF10110F) : const Color(0xFFF6F4ED),
          child: SafeArea(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Row(children: [
                Container(width: 46, height: 46, padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF292319), borderRadius: BorderRadius.circular(14)), child: SvgPicture.asset('assets/images/monarch-codex-logo.svg')),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('MONARCH CODEX', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  SizedBox(height: 4),
                  Text('SOVEREIGN DESK ADMIN', style: TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .8)),
                ])),
              ]),
            ),
            const Divider(),
            Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
              for (var i = 0; i < deskDestinations.length; i++)
                ListTile(
                  selected: selectedDestination == i,
                  selectedTileColor: gold.withValues(alpha: .12),
                  leading: Icon(deskDestinations[i]['icon'] as IconData, color: selectedDestination == i ? gold : muted),
                  title: Text(deskDestinations[i]['title'] as String, style: TextStyle(fontWeight: selectedDestination == i ? FontWeight.w900 : FontWeight.w600, color: selectedDestination == i ? gold : null)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => openDeskSection(deskDestinations[i]['route'] as String, destination: i),
                ),
            ])),
            const Divider(),
            ListTile(leading: const Icon(Icons.contrast, color: gold), title: const Text('Appearance'), trailing: Text(widget.light ? 'Light' : 'Dark', style: const TextStyle(color: muted)), onTap: widget.toggleTheme),
            ListTile(leading: const Icon(Icons.logout, color: Color(0xFFD8A29A)), title: const Text('Sign out', style: TextStyle(color: Color(0xFFD8A29A))), onTap: widget.signOut),
          ])),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _hero(dark),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('WORKSPACE SHORTCUTS', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: .8))),
              TextButton.icon(onPressed: showMoreDestinations, icon: const Icon(Icons.grid_view_rounded, size: 17), label: const Text('All tools')),
            ]),
            _quickAction(
              title: 'Manage trading signals',
              subtitle: 'Publish signals, preserve revisions and record outcomes.',
              icon: Icons.show_chart_rounded,
              onTap: () => openDeskSection('/sovereign-admin/signals', destination: 1),
            ),
            _quickAction(
              title: 'Review access requests',
              subtitle: 'Review member access and signal subscription requests.',
              icon: Icons.verified_user_outlined,
              onTap: () => openDeskSection('/sovereign-admin/access', destination: 3),
            ),
            _quickAction(
              title: 'Member conversations',
              subtitle: 'Open member support and conversation management.',
              icon: Icons.forum_outlined,
              onTap: () => openDeskSection('/sovereign-admin/chat', destination: 5),
            ),
            _quickAction(
              title: 'Announcements & events',
              subtitle: 'Manage member updates, events and notices.',
              icon: Icons.campaign_outlined,
              onTap: () => openDeskSection('/sovereign-admin/announcements', destination: 6),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: mcCard(dark),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PARTNER ROLE REQUEST', style: TextStyle(color: gold, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('Request Partner status for the company. This request goes to Monarch Codex administrators and does not grant access automatically.', style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
                const SizedBox(height: 12),
                TextField(controller: company, decoration: const InputDecoration(labelText: 'Company / partner name')),
                const SizedBox(height: 10),
                TextField(controller: message, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason for request')),
                const SizedBox(height: 12),
                if (error != null) Message(text: error!, success: false),
                if (notice != null) Message(text: notice!, success: true),
                FilledButton(
                  onPressed: busy ? null : requestPartner,
                  style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink, minimumSize: const Size.fromHeight(48)),
                  child: Text(busy ? 'Submitting…' : 'Request Partner role'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            const Text(
              'Security note: Sovereign Desk admin tools open in the secured website workspace today. Native in-app management requires dedicated authenticated API endpoints for each tool.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.45),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: widget.signOut, icon: const Icon(Icons.logout), label: const Text('Sign out of Sovereign Desk')),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedDestination == 0 ? 0 : selectedDestination == 1 ? 1 : selectedDestination == 3 ? 2 : selectedDestination == 5 ? 3 : 4,
          backgroundColor: dark ? const Color(0xFF101012) : Colors.white,
          indicatorColor: gold.withValues(alpha: .18),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) {
            if (index == 0) {
              setState(() => selectedDestination = 0);
            } else if (index == 1) {
              openDeskSection('/sovereign-admin/signals', destination: 1);
            } else if (index == 2) {
              openDeskSection('/sovereign-admin/access', destination: 3);
            } else if (index == 3) {
              openDeskSection('/sovereign-admin/chat', destination: 5);
            } else {
              showMoreDestinations();
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard, color: gold), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.show_chart), selectedIcon: Icon(Icons.show_chart, color: gold), label: 'Signals'),
            NavigationDestination(icon: Icon(Icons.verified_user_outlined), selectedIcon: Icon(Icons.verified_user, color: gold), label: 'Access'),
            NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum, color: gold), label: 'Members'),
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view, color: gold), label: 'More'),
          ],
        ),
      ),
    );
  }
}

class KycStatusPage extends StatefulWidget {
  const KycStatusPage({super.key, required this.api, required this.dark});
  final MonarchApi api;
  final bool dark;
  @override State<KycStatusPage> createState() => _KycStatusPageState();
}
class _KycStatusPageState extends State<KycStatusPage> {
  late Future<Map<String,dynamic>> future;
  @override void initState(){super.initState();future=widget.api.kycStatus();}
  void reload()=>setState(()=>future=widget.api.kycStatus());
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snap){
    if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(snap.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Identity verification',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:reload,child:const Text('Retry'))]);
    final d=snap.data??{};final status=(d['status']??'not_submitted').toString().toLowerCase();final note=(d['reviewerNote']??'').toString();
    final label={'not_submitted':'Not submitted','pending':'Pending review','approved':'Approved','rejected':'Needs correction','needs_resubmission':'Resubmission required'}[status]??status.replaceAll('_',' ');
    final color=status=='approved'?const Color(0xFF68D99B):(status=='rejected'||status=='needs_resubmission'?const Color(0xFFFF8D85):gold);
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('Identity verification',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),const SizedBox(height:5),
      const Text('Your verification status is retrieved securely from your account.',style:TextStyle(color:muted,fontSize:12)),const SizedBox(height:14),
      Container(padding:const EdgeInsets.all(18),decoration:mcCard(widget.dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('CURRENT STATUS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:10,letterSpacing:1.1)),const SizedBox(height:9),
        Text(label.toUpperCase(),style:TextStyle(color:color,fontWeight:FontWeight.w900,fontSize:20)),
        if(d['submittedAt']!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text('Last submitted: '+d['submittedAt'].toString(),style:const TextStyle(color:muted,fontSize:11))),
        if(note.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Text('Reviewer note: '+note,style:const TextStyle(color:muted,fontSize:12,height:1.5))),
        const SizedBox(height:12),
        if(status=='approved')const Text('Your identity verification is approved. No further submission is needed.',style:TextStyle(color:muted,fontSize:12,height:1.5))
        else if(status=='pending')const Text('Your application is awaiting review. Please wait for the review result before submitting again.',style:TextStyle(color:muted,fontSize:12,height:1.5))
        else const Text('Continue to the secure verification form to submit your details or correct a returned application.',style:TextStyle(color:muted,fontSize:12,height:1.5)),
      ])),
      const SizedBox(height:12),
      if(status!='approved'&&status!='pending')FilledButton.icon(onPressed:()=>launchUrl(Uri.parse('$site/kyc'),mode:LaunchMode.externalApplication),icon:const Icon(Icons.open_in_new),label:const Text('Open secure KYC form'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,minimumSize:const Size.fromHeight(48))),
      OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Refresh verification status')),
    ]);
  });
}

class ReferralsPage extends StatefulWidget {
  const ReferralsPage({super.key, required this.api, required this.dark});
  final MonarchApi api;
  final bool dark;
  @override State<ReferralsPage> createState()=>_ReferralsPageState();
}
class _ReferralsPageState extends State<ReferralsPage>{
  late Future<Map<String,dynamic>> future;
  @override void initState(){super.initState();future=widget.api.referrals();}
  void reload()=>setState(()=>future=widget.api.referrals());
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snap){
    if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(snap.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Referrals',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:reload,child:const Text('Retry'))]);
    final d=snap.data??{};final link=(d['referralLink']??'').toString();final rows=(d['referrals'] as List? ??[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('Your referrals',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),const SizedBox(height:5),
      const Text('People attributed to your referral code from the account database.',style:TextStyle(color:muted,fontSize:12)),const SizedBox(height:14),
      Container(padding:const EdgeInsets.all(18),decoration:mcCard(widget.dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('RECORDED REFERRALS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:10,letterSpacing:1.1)),const SizedBox(height:7),
        Text((d['referralCount']??rows.length).toString(),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900)),
        const SizedBox(height:12),const Text('YOUR INVITE LINK',style:TextStyle(color:muted,fontWeight:FontWeight.w800,fontSize:10)),const SizedBox(height:6),
        SelectableText(link,style:const TextStyle(color:gold,fontWeight:FontWeight.w800,fontSize:12)),
        const SizedBox(height:8),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:link.isEmpty?null:(){Clipboard.setData(ClipboardData(text:link));ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Referral link copied')));},icon:const Icon(Icons.link),label:const Text('Copy referral link')),
          OutlinedButton.icon(onPressed:((d['uid']??d['monarchUid']??'').toString().isEmpty)?null:(){Clipboard.setData(ClipboardData(text:(d['uid']??d['monarchUid']).toString()));ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Monarch UID copied')));},icon:const Icon(Icons.copy),label:const Text('Copy Monarch UID')),
        ]),
      ])),
      const SizedBox(height:14),Row(children:[const Expanded(child:Text('Referral history',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900))),IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),
      if(rows.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:20),child:Center(child:Text('No referred members are recorded yet.',style:TextStyle(color:muted)))),
      ...rows.map((r)=>Container(margin:const EdgeInsets.only(bottom:9),padding:const EdgeInsets.all(13),decoration:mcCard(widget.dark),child:Row(children:[
        const CircleAvatar(backgroundColor:Color(0x332E2716),child:Icon(Icons.person_outline,color:gold)),
        const SizedBox(width:11),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((r['fullName']??'Monarch member').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
          if((r['username']??'').toString().isNotEmpty)Text('@'+r['username'].toString(),style:const TextStyle(color:muted,fontSize:11)),
          if((r['monarchId']??'').toString().isNotEmpty)Text(r['monarchId'].toString(),style:const TextStyle(color:gold,fontSize:10)),
          if(r['joinedAt']!=null)Text('Joined: '+r['joinedAt'].toString(),style:const TextStyle(color:muted,fontSize:10)),
        ])),
      ]))),
    ]);
  });
}

class TransactionsPage extends StatefulWidget{
  const TransactionsPage({super.key,required this.api,required this.dark});final MonarchApi api;final bool dark;
  @override State<TransactionsPage> createState()=>_TransactionsPageState();
}
class _TransactionsPageState extends State<TransactionsPage>{
  late Future<Map<String,dynamic>> data;
  @override void initState(){super.initState();data=widget.api.transactions();}
  void reload()=>setState(()=>data=widget.api.transactions());
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:data,builder:(context,snap){
    if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(snap.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Transaction history',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:reload,child:const Text('Try again'))]);
    final d=snap.data??{};final rows=<Map<String,dynamic>>[];
    for(final v in (d['transactions'] as List? ?? [])){if(v is Map)rows.add({...Map<String,dynamic>.from(v),'_kind':'Ledger'});}
    for(final v in (d['deposits'] as List? ?? [])){if(v is Map)rows.add({...Map<String,dynamic>.from(v),'_kind':'Deposit'});}
    for(final v in (d['withdrawals'] as List? ?? [])){if(v is Map)rows.add({...Map<String,dynamic>.from(v),'_kind':'Withdrawal'});}
    rows.sort((a,b)=>(b['created_at']?.toString()??'').compareTo(a['created_at']?.toString()??''));
    return ListView(padding:const EdgeInsets.all(15),children:[
      Row(children:[const Expanded(child:Text('Transaction history',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900))),IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),
      const Text('Recorded activity and request status from your account ledger.',style:TextStyle(color:muted,fontSize:12)),const SizedBox(height:12),
      if(rows.isEmpty)const Padding(padding:EdgeInsets.only(top:35),child:Center(child:Text('No transaction records yet.',style:TextStyle(color:muted)))),
      ...rows.map((row){
        final kind=(row['_kind']??'Transaction').toString();final status=(row['status']??(kind=='Ledger'?'completed':'recorded')).toString();final amount=number(row['amount']);final currency=(row['currency']??'').toString();final ref=(row['reference']??row['payment_reference']??'—').toString();
        final color=status=='rejected'?const Color(0xFFFF8D85):((status=='pending'||status=='approved')?gold:const Color(0xFF68D99B));
        return Container(margin:const EdgeInsets.only(bottom:9),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:widget.dark?panel:Colors.white,borderRadius:BorderRadius.circular(15),border:Border.all(color:widget.dark?const Color(0xFF302E29):const Color(0xFFE4DFD2))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(kind.toUpperCase(),style:const TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:10))),Text(status.replaceAll('_',' ').toUpperCase(),style:TextStyle(color:color,fontSize:9,fontWeight:FontWeight.w900))]),
          const SizedBox(height:8),Text(currency+' '+amount.abs().toStringAsFixed(2),style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
          const SizedBox(height:5),Text('Ref: '+ref,style:const TextStyle(color:muted,fontSize:11)),
          if(row['payment_label']!=null)Text('Payment: '+row['payment_label'].toString(),style:const TextStyle(color:muted,fontSize:11)),
          if(row['reviewer_note']!=null&&row['reviewer_note'].toString().isNotEmpty)Text(row['reviewer_note'].toString(),style:const TextStyle(color:muted,fontSize:11)),
        ]));
      }),
    ]);
  });
}

class DepositPage extends StatefulWidget{
  const DepositPage({super.key,required this.api,required this.dark,required this.onDone});final MonarchApi api;final bool dark;final VoidCallback onDone;
  @override State<DepositPage> createState()=>_DepositPageState();
}
class _DepositPageState extends State<DepositPage>{
  final form=GlobalKey<FormState>();final amount=TextEditingController(),reference=TextEditingController(),note=TextEditingController();late Future<Map<String,dynamic>> options;
  String currency='NGN',methodId='',error='',success='';PlatformFile? proof;bool busy=false;
  @override void initState(){super.initState();options=widget.api.depositOptions();}
  @override void dispose(){amount.dispose();reference.dispose();note.dispose();super.dispose();}
  Future<void> chooseProof()async{final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['jpg','jpeg','png','webp','pdf'],withData:true);if(r!=null&&r.files.isNotEmpty&&mounted)setState(()=>proof=r.files.first);}
  Future<void> _copyDepositValue(String value,String label) async {
    if(value.trim().isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No payment detail is available to copy.')));return;}
    try {
      await Clipboard.setData(ClipboardData(text:value));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(label.toLowerCase()+' copied.'),duration:const Duration(seconds:2)));
    } catch (_) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Copy failed. Please select and copy the detail manually.')));
    }
  }
  Future<void> submit()async{
    if(!form.currentState!.validate())return;if(proof==null){setState(()=>error='Attach your payment receipt before submitting.');return;}
    setState(() { busy=true; error=''; success=''; });
    try{final r=await widget.api.submitDeposit(currency:currency,amount:amount.text.trim(),methodId:methodId,reference:reference.text.trim(),note:note.text.trim(),proof:proof!);if(!mounted)return;setState(() { success=(r['message']??'Deposit request submitted.').toString(); amount.clear(); reference.clear(); note.clear(); proof=null; methodId=''; });widget.onDone();}
    catch(e){if(mounted)setState(()=>error=_workspaceError(e));}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:options,builder:(context,snap){
    if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(snap.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Deposit',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:()=>setState(()=>options=widget.api.depositOptions()),child:const Text('Retry'))]);
    final d=snap.data??{};final methods=(d['methods'] as List? ?? []).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).where((m)=>m['currency']==currency).toList();
    if(!methods.any((m)=>m['id'].toString()==methodId))methodId=methods.isNotEmpty?methods.first['id'].toString():'';
    final selected=methods.firstWhere((m)=>m['id'].toString()==methodId,orElse:()=>methods.isNotEmpty?methods.first:<String,dynamic>{});
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('Make a deposit',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),const SizedBox(height:5),const Text('Submit transfer details and your receipt for administrator review.',style:TextStyle(color:muted,fontSize:12)),const SizedBox(height:13),
      if(error.isNotEmpty)Message(text:error,success:false),if(success.isNotEmpty)Message(text:success,success:true),
      Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(initialValue:currency,decoration:const InputDecoration(labelText:'Deposit currency'),items:const[DropdownMenuItem(value:'NGN',child:Text('Nigerian Naira (NGN)')),DropdownMenuItem(value:'USD',child:Text('US Dollar (USD)'))],onChanged:busy?null:(v)=>setState(() { currency=v??'NGN'; methodId=''; })),
        const SizedBox(height:10),if(methods.isEmpty)const Message(text:'No active payment methods are configured for this currency. Contact support.',success:false),
        if(methods.isNotEmpty)DropdownButtonFormField<String>(initialValue:methodId,isExpanded:true,decoration:const InputDecoration(labelText:'Payment destination'),items:methods.map((m)=>DropdownMenuItem(value:m['id'].toString(),child:Text((m['label']??m['method_type']??'Payment method').toString(),overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:(v)=>setState(()=>methodId=v??'')),
        if(methods.isNotEmpty)Container(margin:const EdgeInsets.only(top:10),padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:widget.dark?panel:Colors.white,borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFF6D5920))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((selected['label']??'Payment details').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:7),
          ...['bank_name','account_name','account_number','wallet_network','wallet_asset','wallet_address','instructions'].where((k)=>selected[k]!=null&&selected[k].toString().trim().isNotEmpty).map((k){
            final value=selected[k].toString().trim();
            final label=k.replaceAll('_',' ').toUpperCase();
            final copyable=['bank_name','account_name','account_number','wallet_address'].contains(k);
            return Padding(padding:const EdgeInsets.only(bottom:8),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(label,style:const TextStyle(fontSize:10,color:muted,fontWeight:FontWeight.w800,letterSpacing:.4)),
                const SizedBox(height:3),
                SelectableText(value,style:const TextStyle(fontSize:12,color:muted,height:1.4)),
              ])),
              if(copyable)Padding(padding:const EdgeInsets.only(left:8),child:OutlinedButton.icon(
                onPressed:()=>_copyDepositValue(value,label),
                icon:const Icon(Icons.copy,size:14,color:gold),
                label:const Text('Copy',style:TextStyle(fontSize:11)),
                style:OutlinedButton.styleFrom(foregroundColor:gold,side:const BorderSide(color:Color(0xFF6D5920)),padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),minimumSize:const Size(0,34),tapTargetSize:MaterialTapTargetSize.shrinkWrap),
              )),
            ]));
          }),
        ])),
        const SizedBox(height:10),TextFormField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount to deposit'),validator:(v){final n=double.tryParse(v??'');return n==null||n<=0?'Enter a valid amount':null;}),
        const SizedBox(height:10),TextFormField(controller:reference,decoration:const InputDecoration(labelText:'Transfer reference'),validator:(v)=>v==null||v.trim().isEmpty?'Enter your transfer reference':null),
        const SizedBox(height:10),TextFormField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Note (optional)')),
        const SizedBox(height:10),OutlinedButton.icon(onPressed:busy?null:chooseProof,icon:const Icon(Icons.attach_file,color:gold),label:Text(proof==null?'Attach receipt (JPG, PNG, WEBP or PDF)':proof!.name)),
        const SizedBox(height:12),FilledButton(onPressed:busy||methods.isEmpty?null:submit,style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:Colors.black,minimumSize:const Size.fromHeight(50)),child:busy?const CircularProgressIndicator(color:Colors.black):const Text('SUBMIT DEPOSIT FOR REVIEW',style:TextStyle(fontWeight:FontWeight.w900))),
        const SizedBox(height:8),const Text('Your wallet is not credited when you submit. An administrator must verify the real payment first.',style:TextStyle(color:muted,fontSize:11,height:1.4)),
      ])),
    ]);
  });
}

class WithdrawalPage extends StatefulWidget{
  const WithdrawalPage({super.key,required this.api,required this.dark,required this.onDone});final MonarchApi api;final bool dark;final VoidCallback onDone;
  @override State<WithdrawalPage> createState()=>_WithdrawalPageState();
}
class _WithdrawalPageState extends State<WithdrawalPage>{
  final form=GlobalKey<FormState>();final amount=TextEditingController(),note=TextEditingController();late Future<Map<String,dynamic>> options;String currency='NGN',bankId='',error='',success='';bool busy=false;
  @override void initState(){super.initState();options=widget.api.withdrawalOptions();}
  @override void dispose(){amount.dispose();note.dispose();super.dispose();}
  Future<void> submit()async{if(!form.currentState!.validate())return;setState(() { busy=true; error=''; success=''; });try{final r=await widget.api.submitWithdrawal(currency:currency,amount:amount.text.trim(),bankId:bankId,note:note.text.trim());if(!mounted)return;setState(() { success=(r['message']??'Withdrawal request submitted.').toString(); amount.clear(); note.clear(); });widget.onDone();}catch(e){if(mounted)setState(()=>error=_workspaceError(e));}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:options,builder:(context,snap){
    if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(snap.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Withdraw',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),Message(text:_workspaceError(snap.error!),success:false),FilledButton(onPressed:()=>setState(()=>options=widget.api.withdrawalOptions()),child:const Text('Retry'))]);
    final d=snap.data??{};final accounts=(d['accounts'] as List? ?? []).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();final available=d['available'] is Map?Map<String,dynamic>.from(d['available'] as Map):<String,dynamic>{};
    if(!accounts.any((a)=>a['id'].toString()==bankId))bankId=accounts.isNotEmpty?accounts.first['id'].toString():'';
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('Request a withdrawal',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),const SizedBox(height:5),const Text('Requests are reviewed by the team. Payout is not automatic.',style:TextStyle(color:muted,fontSize:12)),const SizedBox(height:13),
      if(error.isNotEmpty)Message(text:error,success:false),if(success.isNotEmpty)Message(text:success,success:true),
      Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:widget.dark?panel:Colors.white,borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFF6D5920))),child:Text('Available NGN: ₦'+number(available['NGN']).toStringAsFixed(2)+'\nAvailable USD: \$'+number(available['USD']).toStringAsFixed(2),style:const TextStyle(color:gold,fontWeight:FontWeight.w900,height:1.6))),
      const SizedBox(height:12),if(accounts.isEmpty)const Message(text:'No saved payout account was found. Add one in your account profile before requesting a withdrawal.',success:false),
      Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(initialValue:currency,decoration:const InputDecoration(labelText:'Currency'),items:const[DropdownMenuItem(value:'NGN',child:Text('NGN')),DropdownMenuItem(value:'USD',child:Text('USD'))],onChanged:busy?null:(v)=>setState(()=>currency=v??'NGN')),
        const SizedBox(height:10),if(accounts.isNotEmpty)DropdownButtonFormField<String>(initialValue:bankId,isExpanded:true,decoration:const InputDecoration(labelText:'Saved payout account'),items:accounts.map((a)=>DropdownMenuItem(value:a['id'].toString(),child:Text([a['bankName'],a['accountName'],a['accountNumber'],a['label']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' · '),overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:(v)=>setState(()=>bankId=v??'')),
        const SizedBox(height:10),TextFormField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount'),validator:(v){final n=double.tryParse(v??'');return n==null||n<=0?'Enter a valid amount':n>number(available[currency])?'Amount exceeds available balance':null;}),
        const SizedBox(height:10),TextFormField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Note (optional)')),
        const SizedBox(height:12),FilledButton(onPressed:busy||accounts.isEmpty?null:submit,style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:Colors.black,minimumSize:const Size.fromHeight(50)),child:busy?const CircularProgressIndicator(color:Colors.black):const Text('SUBMIT WITHDRAWAL REQUEST',style:TextStyle(fontWeight:FontWeight.w900))),
        const SizedBox(height:8),const Text('Pending and approved requests reserve funds. Wallet funds are debited only after an administrator verifies the actual payout.',style:TextStyle(color:muted,fontSize:11,height:1.4)),
      ])),
    ]);
  });
}


class AdminCooperativePage extends StatefulWidget {
  const AdminCooperativePage({super.key,required this.api,required this.dark});
  final MonarchApi api; final bool dark;
  @override State<AdminCooperativePage> createState()=>_AdminCooperativePageState();
}
class _AdminCooperativePageState extends State<AdminCooperativePage>{
  late Future<Map<String,dynamic>> future;final Map<int,TextEditingController> notes={};final Set<int> busy={};String? message;
  @override void initState(){super.initState();future=widget.api.adminCooperativeConnections();}
  void reload()=>setState(()=>future=widget.api.adminCooperativeConnections());
  Future<void> review(int id,String decision)async{
    final note=notes.putIfAbsent(id,()=>TextEditingController()).text.trim();
    if(decision=='reject'&&note.isEmpty){setState(()=>message='Add a rejection reason before rejecting a connection.');return;}
    setState(() { busy.add(id); message=null; });
    try{await widget.api.reviewCooperativeConnection(id:id,decision:decision,note:note);if(mounted){setState(()=>message='Connection request '+(decision=='approve'?'approved.':'rejected.'));reload();}}
    catch(e){if(mounted)setState(()=>message='Could not review the request. Please retry.');}
    finally{if(mounted)setState(()=>busy.remove(id));}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(s.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Cooperative verification queue unavailable.'),const SizedBox(height:10),FilledButton(onPressed:reload,child:const Text('Retry'))]);
    final items=(s.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('ONLINE COOPERATIVE · CONNECTION REVIEW',style:TextStyle(color:gold,fontWeight:FontWeight.w700,letterSpacing:1)),
      const SizedBox(height:6),const Text('Check the member’s submitted registration name and email with the Cooperative administrator. Approve only after the registration is confirmed; reject with a clear reason if it cannot be verified. Never ask for passwords or OTPs.',style:TextStyle(color:muted)),
      if(message!=null)Padding(padding:const EdgeInsets.all(8),child:Text(message!,style:const TextStyle(color:gold))),
      if(items.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No pending connection requests.',textAlign:TextAlign.center,style:TextStyle(color:muted))),
      ...items.map((x){final id=(x['id'] as num).toInt();final note=notes.putIfAbsent(id,()=>TextEditingController());return Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text((x['memberName']??'Member').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w700)),
        const SizedBox(height:4),Text('Member email: ${x['memberEmail']??'—'}'),
        Text('Registered name: ${x['registeredName']??'—'}'),Text('Registered email: ${x['registeredEmail']??'—'}'),
        Text('Submitted: ${x['createdAt']??'—'}',style:const TextStyle(color:muted,fontSize:10)),
        const SizedBox(height:10),TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Review note (required when rejecting)',border:OutlineInputBorder())),
        const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:busy.contains(id)?null:()=>review(id,'reject'),child:const Text('Reject'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:busy.contains(id)?null:()=>review(id,'approve'),child:const Text('Approve')))])
      ])));}),
      OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Refresh queue')),
    ]);
  });
}

class AdminPermissionsPage extends StatefulWidget {
  const AdminPermissionsPage({super.key,required this.api,required this.dark,required this.currentMemberId});
  final MonarchApi api; final bool dark; final int currentMemberId;
  @override State<AdminPermissionsPage> createState()=>_AdminPermissionsPageState();
}
class _AdminPermissionsPageState extends State<AdminPermissionsPage>{
  late Future<Map<String,dynamic>> future;final Map<String,String> levels={};final Map<String,Set<String>> actions={};final Set<String> saving={};String? message;
  static const actionOptions=['view','create','edit','approve','reject','publish','moderate','delete','export','manage'];
  @override void initState(){super.initState();future=widget.api.adminPermissions();}
  void reload()=>setState(()=>future=widget.api.adminPermissions());
  String key(int memberId,String category)=>'$memberId:$category';
  List<String> readActions(dynamic raw){try{final value=raw is String?jsonDecode(raw):raw;if(value is List)return value.map((x)=>x.toString()).toList();}catch(_){}return <String>[];}
  Future<void> save(int memberId,String category)async{
    final k=key(memberId,category),level=levels[k]??'red';
    if(memberId==widget.currentMemberId){setState(()=>message='You cannot change your own permissions.');return;}
    if(level=='gold'&&(actions[k]==null||actions[k]!.isEmpty)){setState(()=>message='Gold access requires at least one selected action.');return;}
    setState(() { saving.add(k); message=null; });
    try{await widget.api.saveAdminPermission(adminMemberId:memberId,category:category,level:level,allowedActions:(actions[k]??<String>{}).toList());if(mounted)setState(()=>message='Permission saved for '+category.replaceAll('_',' ')+'.');}
    catch(e){if(mounted)setState(()=>message='Could not save permission. Confirm you are signed in as Super Admin.');}
    finally{if(mounted)setState(()=>saving.remove(k));}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(s.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Permission controls require Super Admin access and the platform migration.'),const SizedBox(height:10),FilledButton(onPressed:reload,child:const Text('Retry'))]);
    final data=s.data??{};final admins=(data['admins'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    final categories=(data['categories'] as List? ?? const []).map((x)=>x.toString()).toList();
    final permissions=(data['permissions'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('ADMIN ACCESS CONTROL',style:TextStyle(color:gold,fontWeight:FontWeight.w700,letterSpacing:1)),
      const SizedBox(height:6),const Text('Set access separately for each administrator and category. Green grants full access; Gold grants only the actions you select; Red blocks access. Only the Founder / Super Admin may change these permissions. Administrators cannot elevate their own access.',style:TextStyle(color:muted)),
      if(message!=null)Padding(padding:const EdgeInsets.all(8),child:Text(message!,style:const TextStyle(color:gold))),
      ...admins.where((a)=>(a['role']??'').toString()!='super_admin').map((admin){
        final memberId=(admin['memberId'] as num).toInt();
        return Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((admin['fullName']??admin['email']??'Administrator').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w700)),
          Text((admin['role']??'').toString().replaceAll('_',' ').toUpperCase(),style:const TextStyle(color:muted,fontSize:10)),
          const SizedBox(height:8),
          ...categories.map((category){
            final k=key(memberId,category);
            final matches=permissions.where((p)=>(p['adminMemberId'] as num?)?.toInt()==memberId&&p['category']==category);
            final existing=matches.isEmpty?null:matches.first;
            final current=levels[k]??(existing?['level']??'red').toString();
            actions.putIfAbsent(k,()=>readActions(existing?['allowedActions']).toSet());
            return Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[Expanded(child:Text(category.replaceAll('_',' '),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:12))),SizedBox(width:125,child:DropdownButtonFormField<String>(initialValue:current,decoration:const InputDecoration(isDense:true,contentPadding:EdgeInsets.symmetric(horizontal:8,vertical:8)),items:const [DropdownMenuItem(value:'green',child:Text('Green · Full')),DropdownMenuItem(value:'gold',child:Text('Gold · Partial')),DropdownMenuItem(value:'red',child:Text('Red · None'))],onChanged:(v){if(v!=null)setState(()=>levels[k]=v);}))]),
              if(current=='gold')
                Wrap(
                  spacing:4,
                  runSpacing:0,
                  children:actionOptions.map((action) {
                    return FilterChip(
                      label:Text(action,style:const TextStyle(fontSize:10)),
                      selected:actions[k]!.contains(action),
                      onSelected:(selected) {
                        setState(() {
                          if(selected) {
                            actions[k]!.add(action);
                          } else {
                            actions[k]!.remove(action);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              Align(alignment:Alignment.centerRight,child:TextButton(onPressed:saving.contains(k)?null:()=>save(memberId,category),child:Text(saving.contains(k)?'Saving…':'Save permission')))
            ]));
          })
        ])));
      }),
      OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Refresh permissions')),
    ]);
  });
}


class AdminSocialLinksPage extends StatefulWidget {
  const AdminSocialLinksPage({super.key,required this.api,required this.dark});
  final MonarchApi api;final bool dark;
  @override State<AdminSocialLinksPage> createState()=>_AdminSocialLinksPageState();
}
class _AdminSocialLinksPageState extends State<AdminSocialLinksPage>{
  late Future<Map<String,dynamic>> future;final Map<String,TextEditingController> urls={};final Map<String,TextEditingController> labels={};final Map<String,bool> active={};final Set<String> saving={};String? message;
  @override void initState(){super.initState();future=widget.api.adminSocialLinks();}
  void reload()=>setState(()=>future=widget.api.adminSocialLinks());
  Future<void> save(String key)async{
    final url=urls[key]?.text.trim()??'',label=labels[key]?.text.trim()??key;
    if(active[key]==true&&url.isEmpty){setState(()=>message='An active social link must have an HTTPS URL.');return;}
    if(url.isNotEmpty){final uri=Uri.tryParse(url);if(uri==null||uri.scheme!='https'||uri.host.isEmpty){setState(()=>message='Use a valid HTTPS URL for '+label+'.');return;}}
    setState(() {saving.add(key);message=null;});
    try{await widget.api.saveAdminSocialLink(key:key,label:label,url:url,active:active[key]??false);if(mounted)setState(()=>message=label+' saved.');}
    catch(e){if(mounted)setState(()=>message='Could not save '+label+'. Confirm Super Admin access and try again.');}
    finally{if(mounted)setState(()=>saving.remove(key));}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
    if(s.hasError)return ListView(padding:const EdgeInsets.all(18),children:[const Text('Social link management requires Super Admin access and the platform migration.'),const SizedBox(height:10),FilledButton(onPressed:reload,child:const Text('Retry'))]);
    final items=(s.data?['items'] as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    return ListView(padding:const EdgeInsets.all(15),children:[
      const Text('OFFICIAL SOCIAL LINKS',style:TextStyle(color:gold,fontWeight:FontWeight.w700,letterSpacing:1)),
      const SizedBox(height:6),const Text('These are the official links members can open from Monarch Codex. Use a valid HTTPS address and switch a link on only after testing it. Leave a platform blank or inactive to hide it. Founder personal contacts should remain separate unless deliberately published.',style:TextStyle(color:muted)),
      if(message!=null)Padding(padding:const EdgeInsets.all(8),child:Text(message!,style:const TextStyle(color:gold))),
      ...items.map((item){
        final key=(item['key_name']??'other').toString();
        labels.putIfAbsent(key,()=>TextEditingController(text:(item['label']??key).toString()));
        urls.putIfAbsent(key,()=>TextEditingController(text:(item['url']??'').toString()));
        active.putIfAbsent(key,()=>item['active']==true||item['active']==1);
        return Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(key.toUpperCase(),style:const TextStyle(color:gold,fontWeight:FontWeight.w700))),Switch(value:active[key]!,activeThumbColor:gold,onChanged:(v)=>setState(()=>active[key]=v),)]),
          TextField(controller:labels[key],decoration:const InputDecoration(labelText:'Public label',border:OutlineInputBorder())),
          const SizedBox(height:8),TextField(controller:urls[key],keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'HTTPS URL (blank hides the link)',border:OutlineInputBorder())),
          Align(alignment:Alignment.centerRight,child:FilledButton(onPressed:saving.contains(key)?null:()=>save(key),child:Text(saving.contains(key)?'Saving…':'Save')))
        ])));
      }),
      OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Reload links'))
    ]);
  });
}



class SovereignDeskSectionPage extends StatefulWidget {
  const SovereignDeskSectionPage({super.key,required this.api,required this.section,required this.title});
  final MonarchApi api; final String section; final String title;
  @override State<SovereignDeskSectionPage> createState()=>_SovereignDeskSectionPageState();
}
class _SovereignDeskSectionPageState extends State<SovereignDeskSectionPage>{
  late Future<Map<String,dynamic>> future; bool busy=false; String? message;
  @override void initState(){super.initState();future=_load();}
  Future<Map<String,dynamic>> _load()=>widget.section=='markets'?Future.value({'items':<dynamic>[]}):widget.api.sovereignDeskSection(widget.section);
  void reload()=>setState(()=>future=_load());
  String errorText(Object e){if(e is DioException&&e.response?.data is Map){final d=e.response!.data as Map;return (d['message']??d['error']??'Request failed').toString();}return 'Could not complete the request. Check your connection and administrator permissions.';}
  List<Map<String,dynamic>> list(dynamic v)=>v is List?v.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
  Future<void> update(String path,Map<String,dynamic> body)async{
    setState(()=>busy=true);
    try{await widget.api.sovereignDeskUpdate(path,body);if(mounted)setState((){message='Saved to the shared database.';future=_load();});}
    catch(e){if(mounted)setState(()=>message=errorText(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> create()async{
    final defs=switch(widget.section){
      'signals'=>{'asset_pair':'Instrument (e.g. XAUUSD)','direction':'Direction: buy or sell','price':'Entry price','stop_loss':'Stop loss (optional)','take_profit_1':'Take profit (optional)','explanation':'Analysis / notes'},
      'guidance'=>{'title':'Lesson title','body':'Guidance content'},
      'announcements'=>{'title':'Announcement title','body':'Announcement message'},
      'watchlist'=>{'instrument':'Instrument','direction':'Direction: buy or sell','outcome':'Outcome: profit, loss or breakeven','trade_date':'Trade date YYYY-MM-DD','notes':'Trade notes'},
      'events'=>{'title':'Event title','summary':'Event description','event_label':'Homepage label','starts_at':'Starts at YYYY-MM-DDTHH:mm','ends_at':'Ends at YYYY-MM-DDTHH:mm'},
      'governance'=>{'subject':'Concern / review title','details':'Details and rationale'},
      _=><String,String>{},
    };
    if(defs.isEmpty)return;
    final ctrls=<String,TextEditingController>{};
    for(final e in defs.entries){ctrls[e.key]=TextEditingController(text:e.key=='direction'?'buy':e.key=='outcome'?'breakeven':e.key=='trade_date'?DateTime.now().toIso8601String().substring(0,10):e.key=='starts_at'?DateTime.now().toIso8601String().substring(0,16):e.key=='ends_at'?DateTime.now().add(const Duration(days:30)).toIso8601String().substring(0,16):e.key=='event_label'?'MONARCH CODEX EVENT':'');}
    final key=GlobalKey<FormState>();
    final save=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text('Create ${widget.title.toLowerCase()}'),
      content:SizedBox(width:460,child:SingleChildScrollView(child:Form(key:key,child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final e in defs.entries) Padding(padding:const EdgeInsets.only(bottom:10),child:TextFormField(controller:ctrls[e.key],maxLines:['body','explanation','notes'].contains(e.key)?4:1,decoration:InputDecoration(labelText:e.value,border:const OutlineInputBorder()),validator:(v)=>['stop_loss','take_profit_1','explanation','notes'].contains(e.key)||(v??'').trim().isNotEmpty?null:'Required')),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:(){if(key.currentState?.validate()??false)Navigator.pop(c,true);},child:const Text('Save'))],
    ));
    if(save!=true||!mounted){for(final c in ctrls.values){c.dispose();}return;}
    setState(()=>busy=true);
    try{final body=<String,dynamic>{for(final e in ctrls.entries)e.key:e.value.text.trim()};if(widget.section=='signals')body['validation_status']='pending';await widget.api.sovereignDeskCreate(widget.section,body);if(mounted)setState(()=>message='Saved to the shared database.');reload();}
    catch(e){if(mounted)setState(()=>message=errorText(e));}
    finally{for(final c in ctrls.values){c.dispose();}if(mounted)setState(()=>busy=false);}
  }
  Widget record(Map<String,dynamic> item,{List<Widget> actions=const [],String? subtitle,VoidCallback? onTap}){
    final title=(item['title']??item['subject']??item['asset_pair']??item['instrument']??item['full_name']??item['name']??item['monarch_uid']??item['member_id']??'Record').toString();
    final status=(item['status']??item['outcome']??item['direction']??item['kind']??'').toString().replaceAll('_',' ');
    final desc=(item['body']??item['explanation']??item['details']??item['summary']??item['reason']??item['notes']??item['preview']??'').toString();
    final meta=[if(status.isNotEmpty)status.toUpperCase(),if(item['email']!=null)item['email'].toString(),if(item['monarch_uid']!=null)item['monarch_uid'].toString(),if(item['created_at']!=null)item['created_at'].toString()].join(' · ');
    return Card(child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(16),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text(title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:14))),if(status.isNotEmpty)Text(status.toUpperCase(),style:const TextStyle(color:gold,fontSize:9,fontWeight:FontWeight.w900))]),
      if(meta.isNotEmpty)Padding(padding:const EdgeInsets.only(top:5),child:Text(meta,style:const TextStyle(color:muted,fontSize:10))),
      if(desc.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(desc,maxLines:5,overflow:TextOverflow.ellipsis,style:const TextStyle(height:1.4))),
      if(item['price']!=null||item['entry_zone']!=null)Padding(padding:const EdgeInsets.only(top:7),child:Text('Entry: ${item['price']??item['entry_zone']} · TP: ${item['take_profit_1']??'—'} · SL: ${item['stop_loss']??'—'}',style:const TextStyle(color:gold,fontSize:11,fontWeight:FontWeight.w700))),
      if(subtitle!=null)Padding(padding:const EdgeInsets.only(top:6),child:Text(subtitle,style:const TextStyle(color:muted,fontSize:11))),
      if(actions.isNotEmpty)Padding(padding:const EdgeInsets.only(top:10),child:Wrap(spacing:8,runSpacing:6,children:actions)),
    ]))));
  }
  List<Widget> actions(Map<String,dynamic> x){
    final id=(x['id']??'').toString();
    if(widget.section=='signals')return [if(x['validation_status']!='valid')FilledButton(onPressed:busy?null:()=>update('signals/$id/validation',{'validation_status':'valid'}),child:const Text('Validate')),if(x['validation_status']=='valid')FilledButton(onPressed:busy?null:()=>update('signals/$id/status',{'status':x['status']=='published'?'closed':'published'}),child:Text(x['status']=='published'?'Close signal':'Publish')),if(x['validation_status']!='invalid')OutlinedButton(onPressed:busy?null:()=>update('signals/$id/validation',{'validation_status':'invalid'}),child:const Text('Mark invalid'))];
    if(widget.section=='guidance')return [OutlinedButton(onPressed:busy?null:()=>update('guidance/$id/status',{'status':'archived'}),child:const Text('Archive')),FilledButton(onPressed:busy?null:()=>update('guidance/$id/status',{'status':x['status']=='published'?'draft':'published'}),child:Text(x['status']=='published'?'Unpublish':'Publish'))];
    if(widget.section=='events')return [OutlinedButton(onPressed:busy?null:()=>update('events/$id/status',{'status':'archived'}),child:const Text('Archive')),FilledButton(onPressed:busy?null:()=>update('events/$id/status',{'status':x['status']=='published'?'draft':'published'}),child:Text(x['status']=='published'?'Unpublish':'Publish'))];
    if(widget.section=='governance')return [OutlinedButton(onPressed:busy?null:()=>update('governance/$id/status',{'status':'under_review','resolution_note':'Moved to review in Android app'}),child:const Text('Review')),FilledButton(onPressed:busy?null:()=>update('governance/$id/status',{'status':'resolved','resolution_note':'Resolved in Android app'}),child:const Text('Resolve'))];
    if(widget.section=='announcements')return [OutlinedButton(onPressed:busy?null:()=>update('announcements/$id/status',{'status':'archived'}),child:const Text('Archive')),FilledButton(onPressed:busy?null:()=>update('announcements/$id/status',{'status':x['status']=='published'?'draft':'published'}),child:Text(x['status']=='published'?'Unpublish':'Publish & notify'))];
    if(widget.section=='signal-access'&&x['status']=='pending')return [OutlinedButton(onPressed:busy?null:()=>update('signal-access/$id/review',{'decision':'rejected','note':'Reviewed in Android app'}),child:const Text('Reject')),FilledButton(onPressed:busy?null:()=>update('signal-access/$id/review',{'decision':'approved','note':'Payment verified in Android app'}),child:const Text('Approve'))];
    return const [];
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(leading:IconButton(onPressed:()=>Navigator.of(context).pop(),icon:const Icon(Icons.arrow_back)),title:Text(widget.title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:15)),actions:[IconButton(onPressed:busy?null:reload,icon:const Icon(Icons.refresh,color:gold))]),
    body:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){
      if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
      if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off,color:gold,size:42),const SizedBox(height:12),const Text('Could not load this section',style:TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:8),Text(errorText(s.error!),textAlign:TextAlign.center,style:const TextStyle(color:muted)),FilledButton(onPressed:reload,child:const Text('Try again'))])));
      final d=s.data??<String,dynamic>{};
      if(widget.section=='markets')return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('This native screen is ready, but a live market quote provider still needs to be connected to the server.',textAlign:TextAlign.center,style:TextStyle(color:muted))));
      if(widget.section=='overview')return ListView(padding:const EdgeInsets.all(16),children:[
        Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),border:Border.all(color:const Color(0xFF6D5920)),gradient:const LinearGradient(colors:[Color(0xFF30250C),Color(0xFF151411),Color(0xFF101012)])),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('SOVEREIGN DESK',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1.3)),SizedBox(height:10),Text('Native command centre',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w900)),SizedBox(height:7),Text('Authenticated, native workspace using the shared Monarch Codex database.',style:TextStyle(color:Colors.white70,height:1.4))])),
        const SizedBox(height:12),GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.7,crossAxisSpacing:8,mainAxisSpacing:8,children:[
          _metric('Published signals',(d['signals'] is Map?(d['signals'] as Map)['published']:0),Icons.show_chart),
          _metric('Published guidance',(d['guidance'] is Map?(d['guidance'] as Map)['published']:0),Icons.school_outlined),
          _metric('Active access',(d['access'] is Map?(d['access'] as Map)['active']:0),Icons.verified_user_outlined),
          _metric('Pending requests',(d['requests'] is Map?(d['requests'] as Map)['pending']:0),Icons.pending_actions),
        ]),
      ]);
      final items=widget.section=='access'?list(d['requests']):list(d['items']);
      final children=<Widget>[if(message!=null)Padding(padding:const EdgeInsets.all(8),child:Text(message!,style:const TextStyle(color:gold))),
        if(widget.section=='access')const Text('ACCESS REQUESTS',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),
        if(widget.section=='access'&&items.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No access requests waiting for review.'))),
        if(widget.section=='access')...items.map((x)=>record(x,actions:x['status']=='pending'?[OutlinedButton(onPressed:busy?null:()=>update('access-requests/${x['id']}/review',{'decision':'rejected','reason':'Reviewed in Android app'}),child:const Text('Reject')),FilledButton(onPressed:busy?null:()=>update('access-requests/${x['id']}/review',{'decision':'approved','reason':'Approved in Android app'}),child:const Text('Approve'))]:const [])),
        if(widget.section=='access')const Padding(padding:EdgeInsets.only(top:16,bottom:6),child:Text('MEMBER ACCESS RECORDS',style:TextStyle(color:gold,fontWeight:FontWeight.w900))),
        if(widget.section=='access')...list(d['members']).take(100).map((x)=>record(x,actions:[FilledButton(onPressed:busy?null:()=>update('access/${x['id']}',{'decision':x['status']=='approved'?'revoked':'approved','reason':'Updated in Android app'}),child:Text(x['status']=='approved'?'Revoke access':'Grant access'))])),
        if(widget.section!='access'&&items.isEmpty&&widget.section!='governance')const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('Nothing has been added here yet.'))),
        if(widget.section=='chat')...items.map((x)=>record(x,subtitle:'${x['unread']??0} unread',onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>SovereignDeskChatPage(api:widget.api,memberId:(x['member_id'] as num).toInt(),memberName:(x['full_name']??x['username']??'Member').toString()))))),
        if(widget.section!='chat'&&widget.section!='access')...items.map((x)=>record(x,actions:actions(x))),
        if(widget.section=='governance')...list(d['decisions']).map((x)=>record(x,subtitle:'Governance decision')),
        if(widget.section=='governance'&&items.isEmpty&&list(d['decisions']).isEmpty)const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('No governance records yet.'))),
        
      ];
      final canCreate=['signals','guidance','announcements','watchlist','events','governance'].contains(widget.section);
      return Stack(children:[ListView(padding:const EdgeInsets.fromLTRB(14,14,14,90),children:children),if(canCreate)Positioned(right:18,bottom:18,child:FloatingActionButton.extended(onPressed:busy?null:create,backgroundColor:gold,foregroundColor:ink,icon:const Icon(Icons.add),label:Text('Create ${widget.title.toLowerCase()}'))),if(busy)const Positioned(top:0,left:0,right:0,child:LinearProgressIndicator(color:gold,minHeight:3))]);
    }),
  );
  Widget _metric(String title,dynamic value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(13),child:Row(children:[Icon(icon,color:gold),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:muted,fontSize:10)),Text((value??0).toString(),style:const TextStyle(color:gold,fontSize:21,fontWeight:FontWeight.w900))]))])));
}
class SovereignDeskChatPage extends StatefulWidget {
  const SovereignDeskChatPage({super.key,required this.api,required this.memberId,required this.memberName});
  final MonarchApi api; final int memberId; final String memberName;
  @override State<SovereignDeskChatPage> createState()=>_SovereignDeskChatPageState();
}
class _SovereignDeskChatPageState extends State<SovereignDeskChatPage>{
  late Future<Map<String,dynamic>> future;
  final reply=TextEditingController(); bool busy=false; String? message;
  @override void initState(){super.initState();future=widget.api.sovereignDeskSection('chat/${widget.memberId}');}
  @override void dispose(){reply.dispose();super.dispose();}
  void reload()=>setState(()=>future=widget.api.sovereignDeskSection('chat/${widget.memberId}'));
  Future<void> send()async{
    final body=reply.text.trim();if(body.isEmpty)return;setState(()=>busy=true);
    try{await widget.api.sovereignDeskUpdate('chat/${widget.memberId}',{'body':body});reply.clear();if(mounted){setState(()=>message='Reply sent.');reload();}}
    catch(e){if(mounted)setState(()=>message=e is DioException&&e.response?.data is Map?((e.response!.data as Map)['message']??'Could not send reply').toString():'Could not send reply.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.memberName,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),
    body:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){
      if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:gold));
      if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(20),child:Text('Could not load conversation: ${s.error}')));
      final data=s.data??<String,dynamic>{};final messages=data['messages'] is List?(data['messages'] as List).whereType<Map>().toList():<Map>[];
      return Column(children:[
        Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[
          for(final item in messages)Align(alignment:item['sender_role']=='desk'?Alignment.centerRight:Alignment.centerLeft,child:Container(
            margin:const EdgeInsets.symmetric(vertical:5),padding:const EdgeInsets.all(12),constraints:const BoxConstraints(maxWidth:320),
            decoration:BoxDecoration(color:item['sender_role']=='desk'?gold.withValues(alpha:.15):Theme.of(context).cardColor,borderRadius:BorderRadius.circular(14),border:Border.all(color:item['sender_role']=='desk'?gold.withValues(alpha:.5):muted.withValues(alpha:.2))),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((item['body']??'').toString()),const SizedBox(height:5),Text((item['created_at']??'').toString(),style:const TextStyle(color:muted,fontSize:9))]),
          )),
        ])),
        if(message!=null)Padding(padding:const EdgeInsets.all(5),child:Text(message!,style:const TextStyle(color:gold,fontSize:11))),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(10,6,10,10),child:Row(children:[
          Expanded(child:TextField(controller:reply,minLines:1,maxLines:4,decoration:const InputDecoration(hintText:'Reply to member…',border:OutlineInputBorder()))),
          const SizedBox(width:8),IconButton.filled(onPressed:busy?null:send,style:IconButton.styleFrom(backgroundColor:gold,foregroundColor:ink),icon:const Icon(Icons.send_rounded)),
        ]))),
      ]);
    }),
  );
}



class TelegramAdminPage extends StatefulWidget {
  const TelegramAdminPage({super.key, required this.api, required this.member});
  final MonarchApi api;
  final Map<String, dynamic> member;
  @override
  State<TelegramAdminPage> createState() => _TelegramAdminPageState();
}

class _TelegramAdminPageState extends State<TelegramAdminPage> {
  bool loading = true, busy = false;
  String? error, notice, selectedChatId;
  List<Map<String, dynamic>> chats = [];
  final message = TextEditingController();
  final title = TextEditingController();
  final description = TextEditingController();

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { message.dispose(); title.dispose(); description.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final data = await widget.api.telegramAdminChats();
      final rows = (data['chats'] as List? ?? const []).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        chats = rows;
        if (selectedChatId == null && rows.isNotEmpty) selectedChatId = (rows.first['telegram_chat_id'] ?? '').toString();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e is DioException && e.response?.data is Map ? ((e.response!.data as Map)['message'] ?? (e.response!.data as Map)['error'] ?? 'Could not load Telegram chats').toString() : 'Could not load Telegram chats. Check the connection and administrator access.'; loading = false; });
    }
  }

  Future<void> act(String action, {String? text}) async {
    final id = selectedChatId;
    if (id == null || id.isEmpty) { setState(() => error = 'Choose a group or channel first.'); return; }
    setState(() { busy = true; error = null; notice = null; });
    try {
      await widget.api.telegramAdminAction({'action': action, 'chat_id': id, if (text != null) 'text': text});
      if (!mounted) return;
      setState(() { notice = 'Telegram action completed.'; busy = false; });
      await load();
    } catch (e) {
      if (!mounted) return;
      setState(() { busy = false; error = e is DioException && e.response?.data is Map ? ((e.response!.data as Map)['message'] ?? (e.response!.data as Map)['error'] ?? 'Telegram action failed').toString() : 'Telegram action failed. Check the bot permissions and try again.'; });
    }
  }

  Future<void> showMembers() async {
    if (selectedChatId == null) return;
    setState(() { busy = true; error = null; });
    try {
      final data = await widget.api.telegramAdminMembers(selectedChatId!);
      if (!mounted) return;
      final members = (data['members'] as List? ?? const []).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
      setState(() => busy = false);
      await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (ctx) => SafeArea(child: SizedBox(height: MediaQuery.of(ctx).size.height * .7, child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('KNOWN TELEGRAM MEMBERS', style: TextStyle(color: gold, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text((data['note'] ?? 'Member list').toString(), style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 12),
        if (members.isEmpty) const Text('No known members are available for this chat yet.'),
        for (final m in members) ListTile(leading: const Icon(Icons.person_outline, color: gold), title: Text('@${(m['telegram_username'] ?? 'unknown').toString()}'), subtitle: Text('${(m['first_name'] ?? '').toString()} ${(m['last_name'] ?? '').toString()} · ${(m['status'] ?? 'unknown').toString()}'))
      ]))));
    } catch (e) {
      if (mounted) setState(() { busy = false; error = e is DioException && e.response?.data is Map ? ((e.response!.data as Map)['message'] ?? (e.response!.data as Map)['error'] ?? 'Could not load members').toString() : 'Could not load Telegram members.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Map<String, dynamic>? selected;
    for (final chat in chats) { if ((chat['telegram_chat_id'] ?? '').toString() == selectedChatId) { selected = chat; break; } }
    return Scaffold(
      appBar: AppBar(title: const Text('TELEGRAM OPERATIONS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: loading || busy ? null : load, icon: const Icon(Icons.refresh, color: gold), tooltip: 'Refresh chats')]),
      body: loading ? const Center(child: CircularProgressIndicator(color: gold)) : ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF6D5920)), gradient: const LinearGradient(colors: [Color(0xFF30250C), Color(0xFF151411), Color(0xFF101012)])), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SOVEREIGN DESK · TELEGRAM', style: TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
          SizedBox(height: 10), Text('Groups & channels', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          SizedBox(height: 6), Text('Manage registered Telegram groups and channels using the existing Cloudflare bot. Actions depend on the permissions granted to the bot.', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5))
        ])),
        const SizedBox(height: 14),
        if (error != null) Message(text: error!, success: false),
        if (notice != null) Message(text: notice!, success: true),
        if (chats.isEmpty) Container(padding: const EdgeInsets.all(18), decoration: mcCard(dark), child: const Text('No registered groups or channels were returned. Confirm the Worker URL and shared secret are configured and that the bot has joined the chat.')),
        for (final chat in chats) Card(color: (chat['telegram_chat_id'] ?? '').toString() == selectedChatId ? gold.withValues(alpha: .12) : null, child: ListTile(onTap: () => setState(() { selectedChatId = (chat['telegram_chat_id'] ?? '').toString(); title.text = (chat['title'] ?? '').toString(); description.text = (chat['description'] ?? '').toString(); }), leading: Icon(chat['chat_type'] == 'channel' ? Icons.campaign_outlined : Icons.groups_outlined, color: gold), title: Text((chat['title'] ?? 'Telegram chat').toString(), style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${(chat['chat_type'] ?? 'group').toString()} · ${(chat['member_count'] ?? '—').toString()} members\nChat ID: ${(chat['telegram_chat_id'] ?? '').toString()}'), isThreeLine: true, trailing: Icon((chat['telegram_chat_id'] ?? '').toString() == selectedChatId ? Icons.check_circle : Icons.chevron_right, color: gold))),
        if (selected != null) ...[
          const SizedBox(height: 10),
          Text('SELECTED: ${(selected['title'] ?? 'Telegram chat').toString()}', style: const TextStyle(color: gold, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(controller: message, onChanged: (_) => setState(() {}), maxLines: 3, maxLength: 4000, decoration: const InputDecoration(labelText: 'Message to send', hintText: 'Write an update for this group or channel')),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: busy || message.text.trim().isEmpty ? null : () => act('send_message', text: message.text.trim()), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink, minimumSize: const Size.fromHeight(48)), icon: const Icon(Icons.send), label: Text(busy ? 'Working…' : 'Send message')),
          const SizedBox(height: 8),
          TextField(controller: title, onChanged: (_) => setState(() {}), maxLength: 128, decoration: const InputDecoration(labelText: 'Change chat title')),
          OutlinedButton(onPressed: busy || title.text.trim().isEmpty ? null : () => act('set_chat_title', text: title.text.trim()), child: const Text('Update title')),
          TextField(controller: description, onChanged: (_) => setState(() {}), maxLength: 255, maxLines: 2, decoration: const InputDecoration(labelText: 'Change chat description')),
          OutlinedButton(onPressed: busy || description.text.trim().isEmpty ? null : () => act('set_chat_description', text: description.text.trim()), child: const Text('Update description')),
          OutlinedButton.icon(onPressed: busy ? null : showMembers, icon: const Icon(Icons.people_outline), label: const Text('View known members')),
          const SizedBox(height: 12),
          const Text('Note: Telegram does not let bots fetch every member in a chat. This list includes members the bot has previously seen.', style: TextStyle(color: muted, fontSize: 11, height: 1.4))
        ]
      ]),
    );
  }
}
