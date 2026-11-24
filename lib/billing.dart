import 'dart:convert';
import 'package:flutter/material.dart';
import 'energy.dart';

const billFields=<String,String>{
  'name':'Name / Rechnungsempfänger','customer':'Kundennummer',
  'mp':'Messpunktbezeichnung','meter':'Gerätenummer / Zählernummer','meterType':'Zählertyp',
  'issued':'Rechnungsdatum (TT.MM.JJJJ)','from':'Zeitraum von (TT.MM.JJJJ)','to':'Zeitraum bis (TT.MM.JJJJ)',
  'total':'Rechnungsbetrag CHF','ht':'Energie HT (Rp./kWh)','nt':'Energie NT (Rp./kWh)',
  'gridHt':'Netznutzung HT (Rp./kWh)','gridNt':'Netznutzung NT (Rp./kWh)',
  'feedRate':'Rückliefertarif (Rp./kWh)','other':'Weitere Abgaben / Grundpreise / Tarifdetails',
};
Map<String,String> billDetails(Map<String,Object?> row){
  try{
    final v=jsonDecode(row['details'] as String? ?? '{}') as Map;
    return v.map((k,v)=>MapEntry(k.toString(),v.toString()));
  }catch(_){return {};}
}
String shortMp(String? value){
  if(value==null||value.trim().isEmpty)return 'Nicht erfasst';
  final suffix=RegExp(r'\d{4}$').firstMatch(value.trim())?.group(0);
  return suffix==null?'MP $value':'MP *$suffix';
}
DateTime? billDate(String? s){
  if(s==null||s.isEmpty)return null;
  try{return parseDay(s,false);}catch(_){return null;}
}
String billPeriod(Map<String,String> d){
  final a=billDate(d['from']),z=billDate(d['to']);
  if(a==null||z==null)return 'Zeitraum nicht erfasst';
  final end=z.add(const Duration(days:1));
  final n=(end.year-a.year)*12+end.month-a.month;
  final label=n>0&&a.day==1&&end.day==1?' ($n-monatig)':' (${z.difference(a).inDays+1} Tage)';
  return '${date(a)} – ${date(z)}$label';
}
Map<String,String> extractBill(String text){
  final d=<String,String>{};
  void put(String key,String pattern){
    final s=RegExp(pattern,caseSensitive:false,multiLine:true).firstMatch(text)?.group(1)?.trim();
    if(s!=null&&s.isNotEmpty)d[key]=s;
  }
  put('name',r'^[ \t]*(?:Kundenname|Rechnungsempfänger|Name)[ \t]*[:\-]?[ \t]*([^\r\n]+)');
  put('customer',r'\b(?:Kunden(?:nummer|[\s-]*Nr\.?)|Vertragskonto)\s*[:#]?\s*([A-Z0-9][A-Z0-9./-]*)');
  put('mp',r'\b(?:Messpunktbezeichnung|Messpunkt(?:nummer|[\s-]*Nr\.?)?)\s*[:#]?\s*([A-Z0-9][A-Z0-9.-]*)');
  put('meter',r'\b(?:Gerätenummer|Geräte[\s-]*Nr\.?|Zählernummer|Zähler[\s-]*Nr\.?)\s*[:#]?\s*([A-Z0-9][A-Z0-9.-]*)');
  put('meterType',r'\b(?:Zählertyp|Gerätetyp)[ \t]*[:#]?[ \t]*([^\r\n]+)');
  const dt=r'(\d{1,2}\.\d{1,2}\.\d{4})';
  put('issued',r'\b(?:Rechnungsdatum|Datum der Rechnung)\s*[:#]?\s*'+dt);
  final period=RegExp(r'(?:Abrechnungszeitraum|Abrechnungsperiode|Rechnungsperiode|Verbrauchsperiode|Zeitraum)\s*[:#]?\s*'+dt+r'\s*(?:bis|[-–—])\s*'+dt,caseSensitive:false).firstMatch(text);
  if(period!=null){d['from']=period.group(1)!;d['to']=period.group(2)!;}
  put('total',r'\b(?:Rechnungsbetrag|Totalbetrag|Zahlbetrag|Zu bezahlen|Gesamtbetrag|Total inkl\.? MwSt\.?)\s*[: ]*\s*(?:CHF\s*)?(-?[\d’\x27]+[.,]\d{2})');
  const price=r'([0-9]+(?:[.,][0-9]+)?)\s*(?:Rp\.?|Rappen|ct)\s*/\s*kWh';
  put('ht',r'\b(?:Energie\s+HT|Hochtarif(?:\s+Energie)?)\s*[: ]*'+price);
  put('nt',r'\b(?:Energie\s+NT|Niedertarif(?:\s+Energie)?)\s*[: ]*'+price);
  put('gridHt',r'\bNetznutzung\s+HT\s*[: ]*'+price);
  put('gridNt',r'\bNetznutzung\s+NT\s*[: ]*'+price);
  put('feedRate',r'\b(?:Rückliefertarif|Einspeisetarif|Rückliefervergütung)\s*[: ]*'+price);
  final lines=text.split('\n').where((s)=>RegExp(r'Netznutzung|Grundpreis|Abgabe|Energiepreis|Rückliefer|Einspeis|Tarif|Rp\./kWh',caseSensitive:false).hasMatch(s)).take(30).join('\n');
  if(lines.trim().isNotEmpty)d['other']=lines;
  return d;
}
double? money(String? s)=>double.tryParse((s??'').replaceAll(RegExp(r"['’\s]"),'').replaceAll(',','.'));
class BillReview extends StatefulWidget{
  final Map<String,String> initial;
  final String text;
  const BillReview(this.initial,this.text,{super.key});
  @override State<BillReview> createState()=>_BillReview();
}
class _BillReview extends State<BillReview>{
  late final values=Map<String,String>.from(widget.initial);
  String error='';
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Rechnungsdaten prüfen')),
    body:Column(children:[
      Expanded(child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(widget.text.trim().isEmpty?'Kein PDF-Text erkannt. Daten können manuell ergänzt werden.':'Automatisch erkannte Angaben bitte mit der Rechnung abgleichen.'),
        if(widget.text.trim().isNotEmpty)ExpansionTile(title:const Text('PDF-Text ansehen'),children:[SelectableText(widget.text)]),
        for(final f in billFields.entries)Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(initialValue:values[f.key]??'',maxLines:f.key=='other'?4:1,decoration:InputDecoration(labelText:f.value,border:const OutlineInputBorder()),onChanged:(v)=>values[f.key]=v.trim())),
        if(error.isNotEmpty)Text(error,style:const TextStyle(color:Colors.red)),
      ])),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(12),child:FilledButton(onPressed:(){
        for(final k in ['issued','from','to']){
          if((values[k]??'').isNotEmpty&&billDate(values[k])==null){setState(()=>error='Bitte Datumsformat prüfen.');return;}
        }
        final a=billDate(values['from']),z=billDate(values['to']);
        if(a!=null&&z!=null&&z.isBefore(a)){setState(()=>error='Abrechnungszeitraum prüfen.');return;}
        for(final k in ['total','ht','nt','gridHt','gridNt','feedRate']){
          if((values[k]??'').isNotEmpty&&(money(values[k])==null||!money(values[k])!.isFinite)){setState(()=>error='Bitte Beträge und Tarife prüfen.');return;}
        }
        values.removeWhere((_,v)=>v.isEmpty);
        Navigator.pop(context,values);
      },child:const Text('Rechnung speichern'))))
    ]));
}
