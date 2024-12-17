import 'dart:io';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:image/image.dart' as img;


class ZoneData {
  ZoneData({this.value = 0, 
    this.color 
  });
  int value;
  String? color;
}


class BarChartData {
  BarChartData({
    this.width = 0,
    this.height = 0,
    this.zoneCount = 0, 
    this.zones});
  int width = 0;
  int height = 0;
  int zoneCount = 0;
  List<ZoneData>? zones = [];
}


final palettes = <List<String>> [
  <String> [ 'A2AAAD', '000001', 'DB0A58', 'FF671F', '87189D' ],
  <String> [ 'BF1A2F', 'F00699', '454E9E', '018E42', 'F7D002' ],
  <String> [ '0C0A3E', '7B1E7A', 'B33F62', 'F9564F', 'F3C677' ],
];

Future<Response> onRequest(RequestContext context) async {

  final request = context.request;
  final parameters = request.uri.queryParameters;

  const minWidthForLabels = 300;
  const minHeightForLabels = 150;

  final zoneData = <ZoneData>[];

   // parse parameterss
  var width = int.parse(parameters['width']??'322');
  var height = int.parse(parameters['height']??'162');
  final zoneCount = int.parse(parameters['zones']??'0');
  final palette = int.parse(parameters['palette']??'0');
  final showLabels = int.parse(parameters['show_labels']??'0');
   
  if(zoneCount==0) {
    return Response(
      statusCode: 422,
      body: 'No zone data found'
    );
  }

  // hard limits on image width/height
  width  = (width>2000) ? 2000 : width;
  height = (height>1000) ? 1000 : height;
  width  = (width<32) ? 322 : width;
  height = (height<32) ? 162 : height;

  // asseble the zone data
  for (var i = 0; i < zoneCount; i++) {
    // fallback to palettes if no color passed 
    String zoneColor = parameters['zone${i+1}color'] ?? '';
    if(zoneColor==''){
      zoneColor = palettes[0][i%5];
    }
    final zone = ZoneData(
      value: int.parse(parameters['zone${i+1}time'] ?? '0'), 
      color: (palette>0) 
          ? palettes[palette-1][i%5]
          : zoneColor,
      );
    zoneData.add(zone);
  }

  final graphData = BarChartData(
    width: width, 
    height: height,
    zoneCount: zoneCount,
    zones: zoneData,
  );

  Uint8List imageData;
  img.Image image;

  if(showLabels==0 || width<minWidthForLabels || height<minHeightForLabels) {
    image = await getGraphImageBytes(graphData);
  } else {
    image = await getLabelledGraphImageBytes(graphData);
  }

  imageData = img.encodePng(image);

  return Response.bytes(
    body: imageData, 
    headers: {
      'Content-Type': 'image/png',
    },);
}

Future<img.Image> getLabelledGraphImageBytes(BarChartData graphData) async {
  // bar chart values
  const columnPadding = 20;
  final requestedHeight = graphData.height;
  final requestedWidth = graphData.width;

  const fontBreakpointWidth = 640;
  const fontBreakpointHeight = 250;

  var fontFilename = 'Roboto-Medium-32px.ttf.zip';
  var fontHeight = 32;

  var labelHeaderWidth = 244;
  var labelFooterWidth = 400;
  var labelTimeWidth = 45;
  final buildHeight = requestedHeight;
  final buildWidth = requestedWidth;

  if(requestedWidth<=fontBreakpointWidth 
        || requestedHeight<=fontBreakpointHeight) {
    fontHeight = 16;
    fontFilename = 'Roboto-Medium-16px.ttf.zip';
    labelHeaderWidth = labelHeaderWidth~/2;
    labelFooterWidth = labelFooterWidth~/2;
    labelTimeWidth = labelTimeWidth~/2;
  }

  final labelHeaderHeight = fontHeight*2;
  final labelFooterHeight = fontHeight*3;

  final fontZipFile = await File(fontFilename).readAsBytes();
  final font = img.BitmapFont.fromZip(fontZipFile);

  final columnWidth = (buildWidth-columnPadding*2)/graphData.zoneCount;

  final image = img.Image(
    width: buildWidth, 
    height: buildHeight,
    numChannels: 4,
  );

  img.fill(image, color:img.ColorRgba8(255, 255, 255, 0)); // transparent background
  
  // set the height for the graph
  graphData.height = buildHeight - (labelHeaderHeight+labelFooterHeight);

  final chartImage = await getGraphImageBytes(graphData);
  img.compositeImage(image, chartImage, dstX: 0, dstY: labelHeaderHeight);

  var columnCounter = 0;
  for(final zone in graphData.zones!) {
    
    final time = DateTime(0,0,0,0,0,zone.value);
    final displayTime = "${time.minute.toString().padLeft(2,'0')}:${time.second.toString().padLeft(2,'0')}";

    img.drawString(image, displayTime, font: font, 
      x: (20+(columnWidth/2)+(columnCounter*columnWidth)
            -labelTimeWidth).toInt(),
      y: buildHeight+8-labelFooterHeight,
    );

    columnCounter++;
  }

  img.drawString(image, 'ZONE SUMMARY', font: font, 
    x: ((graphData.width-labelHeaderWidth)/2).round(), 
    y: 0,
  );

  img.drawString(image, 'TIME SPENT IN EACH ZONE', font: font, 
    x: ((graphData.width-labelFooterWidth)/2).round(), 
    y: buildHeight-fontHeight,
  );

  return image;
}



Future<img.Image> getGraphImageBytes(BarChartData graphData) async {
  // bar chart values
  const columnPadding = 20;
  const baselineHeight = 2;
  final columnWidth = (graphData.width-columnPadding*2)/graphData.zoneCount;

  // create the image with channels for alpha support
  final image = img.Image(
    width: graphData.width, 
    height: graphData.height,
    numChannels: 4,
  );

  img.fill(image, color:img.ColorRgba8(255, 255, 255, 0)); // transparent background
  // img.fill(image, color:img.ColorRgba8(255, 255, 255, 255)); // or maybe white background
  
  var maxValue = 1;

  for(final zone in graphData.zones ?? <ZoneData>[]) {
    if(zone.value>maxValue) {
      maxValue = zone.value;
    }
  }
  
  final heightFactor = (graphData.height-baselineHeight)/maxValue;

  var columnCounter = 0;
  for(final zone in graphData.zones!) {

    // extract RGB code here
    final colorText = zone.color.toString(); 
    final hexColor = '0xff$colorText'; //eg "0xff4f6872";
    final intColor = int.parse(hexColor);
    final red = (intColor >> 16) & 0xff;
    final green = (intColor >> 8) & 0xff;
    final blue = (intColor >> 0) & 0xff;

    // calculate the position
    final x1 = (columnPadding + (columnWidth*columnCounter)).toInt();
    final x2 = (x1+columnWidth).toInt();
    final y1 = graphData.height-baselineHeight;
    final y2 =(y1-(zone.value*heightFactor)).toInt();

    img.fillRect(image, 
      x1: x1, y1: y1, x2: x2, y2: y2, 
      color: img.ColorRgba8(red, green, blue, 255),
      alphaBlend: false,
    );

    columnCounter++;
  }

  // draw baseline last
  img.drawLine(image,
    x1: 0,
    y1: graphData.height-(baselineHeight-1),
    x2: graphData.width,
    y2: graphData.height-(baselineHeight-1), 
    color: img.ColorRgba8(0, 0, 0, 255),
    thickness: baselineHeight,
  );

  return image;
}
