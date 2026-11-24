import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'energy.dart';
import 'storage.dart';
import 'charts.dart';
import 'forms.dart';
import 'billing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final store=await Store.open();
  runApp(App(store));
}
class App extends StatelessWidget {
  final Store store;
  const App(this.store,{super.key});
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,title:'Stromheftli',locale:const Locale('de','CH'),
    supportedLocales:const [Locale('de','CH')],localizationsDelegates:GlobalMaterialLocalizations.delegates,
    theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:htColor,primary:htColor,surface:Colors.white),
      scaffoldBackgroundColor:const Color(0xfff1f7fa),appBarTheme:const AppBarTheme(backgroundColor:Colors.white,surfaceTintColor:Colors.transparent),
      dividerTheme:const DividerThemeData(color:Color(0xffdddddd),thickness:.7)),
    home:Home(store));
}
const bridge=MethodChannel('stromheftli/files');
class Home extends StatefulWidget{
  final Store store;
  const Home(this.store,{super.key});
  @override State<Home> createState()=>_Home();
}
class _Home extends State<Home>{
  Store get db=>widget.store;
  int tab=0,period=0;
  bool exportView=false;
  int? billYear;
  bool busy=false;
  late DateTime focus=latestDay();
  DateTime latestDay(){
    final yesterday=day(local(DateTime.now().millisecondsSinceEpoch)).subtract(const Duration(days:1));
    if(db.readings.isEmpty)return yesterday;
    final start=midnight(yesterday),stop=midnight(yesterday.add(const Duration(days:1)));
    if(db.readings.keys.any((t)=>t>=start&&t<stop))return yesterday;
    return day(local(db.readings.keys.reduce((a,b)=>a>b?a:b)));
  }
  @override void initState(){
    super.initState();
    bridge.setMethodCallHandler((call)async{
      if(call.method=='shareReady')await shared();
      if(call.method=='shareError')message('PDF-Empfang fehlgeschlagen: ${call.arguments}');
    });
    WidgetsBinding.instance.addPostFrameCallback((_)=>shared());
  }
  @override void dispose(){bridge.setMethodCallHandler(null);super.dispose();}
  void message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> action(Future<void> Function() task) async {
    if(busy)return;
    setState(()=>busy=true);
    try{await task();}catch(e){message('Vorgang fehlgeschlagen: $e');}
    finally{if(mounted){setState(()=>busy=false);await shared();}}
  }
  Future<void> shared() async{
    if(busy||!mounted)return;
    final path=await bridge.invokeMethod<String>('takeShare');
    if(path!=null && mounted)await action(()=>importPdf(path));
  }
  Future<void> importBook({bool export=false}) async {
    final path=await bridge.invokeMethod<String>('pick','xlsx');
    if(path==null)return;
    final file=File(path);
    try{
      final sheet=await compute(readLoad,await file.readAsBytes());
      if(!mounted)return;
      final out=await Navigator.push<(ImportPreview,bool)>(context,MaterialPageRoute(builder:(_)=>ImportReview(sheet,db,export:export)));
      if(out==null)return;
      await db.save(out.$1,out.$2,export:export);
      final stamps=out.$1.data.keys.toList()..sort();
      final first=day(local(stamps.first)), last=day(local(stamps.last));
      focus=last;exportView=export;tab=1;
      period=first!=last?2:0;
      message(export?'Einspeisung gespeichert':'Verbrauch gespeichert');
    }finally{if(await file.exists())await file.delete();}
  }
  Future<void> importPdf(String path) async{
    final source=File(path);
    try{
      final reader=await source.open();
      late List<int> header;
      try{header=await reader.read(1024);}finally{await reader.close();}
      if(!String.fromCharCodes(header).contains('%PDF-'))throw const FormatException('Keine PDF-Datei');
      if(!mounted)return;
      final text=await pdfText(path);
      if(!mounted)return;
      final out=await Navigator.push<Map<String,String>>(context,MaterialPageRoute(builder:(_)=>BillReview(extractBill(text),text)));
      if(out==null)return;
      final root=await bridge.invokeMethod<String>('directory');
      final dir=await Directory('$root/rechnungen').create(recursive:true);
      final dest=File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.pdf');
      try{
        await source.copy(dest.path);
        await db.db.insert('bills',{...billRow(out),'path':dest.path});
      }catch(_){if(await dest.exists())await dest.delete();rethrow;}
      await db.load();billYear=billRow(out)['year'] as int;tab=2;message('Rechnung gespeichert');
    }finally{if(await source.exists())await source.delete();}
  }
  Widget link(String title,IconData icon,Future<void> Function() task)=>ListTile(contentPadding:EdgeInsets.zero,leading:Icon(icon),title:Text(title),trailing:const Icon(Icons.chevron_right),onTap:busy?null:()=>action(task));
  Widget get importLink=>link('Lastgang importieren',Icons.power,()=>importBook());
  Widget get feedLink=>link('Einspeisung importieren',Icons.solar_power_outlined,()=>importBook(export:true));
  Future<String> pdfText(String path)async{
    try{return await bridge.invokeMethod<String>('extractPdf',path)??'';}catch(_){return '';}
  }
  Map<String,Object?> billRow(Map<String,String> d){
    final stamp=billDate(d['issued'])??billDate(d['to'])??local(DateTime.now().millisecondsSinceEpoch);
    final price=money(d['total']);
    return {'year':stamp.year,'month':stamp.month,'cents':price==null?null:(price*100).round(),'details':jsonEncode(d)};
  }
  Future<void> editBill(Map<String,Object?> row)async{
    final text=await pdfText(row['path'] as String);
    if(!mounted)return;
    final initial=<String,String>{...extractBill(text),...billDetails(row)};
    if(row['cents']!=null)initial.putIfAbsent('total',()=>((row['cents'] as int)/100).toStringAsFixed(2));
    final out=await Navigator.push<Map<String,String>>(context,MaterialPageRoute(builder:(_)=>BillReview(initial,text)));
    if(out==null)return;
    final update=billRow(out);
    if(billDate(out['issued'])==null&&billDate(out['to'])==null){update['year']=row['year'];update['month']=row['month'];}
    await db.db.update('bills',update,where:'id = ?',whereArgs:[row['id']]);
    await db.load();billYear=update['year'] as int;
  }
  Map<String,String> get profile{
    final out=<String,String>{};
    for(final row in db.bills.reversed){
      final d=billDetails(row);
      for(final k in ['name','customer','mp','meter','meterType']){if(d[k]!=null)out[k]=d[k]!;}
    }
    return out;
  }
  Map<String,String> get currentRates=>db.bills.isEmpty?{}:billDetails(db.bills.first);
  Widget panel(List<Widget> children)=>Card(elevation:0,margin:const EdgeInsets.only(bottom:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),color:Colors.white,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:children)));
  Widget heading(String text,IconData icon)=>Row(children:[Icon(icon,color:htColor),const SizedBox(width:8),Expanded(child:Text(text,style:Theme.of(context).textTheme.titleMedium))]);
  Widget detail(String key,String? value)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(key)),Expanded(child:Text(value==null||value.isEmpty?'Nicht erfasst':value,textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.w600)))]));
  Future<void> location()async{
    var s=db.settings['place']??'Uzwil';
    final v=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Standort'),content:TextFormField(initialValue:s,onChanged:(v)=>s=v),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Abbrechen')),
      TextButton(onPressed:()=>Navigator.pop(ctx,s.trim()),child:const Text('Speichern'))]));
    if(v!=null&&v.isNotEmpty)await db.setting('place',v);
  }
  List<Widget> overview(){
    final y=day(local(DateTime.now().millisecondsSinceEpoch)).subtract(const Duration(days:1));
    final a=midnight(y),z=midnight(y.add(const Duration(days:1)));
    final b=bucket(db,a,z),f=bucket(db,a,z,export:true),p=profile,rates=currentRates;
    final latest=db.bills.firstOrNull;
    final d=latest==null?<String,String>{}:billDetails(latest);
    String value(double v)=>b.count==0?'Keine Daten':'${amount(v)} kWh';
    return [
      panel([heading(p['name']??'Mein Stromportal',Icons.person_outline),detail('Kundennummer',p['customer']),detail('Messpunkt',shortMp(p['mp']))]),
      panel([heading('Tagesverbrauch gestern',Icons.power),Text(date(y)),const SizedBox(height:8),
        if(b.count==0)const Text('Keine Messwerte für gestern importiert.') else Ring(b),
        detail('Hochtarif',value(b.ht)),detail('Niedertarif',value(b.nt)),
        if(b.count>0&&!b.complete)Text('Unvollständig · ${b.count} von ${(z-a)~/quarter} Viertelstunden'),
        if(db.rules.isEmpty)const Text('Standard-Tarifzeiten aktiv (Mo–Fr 07:00–19:00 HT). Bitte abgleichen.'),
        importLink]),
      panel([heading('Überschüssiger Strom · gestern',Icons.solar_power_outlined),Text(date(y)),
        Text(f.count==0?'Keine Einspeisedaten':'${amount(f.total)} kWh',style:Theme.of(context).textTheme.headlineSmall),
        if(f.count>0&&!f.complete)Text('Unvollständig · ${f.count} von ${(z-a)~/quarter} Viertelstunden'),feedLink]),
      panel([heading('Letzte Rechnung',Icons.receipt_long_outlined),
        if(latest==null)const Text('Noch keine Rechnung abgelegt.') else ...[
          detail('Rechnungsdatum',d['issued']),detail('Zeitraum',billPeriod(d)),
          detail('Betrag',latest['cents']==null?null:'CHF ${((latest['cents'] as int)/100).toStringAsFixed(2)}'),
          link('Rechnung öffnen',Icons.open_in_new,()=>bridge.invokeMethod<void>('openPdf',latest['path']))],
        link('Rechnungsarchiv',Icons.folder_open,()async{tab=2;})]),
      panel([heading('Mein Zähler',Icons.electric_meter_outlined),detail('Gerätenummer',p['meter']),detail('Zählertyp',p['meterType']),link(db.settings['place']??'Uzwil',Icons.place_outlined,location)]),
      panel([heading('Meine Tarife',Icons.price_change_outlined),detail('Energie HT',rates['ht']==null?null:"${rates['ht']} Rp./kWh"),detail('Energie NT',rates['nt']==null?null:"${rates['nt']} Rp./kWh"),link('Alle Tarife',Icons.chevron_right,()async{tab=3;})]),
    ];
  }
  DateTime get start=>switch(period){0=>focus,1=>focus.subtract(Duration(days:focus.weekday-1)),2=>DateTime.utc(focus.year,focus.month),3=>DateTime.utc(focus.year),_=>DateTime.utc(focus.year-4)};
  DateTime get stop=>switch(period){2=>DateTime.utc(start.year,start.month+1),3=>DateTime.utc(start.year+1),4=>DateTime.utc(start.year+5),_=>start.add(Duration(days:period==0?1:7))};
  void step(int n)=>setState(()=>focus=switch(period){2=>DateTime.utc(start.year,start.month+n),3=>DateTime.utc(focus.year+n),4=>DateTime.utc(focus.year+5*n),_=>start.add(Duration(days:n*(period==0?1:7)))});
  Future<void> editTariff()async{
    final r=await Navigator.push<(DateTime,Windows)>(context,MaterialPageRoute(builder:(_)=>TariffForm(db,focus)));
    if(r!=null)await db.saveRule(r.$1,r.$2);
  }
  List<Widget> usage(){
    final a=start,z=stop,bars=<Bucket>[];
    Bucket measure(int x,int y)=>bucket(db,x,y,export:exportView);
    if(period==0){for(var t=midnight(a);t<midnight(z);t+=quarter){bars.add(measure(t,t+quarter));}}
    else if(period>=3){for(var d=a;d.isBefore(z);){final next=period==3?DateTime.utc(d.year,d.month+1):DateTime.utc(d.year+1);bars.add(measure(midnight(d),midnight(next)));d=next;}}
    else{for(var d=a;d.isBefore(z);d=d.add(const Duration(days:1))){bars.add(measure(midnight(d),midnight(d.add(const Duration(days:1)))));}}
    final total=bars.fold(0.0,(n,b)=>n+b.total);
    final missing=bars.fold(0,(n,b)=>n+(b.stop-b.start)~/quarter-b.count);
    final comparable=period==4&&bars.length==5&&bars[3].complete&&bars[4].complete&&bars[3].total>0;
    return [
      SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('Netzbezug'),icon:Icon(Icons.power)),ButtonSegment(value:true,label:Text('Einspeisung'),icon:Icon(Icons.solar_power_outlined))],selected:{exportView},onSelectionChanged:(s)=>setState(()=>exportView=s.single)),
      exportView?feedLink:importLink,
      Wrap(spacing:6,children:[for(var i=0;i<5;i++)ChoiceChip(label:Text(['Tag','Woche','Monat','Jahr','5 Jahre'][i]),selected:period==i,onSelected:(_)=>setState(()=>period=i))]),
      Row(children:[IconButton(tooltip:'Zurück',onPressed:()=>step(-1),icon:const Icon(Icons.chevron_left)),
        Expanded(child:Text(period==0?date(a):'${date(a)} – ${date(z.subtract(const Duration(days:1)))}',textAlign:TextAlign.center)),
        IconButton(tooltip:'Weiter',onPressed:()=>step(1),icon:const Icon(Icons.chevron_right))]),
      if(bars.any((b)=>b.count>0))...[
        Text('${amount(total)} kWh',style:Theme.of(context).textTheme.titleLarge),
        Text('HT ${amount(bars.fold(0.0,(n,b)=>n+b.ht))} kWh · NT ${amount(bars.fold(0.0,(n,b)=>n+b.nt))} kWh'),
        if(period==4)Text(comparable?'Veränderung zum Vorjahr: ${((bars[4].total/bars[3].total-1)*100).toStringAsFixed(1)} %':'Jahrestrend: zwei vollständige Jahre erforderlich.'),
        if(period==3)Builder(builder:(_){
          final previous=measure(midnight(DateTime.utc(a.year-1)),midnight(a));
          return Text(missing==0&&previous.complete&&previous.total>0?'Zum Vorjahr: ${((total/previous.total-1)*100).toStringAsFixed(1)} %':'Vorjahresvergleich erst bei vollständigen Jahresdaten.');
        }),
        const SizedBox(height:12),Graph(bars,period==0,period:period,key:ValueKey('$period-$a-$exportView')),
        if(missing>0) Text('Unvollständig · $missing Viertelstunden fehlen')
      ]else const Text('Keine Messwerte für diesen Zeitraum.'),
      const Divider(),link('Tarifzeiten',Icons.schedule,editTariff)];
  }
  List<Widget> tariffs(){
    final p=currentRates;
    return [panel([heading('Energie und Netznutzung',Icons.electric_meter_outlined),
      for(final k in ['ht','nt','gridHt','gridNt','feedRate'])detail(billFields[k]!,p[k]==null?null:"${p[k]} Rp./kWh"),
      if(p['other']!=null)SelectableText(p['other']!),
      const Text('Preise aus der letzten bestätigten Rechnung. Tarifzeiten werden separat gepflegt.'),
      link('Tarifzeiten',Icons.schedule,editTariff)])];
  }
  List<Widget> archive(){
    final years=db.bills.map((r)=>r['year'] as int).toSet().toList();
    final year=billYear??years.firstOrNull;
    return [if(years.isNotEmpty)DropdownButton<int>(value:year,items:[for(final y in years)DropdownMenuItem(value:y,child:Text('$y'))],onChanged:(v)=>setState(()=>billYear=v)),
      if(years.isEmpty)const Text('Hier findest du deine importierten PDF-Rechnungen.'),
      for(final r in db.bills.where((r)=>r['year']==year))...[
        ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.description_outlined),title:Text(months[(r['month'] as int)-1]),
          subtitle:Text('${billPeriod(billDetails(r))}\n${r["cents"]==null?"Betrag nicht erfasst":"CHF ${((r["cents"] as int)/100).toStringAsFixed(2)}"}'),trailing:const Icon(Icons.open_in_new),
          onTap:()=>action(()=>bridge.invokeMethod<void>('openPdf',r['path']))),link('Rechnungsdaten bearbeiten',Icons.edit_outlined,()=>editBill(r)),const Divider()],
      link('PDF importieren',Icons.file_download_outlined,()async{
        final p=await bridge.invokeMethod<String>('pick','pdf');if(p!=null)await importPdf(p);
      })];
  }
  @override Widget build(BuildContext context){
    const titles=['Dashboard','Verbrauch','Rechnungen','Tarife'];
    return Scaffold(appBar:AppBar(title:const Row(children:[Icon(Icons.bolt,color:htColor),Text('Stromheftli')])),
      body:SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(20,8,20,24),children:[
        Text(titles[tab],style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:12),
        if(busy)const LinearProgressIndicator(),...switch(tab){0=>overview(),1=>usage(),2=>archive(),_=>tariffs()}])),
      bottomNavigationBar:BottomNavigationBar(type:BottomNavigationBarType.fixed,currentIndex:tab,selectedItemColor:htColor,onTap:(v)=>setState(()=>tab=v),
        items:const [BottomNavigationBarItem(icon:Icon(Icons.home_outlined),label:'Dashboard'),BottomNavigationBarItem(icon:Icon(Icons.bar_chart),label:'Verbrauch'),BottomNavigationBarItem(icon:Icon(Icons.description_outlined),label:'Rechnungen'),BottomNavigationBarItem(icon:Icon(Icons.price_change_outlined),label:'Tarife')]));
  }
}
