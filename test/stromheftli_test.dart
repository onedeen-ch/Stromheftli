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
  testWidgets('Leerer Start, Import und alle drei Hauptseiten',(tester)async{
    final db=UnusedDatabase();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge,(call)async=>null);
    await tester.pumpWidget(App(Store(db)));await tester.pumpAndSettle();
    expect(find.text('Lastgang importieren'),findsOneWidget);
    await tester.tap(find.text('Verbrauch'));await tester.pumpAndSettle();
    expect(find.text('Tarifzeiten'),findsOneWidget);
    await tester.tap(find.text('Rechnungen'));await tester.pumpAndSettle();
    expect(find.text('PDF importieren'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
