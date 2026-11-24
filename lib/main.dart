import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'energy.dart';
import 'storage.dart';
import 'charts.dart';
import 'forms.dart';

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
      scaffoldBackgroundColor:Colors.white,appBarTheme:const AppBarTheme(backgroundColor:Colors.white,surfaceTintColor:Colors.transparent),
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
  int? billYear;
  bool busy=false;
  late DateTime focus=overviewDay();
  DateTime overviewDay(){
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
  Future<void> importBook() async {
    final path=await bridge.invokeMethod<String>('pick','xlsx');
    if(path==null)return;
    final file=File(path);
    try{
      final sheet=await compute(readBook,await file.readAsBytes());
      if(!mounted)return;
      final out=await Navigator.push<(Preview,bool)>(context,MaterialPageRoute(builder:(_)=>ImportReview(sheet,db)));
      if(out==null)return;
      await db.save(out.$1,out.$2);
      focus=overviewDay(); message('Lastgang gespeichert');
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
      final out=await Navigator.push<(int,int,int?)>(context,MaterialPageRoute(builder:(_)=>const BillForm()));
      if(out==null)return;
      final root=await bridge.invokeMethod<String>('directory');
      final dir=await Directory('$root/rechnungen').create(recursive:true);
      final dest=File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.pdf');
      try{
        await source.copy(dest.path);
        await db.db.insert('bills',{'year':out.$1,'month':out.$2,'cents':out.$3,'path':dest.path});
      }catch(_){if(await dest.exists())await dest.delete();rethrow;}
      await db.load();billYear=out.$1;tab=2;message('Rechnung gespeichert');
    }finally{if(await source.exists())await source.delete();}
  }
  Widget link(String title,IconData icon,Future<void> Function() task)=>ListTile(contentPadding:EdgeInsets.zero,leading:Icon(icon),title:Text(title),trailing:const Icon(Icons.chevron_right),onTap:busy?null:()=>action(task));
  Widget get importLink=>link('Lastgang importieren',Icons.file_download_outlined,importBook);
  Future<void> location()async{
    var s=db.settings['place']??'Uzwil';
    final v=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Standort'),content:TextFormField(initialValue:s,onChanged:(v)=>s=v),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Abbrechen')),
      TextButton(onPressed:()=>Navigator.pop(ctx,s.trim()),child:const Text('Speichern'))]));
    if(v!=null&&v.isNotEmpty)await db.setting('place',v);
  }
  List<Widget> overview(){
    final d=overviewDay(),y=day(local(DateTime.now().millisecondsSinceEpoch)).subtract(const Duration(days:1));
    final b=bucket(db,midnight(d),midnight(d.add(const Duration(days:1))));
    Widget tariff(String name,Color color,double v)=>ListTile(contentPadding:EdgeInsets.zero,leading:Icon(Icons.circle,size:12,color:color),title:Text(name),
      subtitle:Text('${amount(v)} kWh · ${b.total==0?0:(100*v/b.total).round()} %'));
    return [link(db.settings['place']??'Uzwil',Icons.place_outlined,location),const Divider(),
      if(db.readings.isEmpty)...[const Text('Importiere deinen ersten Excel-Lastgang.'),importLink]
      else ...[Text('${d==y?"Gestern · ":""}${date(d)}'),const SizedBox(height:16),Ring(b),const SizedBox(height:12),
        tariff('Hochtarif',htColor,b.ht),const Divider(),tariff('Niedertarif',ntColor,b.nt),
        if(!b.complete)Text('Unvollständig · ${b.count} von ${(b.stop-b.start)~/quarter} Viertelstunden'),
        const Divider(),if(db.settings['import']!=null)Text('Letzter Import · ${date(local(int.parse(db.settings["import"]!)))}')]];
  }
  DateTime get start=>switch(period){0=>focus,1=>focus.subtract(Duration(days:focus.weekday-1)),_=>DateTime.utc(focus.year,focus.month)};
  DateTime get stop=>period==2?DateTime.utc(start.year,start.month+1):start.add(Duration(days:period==0?1:7));
  void step(int n)=>setState(()=>focus=period==2?DateTime.utc(start.year,start.month+n):start.add(Duration(days:n*(period==0?1:7))));
  Future<void> editTariff()async{
    final r=await Navigator.push<(DateTime,Windows)>(context,MaterialPageRoute(builder:(_)=>TariffForm(db,focus)));
    if(r!=null)await db.saveRule(r.$1,r.$2);
  }
  List<Widget> usage(){
    final a=start,z=stop,bars=<Bucket>[];
    if(period==0){
      for(var t=midnight(a);t<midnight(z);t+=quarter){bars.add(bucket(db,t,t+quarter));}
    }else{
      for(var d=a;d.isBefore(z);d=d.add(const Duration(days:1))){
        bars.add(bucket(db,midnight(d),midnight(d.add(const Duration(days:1)))));
      }
    }
    return [Wrap(spacing:6,children:[for(var i=0;i<3;i++)ChoiceChip(label:Text(['Tag','Woche','Monat'][i]),selected:period==i,selectedColor:htColor,
      showCheckmark:false,labelStyle:TextStyle(color:i==period?Colors.white:Colors.black87),onSelected:(_)=>setState(()=>period=i))]),
      Row(children:[IconButton(tooltip:'Zurück',onPressed:()=>step(-1),icon:const Icon(Icons.chevron_left)),
        Expanded(child:Text(period==0?date(a):'${date(a)} – ${date(z.subtract(const Duration(days:1)))}',textAlign:TextAlign.center)),
        IconButton(tooltip:'Weiter',onPressed:()=>step(1),icon:const Icon(Icons.chevron_right))]),
      if(bars.any((b)=>b.count>0))...[
        Text('${amount(bars.fold(0.0,(n,b)=>n+b.total))} kWh',style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:12),Graph(bars,period==0,key:ValueKey('$period-$a')),
        if(bars.any((b)=>!b.complete)) Text('Unvollständig · ${bars.fold(0,(n,b)=>n+(b.stop-b.start)~/quarter-b.count)} Viertelstunden fehlen')
      ]else const Text('Keine Messwerte für diesen Zeitraum.'),
      const Divider(),importLink,const Divider(),link('Tarifzeiten',Icons.schedule,editTariff)];
  }
  List<Widget> archive(){
    final years=db.bills.map((r)=>r['year'] as int).toSet().toList();
    final year=billYear??years.firstOrNull;
    return [if(years.isNotEmpty)DropdownButton<int>(value:year,items:[for(final y in years)DropdownMenuItem(value:y,child:Text('$y'))],onChanged:(v)=>setState(()=>billYear=v)),
      if(years.isEmpty)const Text('Hier findest du deine importierten PDF-Rechnungen.'),
      for(final r in db.bills.where((r)=>r['year']==year))...[
        ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.description_outlined),title:Text(months[(r['month'] as int)-1]),
          subtitle:r['cents']==null?null:Text('CHF ${((r["cents"] as int)/100).toStringAsFixed(2)}'),trailing:const Icon(Icons.open_in_new),
          onTap:()=>action(()=>bridge.invokeMethod<void>('openPdf',r['path']))),const Divider()],
      link('PDF importieren',Icons.file_download_outlined,()async{
        final p=await bridge.invokeMethod<String>('pick','pdf');if(p!=null)await importPdf(p);
      })];
  }
  @override Widget build(BuildContext context){
    const titles=['Übersicht','Verbrauch','Rechnungen'];
    return Scaffold(appBar:AppBar(title:const Row(children:[Icon(Icons.bolt,color:htColor),Text('Stromheftli')])),
      body:SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(20,8,20,24),children:[
        Text(titles[tab],style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:12),
        if(busy)const LinearProgressIndicator(),...switch(tab){0=>overview(),1=>usage(),_=>archive()}])),
      bottomNavigationBar:BottomNavigationBar(currentIndex:tab,selectedItemColor:htColor,onTap:(v)=>setState(()=>tab=v),
        items:const [BottomNavigationBarItem(icon:Icon(Icons.home_outlined),label:'Übersicht'),BottomNavigationBarItem(icon:Icon(Icons.bar_chart),label:'Verbrauch'),BottomNavigationBarItem(icon:Icon(Icons.description_outlined),label:'Rechnungen')]));
  }
}
