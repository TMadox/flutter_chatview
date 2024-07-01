import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:chatview/chatview.dart';
import 'package:chatview/src/models/voice_message_configuration.dart';
import 'package:chatview/src/widgets/reaction_widget.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class VoiceMessageView extends StatefulWidget {
  const VoiceMessageView({
    Key? key,
    required this.screenWidth,
    required this.message,
    required this.isMessageBySender,
    this.inComingChatBubbleConfig,
    this.outgoingChatBubbleConfig,
    this.onMaxDuration,
    this.messageReactionConfig,
    this.config,
  }) : super(key: key);

  /// Provides configuration related to voice message.
  final VoiceMessageConfiguration? config;

  /// Allow user to set width of chat bubble.
  final double screenWidth;

  /// Provides message instance of chat.
  final Message message;
  final Function(int)? onMaxDuration;

  /// Represents current message is sent by current user.
  final bool isMessageBySender;

  /// Provides configuration of reaction appearance in chat bubble.
  final MessageReactionConfiguration? messageReactionConfig;

  /// Provides configuration of chat bubble appearance from other user of chat.
  final ChatBubble? inComingChatBubbleConfig;

  /// Provides configuration of chat bubble appearance from current user of chat.
  final ChatBubble? outgoingChatBubbleConfig;

  @override
  State<VoiceMessageView> createState() => _VoiceMessageViewState();
}

class _VoiceMessageViewState extends State<VoiceMessageView> {
  late PlayerController controller;
  late StreamSubscription<PlayerState> playerStateSubscription;

  final ValueNotifier<PlayerState> _playerState = ValueNotifier(PlayerState.stopped);

  PlayerState get playerState => _playerState.value;

  PlayerWaveStyle playerWaveStyle = const PlayerWaveStyle(scaleFactor: 70);

  @override
  void initState() {
    super.initState();
    controller = PlayerController();
    playerStateSubscription = controller.onPlayerStateChanged.listen((state) => _playerState.value = state);
  }

  Future<File> downloadFile(String url, String filename) async {
    Dio dio = Dio();
    var dir = await getApplicationDocumentsDirectory();
    var file = File('${dir.path}/$filename');
    await dio.download(url, file.path);
    return file;
  }

  @override
  void dispose() {
    playerStateSubscription.cancel();
    controller.dispose();
    _playerState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: widget.config?.decoration ??
              BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: widget.isMessageBySender ? widget.outgoingChatBubbleConfig?.color : widget.inComingChatBubbleConfig?.color,
              ),
          padding: widget.config?.padding ?? const EdgeInsets.symmetric(horizontal: 8),
          margin: widget.config?.margin ??
              EdgeInsets.symmetric(
                horizontal: 8,
                vertical: widget.message.reaction.reactions.isNotEmpty ? 15 : 0,
              ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<PlayerState>(
                      builder: (context, state, child) => IconButton(
                        onPressed: _playOrPause,
                        icon: state.isStopped || state.isPaused || state.isInitialised
                            ? widget.config?.playIcon ??
                                const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                )
                            : widget.config?.pauseIcon ??
                                const Icon(
                                  Icons.stop,
                                  color: Colors.white,
                                ),
                      ),
                      valueListenable: _playerState,
                    ),
                    AudioFileWaveforms(
                      size: Size(widget.screenWidth * 0.50, 40),
                      playerController: controller,
                      waveformType: WaveformType.fitWidth,
                      playerWaveStyle: widget.config?.playerWaveStyle ?? playerWaveStyle,
                      padding: widget.config?.waveformPadding ?? const EdgeInsets.only(right: 10),
                      margin: widget.config?.waveformMargin,
                      animationCurve: widget.config?.animationCurve ?? Curves.easeIn,
                      animationDuration: widget.config?.animationDuration ?? const Duration(milliseconds: 500),
                      enableSeekGesture: widget.config?.enableSeekGesture ?? true,
                    ),
                  ],
                ),
                if (widget.message.voiceMessageDuration != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDuration(widget.message.voiceMessageDuration!.inMilliseconds),
                        style: const TextStyle(color: Colors.white, height: 1),
                      ),
                      Text(
                        DateFormat('h:mm a').format(widget.message.createdAt),
                        style: const TextStyle(color: Colors.white, height: 1),
                      )
                    ],
                  ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        if (widget.message.reaction.reactions.isNotEmpty)
          ReactionWidget(
            isMessageBySender: widget.isMessageBySender,
            reaction: widget.message.reaction,
            messageReactionConfig: widget.messageReactionConfig,
          ),
      ],
    );
  }

  String formatDuration(int milliseconds) {
    int minutes = (milliseconds / 60000).floor();
    int seconds = ((milliseconds % 60000) / 1000).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _playOrPause() async {
    assert(
      defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android,
      "Voice messages are only supported with android and ios platform",
    );
    if (playerState.isInitialised || playerState.isPaused || playerState.isStopped) {
      File audioFile = await downloadFile(widget.message.message, Uri.parse(widget.message.message).pathSegments.last);
      controller
          .preparePlayer(
            path: audioFile.path,
            noOfSamples: widget.config?.playerWaveStyle?.getSamplesForWidth(widget.screenWidth * 0.5) ??
                playerWaveStyle.getSamplesForWidth(widget.screenWidth * 0.5),
          )
          .whenComplete(() => widget.onMaxDuration?.call(controller.maxDuration));
      controller.startPlayer(finishMode: FinishMode.pause);
    } else {
      controller.pausePlayer();
    }
  }
}
