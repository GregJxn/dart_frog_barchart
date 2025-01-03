import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart';

import 'package:http/http.dart' as http;

import 'package:dart_frog/dart_frog.dart';
import 'package:image/image.dart' as img;

final palettes = <List<String>>[
  <String>['A2AAAD', '000001', 'DB0A58', 'FF671F', '87189D'],
  <String>['BF1A2F', 'F00699', '454E9E', '018E42', 'F7D002'],
  <String>['0C0A3E', '7B1E7A', 'B33F62', 'F9564F', 'F3C677'],
];

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  final parameters = request.uri.queryParameters;

  // parse parameterss
  var width = int.parse(parameters['width'] ?? '322');
  var height = int.parse(parameters['height'] ?? '162');

  final testDataUrl = 'http://localhost:8080/sfwd_test.json';

  var dataUrl = (parameters['dataUri'] ?? testDataUrl).toString();

  final datapoints = await loadJsonFile(dataUrl);

  if(datapoints.length==0) {
    return Response(statusCode: 422, body: 'No graph data found');
  }

  // hard limits on image width/height
  width = (width > 2000) ? 2000 : width;
  height = (height > 1000) ? 1000 : height;
  width = (width < 32) ? 322 : width;
  height = (height < 32) ? 162 : height;


  Uint8List imageData;
  final image = img.Image(
    width: width,
    height: height,
    numChannels: 4,
  );
  
  // transparent off-white background 
  img.fill(image,
      color: img.ColorRgba8(224, 223, 223, 0)); 

  final barHeight = ((height-21)/5).toInt()+1;
  final solidWhite = img.ColorRgba8(255, 255, 255, 255);

  for (var i = 0; i < 5; i++) {
    
    String zoneColor = palettes[0][i % 5];

    // extract RGB code here
    final colorText = zoneColor;
    final hexColor = '0xff$colorText'; //eg "0xff4f6872";
    final intColor = int.parse(hexColor);
    final red = (intColor >> 16) & 0xff;
    final green = (intColor >> 8) & 0xff;
    final blue = (intColor >> 0) & 0xff;  

    // calculate the position
    
    final y1 = height-(20+(i*barHeight));
    final y2 = y1-barHeight;
  
    img.fillRect(
      image,
      x1: 21,
      y1: y1,
      x2: width,
      y2: y2,
      color: img.ColorRgba8(red, green, blue, 255),
      alphaBlend: false,
    );

    if(i>0) {
      // draw left margin markers
      img.fillRect(
        image,
        x1: 10, y1: y1, x2: 20, y2: y1-1,
        color: solidWhite,
        alphaBlend: false,
      );
    }

  }

  //  draw left margin
  img.drawLine(
    image,
    x1: 20, y1: 0,
    x2: 20, y2: height-21,
    color: solidWhite,
    thickness: 2,
  );


  // draw bottom margin
  img.drawLine(
    image,
    x1: 19, y1: height-20,
    x2: width, y2: height-20,
    color: solidWhite,
    thickness: 2,
  );
  // draw bottom margin markers ? 

  // draw points/lines
  final datapointCount = datapoints.length;
  final graphStepWidth = ((width-42)/datapointCount);

  var minValue = 0;
  var maxValue= 0;

  // find value range
  for (var i = 0; i < datapointCount; i++) {
    final bpm = int.parse((datapoints[i]['bpm'] ?? 0).toString());
    if(i==0) {
      minValue = bpm;
      maxValue = bpm;
    } else {
      if(minValue > bpm) {
        minValue = bpm;
      }
      if(maxValue < bpm) {
        maxValue = bpm;
      }
    }   
  }

  final bpmRange = maxValue - minValue;

  final graphStepHeight = ((height-42)/bpmRange).toInt();

  var prevX = 0;
  var prevY = 0;
  for (var i = 0; i < datapointCount; i++) {
    final bpm = int.parse((datapoints[i]['bpm'] ?? 0).toString());
    final x1 = 21+(i*graphStepWidth).toInt();
    final y1 =  (height-32) - ((bpm-minValue)*graphStepHeight);

    if(i==0) {
      prevX = x1;
      prevY = y1;
    }

    img.drawLine(
    image,
      x1: x1, y1: y1,
      x2: prevX, y2: prevY,
      color: solidWhite,
      thickness: 2,
    );

    prevX = x1;
    prevY = y1;
  }

  imageData = img.encodePng(image);

  return Response.bytes(
    body: imageData,
    headers: {
      'Content-Type': 'image/png',
    },
  );
}

Future<List<Map<String, dynamic>>> loadJsonFile(String filePath) async {

  final httpJsonUrl = Uri.parse(filePath);
  final httpJsonFile = await http.get(httpJsonUrl);
   
  if(httpJsonFile.statusCode!=200) {
    print('HTTP 200 Failed');
    return [];
  }

  try {
    final jsonData = jsonDecode(httpJsonFile.body);
    final cleanData = <Map<String, dynamic>> [];
    if(jsonData is List) {
      for(final item in jsonData){
        var mapItem = item as Map<String, dynamic>;
        cleanData.add(mapItem);
      }
    }
    return cleanData as List<Map<String, dynamic>>;
  } catch(e) {
    print(e);
    return [];
  }
}