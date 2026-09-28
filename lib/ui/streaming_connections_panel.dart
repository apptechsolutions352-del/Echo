import 'package:flutter/material.dart';

import '../services/streaming_manager.dart';

/// Drop this widget into an existing Settings or Playlists section.
class StreamingConnectionsPanel extends StatelessWidget {
  const StreamingConnectionsPanel({super.key, required this.manager});

  final StreamingManager manager;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: manager,
    builder: (context, _) => ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Text('Streaming services', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final service in manager.services)
          Card(
            child: ListTile(
              title: Text(service.serviceName),
              subtitle: Text(
                manager.errors[service.serviceName] ??
                    (service.isConnected ? 'Connected' : 'Not connected'),
              ),
              trailing: manager.busyServices.contains(service.serviceName)
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => service.isConnected
                          ? manager.disconnect(service)
                          : manager.connect(service),
                      child: Text(service.isConnected ? 'Disconnect' : 'Connect'),
                    ),
            ),
          ),
        const SizedBox(height: 20),
        Text('Playlists', style: Theme.of(context).textTheme.titleLarge),
        for (final playlist in manager.playlists)
          ListTile(
            leading: playlist.imageUrl == null
                ? const CircleAvatar(child: Icon(Icons.queue_music))
                : CircleAvatar(
                    backgroundImage: NetworkImage(playlist.imageUrl!),
                    onBackgroundImageError: (_, _) {},
                  ),
            title: Text(playlist.name),
            subtitle: Text(
              '${playlist.trackCount} tracks · ${playlist.sourcePlatform}',
            ),
          ),
      ],
    ),
  );
}
