import 'package:flutter/material.dart';
import 'energy.dart';
import 'storage.dart';

class ImportReview extends StatefulWidget {
  final Sheet sheet;
  final Store store;
  const ImportReview(this.sheet,this.store,{super.key});
  @override State<ImportReview> createState()=>_Review();
}
class _Review extends State<ImportReview>{
  late bool end=widget.store.settings['end']!='false';
  bool lateHour=false;
  @override Widget build(BuildContext context){
    final p=resolveSheet(widget.sheet,end,late:lateHour);
    final keys=p.data.keys.toList()..sort();
    final changes=keys.where((t)=>widget.store.readings.containsKey(t)&&widget.store.readings[t]!=p.data[t]).toList();
    final same=keys.where((t)=>widget.store.readings[t]==p.data[t]).length;
    String label(int n)=>'${date(local(n))} ${clock(local(n))}';
    return Scaffold(appBar:AppBar(title:const Text('Import prüfen')),body:ListView(padding:const EdgeInsets.all(16),children:[
      DropdownButtonFormField<bool>(value:end,isExpanded:true,items:const [
        DropdownMenuItem(value:true,child:Text('Zeit bezeichnet Intervallende')),
        DropdownMenuItem(value:false,child:Text('Zeit bezeichnet Intervallbeginn'))],
        onChanged:(v)=>setState(()=>end=v!)),
      if(keys.isNotEmpty)...[
        Text('${clock(local(keys.first+(end?quarter:0)))} → Verbrauch von ${clock(local(keys.first))} bis ${clock(local(keys.first+quarter))}'),
        const Divider(),Text('${label(keys.first)} – ${label(keys.last+quarter)}'),
        Text('${keys.length} gültige Intervalle · ${amount(p.data.values.fold(0.0,(a,b)=>a+b))} kWh'),
        Text('${p.gaps} fehlende Intervalle innerhalb der Zeitreihe'),
        Text('$same identisch · ${changes.length} Korrekturen'),
        if(changes.isNotEmpty)ExpansionTile(title:const Text('Korrekturen ansehen'),children:[for(final t in changes)Text('${label(t)}: ${amount(widget.store.readings[t]!)} → ${amount(p.data[t]!)} kWh')]),
      ],
      if(p.warnings.isNotEmpty)...[
        Text(p.warnings.join('\n')),
        SwitchListTile(title:const Text('Spätere Stunde für uneindeutige Zeilen'),value:lateHour,onChanged:(v)=>setState(()=>lateHour=v))],
      if(p.errors.isNotEmpty)ExpansionTile(title:Text('${p.errors.length} fehlerhafte Zeilen werden ausgelassen'),children:[SelectableText(p.errors.join('\n'))]),
      const SizedBox(height:16),FilledButton(onPressed:keys.isEmpty?null:()=>Navigator.pop(context,(p,end)),child:Text(changes.isEmpty?'Import bestätigen':'Import und Korrekturen bestätigen'))
    ]));
  }
}
const weekdays=['Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag','Sonntag'];
String minuteText(int m)=>'${two(m~/60)}:${two(m%60)}';
class TariffForm extends StatefulWidget{
  final Store store;
  final DateTime initial;
  const TariffForm(this.store,this.initial,{super.key});
  @override State<TariffForm> createState()=>_TariffForm();
}
class _TariffForm extends State<TariffForm>{
  late DateTime start=widget.initial;
  late Windows w=copy();
  Windows copy()=>widget.store.windows(midnight(start)).map((d)=>d.map((p)=>[...p]).toList()).toList();
  String? error;
  DropdownButton<int> picker(int value,int low,int high,ValueChanged<int> set)=>DropdownButton<int>(
    value:value,items:[for(int i=low;i<=high;i+=15)DropdownMenuItem(value:i,child:Text(minuteText(i)))],onChanged:(v)=>setState(()=>set(v!)));
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Tarifzeiten')),body:ListView(padding:const EdgeInsets.all(16),children:[
    ListTile(title:const Text('Gültig ab'),subtitle:Text(date(start)),trailing:const Icon(Icons.calendar_month),onTap:()async{
      final d=await showDatePicker(context:context,initialDate:start,firstDate:DateTime(1900),lastDate:DateTime(2200));
      if(d!=null)setState((){start=day(d);w=copy();});
    }),const Text('Alle Zeiten ausserhalb der HT-Fenster zählen als Niedertarif.'),
    for(var i=0;i<7;i++)...[
      const Divider(),ListTile(contentPadding:EdgeInsets.zero,title:Text(weekdays[i]),subtitle:w[i].isEmpty?const Text('Ganztags NT'):null,
        trailing:IconButton(tooltip:'HT-Fenster hinzufügen',icon:const Icon(Icons.add),onPressed:()=>setState(()=>w[i].add([420,1140])))),
      for(final p in w[i])Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[picker(p[0],0,1425,(v)=>p[0]=v),const Text(' bis '),picker(p[1],15,1440,(v)=>p[1]=v),
        IconButton(tooltip:'Zeitfenster entfernen',icon:const Icon(Icons.close),onPressed:()=>setState(()=>w[i].remove(p)))])
    ],
    if(error!=null)Text(error!),
    FilledButton(onPressed:(){
      for(final d in w){
        d.sort((a,b)=>a[0].compareTo(b[0]));
        for(var i=0;i<d.length;i++){
          if(d[i][0]>=d[i][1] || i>0 && d[i-1][1]>d[i][0]){
            setState(()=>error='Bitte Anfang, Ende und Überschneidungen prüfen.');return;
          }
        }
      }
      Navigator.pop(context,(start,w));
    },child:const Text('Tarifregel speichern'))
  ]));
}
class BillForm extends StatefulWidget{
  const BillForm({super.key});
  @override State<BillForm> createState()=>_BillForm();
}
const months=['Januar','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'];
class _BillForm extends State<BillForm>{
  final now=local(DateTime.now().millisecondsSinceEpoch);
  late int month=now.month;
  late String year=now.year.toString();
  String price='',error='';
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('PDF importieren')),body:ListView(padding:const EdgeInsets.all(16),children:[
    DropdownButtonFormField<int>(decoration:const InputDecoration(labelText:'Rechnungsmonat'),value:month,items:[for(var i=1;i<=12;i++)DropdownMenuItem(value:i,child:Text(months[i-1]))],onChanged:(v)=>setState(()=>month=v!)),
    TextFormField(initialValue:year,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jahr'),onChanged:(v)=>year=v),
    TextFormField(keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Betrag in CHF (optional)'),onChanged:(v)=>price=v.trim().replaceAll(',','.')),
    Text(error),FilledButton(onPressed:(){
      final y=int.tryParse(year),v=double.tryParse(price);
      if(y==null || y<1900 || y>2200 || (price.isNotEmpty && (v==null || !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(price)))){
        setState(()=>error='Bitte Jahr und Betrag prüfen.');return;
      }
      Navigator.pop(context,(y,month,v==null?null:(v*100).round()));
    },child:const Text('Rechnung speichern'))
  ]));
}
