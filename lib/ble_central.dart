import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:logging/logging.dart';
import 'package:ssi_ble_package/ble_utils.dart';
import 'package:ssi_ble_package/message_buffer.dart';

class BleCentral {
  static BleCentral? _bleCentral;

  /// Clase encargada de manejar la Central de BLE
  final CentralManager _centralManager = CentralManager();

  /// Array de dispositivos encontrados Adversting
  List<DiscoveredEventArgs> _arDiscoverys = [];

  /// Bandera para saber si ya se esta buscando dispositivos
  bool _discovering = false;

  /// Lista de Streams, que manejan
  /// Cambios en estado de conexion => Dispositivo conectado o no al periferico
  // late final StreamSubscription _connectionStateChangedSubscription;

  /// Estado del Bluetooth Encendido apagado (Para pedir permisos)
  // late final StreamSubscription _stateChangedSubscription;

  /// Stream que se va llenando con los dispositivos encontrados
  // late final StreamSubscription _discoveredSubscription;

  /// Stream con la notificacion recibida desde el Periferico
  // late final StreamSubscription _characteristicNotifiedSubscription;

  /// Bandera que me indica si los Stream ya han sido inicializados
  bool _subscripcionesCargadas = false;

  /// Este es el periferico al cual me debo conectar (Dispostivo en modo Adversting => Tendra el UUID de SSI)
  late Peripheral _peripheralSsi;

  /// Esta es la caracteristica que me habilita el write y read del Adversting
  late GATTCharacteristic _characteristicSsi;

  /// Esta es la caracteristica que me habilita el ping
  late GATTCharacteristic _characteristicPing;

  /// Bandera que me indica si ya se logro conectar con el dispositivo Adversting
  bool _peripheralConectado = false;

  /// El WriteType, solo me define la respuesta del Adverstingo o no respuesta, cuando se le realiza un Write
  final GATTCharacteristicWriteType _writeType =
      GATTCharacteristicWriteType.withResponse;

  //? Stream que captura cuando el mensaje llega del periferico
  final Map<int, MessageBuffer> _messageBuffers = {};

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<bool> _disconnectController =
      StreamController<bool>.broadcast();

  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<bool>? _disconnectSubscription;

  BleCentral._();

  // Método para obtener la instancia
  static BleCentral obtenerInstancia() {
    // Verifica si ya existe una instancia, de lo contrario la inicializa
    _bleCentral ??= BleCentral._();
    _bleCentral!._cargarSuscripciones();
    // Devuelve la instancia existente o recién creada
    return _bleCentral!;
  }

  BluetoothLowEnergyState get state => _centralManager.state;
  bool get discovering => _discovering;
  bool get peripheralSsiEncontrado => _peripheralConectado;
  // // Stream público para que el usuario se suscriba
  // Stream<String> get onMessageReceived => _messageController.stream;
  // // Stream público para que el usuario se suscriba
  // Stream<bool> get onDisconnectStream => _disconnectController.stream;

  void _cargarSuscripciones() {
    if (hierarchicalLoggingEnabled) {
      _centralManager.logLevel = Level.INFO;
    }
    if (_subscripcionesCargadas) {
      //!Ya se han cargado las subscripciones
      return;
    }

    _centralManager.stateChanged.listen((eventArgs) async {
      if (eventArgs.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _centralManager.authorize();
      }
    });

    _centralManager.discovered.listen((eventArgs) async {
      final peripheral = eventArgs.peripheral;
      final index = _arDiscoverys.indexWhere((i) => i.peripheral == peripheral);
      if (index < 0) {
        _arDiscoverys.add(eventArgs);
      } else {
        _arDiscoverys[index] = eventArgs;
      }
    });

    _centralManager.connectionStateChanged.listen((eventArgs) {
      if (eventArgs.peripheral != _peripheralSsi) {
        return;
      }
      if (eventArgs.state == ConnectionState.connected) {
        _peripheralConectado = true;
      } else {
        _peripheralConectado = false;
      }
    });

    _centralManager.characteristicNotified.listen((eventArgs) {
      if (eventArgs.characteristic != _characteristicSsi) {
        return;
      }

      final value = eventArgs.value;

      //Si tienen el mismo length de disconnect, se valida si es el mensaje de disconnect, de ser hace se lanza evento de desconexion
      if (value.length == dataDisconnect.length) {
        if (listEquals(value, dataDisconnect)) {
          _disconnectController.add(false);
          // desconectarDispositivos(notificar: false);
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
        // Elimina el buffer del mensaje recibido
        _messageBuffers.remove(messageId);
      }
    });

    _subscripcionesCargadas = true;
  }

  Future<void> startDiscovery({
    List<UUID>? serviceUUIDs,
  }) async {
    if (_discovering) {
      return;
    }
    _arDiscoverys.clear();
    await _centralManager.startDiscovery(
      serviceUUIDs: serviceUUIDs,
    );
    _discovering = true;
  }

  Future<void> stopDiscovery() async {
    // await _centralManager.disconnect(_peripheralSsi);
    if (!_discovering) {
      return;
    }
    await _centralManager.stopDiscovery();
    _discovering = false;
  }

  Future<void> _desconectarPeriferico() async {
    await _centralManager.disconnect(_peripheralSsi);
  }

  Future<bool> buscarYConectarPorNombre({required String nombre}) async {
    try {
      await _buscarPerifericoPorNombre(nombre: nombre)
          .timeout(const Duration(seconds: 15));
      return true;
    } on TimeoutException {
      // Si no se ha conectado en 10 segundos, lanzará una TimeoutException
      print('No se pudo conectar en el tiempo estipulado.');
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _buscarPerifericoPorNombre({required String nombre}) async {
    while (!_peripheralConectado) {
      final discoveryPorNombre = _arDiscoverys.where((discovery) {
        return discovery.advertisement.name == nombre;
      });
      if (discoveryPorNombre.isNotEmpty) {
        _peripheralSsi = discoveryPorNombre.first.peripheral;
        await _conectarPeriferico();
        return;
      }
      //!Si no se ha encontrado espera 5 milesimas e intenta nuevamente
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _conectarPeriferico() async {
    await _centralManager.connect(_peripheralSsi);
    while (!_peripheralConectado) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    try {
      if (Platform.isAndroid) {
        int mtuNegociado =
            await _centralManager.requestMTU(_peripheralSsi, mtu: 256);
        print("mtuNegociado => ${mtuNegociado}");
      }
    } catch (e) {
      print("!!!!!!!!!ERROR ASIGNANDO EL MTU");
    }
  }

  Future<void> conectarCaracteristicaSSi() async {
    final services = await discoverGATT();
    final servicePeriferico = services.firstWhere((serv) {
      return serv.uuid == UUID.short(100);
    });
    _characteristicSsi = servicePeriferico.characteristics.firstWhere((char) {
      return char.uuid == UUID.short(201);
    });
    _characteristicPing = servicePeriferico.characteristics.firstWhere((char) {
      return char.uuid == UUID.short(200);
    });
    _iniciarPing();
    await Future.delayed(Duration(seconds: 2));
    //!Una vez conectada la caracteristica se escribe el mensaje de conexion
    // //!Habilito que el Central pueda recibir notificaciones
    await _centralManager.setCharacteristicNotifyState(
      _peripheralSsi,
      _characteristicSsi,
      state: true,
    );
  }

  void _iniciarPing() async {
    while (_peripheralConectado) {
      try {
        final pingResult = await _centralManager.readCharacteristic(
            _peripheralSsi, _characteristicPing);
        print("Ping RESULT =< $pingResult");
        await Future.delayed(const Duration(seconds: 3));
      } catch (e) {
        print("Hubo error en la centrar leyendo el PING!!!!!!!!!");
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> writeMessage({required String mensaje}) async {
    if (_peripheralConectado) {
      final fragmentSize = await _centralManager.getMaximumWriteLength(
        _peripheralSsi,
        type: _writeType,
      );

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

        final type = _writeType;
        await _centralManager.writeCharacteristic(
          _peripheralSsi,
          _characteristicSsi,
          value: dataToSend,
          type: type,
        );
        start = end;
        fragmentNumber++;
      }
    } else {
      print("No se ha conectado al Periferico");
      try {
        await conectarCaracteristicaSSi();
        await writeMessage(mensaje: mensaje);
      } catch (e) {
        print("Error reconectando");
      }
    }
  }

  Future<List<GATTService>> discoverGATT() async {
    return await _centralManager.discoverGATT(_peripheralSsi);
  }

  Future<void> desconectarDispositivos({bool notificar = true}) async {
    if (notificar) {
      try {
        await _centralManager.writeCharacteristic(
          _peripheralSsi,
          _characteristicSsi,
          value: dataDisconnect,
          type: _writeType,
        );
      } catch (e) {
        print("CENTRAL: Error Escribiendo desconexion al Periferico");
      }
    }

    await _desconectarPeriferico();

    _messageBuffers.clear();

    _messageSubscription?.cancel();
    _messageSubscription = null;

    _disconnectSubscription?.cancel();
    _disconnectSubscription = null;
  }

  void subscribeToMessages(
      Function(String) onData, Function? onError, VoidCallback? onDone) {
    if (_messageSubscription != null) {
      _messageSubscription?.cancel();
      _messageSubscription = null;
    }
    _messageSubscription = _messageController.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: false,
    );
  }

  void subscribeToDisconnects(
      Function(bool) onData, Function? onError, VoidCallback? onDone) {
    if (_messageSubscription != null) {
      _disconnectSubscription?.cancel();
      _disconnectSubscription = null;
    }
    _disconnectSubscription = _disconnectController.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: false,
    );
  }
}
