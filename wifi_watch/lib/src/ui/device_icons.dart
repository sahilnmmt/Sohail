import 'package:flutter/material.dart';

import '../device_kind.dart';

IconData kindIcon(DeviceKind k) => switch (k) {
      DeviceKind.phone => Icons.smartphone,
      DeviceKind.tablet => Icons.tablet_android,
      DeviceKind.computer => Icons.laptop,
      DeviceKind.tv => Icons.tv,
      DeviceKind.speaker => Icons.speaker,
      DeviceKind.console => Icons.sports_esports,
      DeviceKind.smartHome => Icons.lightbulb_outline,
      DeviceKind.camera => Icons.videocam_outlined,
      DeviceKind.printer => Icons.print_outlined,
      DeviceKind.router => Icons.router_outlined,
      DeviceKind.other => Icons.devices_other,
    };
