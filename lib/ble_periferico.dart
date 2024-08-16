import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:logging/logging.dart';
import 'package:ssi_ble_package/ble_utils.dart';
import 'package:ssi_ble_package/message_buffer.dart';

class BlePeriferico {
  static BlePeriferico? _blePeriferico;

  final PeripheralManager _perifericalManager = PeripheralManager();
  bool _advertising = false;

  final StreamController<String> _messageController =
      StreamController<String>();
  final StreamController<bool> _disconnectController = StreamController<bool>();
  bool _subscripcionesCargadas = false;

  final Map<int, MessageBuffer> _messageBuffers = {};
  Central? _central;

  // Stream público para que el usuario se suscriba
  Stream<String> get onMessageReceived => _messageController.stream;
  // Stream público para que el usuario se suscriba
  Stream<bool> get onDisconnectStream => _disconnectController.stream;

  BlePeriferico._();

  // Método para obtener la instancia
  static BlePeriferico obtenerInstancia() {
    // Verifica si ya existe una instancia, de lo contrario la inicializa
    _blePeriferico ??= BlePeriferico._();
    _blePeriferico!._cargarSuscripciones();
    // Devuelve la instancia existente o recién creada
    return _blePeriferico!;
  }

  void _cargarSuscripciones() {
    if (hierarchicalLoggingEnabled) {
      _perifericalManager.logLevel = Level.INFO;
    }
    if (_subscripcionesCargadas) {
      //!Ya se han cargado las subscripciones
      return;
    }

    _perifericalManager.stateChanged.listen((eventArgs) async {
      if (eventArgs.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _perifericalManager.authorize();
      }
    });
    _perifericalManager.characteristicReadRequested.listen((eventArgs) async {
      final central = eventArgs.central;
      final characteristic = eventArgs.characteristic;
      final request = eventArgs.request;
      final offset = request.offset;
      print("Llego read Request de Central");
      final elements = List.generate(100, (i) => i % 256);
      final value = Uint8List.fromList(elements);
      final trimmedValue = value.sublist(offset);

      await _perifericalManager.respondReadRequestWithValue(
        request,
        value: utf8.encode("Mensaje enviado al readRequest del Central"),
      );
    });

    _perifericalManager.characteristicWriteRequested.listen((eventArgs) async {
      final central = eventArgs.central;
      final characteristic = eventArgs.characteristic;
      final request = eventArgs.request;
      final offset = request.offset;
      final value = request.value;

      //Si tienen el mismo length de disconnect, se valida si es el mensaje de disconnect, de ser hace se lanza evento de desconexion
      if (value.length == dataDisconnect.length) {
        if (listEquals(value, dataDisconnect)) {
          await _perifericalManager.respondWriteRequest(request);
          _disconnectController.add(false);
          desconectarDispositivos(notificar: false);
          return;
        }
      }

      // Extrae el encabezado
      final messageId = bytesToInt(value.sublist(0, 2));
      final fragmentNumber = bytesToInt(value.sublist(2, 3));
      final totalFragments = bytesToInt(value.sublist(3, 4));

      // Extrae los datos del fragmento
      final fragmentData = value.sublist(4);
      // print("--------------------------");
      // print(fragmentData);

      // Busca o crea un buffer para este messageId
      if (!_messageBuffers.containsKey(messageId)) {
        _messageBuffers[messageId] = MessageBuffer(messageId, totalFragments);
      }

      final buffer = _messageBuffers[messageId]!;
      buffer.addFragment(fragmentNumber, fragmentData);

      // Si el mensaje está completo, reensamblalo
      if (buffer.isComplete()) {
        final message = buffer.reassembleMessage();
        _messageController.add(message);
        // _perifericalManager.notifyCharacteristic(central, characteristic,
        //     value: utf8.encode("notificacion LLEGA"));
        // Elimina el buffer del mensaje recibido
        _messageBuffers.remove(messageId);
      }
      await _perifericalManager.respondWriteRequest(request);
    });
    _perifericalManager.characteristicNotifyStateChanged
        .listen((eventArgs) async {
      final central = eventArgs.central;
      final characteristic = eventArgs.characteristic;
      final state = eventArgs.state;
      print("Entro al changeNotify");
      _central = central;
      // Write someting to the central when notify started.
      // if (state) {
      //   final maximumNotifyLength =
      //       await _perifericalManager.getMaximumNotifyLength(central);
      //   final elements = List.generate(maximumNotifyLength, (i) => i % 256);
      //   final value = Uint8List.fromList(elements);
      //   await _perifericalManager.notifyCharacteristic(
      //     central,
      //     characteristic,
      //     value: value,
      //   );
      // }
    });

    _subscripcionesCargadas = true;
  }

  BluetoothLowEnergyState get state => _perifericalManager.state;
  bool get advertising => _advertising;

  Future<void> showAppSettings() async {
    await _perifericalManager.showAppSettings();
  }

  final _characteristicCommunication = GATTCharacteristic.mutable(
    uuid: UUID.short(201),
    properties: [
      GATTCharacteristicProperty.read,
      GATTCharacteristicProperty.write,
      GATTCharacteristicProperty.writeWithoutResponse,
      GATTCharacteristicProperty.notify,
      GATTCharacteristicProperty.indicate,
    ],
    permissions: [
      GATTCharacteristicPermission.read,
      GATTCharacteristicPermission.write,
    ],
    descriptors: [],
  );

  Future<void> startAdvertising() async {
    if (_advertising) {
      return;
    }
    await _perifericalManager.removeAllServices();
    // final elements = List.generate(100, (i) => i % 256);
    // final value = Uint8List.fromList(elements);
    final uuidService = UUID.short(100);
    print("Service es => $uuidService");
    final service = GATTService(
      uuid: uuidService,
      isPrimary: true,
      includedServices: [],
      characteristics: [
        GATTCharacteristic.immutable(
          uuid: UUID.short(200),
          value: utf8.encode("ping"),
          descriptors: [],
        ),
        _characteristicCommunication,
      ],
    );
    await _perifericalManager.addService(service);
    final advertisement = Advertisement(
      name: Platform.isWindows ? null : 'BLE-SSI',
      manufacturerSpecificData: Platform.isIOS || Platform.isMacOS
          ? []
          : [
              ManufacturerSpecificData(
                id: 0x2e19,
                data: Uint8List.fromList([0x01, 0x02, 0x03]),
              )
            ],
    );
    await _perifericalManager.startAdvertising(advertisement);
    _advertising = true;
  }

  Future<void> stopAdvertising() async {
    if (!_advertising) {
      return;
    }
    await _perifericalManager.stopAdvertising();
    _advertising = false;
  }

  Future<void> writeNotificationToCentral({required String mensaje}) async {
    if (_central != null) {
      final fragmentSize =
          await _perifericalManager.getMaximumNotifyLength(_central!);

      //? Mensaje a Enviar
      final value = utf8.encode(mensaje);

      var messageId = Random().nextInt(65536);
      final totalFragments = (value.length / (fragmentSize - 4))
          .ceil(); // Espacio para el encabezado

      var start = 0;
      var fragmentNumber = 0;

      while (start < value.length) {
        final end =
            start + (fragmentSize - 4); // Reserva 4 bytes para el encabezado
        final fragmentedValue = end < value.length
            ? value.sublist(start, end)
            : value.sublist(start);

        // print("-------------------------");
        // print(fragmentedValue);

        // Construye el encabezado
        final header =
            builBledHeader(messageId, fragmentNumber, totalFragments);

        // Agrega el encabezado al fragmento
        final dataToSend = Uint8List.fromList(header + fragmentedValue);

        await _perifericalManager.notifyCharacteristic(
          _central!,
          _characteristicCommunication,
          value: dataToSend,
        );
        start = end;
        fragmentNumber++;
      }
    } else {
      print("No se ha conectado a Central");
    }
  }

  Future<void> desconectarDispositivos({bool notificar = true}) async {
    if (notificar) {
      await _perifericalManager.notifyCharacteristic(
        _central!,
        _characteristicCommunication,
        value: dataDisconnect,
      );
    }
    _messageBuffers.clear();
    _central = null;
    await stopAdvertising();
  }
}
