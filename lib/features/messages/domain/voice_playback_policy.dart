/// Pure voice playback calculations.
///
/// AudioPlayer ownership, playback and lifecycle remain in the chat screen.
class VoicePlaybackPolicy {
  static double clampSeekFraction(double fraction) {
    return fraction.clamp(0.0, 1.0);
  }

  static double nextRate(double current) {
    return current < 1.25
        ? 1.5
        : current < 1.75
            ? 2.0
            : 1.0;
  }

  static double progress(Duration position, Duration duration) {
    return duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);
  }
}