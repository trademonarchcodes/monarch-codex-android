import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:monarch_codex/main.dart';

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

Future<void> _openAdminRoute(String route) async {
  final uri=Uri.parse('$site$route');
  final opened=await launchUrl(uri,mode:LaunchMode.externalApplication);
  if(!opened) throw Exception('Could not open the administrator review page.');
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
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Review requests, bugs and improvement ideas. Members see status changes in their feedback history.',
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
              style: const TextStyle(color: gold, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              (item['memberName'] ?? 'Member').toString() + ' · ' + category,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Text((item['description'] ?? '').toString()),
            const SizedBox(height: 8),
            Text('Status: ' + status, style: const TextStyle(fontWeight: FontWeight.w800)),
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
  bool drawerBusy=false;
  final GlobalKey<ScaffoldState> scaffoldKey=GlobalKey<ScaffoldState>();
  @override void initState(){super.initState();data=widget.api.adminOverview();}
  void reload()=>setState(()=>data=widget.api.adminOverview());

  Future<void> openSection(int index) async {
    if(index==0){scaffoldKey.currentState?.closeDrawer();setState(()=>selected=0);reload();return;}
    if(index==4){scaffoldKey.currentState?.closeDrawer();await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>RoleManagerPage(api:widget.api,dark:Theme.of(context).brightness==Brightness.dark)));if(mounted)setState(()=>selected=0);return;}
    scaffoldKey.currentState?.closeDrawer();
    setState(()=>selected=index);
    final dark=Theme.of(context).brightness==Brightness.dark;
    Widget? page;
    if(index>=1&&index<=3)page=AdminReviewQueuePage(api:widget.api,type:const ['kyc','deposits','withdrawals'][index-1],dark:dark);
    if(index==5)page=AdminDataPage(api:widget.api,kind:'audit',dark:dark);
    if(index==6)page=AdminDataPage(api:widget.api,kind:'analytics',dark:dark);
    if(index==7)page=AdminDataPage(api:widget.api,kind:'security',dark:dark);
    if(index==8){try{await _openAdminRoute('/admin/settings');}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not open settings: '+e.toString())));}if(mounted)setState(()=>selected=0);return;}
    if(index==9)page=AdminPermissionsPage(api:widget.api,dark:dark,currentMemberId:(widget.member['id'] as num?)?.toInt()??(widget.member['memberId'] as num?)?.toInt()??-1);
    if(index==10)page=AdminCooperativePage(api:widget.api,dark:dark);
    if(index==11)page=AdminSocialLinksPage(api:widget.api,dark:dark);
    if(index==12)page=AdminFeedbackPage(api:widget.api,dark:dark);
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
        trailing:active?Container(width:3,height:22,decoration:BoxDecoration(color:gold,borderRadius:BorderRadius.circular(4))):null,
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
            _navItem(5,Icons.history_outlined,'Audit history'),
            _navItem(6,Icons.query_stats_outlined,'Analytics'),
            _navItem(7,Icons.shield_outlined,'Security centre'),
            _navItem(8,Icons.settings_outlined,'Settings'),
            if((widget.member['adminRole']??'').toString()=='super_admin') _navItem(9,Icons.admin_panel_settings_outlined,'Admin permissions'),
            if((widget.member['adminRole']??'').toString()=='super_admin') _navItem(10,Icons.link_outlined,'Online Cooperative'),
            if((widget.member['adminRole']??'').toString()=='super_admin') _navItem(11,Icons.public,'Social links'),
            if(['super_admin','main_admin'].contains((widget.member['adminRole']??'').toString())) _navItem(12,Icons.feedback_outlined,'Member feedback'),
          ])),
          Divider(color:dark?const Color(0xFF4C4029):const Color(0xFFE4DFD2),height:1),
          ListTile(leading:const Icon(Icons.contrast,color:gold),title:const Text('Appearance',style:TextStyle(fontSize:12)),trailing:Text(widget.light?'Light':'Dark',style:const TextStyle(color:muted,fontSize:11)),onTap:(){scaffoldKey.currentState?.closeDrawer();widget.toggleTheme();}),
          ListTile(leading:const Icon(Icons.logout,color:Color(0xFFD8A29A)),title:const Text('Sign out',style:TextStyle(color:Color(0xFFD8A29A),fontSize:12)),onTap:widget.signOut),
          const SizedBox(height:8),
        ])),
      ),
      appBar:AppBar(
        title:Row(children:[SvgPicture.asset('assets/images/monarch-codex-logo.svg',width:32,height:32),const SizedBox(width:8),const Expanded(child:Text('ADMIN CONTROL CENTRE',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900)))]),
        actions:[IconButton(onPressed:widget.toggleTheme,icon:const Icon(Icons.contrast,color:gold),tooltip:'Toggle appearance'),IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold),tooltip:'Refresh overview')],
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
            SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>_openAdminRoute('/admin/kyc'),icon:const Icon(Icons.verified_user_outlined),label:const Text('Open KYC review'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,minimumSize:const Size.fromHeight(46)))),
            const SizedBox(height:8),
            SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>_openAdminRoute('/admin/deposits'),icon:const Icon(Icons.receipt_long),label:const Text('Open deposit review'),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(44)))),
            const SizedBox(height:8),
            SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>_openAdminRoute('/admin/withdrawals'),icon:const Icon(Icons.payments_outlined),label:const Text('Open withdrawal review'),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(44)))),
          ])),
          const SizedBox(height:12),FilledButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>RoleManagerPage(api:widget.api,dark:dark))),icon:const Icon(Icons.manage_accounts_outlined),label:const Text('Manage member roles'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,minimumSize:const Size.fromHeight(48))),
          const SizedBox(height:12),OutlinedButton.icon(onPressed:widget.signOut,icon:const Icon(Icons.logout),label:const Text('Sign out of administrator account')),
        ]);
      }),
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
      if(widget.type=='kyc')FilledButton(onPressed:busy.contains(id)?null:()=>act(r,'approved'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink),child:const Text('Approve')),
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
 const SovereignAdminShell({super.key,required this.api,required this.member,required this.signOut,required this.light,required this.toggleTheme});
 final MonarchApi api;final Map<String,dynamic> member;final Future<void> Function() signOut;final bool light;final VoidCallback toggleTheme;
 @override State<SovereignAdminShell> createState()=>_SovereignAdminShellState();
}
class _SovereignAdminShellState extends State<SovereignAdminShell>{
 final company=TextEditingController(text:'Sovereign Desk');final message=TextEditingController(text:'Request Partner role for the Sovereign Desk company.');bool busy=false;String? error,notice;
 @override void dispose(){company.dispose();message.dispose();super.dispose();}
 Future<void> requestPartner()async{setState(()=>busy=true);try{await widget.api.requestSovereignPartner(companyName:company.text.trim(),message:message.text.trim());if(mounted)setState(()=>notice='Partner request submitted for review.');}catch(e){if(mounted)setState(()=>error=e is DioException&&e.response?.data is Map?((e.response!.data as Map)['message']??'Request failed').toString():e.toString());}finally{if(mounted)setState(()=>busy=false);}}
 @override Widget build(BuildContext context){final dark=Theme.of(context).brightness==Brightness.dark;return PopScope<Object?>(canPop:false,onPopInvokedWithResult:(didPop,result){if(!didPop)confirmAppExit(context);},child:Scaffold(appBar:AppBar(automaticallyImplyLeading:false,title:Row(children:[SvgPicture.asset('assets/images/monarch-codex-logo.svg',width:34,height:34),const SizedBox(width:8),const Expanded(child:Text('SOVEREIGN DESK CONTROL',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900)))]),actions:[IconButton(onPressed:widget.toggleTheme,icon:const Icon(Icons.contrast,color:gold)),IconButton(onPressed:()=>launchUrl(Uri.parse('$site/sovereign-admin'),mode:LaunchMode.externalApplication),icon:const Icon(Icons.open_in_new,color:gold),tooltip:'Open full Sovereign Desk dashboard')]),body:ListView(padding:const EdgeInsets.all(16),children:[
 Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFF6D5920)),gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF30250C),Color(0xFF151411),Color(0xFF101012)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('SOVEREIGN DESK · PRIVATE WORKSPACE',style:TextStyle(color:gold,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.1)),const SizedBox(height:10),const Text('Sovereign Desk administration',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text('Signed in as '+(widget.member['fullName']??'Sovereign Desk administrator').toString(),style:const TextStyle(color:muted,fontSize:12)),const SizedBox(height:8),const Text('This workspace is separate from Monarch Codex financial administration.',style:TextStyle(color:muted,fontSize:12))])),
 const SizedBox(height:14),Container(padding:const EdgeInsets.all(16),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('PARTNER ROLE REQUEST',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:6),const Text('Request Partner status for the company. Founder is reserved exclusively for the Monarch Codex Super Admin and is not available to other members. This request goes to Monarch Codex administrators and does not grant access automatically.',style:TextStyle(color:muted,fontSize:12)),const SizedBox(height:12),TextField(controller:company,decoration:const InputDecoration(labelText:'Company / partner name')),const SizedBox(height:10),TextField(controller:message,maxLines:3,decoration:const InputDecoration(labelText:'Reason for request')),const SizedBox(height:12),if(error!=null)Message(text:error!,success:false),if(notice!=null)Message(text:notice!,success:true),FilledButton(onPressed:busy?null:requestPartner,style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink,minimumSize:const Size.fromHeight(48)),child:Text(busy?'Submitting…':'Request Partner role'))])),
 const SizedBox(height:14),Container(padding:const EdgeInsets.all(16),decoration:mcCard(dark),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('SIGNALS & GUIDANCE',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:6),const Text('Open the dedicated Sovereign Desk dashboard to manage its signals and guidance. This does not open Monarch Codex financial administration.',style:TextStyle(color:muted,fontSize:12)),const SizedBox(height:10),FilledButton.icon(onPressed:()=>launchUrl(Uri.parse('$site/sovereign-admin'),mode:LaunchMode.externalApplication),icon:const Icon(Icons.open_in_new),label:const Text('Open Sovereign Desk dashboard'),style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:ink))])),
 const SizedBox(height:14),OutlinedButton.icon(onPressed:widget.signOut,icon:const Icon(Icons.logout),label:const Text('Sign out of Sovereign Desk'))])));}
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
          ...['bank_name','account_name','account_number','wallet_network','wallet_asset','wallet_address','instructions'].where((k)=>selected[k]!=null&&selected[k].toString().isNotEmpty).map((k)=>Padding(padding:const EdgeInsets.only(bottom:4),child:Text(k.replaceAll('_',' ').toUpperCase()+': '+selected[k].toString(),style:const TextStyle(fontSize:11,color:muted)))),
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
      const Text('ONLINE COOPERATIVE VERIFICATION',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:6),const Text('Contact the Cooperative administrator and confirm the submitted name/email before approving. Keep uncertain requests pending.',style:TextStyle(color:muted)),
      if(message!=null)Padding(padding:const EdgeInsets.all(8),child:Text(message!,style:const TextStyle(color:gold))),
      if(items.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No pending connection requests.',textAlign:TextAlign.center,style:TextStyle(color:muted))),
      ...items.map((x){final id=(x['id'] as num).toInt();final note=notes.putIfAbsent(id,()=>TextEditingController());return Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text((x['memberName']??'Member').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),
        const SizedBox(height:4),Text('Member email: ${x['memberEmail']??'—'}'),
        Text('Registered name: ${x['registeredName']??'—'}'),Text('Registered email: ${x['registeredEmail']??'—'}'),
        Text('Submitted: ${x['createdAt']??'—'}',style:const TextStyle(color:muted,fontSize:10)),
        const SizedBox(height:10),TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Review note (required for rejection)',border:OutlineInputBorder())),
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
      const Text('ADMIN CONTROL & PERMISSIONS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:6),const Text('Green = full category access. Gold = only the selected actions. Red = no category access. Only the Super Admin can change these controls.',style:TextStyle(color:muted)),
      if(message!=null)Padding(padding:const EdgeInsets.all(8),child:Text(message!,style:const TextStyle(color:gold))),
      ...admins.where((a)=>(a['role']??'').toString()!='super_admin').map((admin){
        final memberId=(admin['memberId'] as num).toInt();
        return Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((admin['fullName']??admin['email']??'Administrator').toString(),style:const TextStyle(color:gold,fontWeight:FontWeight.w900)),
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
      const Text('OFFICIAL SOCIAL LINKS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:6),const Text('Only HTTPS links are accepted. Empty platforms stay hidden from members; never enter personal links here unless explicitly intended to be public.',style:TextStyle(color:muted)),
      if(message!=null)Padding(padding:const EdgeInsets.all(8),child:Text(message!,style:const TextStyle(color:gold))),
      ...items.map((item){
        final key=(item['key_name']??'other').toString();
        labels.putIfAbsent(key,()=>TextEditingController(text:(item['label']??key).toString()));
        urls.putIfAbsent(key,()=>TextEditingController(text:(item['url']??'').toString()));
        active.putIfAbsent(key,()=>item['active']==true||item['active']==1);
        return Card(color:widget.dark?panel:Colors.white,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(key.toUpperCase(),style:const TextStyle(color:gold,fontWeight:FontWeight.w900))),Switch(value:active[key]!,activeThumbColor:gold,onChanged:(v)=>setState(()=>active[key]=v),)]),
          TextField(controller:labels[key],decoration:const InputDecoration(labelText:'Public label',border:OutlineInputBorder())),
          const SizedBox(height:8),TextField(controller:urls[key],keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'HTTPS URL (blank hides the link)',border:OutlineInputBorder())),
          Align(alignment:Alignment.centerRight,child:FilledButton(onPressed:saving.contains(key)?null:()=>save(key),child:Text(saving.contains(key)?'Saving…':'Save')))
        ])));
      }),
      OutlinedButton.icon(onPressed:reload,icon:const Icon(Icons.refresh),label:const Text('Reload links'))
    ]);
  });
}
