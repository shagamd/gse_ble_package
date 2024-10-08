import 'dart:async';
import 'dart:developer';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:ssi_ble_package/ble_central.dart';
import 'package:ssi_ble_package/ble_periferico.dart';

void main() {
  runZonedGuarded(onStartUp, onCrashed);
}

void onStartUp() async {
  Logger.root.onRecord.listen(onLogRecord);
  hierarchicalLoggingEnabled = true;
  runApp(const MainApp());
}

void onCrashed(Object error, StackTrace stackTrace) {
  Logger.root.shout('App crached.', error, stackTrace);
}

void onLogRecord(LogRecord record) {
  log(
    record.message,
    time: record.time,
    sequenceNumber: record.sequenceNumber,
    level: record.level.value,
    name: record.loggerName,
    zone: record.zone,
    error: record.error,
    stackTrace: record.stackTrace,
  );
}

const cred =
    "eyJhbGciOiJFZERTQSIsImtpZCI6IkFlZ1hOOUo3MUNJUVd3N1RqaE0tZUhZWlc0NVRmUDB1QzV4SmR1aUhfdzAiLCJ0eXAiOiJ2YytzZC1qd3QifQ.eyJfc2QiOlsiU0xIa19fY3J4UTNtLVlTbnBqbmprc0tWV21yUmRWSDRTbE16b3YzR2tWNCIsImhOakhmUXh2cklQTnhJWlFXVmRtRVNBUGR4anZfb3JIRktobk5XRUhvQjQiLCJjZmgtWV82RXZqOUx4Wk5JUjE4UGFDTWN6ZXpwempqLTdveXFrTE5zS0xRIiwiTU1Nejduc2ZzTjZZQ0E1dlZKLW83Nm50Z0xBV080dFBYTVVzS2JDWDRsdyIsIjBIeEhYcC04ZjdDT0tpLV92RlpKNzREUnpIN2huNEZoaVgtc0U3R29fWjQiLCI4UnBvMWJ2NmpzVEtvLXlleS14bnQxZ2VkUU9KUG1kNnIzRHAwY19VSWxJIiwiMHNlRjJqLW82UTIxeWtZM2FNNUNiS0YtTmdVdWlteF96VTBISl9YUUtIbyIsIldpZ3NSNmlDMGc2VzRBMjVzVnR1c0hxMUI3MUgzSkpIc2VUNmw4eHFISFkiXSwiX3NkX2FsZyI6InNoYS0yNTYiLCJjbmYiOnsiandrIjpudWxsfSwiZXhwIjoxNzUyMTY4MDQ4LCJpYXQiOjE3MjA2MzIwNDgsImlzX292ZXJfMTgiOnRydWUsImlzcyI6Imh0dHBzOi8vdGFsYW8uY28vaXNzdWVyL3BleGtocnpsbWoiLCJzdGF0dXMiOnsic3RhdHVzX2xpc3QiOnsiaWR4Ijo4NDYyOCwidXJpIjoiaHR0cHM6Ly90YWxhby5jby9zYW5kYm94L2lzc3Vlci9zdGF0dXNsaXN0LzEifX0sInZjdCI6Imh0dHBzOi8vY3JlZGVudGlhbHMub3BlbmlkLm5ldC9nYWluLXBvYy1zaW1wbGUtaWRlbnRpdHktY3JlZGVudGlhbCJ9.wJn-MYqWmRPEa5AUnaNcMTuJwoNLou4irxjPlixCal4IbFpqRUzSo7L01xjIGTsrwTs_-toSz9tQaZDjPR9ODw~WyJ1WW1hSUlrMkpRajZKMWdrM1ZQY0ZnIiwgImdpdmVuX25hbWUiLCAiUGF0cmljayJd~WyJfUFp2R01MeUpLSzBITjJwQkh6aG1BIiwgImZhbWlseV9uYW1lIiwgIkRvZSJd~WyJkU0M0QVZkNHRCNmNXX1ZELU5zSENBIiwgImJpcnRoX2RhdGUiLCAiMTk2MS0xMi0wMSJd~WyJOSjVYaXFGMmM0UVVqc1dZMHc3NUp3IiwgImlzc3VpbmdfY291bnRyeSIsICJGUiJd~WyIwTXo1Tm5sS1Y5ZUh6MlNUN18tZTBBIiwgInN0cmVldF9hZGRyZXNzIiwgIjEyMyBNYWluIFN0Il0~WyJwWnJHTmZnSHNrNzVVVUJ0RkhGZWRRIiwgImxvY2FsaXR5IiwgIk5ldyBZb3JrIENpdHkiXQ~WyJ4Y1JMclo1WWotU0N3Y1NzWE5DWWpRIiwgInJlZ2lvbiIsICJOZXcgWW9yayJd~WyIxY1N6M2w2MEdyZWl3bi1uWWxsYVdBIiwgImNvdW50cnkiLCAiVVMiXQ~";

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late BleCentral bleCentral;
  late BlePeriferico blePeriferico;
  String tipoDispositivo = "DESCONECTADO";

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    bleCentral = BleCentral.obtenerInstancia();
    blePeriferico = BlePeriferico.obtenerInstancia();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(tipoDispositivo),
              FilledButton.icon(
                onPressed: () async {
                  await bleCentral.startDiscovery();
                  final dispositivosConectados = await bleCentral
                      .buscarYConectarPorNombre(nombre: "SSI_STEVEN");
                  if (dispositivosConectados) {
                    await bleCentral.stopDiscovery();
                    await bleCentral.conectarCaracteristicaSSi();
                    tipoDispositivo = "CENTRAL";
                    setState(() {});

                    bleCentral.subscribeToMessages(
                        (message) => print("MSG CENTRAL => $message"),
                        (error) => print(error),
                        () => print("Finaliza suscripcion en CENTRAL"));
                    bleCentral.subscribeToDisconnects((connected) async {
                      await bleCentral.desconectarDispositivos(
                          notificar: false);
                      print("Disconnect => $connected");
                    }, (error) => print("Err Conn $error"),
                        () => print("Finaliza Sus Conexion en CENTRAL"));
                  } else {
                    print("No se lograron conectar los dispositivos");
                  }
                },
                icon: const Icon(Icons.abc_outlined),
                label: const Text("Iniciar Busqueda"),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await bleCentral.desconectarDispositivos(notificar: true);
                  tipoDispositivo = "DESCONECTADO";
                  setState(() {});
                },
                icon: const Icon(Icons.abc_outlined),
                label: const Text("Desconectar Periferico"),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await bleCentral.writeMessage(mensaje: cred);
                },
                icon: const Icon(Icons.message),
                label: const Text("Enviar Mensaje"),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await blePeriferico.startAdvertising(bleName: "SSI_STEVEN");
                  try {
                    blePeriferico.subscribeToMessages((message) {
                      print("LE LLEGO MENSAJE AL PERIFERICO => $message");
                    }, (er) {
                      print("Error: $er");
                    }, () {
                      print("Finalizo el Stream");
                    });
                    blePeriferico.subscribeToDisconnects((message) async {
                      print("LE LLEGO Disconnect AL PERIFERICO => $message");
                      await blePeriferico.desconectarDispositivos(
                          notificar: false);
                    }, (er) {
                      print("Error: $er");
                    }, () {
                      print("Finalizo el Stream");
                    });
                    tipoDispositivo = "PERIFERICO";
                    setState(() {});
                  } catch (e) {
                    print(e);
                  }
                },
                icon: const Icon(Icons.abc_outlined),
                label: const Text("Iniciar Periferico"),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await blePeriferico.desconectarDispositivos(notificar: true);
                  tipoDispositivo = "DESCONECTADO";
                  setState(() {});
                },
                icon: const Icon(Icons.abc_outlined),
                label: const Text("Desconectar CENTRAL"),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await blePeriferico.writeNotificationToCentral(mensaje: cred);
                },
                icon: const Icon(Icons.message_outlined),
                label: const Text("Enviar Noti"),
              ),
              // FilledButton(
              //     onPressed: () async {
              //       final StreamController<int> intController =
              //           StreamController<int>.broadcast();

              //       StreamSubscription<int>? sub =
              //           intController.stream.listen((numero) {
              //         print("LLEGO NUMERO $numero");
              //       });

              //       intController.add(1);
              //       intController.add(10);

              //       await Future.delayed(const Duration(seconds: 1));

              //       await sub.cancel();
              //       sub = null;

              //       sub = intController.stream.listen((numero) {
              //         print("LLEGO NUMERO SEGUNDA DEFINICION $numero");
              //       });

              //       intController.add(2);
              //       intController.add(20);
              //     },
              //     child: const Text("Test Stream"))
            ],
          ),
        ),
      ),
    );
  }
}
