import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:monarch_codex/main.dart';

String _workspaceError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (error.response?.statusCode == 401) return 'Your session expired. Sign in again.';
  }
  return 'We could not complete this request. Check your connection and try again. No wallet balance was changed.';
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.api, required this.member, required this.signOut, required this.light, required this.toggleTheme});
  final MonarchApi api; final Map<String,dynamic> member; final Future<void> Function() signOut; final bool light; final VoidCallback toggleTheme;
  @override State<AdminShell> createState()=>_AdminShellState();
}
class _AdminShellState extends State<AdminShell>{
  late Future<Map<String,dynamic>> data;
  @override void initState(){super.initState();data=widget.api.adminOverview();}
  void reload()=>setState(()=>data=widget.api.adminOverview());
  @override Widget build(BuildContext context){
    final dark=Theme.of(context).brightness==Brightness.dark;
    return Scaffold(appBar:AppBar(automaticallyImplyLeading:false,title:Row(children:[SvgPicture.asset('assets/images/monarch-codex-logo.svg',width:34,height:34),const SizedBox(width:8),const Expanded(child:Text('ADMIN CONTROL CENTRE',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900)))]),actions:[IconButton(onPressed:widget.toggleTheme,icon:const Icon(Icons.contrast,color:gold)),IconButton(onPressed:reload,icon:const Icon(Icons.refresh,color:gold))]),
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
          const SizedBox(height:14),Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:dark?panel:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:dark?const Color(0xFF302E29):const Color(0xFFE4DFD2))),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('SECURITY & FINANCIAL CONTROL',style:TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:11)),SizedBox(height:8),
            Text('This is a separate administrator workspace. Member navigation is not shown here. Financial requests remain pending until reviewed; this dashboard never edits wallet balances.',style:TextStyle(color:muted,fontSize:12,height:1.5)),
          ])),
          const SizedBox(height:12),OutlinedButton.icon(onPressed:widget.signOut,icon:const Icon(Icons.logout),label:const Text('Sign out of administrator account')),
        ]);
      }));
  }
  Widget _stat(String label,dynamic value,IconData icon,bool dark)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:dark?panel:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:dark?const Color(0xFF302E29):const Color(0xFFE4DFD2))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:gold,size:20),const SizedBox(height:10),Text((value??'—').toString(),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:3),Text(label,style:const TextStyle(color:muted,fontSize:9,fontWeight:FontWeight.w900))]));
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
        DropdownButtonFormField<String>(value:currency,decoration:const InputDecoration(labelText:'Deposit currency'),items:const[DropdownMenuItem(value:'NGN',child:Text('Nigerian Naira (NGN)')),DropdownMenuItem(value:'USD',child:Text('US Dollar (USD)'))],onChanged:busy?null:(v)=>setState(() { currency=v??'NGN'; methodId=''; })),
        const SizedBox(height:10),if(methods.isEmpty)const Message(text:'No active payment methods are configured for this currency. Contact support.',success:false),
        if(methods.isNotEmpty)DropdownButtonFormField<String>(value:methodId,isExpanded:true,decoration:const InputDecoration(labelText:'Payment destination'),items:methods.map((m)=>DropdownMenuItem(value:m['id'].toString(),child:Text((m['label']??m['method_type']??'Payment method').toString(),overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:(v)=>setState(()=>methodId=v??'')),
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
        DropdownButtonFormField<String>(value:currency,decoration:const InputDecoration(labelText:'Currency'),items:const[DropdownMenuItem(value:'NGN',child:Text('NGN')),DropdownMenuItem(value:'USD',child:Text('USD'))],onChanged:busy?null:(v)=>setState(()=>currency=v??'NGN')),
        const SizedBox(height:10),if(accounts.isNotEmpty)DropdownButtonFormField<String>(value:bankId,isExpanded:true,decoration:const InputDecoration(labelText:'Saved payout account'),items:accounts.map((a)=>DropdownMenuItem(value:a['id'].toString(),child:Text([a['bankName'],a['accountName'],a['accountNumber'],a['label']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' · '),overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:(v)=>setState(()=>bankId=v??'')),
        const SizedBox(height:10),TextFormField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount'),validator:(v){final n=double.tryParse(v??'');return n==null||n<=0?'Enter a valid amount':n>number(available[currency])?'Amount exceeds available balance':null;}),
        const SizedBox(height:10),TextFormField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Note (optional)')),
        const SizedBox(height:12),FilledButton(onPressed:busy||accounts.isEmpty?null:submit,style:FilledButton.styleFrom(backgroundColor:gold,foregroundColor:Colors.black,minimumSize:const Size.fromHeight(50)),child:busy?const CircularProgressIndicator(color:Colors.black):const Text('SUBMIT WITHDRAWAL REQUEST',style:TextStyle(fontWeight:FontWeight.w900))),
        const SizedBox(height:8),const Text('Pending and approved requests reserve funds. Wallet funds are debited only after an administrator verifies the actual payout.',style:TextStyle(color:muted,fontSize:11,height:1.4)),
      ])),
    ]);
  });
}
