import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/osg/osg_editor_screen.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/widgets/rgba_color_picker.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

class WorkspaceSettingsDialog extends StatefulWidget {
  const WorkspaceSettingsDialog({super.key});

  @override
  State<WorkspaceSettingsDialog> createState() =>
      _WorkspaceSettingsDialogState();
}

class _WorkspaceSettingsDialogState extends State<WorkspaceSettingsDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _obsAddressController = TextEditingController();
  final TextEditingController _obsPortController = TextEditingController();
  final TextEditingController _obsPasswordController = TextEditingController();
  final TextEditingController _obsVideoSceneController =
      TextEditingController();
  final TextEditingController _obsFaceSceneController = TextEditingController();
  final TextEditingController _obsCaptureSceneController =
      TextEditingController();
  final TextEditingController _obsOsgOverlaySourceController =
      TextEditingController();
  final TextEditingController _captureRecordingDirController =
      TextEditingController();
  final TextEditingController _captureOutputDirController =
      TextEditingController();
  final TextEditingController _playoutRecordStagingController =
      TextEditingController();
  final TextEditingController _playoutRecordOutputController =
      TextEditingController();
  final TextEditingController _ignoredFolderController =
      TextEditingController();
  final TextEditingController _webhookNameController = TextEditingController();
  final TextEditingController _webhookUrlController = TextEditingController();
  final TextEditingController _webhookQueryParamController =
      TextEditingController(text: "scene");
  final TextEditingController _webhookSceneKeyController =
      TextEditingController(text: "scene");
  final TextEditingController _playoutOutputWidthController =
      TextEditingController();
  final TextEditingController _playoutOutputHeightController =
      TextEditingController();
  final TextEditingController _ingestProbeConcurrencyController =
      TextEditingController();
  final TextEditingController _ingestThumbnailConcurrencyController =
      TextEditingController();

  late TabController _tabController;
  bool _initialized = false;
  late TelestratorDefaults _draftTelestratorDefaults;
  late List<DecoderProfile> _enabledDecoders;
  late double _draftDefaultClipVolume;
  WebhookMethod _newWebhookMethod = WebhookMethod.post;
  WebhookPostBodyType _newWebhookPostBodyType = WebhookPostBodyType.json;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _obsAddressController.dispose();
    _obsPortController.dispose();
    _obsPasswordController.dispose();
    _obsVideoSceneController.dispose();
    _obsFaceSceneController.dispose();
    _obsCaptureSceneController.dispose();
    _obsOsgOverlaySourceController.dispose();
    _captureRecordingDirController.dispose();
    _captureOutputDirController.dispose();
    _playoutRecordStagingController.dispose();
    _playoutRecordOutputController.dispose();
    _ignoredFolderController.dispose();
    _webhookNameController.dispose();
    _webhookUrlController.dispose();
    _webhookQueryParamController.dispose();
    _webhookSceneKeyController.dispose();
    _playoutOutputWidthController.dispose();
    _playoutOutputHeightController.dispose();
    _ingestProbeConcurrencyController.dispose();
    _ingestThumbnailConcurrencyController.dispose();
    super.dispose();
  }

  double _gap(BuildContext context) => scaleDimension(context, 12);

  double _sectionDivider(BuildContext context) => scaleDimension(context, 32);

  void _showIngestConcurrencySnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitIngestConcurrencySettings(
    DashboardViewModel viewModel,
  ) async {
    final int? probe = int.tryParse(
      _ingestProbeConcurrencyController.text.trim(),
    );
    if (probe == null) {
      _showIngestConcurrencySnack(
        "Ffprobe batch size must be a whole number.",
      );
      return;
    }
    if (probe < IngestionConcurrencyDefaults.probeMin ||
        probe > IngestionConcurrencyDefaults.probeMax) {
      _showIngestConcurrencySnack(
        "Ffprobe batch size must be between "
        "${IngestionConcurrencyDefaults.probeMin} and "
        "${IngestionConcurrencyDefaults.probeMax}.",
      );
      return;
    }
    final int? thumbs = int.tryParse(
      _ingestThumbnailConcurrencyController.text.trim(),
    );
    if (thumbs == null) {
      _showIngestConcurrencySnack(
        "Thumbnail concurrency must be a whole number.",
      );
      return;
    }
    if (thumbs < IngestionConcurrencyDefaults.thumbnailMin ||
        thumbs > IngestionConcurrencyDefaults.thumbnailMax) {
      _showIngestConcurrencySnack(
        "Thumbnail concurrency must be between "
        "${IngestionConcurrencyDefaults.thumbnailMin} and "
        "${IngestionConcurrencyDefaults.thumbnailMax}.",
      );
      return;
    }
    await viewModel.saveIngestProbeConcurrency(probe);
    await viewModel.saveIngestThumbnailConcurrency(thumbs);
    if (!mounted) {
      return;
    }
    setState(() {
      _ingestProbeConcurrencyController.text =
          "${viewModel.ingestProbeConcurrency}";
      _ingestThumbnailConcurrencyController.text =
          "${viewModel.ingestThumbnailConcurrency}";
    });
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
      _obsOsgOverlaySourceController.text = obsConfig.osgOverlaySource;
      final CapturePathsSettings capturePaths = viewModel.capturePathsSettings;
      _captureRecordingDirController.text = capturePaths.recordingRelativeDir;
      _captureOutputDirController.text = capturePaths.outputRelativeDir;
      final PlayoutRecordPathsSettings playoutRecordPaths =
          viewModel.playoutRecordPathsSettings;
      _playoutRecordStagingController.text =
          playoutRecordPaths.stagingRelativeDir;
      _playoutRecordOutputController.text = playoutRecordPaths.outputRelativeDir;
      _draftTelestratorDefaults = viewModel.telestratorDefaults;
      _enabledDecoders = List<DecoderProfile>.from(
        viewModel.decoderConfig.enabledProfiles,
      );
      final PlayoutOutputSize playoutOut = viewModel.playoutOutputSize;
      _playoutOutputWidthController.text = "${playoutOut.width}";
      _playoutOutputHeightController.text = "${playoutOut.height}";
      _ingestProbeConcurrencyController.text =
          "${viewModel.ingestProbeConcurrency}";
      _ingestThumbnailConcurrencyController.text =
          "${viewModel.ingestThumbnailConcurrency}";
      _draftDefaultClipVolume = PlaybackVolumeDefaults.clamp(
        viewModel.defaultClipVolume,
      );
      _initialized = true;
    }

    final platform = DecoderPlatform.get();
    final List<DecoderProfile> availableDecoders = DecoderProfile.values
        .where((DecoderProfile item) => item.supportedPlatforms.contains(platform) && !_enabledDecoders.contains(item))
        .toList();

    return AlertDialog(
      title: const Text("Workspace Settings"),
      content: SizedBox(
        width: scaleDimension(context, 1080),
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const <Tab>[
                Tab(text: "Workspace and Canvas"),
                Tab(text: "On-Screen Graphics"),
                Tab(text: "Scene Switch"),
              ],
            ),
            SizedBox(height: _gap(context)),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _scrollTab(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
              _SectionTitle("Playout canvas size", theme),
              SizedBox(height: _gap(context)),
              Text(
                "Logical resolution for playout and on-screen graphics (pixels). "
                "The playout window fits this aspect ratio within your display.",
                style: theme.textTheme.bodySmall,
              ),
              SizedBox(height: _gap(context)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  SizedBox(
                    width: scaleDimension(context, 140),
                    child: TextField(
                      controller: _playoutOutputWidthController,
                      decoration: const InputDecoration(
                        labelText: "Width",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 12)),
                  SizedBox(
                    width: scaleDimension(context, 140),
                    child: TextField(
                      controller: _playoutOutputHeightController,
                      decoration: const InputDecoration(
                        labelText: "Height",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 12)),
                  _AsyncFilledButton(
                    label: "Save",
                    onPressed: () async {
                      final int w = int.tryParse(
                            _playoutOutputWidthController.text.trim(),
                          ) ??
                          PlayoutOutputSize.fallback.width;
                      final int h = int.tryParse(
                            _playoutOutputHeightController.text.trim(),
                          ) ??
                          PlayoutOutputSize.fallback.height;
                      if (w <= 0 || h <= 0) {
                        return;
                      }
                      await viewModel.savePlayoutOutputSize(
                        PlayoutOutputSize(width: w, height: h),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Playout canvas size saved."),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              Divider(height: _sectionDivider(context)),
              _SectionTitle("Playback", theme),
              SizedBox(height: _gap(context)),
              Text(
                "Default clip volume applied when the workspace loads. "
                "Adjust during playback with Up/Down (\u00B110%) and M (mute); "
                "those adjustments are session-only.",
                style: theme.textTheme.bodySmall,
              ),
              SizedBox(height: _gap(context)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: _draftDefaultClipVolume,
                      min: PlaybackVolumeDefaults.min,
                      max: PlaybackVolumeDefaults.max,
                      divisions: 20,
                      label:
                          "${(_draftDefaultClipVolume * 100).round()}%",
                      onChanged: (double value) => setState(() {
                        _draftDefaultClipVolume =
                            PlaybackVolumeDefaults.clamp(value);
                      }),
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 8)),
                  SizedBox(
                    width: scaleDimension(context, 64),
                    child: Text(
                      "${(_draftDefaultClipVolume * 100).round()}%",
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 12)),
                  _AsyncFilledButton(
                    label: "Save",
                    onPressed: () async {
                      await viewModel.saveDefaultClipVolume(
                        _draftDefaultClipVolume,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Default clip volume saved."),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              Divider(height: _sectionDivider(context)),
              _SectionTitle("Playback Engine", theme),
              SizedBox(height: _gap(context)),
              DropdownButtonFormField<PlayerBackend>(
                initialValue: viewModel.playerBackend,
                decoration: const InputDecoration(
                  labelText: "Player Backend",
                  border: OutlineInputBorder(),
                  helperText:
                      "Applies at next app start. Fvp uses libmdk; Media Kit uses libmpv.",
                ),
                items: const <DropdownMenuItem<PlayerBackend>>[
                  DropdownMenuItem<PlayerBackend>(
                    value: PlayerBackend.fvp,
                    child: Text("Fvp (Default)"),
                  ),
                  DropdownMenuItem<PlayerBackend>(
                    value: PlayerBackend.mediaKit,
                    child: Text("Media Kit"),
                  ),
                ],
                onChanged: (PlayerBackend? value) {
                  if (value == null) {
                    return;
                  }
                  unawaited(viewModel.savePlayerBackend(value));
                },
              ),
              Divider(height: _sectionDivider(context)),
              _SectionTitle("Decoder config", theme),
              SizedBox(height: _gap(context)),
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
                  SizedBox(width: scaleDimension(context, 12)),
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
              SizedBox(height: _gap(context)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _cardWithTitle(
                      title: "Enabled (priority order)",
                      child: ReorderableListView(
                        shrinkWrap: true,
                        onReorderItem: (int oldIndex, int newIndex) {
                          setState(() {
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
                  SizedBox(width: scaleDimension(context, 8)),
                  Expanded(
                    child: _cardWithTitle(
                      title: "Available",
                      child: Column(
                        children: availableDecoders
                            .map(
                              (DecoderProfile profile) => ListTile(
                                
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
              SizedBox(height: _gap(context)),
              _AsyncFilledButton(
                label: "Apply Decoder Settings",
                onPressed: () async {
                  await viewModel.saveDecoderConfig(
                    DecoderConfig(enabledProfiles: _enabledDecoders, platform: DecoderPlatform.get()),
                  );
                },
              ),
              SizedBox(height: scaleDimension(context, 6)),
              Text(
                "Future: decoder options list should be populated by platform/capability.",
                style: theme.textTheme.bodySmall,
              ),
              Divider(height: _sectionDivider(context)),
              _SectionTitle("Ingestion & preview", theme),
              SizedBox(height: _gap(context)),
              SwitchListTile(
                title: const Text("Pause Background Ingest During Manage Playback"),
                subtitle: Text(
                  "When enabled, scanning and ffprobe pause while a clip plays in the dashboard preview to avoid disk contention on slow storage (e.g. USB HDD). Full-screen playout always pauses ingest regardless of this setting. Turn off if media lives on a fast internal or external SSD.",
                  style: theme.textTheme.bodySmall,
                ),
                value: viewModel.pauseIngestScanDuringPreview,
                onChanged: (bool value) =>
                    unawaited(viewModel.savePauseIngestScanDuringPreview(value)),
              ),
              SizedBox(height: scaleDimension(context, 12)),
              Text(
                "Ffprobe batch size (${IngestionConcurrencyDefaults.probeMin}–${IngestionConcurrencyDefaults.probeMax}): "
                "parallel duration probes per batch while scanning the workspace—higher can speed a cold scan on fast storage; lower reduces CPU and disk contention. "
                "Thumbnail concurrency (${IngestionConcurrencyDefaults.thumbnailMin}–${IngestionConcurrencyDefaults.thumbnailMax}): "
                "parallel ffmpeg jobs for sidecar JPEGs—lower if ingest pegs the CPU; raise on fast disks when thumbs lag. ",
                style: theme.textTheme.bodySmall,
              ),
              SizedBox(height: _gap(context)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _ingestProbeConcurrencyController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: "Ffprobe Batch Size",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => unawaited(
                        _submitIngestConcurrencySettings(viewModel),
                      ),
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 8)),
                  Expanded(
                    child: TextField(
                      controller: _ingestThumbnailConcurrencyController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: "Thumbnail Concurrency",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => unawaited(
                        _submitIngestConcurrencySettings(viewModel),
                      ),
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 8)),
                  FilledButton(
                    onPressed: () => unawaited(
                      _submitIngestConcurrencySettings(viewModel),
                    ),
                    child: const Text("Save"),
                  ),
                ],
              ),
              Divider(height: _sectionDivider(context)),
              _SectionTitle("Ignored folders", theme),
              SizedBox(height: _gap(context)),
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
                  SizedBox(width: scaleDimension(context, 8)),
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
              SizedBox(height: _gap(context)),
              Wrap(
                spacing: scaleDimension(context, 8),
                runSpacing: scaleDimension(context, 8),
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
              Divider(height: _sectionDivider(context)),
              _SectionTitle("Export workspace", theme),
              SizedBox(height: _gap(context)),
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
                  _scrollTab(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
              _SectionTitle("Telestrator settings", theme),
              SizedBox(height: _gap(context)),
              Row(
                children: <Widget>[
                  Expanded(
                    child: RgbaColorPickerButton(
                      label: "Color 1",
                      valueArgb: _draftTelestratorDefaults.colorOneArgb,
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
                  SizedBox(width: scaleDimension(context, 8)),
                  Expanded(
                    child: RgbaColorPickerButton(
                      label: "Color 2",
                      valueArgb: _draftTelestratorDefaults.colorTwoArgb,
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
                  SizedBox(width: scaleDimension(context, 8)),
                  Expanded(
                    child: RgbaColorPickerButton(
                      label: "Color 3",
                      valueArgb: _draftTelestratorDefaults.colorThreeArgb,
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
              SizedBox(height: _gap(context)),
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
                  SizedBox(width: scaleDimension(context, 8)),
                  Text(
                    "Brush ${_draftTelestratorDefaults.brushSize.toStringAsFixed(0)}",
                  ),
                  SizedBox(width: scaleDimension(context, 16)),
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
              SizedBox(height: _gap(context)),
              _AsyncFilledButton(
                label: "Apply Telestrator Settings",
                onPressed: () async {
                  await viewModel.saveTelestratorDefaults(
                    _draftTelestratorDefaults,
                  );
                },
              ),
              Divider(height: _sectionDivider(context)),
              _SectionTitle("On-screen graphics", theme),
              SizedBox(height: _gap(context)),
              Text(
                "Templates, semantic types, and preset slots (hotkeys 8 / 9 / 0 in playout).",
                style: theme.textTheme.bodySmall,
              ),
              SizedBox(height: _gap(context)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("OSG Mode Enabled"),
                subtitle: Text(
                  "When enabled, Enter OSG Mode is available on the Tag Sets tab. "
                  "Optional OBS overlay automation uses the OSG Overlay Source "
                  "name on the Scene Switch tab (enabled on the current program "
                  "scene when entering OSG Mode).",
                  style: theme.textTheme.bodySmall,
                ),
                value: viewModel.osgModeEnabled,
                onChanged: (bool value) =>
                    unawaited(viewModel.saveOsgModeEnabled(value)),
              ),
              SizedBox(height: _gap(context)),
              FilledButton.tonal(
                onPressed: viewModel.workspacePath == null
                    ? null
                    : () {
                        unawaited(
                          Navigator.of(context)
                              .push<void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext ctx) {
                                    return ChangeNotifierProvider<
                                        DashboardViewModel>.value(
                                      value: viewModel,
                                      child: OsgEditorScreen(
                                        workspaceRoot:
                                            viewModel.workspacePath!,
                                      ),
                                    );
                                  },
                                ),
                              )
                              .then((void _) {
                                if (!context.mounted) {
                                  return;
                                }
                                final PlayoutOutputSize next =
                                    viewModel.playoutOutputSize;
                                setState(() {
                                  _playoutOutputWidthController.text =
                                      "${next.width}";
                                  _playoutOutputHeightController.text =
                                      "${next.height}";
                                });
                              }),
                        );
                      },
                child: const Text("Open on-screen graphics editor…"),
              ),
              Divider(height: _sectionDivider(context)),
              _SectionTitle("Bake recipes", theme),
              SizedBox(height: _gap(context)),
              Text(
                "Named OSG timing sets applied when baking a clip to a "
                "video file (Bake in the preview bar).",
                style: theme.textTheme.bodySmall,
              ),
              SizedBox(height: _gap(context)),
              if (viewModel.osgBakeRecipes.isEmpty)
                Text(
                  "No bake recipes yet.",
                  style: theme.textTheme.bodySmall,
                )
              else
                Column(
                  children: viewModel.osgBakeRecipes
                      .map(
                        (OsgBakeRecipe recipe) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          
                          title: Text(recipe.name),
                          subtitle: Text(
                            recipe.cues
                                .map(osgBakeCueSummaryLabel)
                                .join("; "),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                tooltip: "Edit Recipe",
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => unawaited(
                                  _editBakeRecipe(viewModel, recipe),
                                ),
                              ),
                              IconButton(
                                tooltip: "Delete Recipe",
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => unawaited(
                                  _deleteBakeRecipe(viewModel, recipe),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              SizedBox(height: _gap(context)),
              FilledButton.tonal(
                onPressed: () => unawaited(_addBakeRecipe(viewModel)),
                child: const Text("Add Bake Recipe…"),
              ),
                      ],
                    ),
                  ),
                  _scrollTab(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
              _cardWithTitle(
                title: "Profiles",
                child: Column(
                  children: <Widget>[
                    if (!hasAnySceneSwitchProfile)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: scaleDimension(context, 16),
                        ),
                        child: const Center(child: Text("None configured")),
                      ),
                    if (viewModel.obsSceneSwitchConfig != null)
                      ListTile(
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
              SizedBox(height: scaleDimension(context, 16)),
              Text("OBS", style: theme.textTheme.titleMedium),
              SizedBox(height: _gap(context)),
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
                  SizedBox(width: scaleDimension(context, 8)),
                  SizedBox(
                    width: scaleDimension(context, 120),
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
              SizedBox(height: _gap(context)),
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
                  SizedBox(width: scaleDimension(context, 8)),
                  Expanded(
                    child: TextField(
                      controller: _obsVideoSceneController,
                      decoration: const InputDecoration(
                        labelText: "Video Scene",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 8)),
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
              SizedBox(height: _gap(context)),
              TextField(
                controller: _obsCaptureSceneController,
                decoration: const InputDecoration(
                  labelText: "Capture Scene (optional)",
                  helperText:
                      "Program scene switched before recording when set.",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: _gap(context)),
              TextField(
                controller: _obsOsgOverlaySourceController,
                decoration: const InputDecoration(
                  labelText: "OSG Overlay Source (optional)",
                  helperText:
                      "Source name enabled on the current OBS program scene "
                      "when entering OSG Mode; disabled on Escape. Program "
                      "scene is unchanged. The source must exist on every "
                      "scene you enter from, or enter fails. Leave blank to "
                      "disable overlay automation.",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: _gap(context)),
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
                      osgOverlaySource:
                          _obsOsgOverlaySourceController.text.trim(),
                    ),
                  );
                },
              ),
              SizedBox(height: scaleDimension(context, 24)),
              Text("OBS Paths", style: theme.textTheme.titleMedium),
              SizedBox(height: _gap(context)),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _captureRecordingDirController,
                      decoration: const InputDecoration(
                        labelText: "Capture Recording (relative)",
                        helperText: "Capture staging; ignored by ingest.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 8)),
                  Expanded(
                    child: TextField(
                      controller: _captureOutputDirController,
                      decoration: const InputDecoration(
                        labelText: "Capture Output (relative)",
                        helperText: "Empty = workspace root after capture.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: scaleDimension(context, 8)),
                  Expanded(
                    child: TextField(
                      controller: _playoutRecordStagingController,
                      decoration: const InputDecoration(
                        labelText: "Playout Record (relative)",
                        helperText: "OBS writes during Record playout.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: _gap(context)),
              TextField(
                controller: _playoutRecordOutputController,
                decoration: const InputDecoration(
                  labelText: "Playout Output (relative)",
                  helperText:
                      "Finished Record playout files are copied here. Both playout folders are ignored by ingest when under the workspace.",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: _gap(context)),
              _AsyncFilledButton(
                label: "Save Paths",
                onPressed: () async {
                  final String? error = await viewModel.saveObsPathsSettings(
                    capture: CapturePathsSettings(
                      recordingRelativeDir: _captureRecordingDirController.text
                          .trim(),
                      outputRelativeDir: _captureOutputDirController.text
                          .trim(),
                    ),
                    playoutRecord: PlayoutRecordPathsSettings(
                      stagingRelativeDir: _playoutRecordStagingController.text
                          .trim(),
                      outputRelativeDir: _playoutRecordOutputController.text
                          .trim(),
                    ),
                  );
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error)),
                    );
                  }
                },
              ),
              SizedBox(height: scaleDimension(context, 24)),
              Text("Webhooks", style: theme.textTheme.titleMedium),
              SizedBox(height: _gap(context)),
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
                  SizedBox(width: scaleDimension(context, 8)),
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
              SizedBox(height: _gap(context)),
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
                  SizedBox(width: scaleDimension(context, 8)),
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
                    SizedBox(width: scaleDimension(context, 8)),
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
              SizedBox(height: _gap(context)),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _scrollTab(Widget child) {
    return SingleChildScrollView(child: child);
  }

  Future<void> _addBakeRecipe(DashboardViewModel viewModel) async {
    final OsgBakeRecipe? draft = await showDialog<OsgBakeRecipe>(
      context: context,
      builder: (BuildContext ctx) => const _BakeRecipeEditorDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    final List<OsgBakeRecipe> existing = viewModel.osgBakeRecipes;
    int nextId = 1;
    for (final OsgBakeRecipe r in existing) {
      if (r.id >= nextId) {
        nextId = r.id + 1;
      }
    }
    await viewModel.saveOsgBakeRecipes(<OsgBakeRecipe>[
      ...existing,
      OsgBakeRecipe(id: nextId, name: draft.name, cues: draft.cues),
    ]);
  }

  Future<void> _editBakeRecipe(
    DashboardViewModel viewModel,
    OsgBakeRecipe recipe,
  ) async {
    final OsgBakeRecipe? draft = await showDialog<OsgBakeRecipe>(
      context: context,
      builder: (BuildContext ctx) =>
          _BakeRecipeEditorDialog(existing: recipe),
    );
    if (draft == null || !mounted) {
      return;
    }
    await viewModel.saveOsgBakeRecipes(
      viewModel.osgBakeRecipes
          .map(
            (OsgBakeRecipe r) => r.id == recipe.id
                ? OsgBakeRecipe(id: r.id, name: draft.name, cues: draft.cues)
                : r,
          )
          .toList(),
    );
  }

  Future<void> _deleteBakeRecipe(
    DashboardViewModel viewModel,
    OsgBakeRecipe recipe,
  ) async {
    await viewModel.saveOsgBakeRecipes(
      viewModel.osgBakeRecipes
          .where((OsgBakeRecipe r) => r.id != recipe.id)
          .toList(),
    );
  }

  Widget _cardWithTitle({required String title, required Widget child}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(scaleDimension(context, 12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title),
            SizedBox(height: _gap(context)),
            child,
          ],
        ),
      ),
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
        SizedBox(width: scaleDimension(context, 8)),
        SizedBox(
          width: scaleDimension(context, 18),
          height: scaleDimension(context, 18),
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
        SizedBox(width: scaleDimension(context, 8)),
        Text(widget.label),
      ],
    );
  }

  Widget _buildStatusChild() {
    if (_state == _AsyncButtonVisualState.loading) {
      final double indicatorBox = scaleDimension(context, 16);
      final double stroke = scaleDimension(context, 2);
      return SizedBox(
        key: const ValueKey<String>("loading"),
        width: indicatorBox,
        height: indicatorBox,
        child: CircularProgressIndicator(strokeWidth: stroke),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: theme.textTheme.titleLarge);
  }
}

/// Mutable per-cue editing state for [_BakeRecipeEditorDialog].
class _DraftBakeCue {
  _DraftBakeCue();

  factory _DraftBakeCue.fromCue(OsgBakeCue cue) {
    final _DraftBakeCue draft = _DraftBakeCue();
    draft.slot = cue.slot;
    draft.startKind = cue.start.kind;
    draft.endKind = cue.end.kind;
    if (draft.startKind == OsgBakeAnchorKind.absoluteMs ||
        draft.startKind == OsgBakeAnchorKind.offsetFromEndMs) {
      draft.startMsController.text = "${cue.start.valueMs}";
    }
    if (draft.endKind == OsgBakeAnchorKind.absoluteMs ||
        draft.endKind == OsgBakeAnchorKind.offsetFromEndMs) {
      draft.endMsController.text = "${cue.end.valueMs}";
    }
    return draft;
  }

  OsgPresetSlot slot = OsgPresetSlot.preset1;
  OsgBakeAnchorKind startKind = OsgBakeAnchorKind.clipStart;
  OsgBakeAnchorKind endKind = OsgBakeAnchorKind.clipEnd;
  final TextEditingController startMsController = TextEditingController(
    text: "0",
  );
  final TextEditingController endMsController = TextEditingController(
    text: "0",
  );

  void dispose() {
    startMsController.dispose();
    endMsController.dispose();
  }

  OsgBakeCue toCue() {
    int parseMs(TextEditingController c) {
      final int v = int.tryParse(c.text.trim()) ?? 0;
      return v < 0 ? 0 : v;
    }

    return OsgBakeCue(
      slot: slot,
      start: OsgBakeAnchor(kind: startKind, valueMs: parseMs(startMsController)),
      end: OsgBakeAnchor(kind: endKind, valueMs: parseMs(endMsController)),
    );
  }
}

/// Creates or edits a bake recipe (name + cue list). Pops with the draft recipe
/// (id 0 when adding; the caller assigns a real id) or null on cancel.
class _BakeRecipeEditorDialog extends StatefulWidget {
  const _BakeRecipeEditorDialog({this.existing});

  /// When set, the dialog opens in edit mode with this recipe pre-filled.
  final OsgBakeRecipe? existing;

  @override
  State<_BakeRecipeEditorDialog> createState() =>
      _BakeRecipeEditorDialogState();
}

class _BakeRecipeEditorDialogState extends State<_BakeRecipeEditorDialog> {
  final TextEditingController _nameController = TextEditingController();
  late final List<_DraftBakeCue> _cues;
  String? _validationError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final OsgBakeRecipe? existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _cues = existing.cues.isEmpty
          ? <_DraftBakeCue>[_DraftBakeCue()]
          : existing.cues.map(_DraftBakeCue.fromCue).toList();
    } else {
      _cues = <_DraftBakeCue>[_DraftBakeCue()];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final _DraftBakeCue cue in _cues) {
      cue.dispose();
    }
    super.dispose();
  }

  bool _anchorNeedsMs(OsgBakeAnchorKind kind) =>
      kind == OsgBakeAnchorKind.absoluteMs ||
      kind == OsgBakeAnchorKind.offsetFromEndMs;

  Widget _anchorEditor({
    required String label,
    required OsgBakeAnchorKind kind,
    required TextEditingController msController,
    required ValueChanged<OsgBakeAnchorKind> onKindChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: scaleDimension(context, 140),
          child: DropdownButtonFormField<OsgBakeAnchorKind>(
            initialValue: kind,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: OsgBakeAnchorKind.values
                .map(
                  (OsgBakeAnchorKind k) => DropdownMenuItem<OsgBakeAnchorKind>(
                    value: k,
                    child: Text(k.label),
                  ),
                )
                .toList(),
            onChanged: (OsgBakeAnchorKind? value) {
              if (value != null) {
                onKindChanged(value);
              }
            },
          ),
        ),
        if (_anchorNeedsMs(kind)) ...<Widget>[
          SizedBox(width: scaleDimension(context, 8)),
          SizedBox(
            width: scaleDimension(context, 90),
            child: TextField(
              controller: msController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: "Ms",
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cueRow(int index) {
    final _DraftBakeCue cue = _cues[index];
    return Card(
      margin: EdgeInsets.only(bottom: scaleDimension(context, 8)),
      child: Padding(
        padding: EdgeInsets.all(scaleDimension(context, 8)),
        child: Wrap(
          spacing: scaleDimension(context, 8),
          runSpacing: scaleDimension(context, 8),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: scaleDimension(context, 148),
              child: DropdownButtonFormField<OsgPresetSlot>(
                initialValue: cue.slot,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "OSG",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: OsgPresetSlot.values
                    .map(
                      (OsgPresetSlot s) => DropdownMenuItem<OsgPresetSlot>(
                        value: s,
                        child: Text("OSG ${s.playoutHotkeyDigitLabel}"),
                      ),
                    )
                    .toList(),
                onChanged: (OsgPresetSlot? value) {
                  if (value != null) {
                    setState(() => cue.slot = value);
                  }
                },
              ),
            ),
            _anchorEditor(
              label: "Show From",
              kind: cue.startKind,
              msController: cue.startMsController,
              onKindChanged: (OsgBakeAnchorKind k) =>
                  setState(() => cue.startKind = k),
            ),
            _anchorEditor(
              label: "Until",
              kind: cue.endKind,
              msController: cue.endMsController,
              onKindChanged: (OsgBakeAnchorKind k) =>
                  setState(() => cue.endKind = k),
            ),
            IconButton(
              tooltip: "Remove Cue",
              icon: const Icon(Icons.delete_outline),
              onPressed: _cues.length <= 1
                  ? null
                  : () {
                      setState(() {
                        _cues.removeAt(index).dispose();
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _validationError = "Recipe name is required.");
      return;
    }
    if (_cues.isEmpty) {
      setState(() => _validationError = "Add at least one cue.");
      return;
    }
    Navigator.of(context).pop(
      OsgBakeRecipe(
        id: widget.existing?.id ?? 0,
        name: name,
        cues: _cues.map((_DraftBakeCue c) => c.toCue()).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? "Edit bake recipe" : "Add bake recipe"),
      content: SizedBox(
        width: scaleDimension(context, 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Recipe Name",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: scaleDimension(context, 12)),
              for (int i = 0; i < _cues.length; i++) _cueRow(i),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _cues.add(_DraftBakeCue())),
                  icon: const Icon(Icons.add),
                  label: const Text("Add Cue"),
                ),
              ),
              if (_validationError != null) ...<Widget>[
                SizedBox(height: scaleDimension(context, 8)),
                Text(
                  _validationError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text("Save Recipe"),
        ),
      ],
    );
  }
}
