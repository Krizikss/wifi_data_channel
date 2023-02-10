library wifi_data_channel;

import 'dart:io';

import 'package:venice_core/channels/abstractions/bootstrap_channel.dart';
import 'package:venice_core/channels/abstractions/data_channel.dart';
import 'package:venice_core/channels/channel_metadata.dart';
import 'package:venice_core/file/file_chunk.dart';
import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';

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
      debugPrint("[WifiChannel] SSID to find : ${data.apIdentifier}");
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
      debugPrint("[WifiChannel] ssid : ${data.apIdentifier}, password : ${data.password}");
      connected = await WiFiForIoTPlugin.findAndConnect(data.apIdentifier, password: data.password);
      await Future.delayed(const Duration(seconds: 1));
    }
    debugPrint("[WifiChannel] Connected to AP.");

    // Opening data connection with host.
    connected = false;
    while (!connected) {
      try {
        //debugPrint("[WifiChannel] address : ${data.address}");
        //final socket = await Socket.connect(data.address, 62526);
        final socket = await Socket.connect("192.168.43.87", 62526);
        debugPrint('[WifiChannel] Client is connected to: ${socket.remoteAddress.address}:${socket.remotePort}');
        connected = true;
      } catch (err) {
        debugPrint("[WifiChannel] Failed to connect to host, retrying...");
        await Future.delayed(const Duration(seconds: 1));
      }
    }

  }

  @override

  @override
  Future<void> initSender(BootstrapChannel channel) async {
    if (await WiFiForIoTPlugin.isEnabled()) {
      await WiFiForIoTPlugin.disconnect();
    }
    await WiFiForIoTPlugin.setWiFiAPEnabled(true);

    String address = (await WiFiForIoTPlugin.getIP())!;
    String ssid = (await WiFiForIoTPlugin.getWiFiAPSSID())!;
    String key = (await WiFiForIoTPlugin.getWiFiAPPreSharedKey())!;

    debugPrint("[WifiChannel] Sender successfully initialized.");
    debugPrint("[WifiChannel]     IP: $address");
    debugPrint("[WifiChannel]     SSID: $ssid");
    debugPrint("[WifiChannel]     Key: $key");


    final server = await ServerSocket.bind(address, 62526);
    MethodChannel _channel = const MethodChannel('get_ip');
    String ip = await _channel.invokeMethod('getIpAdress');
    debugPrint("getWifiIP : ${ip}");
    await channel.sendChannelMetadata(ChannelMetadata(super.identifier, ip, ssid, key));
    var subscription = server.listen((clientSocket) {
      debugPrint('Connection from ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}');
      client = clientSocket;
    });
    await subscription.asFuture<void>();
  }

  @override
  Future<void> sendChunk(FileChunk chunk) async {
    while (client == null && chunk.data == null) {
      if (client == null) {
        debugPrint("[WifiChannel] Waiting for client to connect...");
        await Future.delayed(const Duration(milliseconds: 500));
      }
      else if (chunk.data == null) {
        debugPrint("[WifiChannel] Waiting for chunk to send...");
        await Future.delayed(const Duration(milliseconds: 500));
      }
      else {
        client!.write(chunk);
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }
}