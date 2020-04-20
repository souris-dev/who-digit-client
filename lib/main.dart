import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logger/logger.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:http/http.dart' as http;

void main() {
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(systemNavigationBarColor: Colors.black, systemNavigationBarIconBrightness: Brightness.dark));
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhoDigit',
      debugShowCheckedModeBanner: false,
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
  List<String> predictedVal;

  bool askedToPredict = false;
  bool pingAndVerifyProcessDone = false;

  void pingAndVerify() async {
      Fluttertoast.showToast(msg: 'Initializing...', backgroundColor: Colors.indigo, textColor: Colors.white);
      var loggr = Logger();
      var cl = http.Client();
      var uri = 'https://who-digit-webapp.herokuapp.com/';

      try {
          loggr.d('Initiating connection with server...');
          var resp = await cl.get(uri);

          if (resp.statusCode == 200) {
              pingAndVerifyProcessDone = true;
              loggr.d('Initialization successful!');
              Fluttertoast.showToast(msg: 'Initialization successful!', backgroundColor: Colors.indigo, textColor: Colors.white);
          }
          else {
              pingAndVerifyProcessDone = true;
              throw Exception('Init failed: server error ' + resp.statusCode.toString());
          }

      } catch(e) {
          loggr.e(e);
          loggr.e('Initialization failed!');
          Fluttertoast.showToast(msg: 'Initialization failed!', backgroundColor: Colors.red, textColor: Colors.white);
          Fluttertoast.showToast(msg: 'Check your internet connection', backgroundColor: Colors.deepOrangeAccent, textColor: Colors.white);
      } finally {
          pingAndVerifyProcessDone = true;
          cl.close();
      }
  }

  @override
  void initState() {
    super.initState();
    drawArea = Handwriter(points);

    // We'll ping the server once to wake the server up
    // and check that the internet and server are working

    pingAndVerify();
  }

  void _clear() {
    setState(() {
      points.clear();
      drawArea = Handwriter(points);
      askedToPredict = false;
      predictedVal = null;
    });
  }

  Future<List<String>> getPrediction(String base64EncodedPic) async {
    var loggr = Logger();
    loggr.d('Contacting server...');
    List<String> pred;
    var client = http.Client();
    var uri = 'https://who-digit-webapp.herokuapp.com/predict?pic=' + base64EncodedPic;

    try {
      loggr.d('Contacting server...');
      var uriResponse = await client.get(uri);

      loggr.d('Response recieved!');
      if (uriResponse.statusCode == 200) {
        // 200 OK
        var loggr = Logger();
        loggr.d('Predictions from server: ' + uriResponse.body);
        pred = <String>[jsonDecode(uriResponse.body)['pred'][0], jsonDecode(uriResponse.body)['pred'][1]];
        loggr.d('Predictions local: ' + pred.toString());

        predictedVal = pred;

        Fluttertoast.showToast(msg: 'Predicted value: ' + predictedVal[0], textColor: Colors.white, backgroundColor: Colors.deepPurple);
      }
      else {
        throw Exception('Server error! Error code: ' + uriResponse.statusCode.toString());
      }
    } catch(e) {
      var loggr = Logger();
      loggr.e("Couldn't get prediction from the server!");
      loggr.e(e.toString());
      Fluttertoast.showToast(msg: 'Failed to get prediction!', backgroundColor: Colors.red, textColor: Colors.white);

      if (e.toString().contains('server'))
        Fluttertoast.showToast(msg: e, backgroundColor: Colors.red, textColor: Colors.white);
      else
        Fluttertoast.showToast(msg: 'Check your internet connection', backgroundColor: Colors.deepOrangeAccent, textColor: Colors.white);
    } finally {
      client.close();
    }

    return pred;
  }

  Canvas getPaintedCanvas(PictureRecorder recorder) {
    Canvas canvas = Canvas(recorder);

    Paint paint = Paint();

    paint.color = Colors.white;
    paint.strokeCap = StrokeCap.round;
    paint.strokeWidth = 28.0;

    canvas.drawColor(Colors.black, BlendMode.src);

    for (int i = 0; i < points.length - 1; i++){
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }

    return canvas;
  }

  Future<void> predict() async {
    if (!askedToPredict) {
      return;
    }
    else {
      askedToPredict = false;
    }

    if (points.length == 0) {
      Fluttertoast.showToast(msg: 'Please draw something!', backgroundColor: Colors.brown, textColor: Colors.white);
      return;
    }

    // Retrieve the image
    var loggr = Logger();

    loggr.d('Started prediction process...');
    String base46EncodedPic;

    try {
      loggr.d('Retrieving image...');

      var pictureRecorder = new PictureRecorder();
      Canvas canvas = new Canvas(pictureRecorder);
      Handwriter painter = Handwriter(points);

      var size = Size.fromWidth(300); // TODO: Should not be hardcoded!
      // if you pass a smaller size here, it cuts off the lines
      painter.paint(canvas, size);
      // if you use a smaller size for toImage, it also cuts off the lines - so I've
      // done that in here as well, as this is the only place it's easy to get the width & height.
      var img = await pictureRecorder.endRecording().toImage(300, 300); // TODO: 300 should not be hardcoded!

      ByteData imgData = await img.toByteData(format: ImageByteFormat.png);
      Uint8List imgDataList = imgData.buffer.asUint8List();

      //imgModule.Image imgNew = imgModule.decodePng(imgDataList);
      //imgNew = imgModule.copyResize(imgNew, width: 28, height: 28, interpolation: imgModule.Interpolation.nearest);

      //imgDataList = imgNew.getBytes();

      base46EncodedPic = base64Encode(imgDataList);

      print('Image retrieved as string: ' + base46EncodedPic);
      print('\nchars: ' + base46EncodedPic.length.toString());
    } catch(e) {
      loggr.e('Error in retrieving and encoding the picture!');
      loggr.e(e);
      Fluttertoast.showToast(msg: 'Error in retrieving image!', backgroundColor: Colors.red, textColor: Colors.white);
    }

    if (base46EncodedPic != null) {
      loggr.d('Contacting server, calling method...');
      var predVal = await getPrediction(base46EncodedPic);

      predictedVal = predVal;

      setState(() {
        if (predVal != null) {
          predictedVal = predVal;
        }
      });
    }
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

    List<Widget> innerWidgets = <Widget>[
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
                  point = point.translate(-70.0, -320.0);//(AppBar().preferredSize.height)); // TODO: should not be hardcoded

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
        onPressed: () {
          setState(() {
            if (pingAndVerifyProcessDone)
              askedToPredict = true;
          });
        },
        color: pingAndVerifyProcessDone == true ? Colors.green : Colors.grey,
      ),
      SizedBox(
            width: double.infinity,
            height: 40
      ),
    ];


    innerWidgets.add(FutureBuilder(
      future: predict(),

      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
            print(predictedVal);
          return Text(
            predictedVal != null ? 'Predictions: ' + predictedVal[0].toString() + ', ' + predictedVal[1].toString() : ''
          );
        }
        else {
          return SizedBox(
            height: 38,
            width: 38,
            child: CircularProgressIndicator(),
          );
        }
      },
    ));


    Widget bodyAll = Scaffold(
      appBar: AppBar(

        title: Text(widget.title),
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: innerWidgets,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _clear,
        tooltip: 'Clear',
        backgroundColor: Colors.red,
        child: Icon(Icons.delete),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );

    return bodyAll;
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

    paint.color = Colors.white;
    paint.strokeCap = StrokeCap.round;
    paint.strokeWidth = 18.0;

    for (int i = 0; i < points.length - 1; i++){
      if (points[i] != null && points[i + 1] != null) {
          canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }
}