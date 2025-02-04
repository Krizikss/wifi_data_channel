library wifi_data_channel;

import 'dart:io';

import 'package:venice_core/channels/abstractions/bootstrap_channel.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:venice_core/channels/channel_metadata.dart';
import 'package:venice_core/file/file_chunk.dart';
import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'dart:async';
import 'package:flutter/services.dart';




class WifiDataChannel extends DataChannel {
  WifiDataChannel(super.identifier);
  Socket? client;

  @override
  Future<void> initReceiver(ChannelMetadata data) async {
    // Enable Wi-Fi scanning.
    await WiFiScan.instance.canGetScannedResults(askPermissions: true);
    await WiFiScan.instance.startScan();

    // Loop until we find matching AP.
    WiFiAccessPoint? accessPoint;
    while (accessPoint == null) {
      List<WiFiAccessPoint> results = await WiFiScan.instance.getScannedResults();
      Iterable<WiFiAccessPoint> matching = results.where((element) => element.ssid == data.apIdentifier);

      if (matching.isNotEmpty) {
        accessPoint = matching.first;
      } else {
        await Future.delayed(const Duration(seconds: 1));
        debugPrint("[WifiChannel] No matching AP, rescanning...");
      }
    }

    // Connection to access point.
    await WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: true);
    bool connected = false;
    while (!connected) {
      debugPrint("[WifiChannel] Connecting to AP...");
      connected = await WiFiForIoTPlugin.findAndConnect(data.apIdentifier, password: data.password, withInternet: true);
      await Future.delayed(const Duration(seconds: 1));
    }
    debugPrint("[WifiChannel] Connected to AP.");

    // Opening data connection with host.
    connected = false;
    String address = await getIpAddress();
    while (!connected) {
      try {
        final socket = await Socket.connect(data.address, 62526);
        debugPrint('[WifiChannel] Client is connected to: ${socket.remoteAddress.address}:${socket.remotePort}');
        connected = true;
        client = socket;
      } catch (err) {
        debugPrint("[WifiChannel] $err");
        await Future.delayed(const Duration(seconds: 1));
      }
    }

  }

  @override
  Future<void> initSender(BootstrapChannel channel) async {
    if (await WiFiForIoTPlugin.isEnabled()) {
      await WiFiForIoTPlugin.disconnect();
    }
    await WiFiForIoTPlugin.setWiFiAPEnabled(true);

    String ssid = (await WiFiForIoTPlugin.getWiFiAPSSID())!;
    String key = (await WiFiForIoTPlugin.getWiFiAPPreSharedKey())!;
    String address = await getIpAddress();
    if(!address.startsWith('[WifiChannel]')){
      debugPrint("[WifiChannel] Sender successfully initialized.");
      debugPrint("[WifiChannel]     IP: $address");
      debugPrint("[WifiChannel]     SSID: $ssid");
      debugPrint("[WifiChannel]     Key: $key");

      final server = await ServerSocket.bind(address, 62526);

      await channel.sendChannelMetadata(ChannelMetadata(super.identifier, address, ssid, key));
      server.listen(handleClient);
      await waitWhile(() => client == null);
    }
  }

  Future waitWhile(bool test(), [Duration pollInterval = Duration.zero]) {
    var completer = new Completer();
    check() {
      if (!test()) {
        completer.complete();
      } else {
        new Timer(pollInterval, check);
      }
    }
    check();
    return completer.future;
  }

  void handleClient(Socket clientSocket) {
    debugPrint('[WifiChannel] Connection from ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}');
    client = clientSocket;
  }

  @override
  Future<void> sendChunk(FileChunk chunk) async {
    while (client != null && chunk.data != null) {
      client?.write(chunk.toString());
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Future<void> receiveChunks(Map<int, FileChunk> chunks) async {
    if(client != null) {
      client?.listen((event) {
        String toString = String.fromCharCodes(event);
        List<String> splitted = toString.split(' ');
        FileChunk newChunk = FileChunk(identifier: int.parse(splitted[0]), data: Uint8List.fromList(splitted[1].codeUnits));
        chunks.putIfAbsent(newChunk.identifier, () => newChunk);
      });
      //client.close();
    }
  }

  //TODO: independent from interface name
  Future<String> getIpAddress() async {
    String ipAddress = 'null';
    while(ipAddress == 'null'){
      try{
        var interfaces = await NetworkInterface.list();
        for(var i in interfaces){
          if(i.name == 'wlan0'){
            for(var address in i.addresses){
              if(address.type == InternetAddressType.IPv4){
                ipAddress = address.address;
              }
            }
          }
        }
      } catch(e){
        ipAddress = '[WifiChannel] Failed to get IP address : $e';
      }
    }
    if(ipAddress.startsWith('[WifiChannel]')){
      debugPrint('${ipAddress}');
    }
    return ipAddress;
  }
}