import 'dart:typed_data';

//Uint8List de "Conexion"
final Uint8List dataConexion = Uint8List.fromList([67, 111, 110, 101, 120, 105, 111, 110]);
//Uint8List de "Desconexion"
final Uint8List dataDisconnect = Uint8List.fromList([68, 101, 115, 99, 111, 110, 101, 120, 105, 111, 110]);

List<int> builBledHeader(
    int messageId, int fragmentNumber, int totalFragments) {
  // Convierte los valores en bytes y construye el encabezado
  final messageIdBytes = intToBytes(messageId, 2); // ID de mensaje (2 bytes)
  final fragmentNumberByte =
      intToBytes(fragmentNumber, 1); // Número de fragmento (1 byte)
  final totalFragmentsByte =
      intToBytes(totalFragments, 1); // Total de fragmentos (1 byte)

  return messageIdBytes + fragmentNumberByte + totalFragmentsByte;
}

List<int> intToBytes(int value, int length) {
  final bytes = <int>[];
  for (int i = 0; i < length; i++) {
    bytes.insert(0, value & 0xFF);
    value >>= 8;
  }
  return bytes;
}

int bytesToInt(List<int> bytes) {
  var value = 0;
  for (var byte in bytes) {
    value = (value << 8) | byte;
  }
  return value;
}

bool listEquals<E>(List<E> list1, List<E> list2) {
  if (identical(list1, list2)) {
    return true;
  }

  if (list1.length != list2.length) {
    return false;
  }

  for (var i = 0; i < list1.length; i += 1) {
    if (list1[i] != list2[i]) {
      return false;
    }
  }

  return true;
}