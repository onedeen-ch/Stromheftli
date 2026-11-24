import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:timezone/timezone.dart' as tz;

const quarter = 900000;
tz.Location get zurich => tz.getLocation('Europe/Zurich');
DateTime local(int stamp) => tz.TZDateTime.fromMillisecondsSinceEpoch(zurich, stamp);
DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
int midnight(DateTime d) => tz.TZDateTime(zurich,d.year,d.month,d.day).millisecondsSinceEpoch;
String two(int n) => n.toString().padLeft(2,'0');
String date(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
String clock(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String amount(double n) => n.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'),'').replaceFirst(RegExp(r'\.$'),'');
class Raw {
  final int row;
  final DateTime wall;
  final double kw;
  Raw(this.row,this.wall,this.kw);
}
class Sheet {
  String unit='kw';
  final rows=<Raw>[];
  final errors=<String>[];
}
Iterable<XmlElement> tags(XmlNode root,String name) =>
    root.descendants.whereType<XmlElement>().where((e)=>e.name.local==name);
String? attr(XmlElement e,String name) {
  for(final a in e.attributes){if(a.name.local==name)return a.value;}
  return null;
}
DateTime parseDay(String s,bool modern){
  final serial=double.tryParse(s);
  if(serial!=null && serial.isFinite && serial>0 && serial<2958466){
    return (modern?DateTime.utc(1904):DateTime.utc(1899,12,30)).add(Duration(days:serial.floor()));
  }
  final iso=RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);
  final parts=iso?s.split('-').reversed.toList():s.split('.');
  if(parts.length!=3)throw const FormatException('Datum erwartet (TT.MM.JJJJ)');
  final d=int.parse(parts[0]),m=int.parse(parts[1]),y=int.parse(parts[2]);
  final result=DateTime.utc(y,m,d);
  if(result.day!=d || result.month!=m || y<1900)throw const FormatException('Datum ungültig');
  return result;
}
int seconds(String s){
  final v=double.tryParse(s);
  if(v!=null && v>=0 && v<=1)return (v*86400).round();
  final p=s.split(':');
  if(p.length<2 || p.length>3)throw const FormatException('Zeit ungültig');
  final h=int.parse(p[0]),m=int.parse(p[1]),ss=p.length==3?int.parse(p[2]):0;
  if(h<0 || h>24 || m<0 || m>59 || ss!=0 || (h==24 && m!=0))throw const FormatException('Zeit ungültig');
  return h*3600+m*60;
}

class Columns {
  final String dateKey, timeKey, valueKey, unit;
  Columns(this.dateKey,this.timeKey,this.valueKey,this.unit);
  static Columns? detect(Map<String,String> cells){
    String clean(String s)=>s.trim().toLowerCase().replaceAll(RegExp(r'[\s\[\]()]'),'');
    final names={for(final e in cells.entries)clean(e.value):e.key};
    final d=names['datum']??names['date'], t=names['zeit']??names['uhrzeit']??names['time'];
    if(d==null||t==null)return null;
    final pattern=RegExp(r'^(wirkleistung|leistung|wirkenergie|energie|verbrauch|netzbezug|bezug|lastgang|messwert|arbeit|wert)?_?(kwh|wh|kw|w)$');
    final measures=cells.entries.where((e)=>pattern.hasMatch(clean(e.value))).toList();
    if(measures.length!=1)throw const FormatException('Eine eindeutige Intervallwert-Spalte mit Einheit kW, W, kWh oder Wh wird benötigt. Zählerstände werden nicht summiert.');
    final m=measures.single;
    return Columns(d,t,m.key,pattern.firstMatch(clean(m.value))!.group(2)!);
  }
  void append(Sheet sheet,int index,Map<String,String> cells,bool modern){
    if(cells.values.every((s)=>s.trim().isEmpty))return;
    final d=parseDay((cells[dateKey]??'').trim(),modern);
    final sec=seconds((cells[timeKey]??'').trim());
    if(sec%900!=0)throw const FormatException('Zeit ausserhalb des 15-Minuten-Rasters');
    final value=parseValue(cells[valueKey]??'');
    final scale=switch(unit){'w'=>0.001,'wh'=>0.004,'kwh'=>4.0,_=>1.0};
    sheet.rows.add(Raw(index,d.add(Duration(seconds:sec)),value*scale));
  }
}
double parseValue(String input){
  var s=input.trim();
  if(RegExp(r"^\d{1,3}(['’]\d{3})+([.,]\d+)?$").hasMatch(s))s=s.replaceAll(RegExp("['’]"),'');
  final v=double.tryParse(s.replaceAll(',','.'));
  if(v==null||!v.isFinite||v<0)throw FormatException('Ungültiger Messwert: $input');
  return v;
}
Sheet readLoad(Uint8List bytes){
  if(bytes.length>3&&bytes[0]==80&&bytes[1]==75)return readBook(bytes);
  String csv;
  try{csv=utf8.decode(bytes);}on FormatException{csv=latin1.decode(bytes);}
  csv=csv.replaceFirst('\ufeff','').replaceAll('\r\n','\n').replaceAll('\r','\n');
  for(final delimiter in [';','\t',',']){
    final lines=CsvToListConverter(fieldDelimiter:delimiter,eol:'\n',shouldParseNumbers:false).convert(csv);
    Columns? columns;
    final sheet=Sheet();
    for(var i=0;i<lines.length;i++){
      final cells={for(var j=0;j<lines[i].length;j++)j.toString():lines[i][j].toString().trim()};
      if(columns==null){
        columns=Columns.detect(cells);
        if(columns!=null)sheet.unit=columns.unit;
      }else{
        try{columns.append(sheet,i+1,cells,false);}catch(e){sheet.errors.add('Zeile ${i+1}: $e');}
      }
    }
    if(columns!=null)return sheet;
  }
  throw const FormatException('Erwartet werden Datum, Zeit und ein Intervallwert mit Einheit (XLSX oder CSV).');
}
Sheet readBook(Uint8List bytes){
  final zip=ZipDecoder().decodeBytes(bytes);
  XmlDocument read(String name){
    final file=zip.findFile(name);
    if(file==null)throw FormatException('Excel-Datei unvollständig: $name');
    return XmlDocument.parse(utf8.decode(file.content as List<int>));
  }
  final wb=read('xl/workbook.xml');
  final modern=tags(wb,'workbookPr').any((e)=>['true','1'].contains(attr(e,'date1904')));
  final strings=zip.findFile('xl/sharedStrings.xml')==null?<String>[]:
      tags(read('xl/sharedStrings.xml'),'si').map((e)=>tags(e,'t').map((t)=>t.innerText).join()).toList();
  final links=tags(read('xl/_rels/workbook.xml.rels'),'Relationship');
  for(final tab in tags(wb,'sheet')){
    final rel=links.where((e)=>attr(e,'Id')==attr(tab,'id')).firstOrNull;
    if(rel==null)continue;
    final path=Uri.parse('/xl/workbook.xml').resolve(attr(rel,'Target')!).path.substring(1);
    final result=Sheet();
    Columns? columns;
    for(final line in tags(read(path),'row')){
      final index=int.parse(attr(line,'r')??'0');
      try{
        final cells=<String,String>{};
        for(final c in line.childElements.where((e)=>e.name.local=='c')){
          final col=(attr(c,'r')??'').replaceAll(RegExp('[0-9]'),'');
          var value=tags(c,'v').firstOrNull?.innerText??'';
          final type=attr(c,'t');
          if(type=='s')value=strings[int.parse(value)];
          if(type=='inlineStr')value=tags(c,'t').map((t)=>t.innerText).join();
          cells[col]=value.trim();
        }
        if(columns==null){
          columns=Columns.detect(cells);
          if(columns!=null)result.unit=columns.unit;
          continue;
        }
        columns.append(result,index,cells,modern);
      }catch(e){if(columns==null)rethrow;result.errors.add('Zeile $index: $e');}
    }
    if(columns!=null)return result;
  }
  throw const FormatException('Spalten Datum, Zeit und Wirkleistung [kW] fehlen.');
}
class ImportPreview {
  final data=<int,double>{};
  final warnings=<String>[];
  final errors=<String>[];
  int get gaps => data.isEmpty?0:((data.keys.reduce((a,b)=>a>b?a:b)-data.keys.reduce((a,b)=>a<b?a:b))~/quarter+1)-data.length;
}
List<int> candidates(DateTime w){
  final start=w.millisecondsSinceEpoch;
  return {for(final shift in [-86400000,86400000])start-zurich.timeZone(start+shift).offset}
      .where((t){final l=local(t);return l.year==w.year&&l.month==w.month&&l.day==w.day&&l.hour==w.hour&&l.minute==w.minute;}).toList()..sort();
}
ImportPreview resolveSheet(Sheet sheet,bool end,{bool late=false}){
  final p=ImportPreview()..errors.addAll(sheet.errors);
  final options=sheet.rows.map((r)=>candidates(r.wall)).toList();
  final latest=List<int?>.filled(options.length,null);
  int? next;
  for(var i=options.length-1;i>=0;i--){
    final valid=options[i].where((t)=>next==null || t<next).toList();
    latest[i]=valid.lastOrNull;
    next=latest[i];
  }
  int? prev;
  for(var i=0;i<sheet.rows.length;i++){
    final r=sheet.rows[i], all=options[i];
    if(all.isEmpty){p.errors.add('Zeile ${r.row}: Ortszeit existiert nicht');continue;}
    final valid=all.where((t)=>(prev==null || t>prev) && (latest[i]==null || t<=latest[i]!)).toList();
    if(all.length>1 && valid.isEmpty){p.errors.add('Zeile ${r.row}: Winterzeit-Reihenfolge unklar');continue;}
    if(valid.length>1)p.warnings.add('Zeile ${r.row}: doppeldeutige Ortszeit ${clock(r.wall)}');
    final instant=valid.isEmpty?all.first:(late?valid.last:valid.first);
    prev=instant;
    final stamp=instant-(end?quarter:0);
    if(p.data.containsKey(stamp)){p.errors.add('Zeile ${r.row}: Intervall mehrfach in Datei');continue;}
    p.data[stamp]=r.kw*0.25;
  }
  return p;
}
typedef Windows = List<List<List<int>>>;
Windows standard()=>List.generate(7,(i)=>i<5?[[420,1140]]:[]);
bool high(int t,Windows windows){
  final d=local(t), minute=d.hour*60+d.minute;
  return windows[d.weekday-1].any((pair)=>minute>=pair[0] && minute<pair[1]);
}
