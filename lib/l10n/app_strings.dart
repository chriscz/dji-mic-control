// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

/// Optional UI localization ported from upstream PR #3 by VaderCheng
/// (https://github.com/ShadowBitBasher/DJI-Mic-Control/pull/3),
/// supporting English (`en`) and Simplified Chinese (`zh-CN`) with English fallback.
class AppStrings {
  AppStrings._();

  static const Map<String, String> _zhCN = <String, String>{
    'DEVICES': '设备',
    'Devices': '设备',
    'Toggle devices': '显示或隐藏设备',
    'No devices': '暂无设备',
    'Connected': '已连接',
    'Connecting...': '正在连接...',
    'Unknown': '未知',
    'No signal': '无信号',
    'RECEIVER': '接收器',
    'Receiver': '接收器',
    'Serial': '序列号',
    'Firmware': '固件版本',
    'No data': '暂无数据',
    'Protocol': '协议版本',
    'Power': '供电',
    'Gain': '增益',
    'Level': '音频电平',
    'Disconnected': '未连接',
    'SETTINGS': '设置',
    'Settings': '设置',
    'Settings layout': '设置布局',
    'Compact': '紧凑',
    'List': '列表',
    'Mode': '模式',
    'Fully Charged': '满电',
    'Good': '电量充足',
    'Low': '电量偏低',
    'Very Low': '电量很低',
    'Critical': '电量即将耗尽',
    'Enable USB access': '启用 USB 访问',
    'Setup guide': '设置说明',
    'Copied': '已复制',
    'Copy rule': '复制规则',
    'Copy command': '复制命令',
    'Requires protocol v2, please update your firmware': '需要协议 v2，请更新设备固件',
    'Turn on Noise Cancel using the button on the transmitter': '请先按发射器上的按钮开启降噪',
    'Use the O/L/H switch on the mobile receiver to change noise cancellation.': '请使用移动接收器上的 O/L/H 物理开关切换降噪。',
    'Turn on "Noise Cancelling" first': '请先开启“降噪”',
    'A microphone is connected but not accessible. Click to fix USB permissions.': '已连接麦克风，但无法访问。点击查看 USB 权限设置。',
    'Choose a device from the sidebar to view live telemetry and adjust settings.': '请在左侧选择设备以查看实时状态并调整设置。',
    'Connect a supported DJI Mic Mini receiver over USB-C and it will appear automatically.': '请通过 USB-C 连接支持的 DJI Mic Mini 接收器，设备将自动显示。',
    'A DJI microphone is plugged in, but Linux is blocking non-root access to its USB control interface.': '已连接支持的麦克风，但应用无法访问其 USB 控制接口。',
    'Off': '关闭',
    'On': '开启',
    'Basic': '基础',
    'Strong': '强效',
    'Mono': '单声道',
    'Stereo': '立体声',
    'Standard': '自然',
    'Rich': '饱满',
    'Bright': '明亮',
    'Audio': '音频',
    'Power & Startup': '电源与启动',
    'Device': '设备',
    'Noise Cancel': '降噪模式',
    'Noise Cancelling': '降噪',
    'Toggle via TX power button': '按发射器电源键切换',
    'Low Cut': '低切滤波',
    'Audio Channels': '声道模式',
    'Safety Track': '安全音轨',
    'Clipping Control': '自动限幅',
    'Auto Off RX (15 min)': '接收器自动关机（15 分钟）',
    'Auto Off TX (15 min)': '发射器自动关机（15 分钟）',
    'RX On/Off follows Camera': '接收器跟随相机开关机',
    'Plug-Free Ext. Speaker': '免拔接收器播放外放',
    'Changing this reboots the receiver.': '更改此项会重启接收器。',
    'Mic LEDs': '麦克风指示灯',
    'Voice Tone': '音色',
    'Receiver Gain': '接收器增益',
    'Monitoring Gain': '监听增益',
    'Language': '语言',
    'Appearance': '外观',
    'System': '跟随系统',
    'Light': '浅色',
    'Dark': '深色',
    'Diagnostics': '诊断日志',
    'System & Capabilities': '系统与功能状态',
    'Permission needed': '需要访问权限',
    'Show setup instructions': '查看设置说明',
    'Install udev rule': '安装 udev 规则',
    'Reload udev rules': '重新加载 udev 规则',
    'No device selected': '未选择设备',
    'No microphone connected': '未连接麦克风',
    'DJI Mic Series Mobile Receiver': 'DJI Mic 系列移动接收器',
    'Turn off "{name}" first': '请先关闭“{name}”',
    'The receiver did not confirm the gain change. The displayed value is the reported value.':
        '接收器未确认增益更改，当前显示的仍是设备上报的值。',
    'Battery: {label}': '电量：{label}',
    'Battery: {label} (charging)': '电量：{label}（充电中）',
    'PREFERENCES': '偏好设置',
    'OS CAPABILITIES & OPTIONAL LIBRARIES': '系统能力与可选组件',
    'Re-check': '重新检测',
    'Copy': '复制',
    'Clear': '清空',
  };

  static String normalizeLocale(String? value) => value == 'zh-CN' ? 'zh-CN' : 'en';

  static String tr(String locale, String key, [Map<String, Object>? params]) {
    var text = locale == 'zh-CN' ? (_zhCN[key] ?? key) : key;
    if (params != null && params.isNotEmpty) {
      params.forEach((name, val) {
        text = text.replaceAll('{$name}', val.toString());
      });
    }
    return text;
  }
}
