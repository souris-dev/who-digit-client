import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:http/http.dart' as http;

void main() {
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(systemNavigationBarColor: Colors.black));
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhoDigit',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'WhoDigit'),
    );
  }
}

/// Just for future reference
/// class Prediction {
///  final String predictedVal;
///
///  Prediction({this.predictedVal});
///
///  factory Prediction.fromJson(Map<String, dynamic> json) {
///    return Prediction(predictedVal: json['predVal']);
///  }
/// }

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Offset> points = <Offset>[];
  Handwriter drawArea;
  int predictedVal;

  @override
  void initState() {
    super.initState();
    drawArea = Handwriter(points);
  }

  void _clear() {
    setState(() {
      points.clear();
      drawArea = Handwriter(points);
    });
  }

  Future<void> predict() async {
    // Retrieve the image
    var loggr = Logger();
    PictureRecorder recorder = PictureRecorder();
    Canvas canvas = Canvas(recorder);

    String base46EncodedPic;

    try {
      drawArea.paint(canvas, Size.fromWidth(300)); // should not be hardcoded
      Picture pic = recorder.endRecording();

      var img = await pic.toImage(28, 28);
      // 28 x 28 because the NN at the server works on that dimension
      // It's better to decrease the size here for fast transmission to the server

      ByteData imgData = await img.toByteData(format: ImageByteFormat.png);
      Uint8List imgDataList = imgData.buffer.asUint8List();

      String base46EncodedPic = base64Encode(imgDataList);

    } catch(e) {
      loggr.e('Error in retrieving and encoding the picture!');
    }

    if (base46EncodedPic != null) {
      var predVal = await getPrediction(base46EncodedPic);

      setState(() {
        if (predVal != null) {
          predictedVal = int.parse(predVal);
        }
      });
    }
  }

  Future<String> getPrediction(String base64EncodedPic) async {
    String pred;
    var client = http.Client();
    var uri = 'https://who-digit-rec.herokuapp.com/predict?pic=' + base64EncodedPic;

    try {
      var uriResponse = await client.get(uri);

      if (uriResponse.statusCode == 200) {
        // 200 OK
        pred = jsonDecode(uriResponse.body)['predVal'];
      }
      else {
        throw Exception('Server error! Error code: ' + uriResponse.statusCode.toString());
      }
    } catch(e) {
      var loggr = Logger();
      loggr.e("Couldn't get prediction from the server!");
      loggr.e(e.toString());

    } finally {
      client.close();
    }

    return pred;
  }

  Widget getDrawAreaWidget() {
    return DottedBorder(
      color: Colors.blueGrey,
      //radius: Radius.circular(20),
      strokeWidth: 3,
      dashPattern: [14, 5, 7, 5],
      //strokeCap: StrokeCap.round,
      child: Container(
        alignment: Alignment.topLeft,
        margin: EdgeInsets.all(2.0),
        color: Colors.black,
        child: CustomPaint(
          painter: drawArea,
        ),
    ));
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(

        title: Text(widget.title),
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Draw the digit here:'
            ),
            SizedBox(
              width: double.infinity,
              height: 50,
            ),
            SizedBox(
              width: 300,
              height: 300,
              child: GestureDetector(
                    onPanUpdate: (DragUpdateDetails details) {
                      setState(() {
                        RenderBox box = context.findRenderObject();
                        Offset point = box.globalToLocal(details.globalPosition);
                        point = point.translate(-70.0, -320.0);//(AppBar().preferredSize.height));

                        points = List.from(points);
                        points.add(point);
                        drawArea = Handwriter(points);
                      });
                    },
                    onPanEnd: (DragEndDetails details) {
                      setState(() {
                        points.add(null);
                        drawArea = Handwriter(points);
                      });
                    },

                    child: getDrawAreaWidget()
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 50,
            ),
            RaisedButton(
              child: Text(
                'Predict'
              ),
              onPressed: predict,
            ),
            SizedBox(
              width: double.infinity,
              height: 20
            ),

            FutureBuilder(
              future: predict(),
              builder: (context, snap) {

              }
            ),

            Text(
              predictedVal != null ? 'Predicted value: $predictedVal' : 'No prediction!'
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _clear,
        tooltip: 'Clear',
        backgroundColor: Colors.red,
        child: Icon(Icons.delete),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

class Handwriter extends CustomPainter {
  List<Offset> points;

  Handwriter(this.points);

  @override
  bool shouldRepaint(Handwriter oldDelegate) {
    return oldDelegate.points != points;
  }

  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();

    var loggr = Logger();
    loggr.d(size);

    paint.color = Colors.white;
    paint.strokeCap = StrokeCap.round;
    paint.strokeWidth = 12.0;

    for (int i = 0; i < points.length - 1; i++){
      if (points[i] != null && points[i + 1] != null) {
          canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }
}