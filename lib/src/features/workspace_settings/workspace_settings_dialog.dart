import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

class WorkspaceSettingsDialog extends StatefulWidget {
  const WorkspaceSettingsDialog({super.key});

  @override
  State<WorkspaceSettingsDialog> createState() =>
      _WorkspaceSettingsDialogState();
}

class _WorkspaceSettingsDialogState extends State<WorkspaceSettingsDialog> {
  final TextEditingController _obsAddressController = TextEditingController();
  final TextEditingController _obsPortController = TextEditingController();
  final TextEditingController _obsPasswordController = TextEditingController();
  final TextEditingController _obsVideoSceneController =
      TextEditingController();
  final TextEditingController _obsFaceSceneController = TextEditingController();
  final TextEditingController _obsCaptureSceneController =
      TextEditingController();
  final TextEditingController _captureRecordingDirController =
      TextEditingController();
  final TextEditingController _captureOutputDirController =
      TextEditingController();
  final TextEditingController _ignoredFolderController =
      TextEditingController();
  final TextEditingController _webhookNameController = TextEditingController();
  final TextEditingController _webhookUrlController = TextEditingController();
  final TextEditingController _webhookQueryParamController =
      TextEditingController(text: "scene");
  final TextEditingController _webhookSceneKeyController =
      TextEditingController(text: "scene");

  bool _initialized = false;
  late TelestratorDefaults _draftTelestratorDefaults;
  late List<DecoderProfile> _enabledDecoders;
  WebhookMethod _newWebhookMethod = WebhookMethod.post;
  WebhookPostBodyType _newWebhookPostBodyType = WebhookPostBodyType.json;

  @override
  void dispose() {
    _obsAddressController.dispose();
    _obsPortController.dispose();
    _obsPasswordController.dispose();
    _obsVideoSceneController.dispose();
    _obsFaceSceneController.dispose();
    _obsCaptureSceneController.dispose();
    _captureRecordingDirController.dispose();
    _captureOutputDirController.dispose();
    _ignoredFolderController.dispose();
    _webhookNameController.dispose();
    _webhookUrlController.dispose();
    _webhookQueryParamController.dispose();
    _webhookSceneKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final ThemeData theme = Theme.of(context);
    final bool hasAnySceneSwitchProfile =
        viewModel.obsSceneSwitchConfig != null ||
        viewModel.webhookSceneSwitchConfigs.isNotEmpty;

    if (!_initialized) {
      final ObsSceneSwitchConfig obsConfig =
          viewModel.obsSceneSwitchConfig ?? ObsSceneSwitchConfig.fallback();
      _obsAddressController.text = obsConfig.serverAddress;
      _obsPortController.text = obsConfig.port.toString();
      _obsPasswordController.text = obsConfig.password;
      _obsVideoSceneController.text = obsConfig.videoScene;
      _obsFaceSceneController.text = obsConfig.faceScene;
      _obsCaptureSceneController.text = obsConfig.captureScene;
      final CapturePathsSettings capturePaths = viewModel.capturePathsSettings;
      _captureRecordingDirController.text = capturePaths.recordingRelativeDir;
      _captureOutputDirController.text = capturePaths.outputRelativeDir;
      _draftTelestratorDefaults = viewModel.telestratorDefaults;
      _enabledDecoders = List<DecoderProfile>.from(
        viewModel.decoderConfig.enabledProfiles,
      );
      _initialized = true;
    }

    final List<DecoderProfile> availableDecoders = DecoderProfile.values
        .where((DecoderProfile item) => !_enabledDecoders.contains(item))
        .toList();

    return AlertDialog(
      title: const Text("Workspace Settings"),
      content: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionTitle("Telestrator defaults", theme),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _colorPickerButton(
                      label: "Color 1",
                      value: _draftTelestratorDefaults.colorOneArgb,
                      onChanged: (int value) => setState(() {
                        _draftTelestratorDefaults = TelestratorDefaults(
                          colorOneArgb: value,
                          colorTwoArgb: _draftTelestratorDefaults.colorTwoArgb,
                          colorThreeArgb:
                              _draftTelestratorDefaults.colorThreeArgb,
                          brushSize: _draftTelestratorDefaults.brushSize,
                          enabledByDefault:
                              _draftTelestratorDefaults.enabledByDefault,
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _colorPickerButton(
                      label: "Color 2",
                      value: _draftTelestratorDefaults.colorTwoArgb,
                      onChanged: (int value) => setState(() {
                        _draftTelestratorDefaults = TelestratorDefaults(
                          colorOneArgb: _draftTelestratorDefaults.colorOneArgb,
                          colorTwoArgb: value,
                          colorThreeArgb:
                              _draftTelestratorDefaults.colorThreeArgb,
                          brushSize: _draftTelestratorDefaults.brushSize,
                          enabledByDefault:
                              _draftTelestratorDefaults.enabledByDefault,
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _colorPickerButton(
                      label: "Color 3",
                      value: _draftTelestratorDefaults.colorThreeArgb,
                      onChanged: (int value) => setState(() {
                        _draftTelestratorDefaults = TelestratorDefaults(
                          colorOneArgb: _draftTelestratorDefaults.colorOneArgb,
                          colorTwoArgb: _draftTelestratorDefaults.colorTwoArgb,
                          colorThreeArgb: value,
                          brushSize: _draftTelestratorDefaults.brushSize,
                          enabledByDefault:
                              _draftTelestratorDefaults.enabledByDefault,
                        );
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: _draftTelestratorDefaults.brushSize,
                      min: 2,
                      max: 24,
                      divisions: 22,
                      label: _draftTelestratorDefaults.brushSize
                          .toStringAsFixed(0),
                      onChanged: (double value) => setState(() {
                        _draftTelestratorDefaults = TelestratorDefaults(
                          colorOneArgb: _draftTelestratorDefaults.colorOneArgb,
                          colorTwoArgb: _draftTelestratorDefaults.colorTwoArgb,
                          colorThreeArgb:
                              _draftTelestratorDefaults.colorThreeArgb,
                          brushSize: value,
                          enabledByDefault:
                              _draftTelestratorDefaults.enabledByDefault,
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Brush ${_draftTelestratorDefaults.brushSize.toStringAsFixed(0)}",
                  ),
                  const SizedBox(width: 16),
                  Row(
                    children: <Widget>[
                      const Text("Default On"),
                      Switch(
                        value: _draftTelestratorDefaults.enabledByDefault,
                        onChanged: (bool value) => setState(() {
                          _draftTelestratorDefaults = TelestratorDefaults(
                            colorOneArgb:
                                _draftTelestratorDefaults.colorOneArgb,
                            colorTwoArgb:
                                _draftTelestratorDefaults.colorTwoArgb,
                            colorThreeArgb:
                                _draftTelestratorDefaults.colorThreeArgb,
                            brushSize: _draftTelestratorDefaults.brushSize,
                            enabledByDefault: value,
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _AsyncFilledButton(
                label: "Apply Telestrator Defaults",
                onPressed: () async {
                  await viewModel.saveTelestratorDefaults(
                    _draftTelestratorDefaults,
                  );
                },
              ),
              const Divider(height: 24),
              _SectionTitle("Decoder config", theme),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<MdkLogVerbosity>(
                      initialValue: viewModel.mdkLogVerbosity,
                      decoration: const InputDecoration(
                        labelText: "Mdk Log Verbosity",
                        border: OutlineInputBorder(),
                      ),
                      items: MdkLogVerbosity.values
                          .map(
                            (MdkLogVerbosity value) =>
                                DropdownMenuItem<MdkLogVerbosity>(
                                  value: value,
                                  child: Text(value.name),
                                ),
                          )
                          .toList(),
                      onChanged: (MdkLogVerbosity? value) {
                        if (value == null) {
                          return;
                        }
                        unawaited(viewModel.saveMdkLogVerbosity(value));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<FvpLogVerbosity>(
                      initialValue: viewModel.fvpLogVerbosity,
                      decoration: const InputDecoration(
                        labelText: "Fvp Log Verbosity (Dart Logger)",
                        border: OutlineInputBorder(),
                      ),
                      items: FvpLogVerbosity.values
                          .map(
                            (FvpLogVerbosity value) =>
                                DropdownMenuItem<FvpLogVerbosity>(
                                  value: value,
                                  child: Text(value.name),
                                ),
                          )
                          .toList(),
                      onChanged: (FvpLogVerbosity? value) {
                        if (value == null) {
                          return;
                        }
                        unawaited(viewModel.saveFvpLogVerbosity(value));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _cardWithTitle(
                      title: "Enabled (priority order)",
                      child: ReorderableListView(
                        shrinkWrap: true,
                        onReorder: (int oldIndex, int newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) {
                              newIndex -= 1;
                            }
                            final DecoderProfile moved = _enabledDecoders
                                .removeAt(oldIndex);
                            _enabledDecoders.insert(newIndex, moved);
                          });
                        },
                        children: _enabledDecoders
                            .map(
                              (DecoderProfile profile) => ListTile(
                                key: ValueKey<String>(
                                  "decoder-${profile.name}",
                                ),
                                dense: true,
                                title: Text(profile.label),
                                trailing: IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  tooltip: "Disable",
                                  onPressed: () => setState(() {
                                    _enabledDecoders.remove(profile);
                                  }),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _cardWithTitle(
                      title: "Available",
                      child: Column(
                        children: availableDecoders
                            .map(
                              (DecoderProfile profile) => ListTile(
                                dense: true,
                                title: Text(profile.label),
                                trailing: IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  tooltip: "Enable",
                                  onPressed: () => setState(() {
                                    _enabledDecoders.add(profile);
                                  }),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _AsyncFilledButton(
                label: "Apply Decoder Settings",
                onPressed: () async {
                  await viewModel.saveDecoderConfig(
                    DecoderConfig(enabledProfiles: _enabledDecoders),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                "Future: decoder options list should be populated by platform/capability.",
                style: theme.textTheme.bodySmall,
              ),
              const Divider(height: 24),
              _SectionTitle("Ingestion & preview", theme),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text("Pause Background Ingest During Preview"),
                subtitle: Text(
                  "When enabled, scanning and ffprobe pause while a clip plays in the dashboard preview to avoid disk contention on slow storage (e.g. USB HDD). Full-screen playout always pauses ingest regardless of this setting. Turn off if media lives on a fast internal or external SSD.",
                  style: theme.textTheme.bodySmall,
                ),
                value: viewModel.pauseIngestScanDuringPreview,
                onChanged: (bool value) =>
                    unawaited(viewModel.savePauseIngestScanDuringPreview(value)),
              ),
              const Divider(height: 24),
              _SectionTitle("Scene switch settings", theme),
              const SizedBox(height: 8),
              _cardWithTitle(
                title: "Profiles",
                child: Column(
                  children: <Widget>[
                    if (!hasAnySceneSwitchProfile)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: Text("None configured")),
                      ),
                    if (viewModel.obsSceneSwitchConfig != null)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.videocam),
                        title: const Text("OBS"),
                        subtitle: Text(
                          "${viewModel.obsSceneSwitchConfig!.serverAddress}:${viewModel.obsSceneSwitchConfig!.port}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Switch(
                              value: viewModel.obsSceneSwitchConfig!.enabled,
                              onChanged: (bool value) => unawaited(
                                viewModel.setObsSceneSwitchEnabled(value),
                              ),
                            ),
                            IconButton(
                              tooltip: "Remove OBS",
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => unawaited(
                                viewModel.saveObsSceneSwitchConfig(null),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...viewModel.webhookSceneSwitchConfigs.map(
                      (WebhookSceneSwitchConfig item) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.link),
                        title: Text(item.name),
                        subtitle: Text(item.url),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Switch(
                              value: item.enabled,
                              onChanged: (bool value) => unawaited(
                                viewModel.setWebhookSceneSwitchEnabled(
                                  item.id,
                                  value,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: "Remove webhook",
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => unawaited(
                                viewModel.deleteWebhookSceneSwitchConfig(
                                  item.id,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text("OBS", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _obsAddressController,
                      decoration: const InputDecoration(
                        labelText: "OBS Server Address",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _obsPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Port",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _obsPasswordController,
                      decoration: const InputDecoration(
                        labelText: "OBS Password",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _obsVideoSceneController,
                      decoration: const InputDecoration(
                        labelText: "Video Scene",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _obsFaceSceneController,
                      decoration: const InputDecoration(
                        labelText: "Face Scene",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _obsCaptureSceneController,
                decoration: const InputDecoration(
                  labelText: "Capture Scene (optional)",
                  helperText:
                      "Program scene switched before recording when set.",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _AsyncFilledButton(
                label: "Save OBS",
                onPressed: () async {
                  final int port =
                      int.tryParse(_obsPortController.text.trim()) ?? 4455;
                  await viewModel.saveObsSceneSwitchConfig(
                    ObsSceneSwitchConfig(
                      enabled: viewModel.obsSceneSwitchConfig?.enabled ?? true,
                      serverAddress: _obsAddressController.text.trim(),
                      port: port,
                      password: _obsPasswordController.text.trim(),
                      videoScene: _obsVideoSceneController.text.trim(),
                      faceScene: _obsFaceSceneController.text.trim(),
                      captureScene: _obsCaptureSceneController.text.trim(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text("OBS Capture Paths", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _captureRecordingDirController,
                      decoration: const InputDecoration(
                        labelText: "Recording Folder (relative)",
                        helperText:
                            "OBS writes here; ignored by ingest while recording.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _captureOutputDirController,
                      decoration: const InputDecoration(
                        labelText: "Output Folder (relative)",
                        helperText:
                            "Empty = workspace root. Finished files are copied here.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _AsyncFilledButton(
                label: "Save Capture Paths",
                onPressed: () async {
                  await viewModel.saveCapturePathsSettings(
                    CapturePathsSettings(
                      recordingRelativeDir: _captureRecordingDirController.text
                          .trim(),
                      outputRelativeDir: _captureOutputDirController.text
                          .trim(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text("Webhooks", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _webhookNameController,
                      decoration: const InputDecoration(
                        labelText: "Webhook Name",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _webhookUrlController,
                      decoration: const InputDecoration(
                        labelText: "Webhook URL",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<WebhookMethod>(
                      initialValue: _newWebhookMethod,
                      items: WebhookMethod.values
                          .map(
                            (WebhookMethod value) =>
                                DropdownMenuItem<WebhookMethod>(
                                  value: value,
                                  child: Text(value.name.toUpperCase()),
                                ),
                          )
                          .toList(),
                      onChanged: (WebhookMethod? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _newWebhookMethod = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Method",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_newWebhookMethod == WebhookMethod.get)
                    Expanded(
                      child: TextField(
                        controller: _webhookQueryParamController,
                        decoration: const InputDecoration(
                          labelText: "GET Query Param",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  if (_newWebhookMethod == WebhookMethod.post) ...<Widget>[
                    Expanded(
                      child: DropdownButtonFormField<WebhookPostBodyType>(
                        initialValue: _newWebhookPostBodyType,
                        items: WebhookPostBodyType.values
                            .map(
                              (WebhookPostBodyType value) =>
                                  DropdownMenuItem<WebhookPostBodyType>(
                                    value: value,
                                    child: Text(value.name),
                                  ),
                            )
                            .toList(),
                        onChanged: (WebhookPostBodyType? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _newWebhookPostBodyType = value;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: "POST Body",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _webhookSceneKeyController,
                        decoration: const InputDecoration(
                          labelText: "POST Scene Key",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _AsyncFilledButton(
                label: "Add Webhook",
                onPressed: () async {
                  await viewModel.addWebhookSceneSwitchConfig(
                    WebhookSceneSwitchConfig(
                      id: 0,
                      name: _webhookNameController.text.trim().isEmpty
                          ? "Webhook"
                          : _webhookNameController.text.trim(),
                      enabled: true,
                      url: _webhookUrlController.text.trim(),
                      method: _newWebhookMethod,
                      getQueryParamName: _webhookQueryParamController.text
                          .trim(),
                      postBodyType: _newWebhookPostBodyType,
                      sceneKey: _newWebhookMethod == WebhookMethod.get
                          ? ""
                          : _webhookSceneKeyController.text.trim(),
                    ),
                  );
                  _webhookNameController.clear();
                  _webhookUrlController.clear();
                },
              ),
              const Divider(height: 24),
              _SectionTitle("Ignored folders", theme),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _ignoredFolderController,
                      decoration: const InputDecoration(
                        labelText: "Relative folder path",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _AsyncFilledButton(
                    label: "Add",
                    onPressed: () async {
                      final String value = _ignoredFolderController.text.trim();
                      if (value.isEmpty) {
                        return;
                      }
                      await viewModel.addIgnoredFolder(value);
                      _ignoredFolderController.clear();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: viewModel.ignoredFolders
                    .map(
                      (String folder) => InputChip(
                        label: Text(folder),
                        onDeleted: () =>
                            unawaited(viewModel.removeIgnoredFolder(folder)),
                      ),
                    )
                    .toList(),
              ),
              const Divider(height: 24),
              _SectionTitle("Export workspace", theme),
              const SizedBox(height: 8),
              _AsyncFilledButton(
                label: "Export JSON",
                icon: Icons.download,
                onPressed: () async {
                  await viewModel.exportWorkspace();
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
      ],
    );
  }

  Widget _cardWithTitle({required String title, required Widget child}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[Text(title), const SizedBox(height: 8), child],
        ),
      ),
    );
  }

  Widget _colorPickerButton({
    required String label,
    required int value,
    required void Function(int value) onChanged,
  }) {
    return OutlinedButton(
      onPressed: () async {
        final int? selected = await _showColorPicker(context, value);
        if (selected != null) {
          onChanged(selected);
        }
      },
      child: Row(
        children: <Widget>[
          Container(width: 16, height: 16, color: Color(value)),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Future<int?> _showColorPicker(BuildContext context, int initialColor) async {
    int r = (initialColor >> 16) & 0xFF;
    int g = (initialColor >> 8) & 0xFF;
    int b = initialColor & 0xFF;
    final TextEditingController hexController = TextEditingController(
      text: _hexColorString(r, g, b),
    );
    return showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (BuildContext context, void Function(void Function()) setState) {
                void syncFromRgb() {
                  hexController.text = _hexColorString(r, g, b);
                }

                return AlertDialog(
                  title: const Text("Pick Color"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 64,
                        height: 64,
                        color: Color.fromARGB(255, r, g, b),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: hexController,
                        decoration: const InputDecoration(
                          labelText: "Hex (#RRGGBB)",
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (String value) {
                          final _RgbColor? parsed = _parseHexColor(value);
                          if (parsed == null) {
                            return;
                          }
                          setState(() {
                            r = parsed.r;
                            g = parsed.g;
                            b = parsed.b;
                            syncFromRgb();
                          });
                        },
                      ),
                      Slider(
                        value: r.toDouble(),
                        min: 0,
                        max: 255,
                        onChanged: (double value) => setState(() {
                          r = value.round();
                          syncFromRgb();
                        }),
                      ),
                      Slider(
                        value: g.toDouble(),
                        min: 0,
                        max: 255,
                        onChanged: (double value) => setState(() {
                          g = value.round();
                          syncFromRgb();
                        }),
                      ),
                      Slider(
                        value: b.toDouble(),
                        min: 0,
                        max: 255,
                        onChanged: (double value) => setState(() {
                          b = value.round();
                          syncFromRgb();
                        }),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Cancel"),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(Color.fromARGB(255, r, g, b).toARGB32()),
                      child: const Text("Use"),
                    ),
                  ],
                );
              },
        );
      },
    );
  }

  String _hexColorString(int r, int g, int b) {
    return "#${r.toRadixString(16).padLeft(2, "0").toUpperCase()}${g.toRadixString(16).padLeft(2, "0").toUpperCase()}${b.toRadixString(16).padLeft(2, "0").toUpperCase()}";
  }

  _RgbColor? _parseHexColor(String raw) {
    final String normalized = raw.trim().replaceFirst("#", "");
    if (normalized.length != 6) {
      return null;
    }
    final int? value = int.tryParse(normalized, radix: 16);
    if (value == null) {
      return null;
    }
    return _RgbColor(
      r: (value >> 16) & 0xFF,
      g: (value >> 8) & 0xFF,
      b: value & 0xFF,
    );
  }
}

enum _AsyncButtonVisualState { idle, loading, done }

class _AsyncFilledButton extends StatefulWidget {
  const _AsyncFilledButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final Future<void> Function() onPressed;

  @override
  State<_AsyncFilledButton> createState() => _AsyncFilledButtonState();
}

class _AsyncFilledButtonState extends State<_AsyncFilledButton> {
  _AsyncButtonVisualState _state = _AsyncButtonVisualState.idle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FilledButton(
          onPressed: _state == _AsyncButtonVisualState.loading
              ? null
              : _runAction,
          child: _buildLabelChild(),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 18,
          height: 18,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _buildStatusChild(),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelChild() {
    if (widget.icon == null) {
      return Text(widget.label);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(widget.icon),
        const SizedBox(width: 8),
        Text(widget.label),
      ],
    );
  }

  Widget _buildStatusChild() {
    if (_state == _AsyncButtonVisualState.loading) {
      return const SizedBox(
        key: ValueKey<String>("loading"),
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_state == _AsyncButtonVisualState.done) {
      return TweenAnimationBuilder<double>(
        key: const ValueKey<String>("done"),
        duration: const Duration(milliseconds: 600),
        tween: Tween<double>(begin: 1, end: 0),
        builder: (BuildContext context, double opacity, Widget? child) {
          return Opacity(opacity: opacity, child: child);
        },
        child: const Icon(Icons.check),
      );
    }
    return const SizedBox(key: ValueKey<String>("idle"));
  }

  Future<void> _runAction() async {
    setState(() {
      _state = _AsyncButtonVisualState.loading;
    });
    await widget.onPressed();
    if (!mounted) {
      return;
    }
    setState(() {
      _state = _AsyncButtonVisualState.done;
    });
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted) {
      return;
    }
    setState(() {
      _state = _AsyncButtonVisualState.idle;
    });
  }
}

class _RgbColor {
  const _RgbColor({required this.r, required this.g, required this.b});

  final int r;
  final int g;
  final int b;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: theme.textTheme.titleLarge);
  }
}
