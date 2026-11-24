import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'energy.dart';
import 'storage.dart';

const htColor=Color(0xff0873b8),ntColor=Color(0xff13a785);
class Ring extends StatelessWidget{
  final Bucket value;
  const Ring(this.value,{super.key});
  @override Widget build(BuildContext context)=>Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:215),child:AspectRatio(aspectRatio:1,child:Stack(alignment:Alignment.center,children:[
    Positioned.fill(child:CustomPaint(painter:_Arc(value))),
    FractionallySizedBox(widthFactor:.80,child:Column(mainAxisSize:MainAxisSize.min,children:[
      FittedBox(fit:BoxFit.scaleDown,child:Text('${amount(value.total)} kWh',style:Theme.of(context).textTheme.headlineSmall)),
      const Text('Gesamtverbrauch',textAlign:TextAlign.center)
    ]))
  ]))));
}
class _Arc extends CustomPainter{
  final Bucket b;
  _Arc(this.b);
  @override void paint(Canvas c,Size s){
    final rect=(Offset.zero&s).deflate(9);
    final brush=Paint()..style=PaintingStyle.stroke..strokeWidth=14..color=b.total==0?const Color(0xffdedede):ntColor;
    c.drawOval(rect,brush);
    if(b.total>0)c.drawArc(rect,-math.pi/2,2*math.pi*b.ht/b.total,false,brush..color=htColor);
  }
  @override bool shouldRepaint(_Arc old)=>old.b.ht!=b.ht||old.b.nt!=b.nt;
}
class Graph extends StatefulWidget{
  final List<Bucket> bars;
  final bool hours;
  final int period;
  const Graph(this.bars,this.hours,{super.key,this.period=0});
  @override State<Graph> createState()=>_Graph();
}
class _Graph extends State<Graph>{
  int? selected;
  String label(Bucket b){
    final d=local(b.start);
    if(widget.period==4)return '${d.year}';
    if(widget.period==3)return '${two(d.month)}.${d.year}';
    return widget.hours?'${date(d)} · ${clock(d)} ${d.timeZoneName}':date(d);
  }
  @override Widget build(BuildContext context){
    final bars=widget.bars;
    final maxValue=bars.fold(0.0,(v,b)=>math.max(v,b.total));
    final b=selected==null||selected!>=bars.length?null:bars[selected!];
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('kWh · Skala 0–${amount(maxValue)}',style:Theme.of(context).textTheme.bodySmall),
      LayoutBuilder(builder:(context,box){
        final width=math.max(box.maxWidth,bars.length*(widget.hours?14.0:18.0));
        return SingleChildScrollView(scrollDirection:Axis.horizontal,child:SizedBox(width:width,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          for(int i=0;i<bars.length;i++)Expanded(child:Semantics(button:true,label:'${label(bars[i])}: ${bars[i].count==0?"Keine Daten":amount(bars[i].total)}',
            child:InkWell(onTap:()=>setState(()=>selected=i),child:Column(children:[
              Container(height:145,alignment:Alignment.bottomCenter,padding:const EdgeInsets.symmetric(horizontal:1),
                decoration:BoxDecoration(border:Border(bottom:BorderSide(color:i==selected?Colors.black:Colors.black26))),
                child:bars[i].count==0?const SizedBox.shrink():Column(mainAxisSize:MainAxisSize.min,children:[
                  Container(height:maxValue==0?0:137*bars[i].nt/maxValue,color:ntColor),
                  Container(height:maxValue==0?0:137*bars[i].ht/maxValue,color:htColor),
                  if(bars[i].total==0)Container(height:3,color:Colors.black54)
                ])),
              SizedBox(height:24,child:FittedBox(fit:BoxFit.scaleDown,child:Text(widget.hours?
                (local(bars[i].start).minute==0?two(local(bars[i].start).hour):''):
                (widget.period==4?'${local(bars[i].start).year}':widget.period==3?two(local(bars[i].start).month):bars.length==7?['Mo','Di','Mi','Do','Fr','Sa','So'][i]:'${local(bars[i].start).day}'))))
            ]))))
        ])));
      }),
      const Wrap(spacing:16,children:[Text('● HT',style:TextStyle(color:htColor)),Text('● NT',style:TextStyle(color:ntColor))]),
      if(b!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text('${label(b)} · ${b.count==0?"Keine Messwerte":"HT ${amount(b.ht)} · NT ${amount(b.nt)} kWh${b.complete?"":" · lückenhaft"}"}'))
    ]);
  }
}
