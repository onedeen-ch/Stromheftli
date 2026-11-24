import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:stromheftli/energy.dart';
import 'package:stromheftli/main.dart';
import 'package:stromheftli/storage.dart';
import 'package:stromheftli/billing.dart';

Uint8List workbook(){
  final archive=Archive();
  void add(String path,String xml){
    final bytes=utf8.encode(xml);archive.addFile(ArchiveFile(path,bytes.length,bytes));
  }
  add('xl/workbook.xml','<workbook xmlns:r="urn:rel"><sheets><sheet r:id="r1"/></sheets></workbook>');
  add('xl/_rels/workbook.xml.rels','<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>');
  String s(String cell,String value)=>'<c r="$cell" t="inlineStr"><is><t>$value</t></is></c>';
  String n(String cell,num value)=>'<c r="$cell"><v>$value</v></c>';
  final values=[1.124,2.252,1.04,1.144];
  final serial=DateTime.utc(2026,10,1).difference(DateTime.utc(1899,12,30)).inDays;
  add('xl/worksheets/sheet1.xml','<worksheet><sheetData><row r="1">${s("A1","Datum")}${s("B1","Zeit")}${s("C1","Wirkleistung [kW]")}</row>'
    '${List.generate(4,(i){final r=i+2;return '<row r="$r">${i==0?s("A$r","01.10.2026"):n("A$r",serial)}${i==0?s("B$r","00:15:00"):n("B$r",(i+1)/96)}${i==0?s("C$r","1,124"):n("C$r",values[i])}</row>';}).join()}'
    '</sheetData></worksheet>');
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
class UnusedDatabase extends Fake implements Database {}
void main(){
  tz.initializeTimeZones();
  test('Oktober: 3623.195 kWh im Monat, 148 kWh am letzten Samstag',(){
    final start=DateTime.utc(2026,9,30,22);
    final csv=StringBuffer('\ufeffDatum;Uhrzeit;Wirkleistung [kW]\r\n');
    final xml=StringBuffer('<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Datum</t></is></c><c r="B1" t="inlineStr"><is><t>Uhrzeit</t></is></c><c r="C1" t="inlineStr"><is><t>Wirkleistung [kW]</t></is></c></row>');
    for(var i=0;i<2980;i++){
      final end=local(start.millisecondsSinceEpoch+(i+1)*quarter);
      final kw=i==0?62.38:i==2884?22.0:i>=2884?6.0:4.8;
      final value=kw.toString().replaceAll('.',',');
      csv.writeln('${date(end)};${clock(end)};$value');
      final r=i+2;
      xml.write('<row r="$r"><c r="A$r" t="inlineStr"><is><t>${date(end)}</t></is></c><c r="B$r" t="inlineStr"><is><t>${clock(end)}</t></is></c><c r="C$r"><v>$kw</v></c></row>');
    }
    xml.write('</sheetData></worksheet>');
    final archive=ZipDecoder().decodeBytes(workbook());
    final data=utf8.encode(xml.toString());
    archive.addFile(ArchiveFile('xl/worksheets/sheet1.xml',data.length,data));
    for(final bytes in [utf8.encode(csv.toString()),ZipEncoder().encode(archive)!]){
      final p=resolveSheet(readLoad(Uint8List.fromList(bytes)),true);
      expect(p.errors,isEmpty);expect(p.data.length,2980);expect(p.gaps,0);
      final store=Store(UnusedDatabase())..readings.addAll(p.data);
      final month=bucket(store,start.millisecondsSinceEpoch,midnight(DateTime.utc(2026,11)));
      expect(month.total,closeTo(3623.195,1e-8));
      expect(month.ht,closeTo(1267.2,1e-8));expect(month.nt,closeTo(2355.995,1e-8));
      final sat=bucket(store,midnight(DateTime.utc(2026,10,31)),month.stop);
      expect(sat.nt,closeTo(148,1e-8));expect(sat.ht,0);
    }
  });
  test('Zählerzeit am Intervallende: 03:00, 02:15 und erneut 03:00',(){
    final a=DateTime.utc(2026,9,30,22).millisecondsSinceEpoch;
    final sheet=Sheet();
    for(var i=0;i<2980;i++){
      final t=a+i*quarter;
      final l=local(t);
      final wall=DateTime.utc(l.year,l.month,l.day,l.hour,l.minute).add(const Duration(minutes:15));
      // Deterministische Testwerte; keine Kundendaten im Repository.
      final saturday=l.day==31;
      final ht=l.weekday<=5 && l.hour>=7 && l.hour<19;
      final energy=saturday?(i==2979?6.179:1.5):ht?
        (l.day==1&&l.hour==7&&l.minute==0?11.189:0.9):
        (i==0?138.727:1.3);
      sheet.rows.add(Raw(i+2,wall,energy*4));
    }
    final p=resolveSheet(sheet,true);
    expect(p.errors,isEmpty);expect(p.warnings,isEmpty);expect(p.gaps,0);
    expect(p.data.keys,[for(var i=0;i<2980;i++)a+i*quarter]);
    final store=Store(UnusedDatabase())..readings.addAll(p.data);
    final b=bucket(store,a,a+2980*quarter);
    expect(b.ht,closeTo(960.689,1e-8));expect(b.nt,closeTo(2662.506,1e-8));
    expect(b.total,closeTo(3623.195,1e-8));
    final last=bucket(store,midnight(DateTime.utc(2026,10,31)),b.stop);
    expect(last.total,closeTo(148.679,1e-8));
  });
  test('Intervallenergie und Leistung liefern dieselben kWh',(){
    for(final (header,value) in [('Energie [kWh]','1,125'),('Wirkleistung [kW]','4,5'),('Leistung [W]','4500'),('Energie [Wh]','1125')]){
      final csv='Datum;Zeit;$header\n01.10.2026;07:15;$value';
      final p=resolveSheet(readLoad(utf8.encode(csv)),true);
      expect(p.data.values.single,1.125);
      expect(high(p.data.keys.single,standard()),true);
    }
    expect(()=>readLoad(utf8.encode('Datum;Zeit;Zählerstand [kWh]\n01.10.2026;00:15;9000')),throwsFormatException);
  });
  test('Excel Datum/Zeit als Text und Zahlen, kW in kWh',(){
    final p=resolveSheet(readBook(workbook()),true);
    expect(p.errors,isEmpty);expect(p.data.length,4);
    expect(p.data.values.reduce((a,b)=>a+b),closeTo(1.390,1e-12));
    expect(p.data.keys.any((t)=>high(t,standard())),false);
  });
  test('Intervallende am Tarifwechsel und Mitternacht',(){
    final sheet=Sheet()..rows.addAll([Raw(2,DateTime.utc(2026,10,1,7),1),Raw(3,DateTime.utc(2026,10,1,7,15),1),Raw(4,DateTime.utc(2026,10,2),0)]);
    final p=resolveSheet(sheet,true);
    expect(p.data.keys.map((t)=>high(t,standard())),[false,true,false]);
    expect(local(p.data.keys.last).day,1);expect(p.data.values.last,0);
  });
  for(final (d,count) in [(DateTime.utc(2026,3,29),92),(DateTime.utc(2026,10,25),100)]){
    test('Vollständiger Zeitwechsel ${date(d)}',(){
      final sheet=Sheet(),a=midnight(d);
      for(var i=1;i<=count;i++){
        final l=local(a+i*quarter);
        sheet.rows.add(Raw(i+1,DateTime.utc(l.year,l.month,l.day,l.hour,l.minute),1));
      }
      final p=resolveSheet(sheet,true);
      expect(p.data.keys,[for(var i=0;i<count;i++)a+i*quarter]);expect(p.gaps,0);expect(p.errors,isEmpty);expect(p.warnings,isEmpty);
    });
  }
  test('Unbestimmte Herbststunde bleibt sichtbar',(){
    final sheet=Sheet()..rows.add(Raw(2,DateTime.utc(2026,10,25,2,15),2));
    expect(resolveSheet(sheet,true).warnings,isNotEmpty);
    expect(resolveSheet(sheet,true,late:true).data.keys.single-resolveSheet(sheet,true).data.keys.single,4*quarter);
  });
  test('Deduplikation, Korrektur, Regelversion und Wiederöffnen der Datenbank',()async{
    sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
    final dir=await Directory.systemTemp.createTemp('stromheftli-test');
    await databaseFactory.setDatabasesPath(dir.path);
    final store=await Store.open(),p=resolveSheet(readBook(workbook()),true);
    await store.save(p,true);await store.save(p,true);
    expect(store.readings.length,4);
    p.data[p.data.keys.first]=1;await store.save(p,true);
    await store.saveRule(DateTime.utc(2027),List.generate(7,(_)=>[[0,1440]]));
    await store.db.insert('bills',{'year':2026,'month':10,'path':'private.pdf'});
    await store.db.close();
    final reopened=await Store.open();
    expect(reopened.bills.single['month'],10);
    final t=p.data.keys.first;
    final b=bucket(reopened,t,t+4*quarter);
    expect(b.ht,0);expect(b.nt,closeTo(1.390-.281+1,1e-12));
    expect(high(midnight(DateTime.utc(2027)),reopened.windows(midnight(DateTime.utc(2027)))),true);
    expect(reopened.settings['end'],'true');
    await reopened.db.close();await dir.delete(recursive:true);
  });
  test('Rechnungsdaten und anonymisierte MP-Anzeige',(){
    final d=extractBill('Kundenname: Max Muster\nKundennummer: 12345\nMesspunktbezeichnung: 000001358\nZeitraum: 01.09.2026 bis 31.10.2026\nRechnungsbetrag CHF 123.45\nEnergie HT 25.0 Rp./kWh');
    expect(d['customer'],'12345');expect(shortMp(d['mp']),'MP *1358');
    expect(billPeriod(d),'01.09.2026 – 31.10.2026 (2-monatig)');
    expect(d['total'],'123.45');expect(d['ht'],'25.0');
  });
  test('Einspeisung und Bezug bleiben getrennt',(){
    final store=Store(UnusedDatabase()),t=midnight(DateTime.utc(2026,10,1));
    store.readings[t]=3;store.feed[t]=1;
    expect(bucket(store,t,t+quarter).total,3);
    expect(bucket(store,t,t+quarter,export:true).total,1);
  });
  testWidgets('Leerer Start, Import und alle drei Hauptseiten',(tester)async{
    final db=UnusedDatabase();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge,(call)async=>null);
    await tester.pumpWidget(App(Store(db)));await tester.pumpAndSettle();
    expect(find.text('Dashboard'),findsWidgets);
    expect(find.text('Tagesverbrauch gestern'),findsOneWidget);
    await tester.tap(find.text('Verbrauch').first);await tester.pumpAndSettle();
    expect(find.text('Tarifzeiten'),findsOneWidget);
    await tester.tap(find.text('Rechnungen').first);await tester.pumpAndSettle();
    expect(find.text('PDF importieren'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
