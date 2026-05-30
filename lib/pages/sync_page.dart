import 'package:fluent_ui/fluent_ui.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/components/title_bar.dart';
import 'package:pixes/foundation/navigation.dart';

import 'package:pixes/services/sync_service.dart';
import 'package:pixes/utils/translation.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _urlCtl = TextEditingController();
  final _keyCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  bool _enabled = false;
  bool _syncSettings = true;

  bool _connecting = false;
  bool _syncing = false;
  bool _connected = false;
  bool _needsSetup = false;
  List<Map<String, dynamic>> _devices = [];
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
    _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    if (!_connected) return;
    final devices = await syncService.getDevices();
    final counts = await syncService.getLocalCounts();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _counts = counts;
    });
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _keyCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  void _load() {
    _urlCtl.text = appdata.settings["syncUrl"] as String? ?? "";
    _keyCtl.text = appdata.settings["syncKey"] as String? ?? "";
    _nameCtl.text = appdata.settings["syncDeviceName"] as String? ?? "";
    _enabled = appdata.settings["syncEnabled"] == true;
    _syncSettings = appdata.settings["syncSettingsEnabled"] != false;
    final code = syncService.lastStatusCode;
    _connected = code != null && code >= 200 && code < 300;
  }

  void _save() {
    appdata.settings["syncUrl"] = _urlCtl.text.trim();
    appdata.settings["syncKey"] = _keyCtl.text.trim();
    appdata.settings["syncDeviceName"] = _nameCtl.text.trim();
    appdata.settings["syncEnabled"] = _enabled;
    appdata.settings["syncSettingsEnabled"] = _syncSettings;
    syncService.reconfigure();
    appdata.writeData();
    if (_enabled) syncService.init();
  }

  Future<void> _connect() async {
    _save();
    setState(() => _connecting = true);
    final code = await syncService.checkConnection();
    if (!mounted) return;
    setState(() => _connecting = false);
    final ok = code != null && code >= 200 && code < 300;
    if (ok) {
      final devices = await syncService.getDevices();
      final counts = await syncService.getLocalCounts();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _needsSetup = false;
        _devices = devices;
        _counts = counts;
      });
      context.showToast(message: "Connection successful".tl);
    } else {
      setState(() {
        _connected = false;
        _needsSetup = syncService.needsSetup;
      });
      if (_needsSetup) {
        context.showToast(message: "401 - check setup guide below".tl);
      } else {
        context.showToast(message: "Connection failed ({code})".tl.replaceAll("{code}", "${code ?? "?"}"));
      }
    }
  }

  Future<void> _syncNow() async {
    _save();
    setState(() => _syncing = true);
    await syncService.syncNow();
    final code = syncService.lastStatusCode;
    if (!mounted) return;
    setState(() => _syncing = false);
    if (code != null && code >= 200 && code < 300) {
      final devices = await syncService.getDevices();
      final counts = await syncService.getLocalCounts();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _needsSetup = false;
        _devices = devices;
        _counts = counts;
      });
      context.showToast(message: "Sync completed".tl);
    } else {
      setState(() {
        _connected = false;
        _needsSetup = syncService.needsSetup;
      });
      context.showToast(message: "Sync failed ({code})".tl.replaceAll("{code}", "$code"));
    }
  }

  Future<void> _clearRemote() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => ContentDialog(
        title: Text("Clear remote data?".tl),
        content: Text("This deletes all sync data from the server except this device.".tl),
        actions: [
          Button(onPressed: () => Navigator.pop(c, false), child: Text("Cancel".tl)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text("Clear".tl)),
        ],
      ),
    );
    if (ok != true) return;
    if (!await syncService.clearRemoteData()) {
      if (!mounted) return;
      context.showToast(message: "Failed".tl);
      return;
    }
    if (!mounted) return;
    context.showToast(message: "Remote data cleared".tl);
    setState(() {
      _devices = [];
      _counts = {};
    });
    await _connect();
  }

  Future<void> _resetDeviceId() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => ContentDialog(
        title: Text("Reset Device ID?".tl),
        content: Text("This will generate a new device ID. The old ID will no longer be recognized as this device.".tl),
        actions: [
          Button(onPressed: () => Navigator.pop(c, false), child: Text("Cancel".tl)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text("Reset".tl)),
        ],
      ),
    );
    if (ok != true) return;
    syncService.resetDeviceId();
    if (!mounted) return;
    context.showToast(message: "Device ID reset".tl);
    setState(() {});
  }

  String get _projectId => syncService.projectId ?? "";

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TitleBar(title: "Sync Settings".tl),
          const SizedBox(height: 16),
          // Enable toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Text("Enable Sync".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                ToggleSwitch(checked: _enabled, onChanged: (v) => setState(() => _enabled = v)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Sync Settings".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("Include app settings in sync".tl, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
                ToggleSwitch(checked: _syncSettings, onChanged: (v) => setState(() => _syncSettings = v)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Configuration
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Supabase Configuration".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text("Supabase URL".tl),
                const SizedBox(height: 4),
                TextBox(controller: _urlCtl, placeholder: "https://xxxxx.supabase.co"),
                const SizedBox(height: 12),
                Text("Anon Key".tl),
                const SizedBox(height: 4),
                TextBox(controller: _keyCtl, placeholder: "eyJhbGciOi...", obscuringCharacter: "*", obscureText: true),
                const SizedBox(height: 12),
                Text("Device Name".tl),
                const SizedBox(height: 4),
                TextBox(controller: _nameCtl, placeholder: "My PC"),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          // Actions
          Row(children: [
            FilledButton(
              onPressed: _connecting ? null : _connect,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_connecting) ...[
                  const SizedBox(width: 12, height: 12, child: ProgressRing(strokeWidth: 2)),
                  const SizedBox(width: 6),
                ],
                Text("Test Connection".tl),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: (!_enabled || _syncing) ? null : _syncNow,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_syncing) ...[
                  const SizedBox(width: 12, height: 12, child: ProgressRing(strokeWidth: 2)),
                  const SizedBox(width: 6),
                ],
                Text("Sync Now".tl),
              ]),
            ),
            const SizedBox(width: 12),
            Button(onPressed: () => context.pop(), child: Text("Back".tl)),
          ]),
          const SizedBox(height: 16),

          // ── Status (always visible) ──
          _statusCard(),
          const SizedBox(height: 12),

          Row(children: [
            Button(
              onPressed: () => _resetDeviceId(),
              child: Text("Reset Device ID".tl),
            ),
            if (_connected) ...[
              const SizedBox(width: 12),
              Button(onPressed: _clearRemote, child: Text("Clear remote data".tl)),
            ],
          ]),

          // ── Devices (only when connected) ──
          if (_connected) ...[
            const SizedBox(height: 12),
            _devicesCard(),
          ],

          // ── Setup guide (401/403) ──
          if (_needsSetup) ...[
            const SizedBox(height: 12),
            _setupGuideCard(),
          ],
        ],
      ),
    );
  }

  Widget _statusCard() {
    final searchCount = _counts['searchHistory'] ?? 0;
    final browseCount = _counts['browsingHistory'] ?? 0;
    final statusText = _connected ? "Connected".tl : "Disconnected".tl;
    final statusColor = _connected ? Colors.green : Colors.orange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Status".tl, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _statRow("Status".tl, statusText, statusColor),
          _statRow("Device".tl, syncService.deviceName.isNotEmpty ? syncService.deviceName : "Unnamed".tl, null),
          _statRow("Search History".tl, searchCount.toString(), null),
          _statRow("Browse History".tl, browseCount.toString(), null),
          if (_connected)
            _statRow("Devices".tl, "${_devices.length} connected".tl, null),
        ]),
      ),
    );
  }

  Widget _statRow(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text("$label: ", style: const TextStyle(fontSize: 13)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor)),
      ]),
    );
  }

  Widget _devicesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Connected Devices".tl, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            Text("No other devices".tl, style: const TextStyle(fontSize: 13))
          else
            for (var d in _devices) _deviceRow(d),
        ]),
      ),
    );
  }

  Widget _deviceRow(Map<String, dynamic> d) {
    final name = d['device_name'] as String? ?? "";
    final lastSync = d['last_sync_at'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        const Icon(FluentIcons.cell_phone, size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text(name.isNotEmpty ? name : "Unnamed".tl, style: const TextStyle(fontSize: 13))),
        if (lastSync != null)
          Text(_fmtTime(lastSync), style: const TextStyle(fontSize: 11)),
      ]),
    );
  }

  Widget _setupGuideCard() {
    final pid = _projectId;
    final sqlGuide = """
create table if not exists sync_devices (
  device_id text primary key,
  device_name text not null default '',
  last_sync_at timestamp with time zone default timezone('utc'::text, now()),
  inserted_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);
create table if not exists sync_settings (
  id bigint generated by default as identity primary key,
  data jsonb,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  inserted_at timestamp with time zone default timezone('utc'::text, now()) not null
);
create table if not exists sync_search_history (
  id bigint generated by default as identity primary key,
  keyword text not null,
  search_type int not null,
  data jsonb,
  unique(keyword, search_type),
  inserted_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);
create table if not exists sync_browsing_history (
  id bigint generated by default as identity primary key,
  illust_id bigint not null,
  data jsonb,
  unique(illust_id),
  inserted_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);
-- Disable RLS (easiest for self-hosted):
alter table sync_devices disable row level security;
alter table sync_settings disable row level security;
alter table sync_search_history disable row level security;
alter table sync_browsing_history disable row level security;
    """.trim();
    final accent = FluentTheme.of(context).accentColor;
    final surface = FluentTheme.of(context).micaBackgroundColor;
    final inactive = FluentTheme.of(context).inactiveColor;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Setup Guide".tl, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
          const SizedBox(height: 8),
          Text(
            "Your Supabase returned HTTP {code}. First check that your anon key is correct, then try the SQL below.".tl.replaceAll("{code}", "${syncService.lastStatusCode}"),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text("1. Verify your anon key:".tl, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          if (pid.isNotEmpty)
            GestureDetector(
              onTap: () => _openUrl("https://supabase.com/dashboard/project/$pid/settings/api-keys/legacy"),
              child: Text(
                "https://supabase.com/dashboard/project/$pid/settings/api-keys/legacy",
                style: TextStyle(fontSize: 12, color: accent),
              ),
            ),
          if (pid.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("2. Or open your project directly:".tl, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _openUrl("https://$pid.supabase.co"),
              child: Text(
                "https://$pid.supabase.co",
                style: TextStyle(fontSize: 12, color: accent),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text("3. Open the SQL Editor and run:".tl, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(sqlGuide, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 12),
          Text("4. After running the SQL, tap 'Test Connection' again.".tl, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            "Tip: The anon key is in Settings → API → Project API keys → anon/public. "
            "RLS disabled is easiest for self-hosted; for production, create proper RLS policies.".tl,
            style: TextStyle(fontSize: 12, color: inactive),
          ),
        ]),
      ),
    );
  }

  void _openUrl(String url) async {
    try {
      await launchUrlString(url);
    } catch (_) {}
  }

  String _fmtTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} "
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso;
    }
  }
}
