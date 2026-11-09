
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../services/ble_diagnostic_service.dart';

class BleDiagnosticScreen extends StatelessWidget {
  const BleDiagnosticScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BleDiagnosticService>(
      builder: (context, ble, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('BLE Diagnostic'),
            actions: [
              IconButton(
                tooltip: 'Disconnect',
                onPressed: ble.isConnected
                    ? () => ble.disconnect()
                    : null,
                icon: const Icon(Icons.bluetooth_disabled),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusCard(ble),
                const SizedBox(height: 16),
                _buildActions(ble),
                const SizedBox(height: 20),
                _buildDevices(ble),
                const SizedBox(height: 20),
                _buildLogs(ble),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(BleDiagnosticService ble) {
    final color = ble.isReady ? Colors.green : Colors.orange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth, color: color, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ble.status,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _info('Perangkat', ble.connectedDeviceName),
            _info('Device ID', ble.connectedDeviceId ?? '-'),
            _info('RX Characteristic', ble.rxStatus),
            _info('TX Characteristic', ble.txStatus),
            _info('BLE Ready', ble.isReady ? 'Ya' : 'Belum'),
            if (ble.error != null) ...[
              const SizedBox(height: 10),
              Text(
                ble.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BleDiagnosticService ble) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: ble.isScanning || ble.isConnecting
              ? null
              : () => ble.startScan(),
          icon: ble.isScanning
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(
            ble.isScanning ? 'Memindai...' : 'Scan Perangkat BLE',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: ble.isReady ? () => ble.sendPing() : null,
          icon: const Icon(Icons.send),
          label: const Text('Kirim PING'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: ble.isConnected ? () => ble.disconnect() : null,
          icon: const Icon(Icons.bluetooth_disabled),
          label: const Text('Disconnect'),
        ),
      ],
    );
  }

  Widget _buildDevices(BleDiagnosticService ble) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Perangkat Ditemukan (${ble.devices.length})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 8),
        if (ble.devices.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('Belum ada perangkat ditemukan.'),
              ),
            ),
          )
        else
          ...ble.devices.map((result) {
            final device = result.device;
            final name = device.platformName.isNotEmpty
                ? device.platformName
                : device.remoteId.toString();

            return Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(name),
                subtitle: Text(
                  '${device.remoteId}\nSignal: ${result.rssi} dBm',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: ble.isConnecting || ble.isConnected
                    ? null
                    : () => ble.connectTo(device),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildLogs(BleDiagnosticService ble) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Communication Logs',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 250,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ble.logs.isEmpty
              ? const Text(
                  'Belum ada aktivitas.',
                  style: TextStyle(color: Colors.white70),
                )
              : ListView.builder(
                  itemCount: ble.logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        ble.logs[index],
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
