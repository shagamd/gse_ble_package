import 'dart:convert';
import 'dart:typed_data';

class MessageBuffer {
  final int messageId;
  final int totalFragments;
  final List<Uint8List?> fragments;

  MessageBuffer(this.messageId, this.totalFragments) 
    : fragments = List<Uint8List?>.filled(totalFragments, null);

  void addFragment(int fragmentNumber, Uint8List fragmentData) {
    fragments[fragmentNumber] = fragmentData;
  }

  bool isComplete() {
    return !fragments.contains(null);
  }

  String reassembleMessage() {
    final messageBytes = fragments.expand((fragment) => fragment!).toList();
    return utf8.decode(messageBytes);
  }
}