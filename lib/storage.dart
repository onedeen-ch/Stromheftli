import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'energy.dart';

class Store {
  final Database db;
  final readings=<int,double>{};
  final feed=<int,double>{};
  final rules=<int,Windows>{};
  final settings=<String,String>{};
  List<Map<String,Object?>> bills=[];
  Store(this.db);
  static Future<Store> open() async {
    final path=await getDatabasesPath();
    final db=await openDatabase('$path/stromheftli.db',version:2,onUpgrade:(db,old,_)async{
      if(old<2){
        await db.execute('CREATE TABLE feed (stamp INTEGER PRIMARY KEY, energy REAL NOT NULL)');
        await db.execute('ALTER TABLE bills ADD COLUMN details TEXT');
      }
    },onCreate:(db,_)async{
      await db.execute('CREATE TABLE readings (stamp INTEGER PRIMARY KEY, energy REAL NOT NULL)');
      await db.execute('CREATE TABLE feed (stamp INTEGER PRIMARY KEY, energy REAL NOT NULL)');
      await db.execute('CREATE TABLE rules (start INTEGER PRIMARY KEY, windows TEXT NOT NULL)');
      await db.execute('CREATE TABLE settings (name TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute('CREATE TABLE bills (id INTEGER PRIMARY KEY, year INTEGER, month INTEGER, cents INTEGER, path TEXT NOT NULL, details TEXT)');
    });
    final store=Store(db);
    await store.load();
    return store;
  }
  Future<void> load() async{
    readings.clear(); feed.clear(); rules.clear(); settings.clear();
    for(final r in await db.query('readings')){ readings[r['stamp'] as int]=(r['energy'] as num).toDouble(); }
    for(final r in await db.query('feed')){feed[r['stamp'] as int]=(r['energy'] as num).toDouble();}
    for(final r in await db.query('rules',orderBy:'start')){
      final decoded=jsonDecode(r['windows'] as String) as List;
      rules[r['start'] as int]=decoded.map((d)=>(d as List).map((w)=>List<int>.from(w)).toList()).toList();
    }
    for(final r in await db.query('settings')){settings[r['name'] as String]=r['value'] as String;}
    bills=await db.query('bills',orderBy:'year DESC, month DESC, id DESC');
  }
  final defaults=standard();
  Windows windows(int t){
    var result=defaults;
    for(final entry in rules.entries){
      if(entry.key>t)break;
      result=entry.value;
    }
    return result;
  }
  Future<void> setting(String key,String value) async{
    await db.insert('settings',{'name':key,'value':value},conflictAlgorithm:ConflictAlgorithm.replace);
    settings[key]=value;
  }
  Future<void> save(ImportPreview p,bool end,{bool export=false}) async{
    final target=export?feed:readings; final table=export?'feed':'readings';
    await db.transaction((tx)async{
      final batch=tx.batch();
      for(final e in p.data.entries){
        if(target[e.key]!=e.value)batch.insert(table,{'stamp':e.key,'energy':e.value},conflictAlgorithm:ConflictAlgorithm.replace);
      }
      for(final e in {(export?'feedEnd':'end'):end.toString(),(export?'feedImport':'import'):DateTime.now().millisecondsSinceEpoch.toString()}.entries){
        batch.insert('settings',{'name':e.key,'value':e.value},conflictAlgorithm:ConflictAlgorithm.replace);
      }
      await batch.commit(noResult:true);
    });
    await load();
  }
  Future<void> saveRule(DateTime start,Windows w) async{
    await db.insert('rules',{'start':midnight(start),'windows':jsonEncode(w)},conflictAlgorithm:ConflictAlgorithm.replace);
    await load();
  }
}
class Bucket {
  final int start,stop;
  double ht=0,nt=0;
  int count=0;
  Bucket(this.start,this.stop);
  double get total=>ht+nt;
  bool get complete=>count==(stop-start)~/quarter;
}
Bucket bucket(Store store,int start,int stop,{bool export=false}){
  final b=Bucket(start,stop);
  for(var t=start;t<stop;t+=quarter){
    final v=(export?store.feed:store.readings)[t];
    if(v==null)continue;
    b.count++;
    if(high(t,store.windows(t))){b.ht+=v;}else{b.nt+=v;}
  }
  return b;
}
