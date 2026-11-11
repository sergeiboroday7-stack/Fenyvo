#ifndef FENYVO_HEX_VIDEO_AUDIO_LEVELS_WINDOWS_H_
#define FENYVO_HEX_VIDEO_AUDIO_LEVELS_WINDOWS_H_

#include <string>
#include <vector>

// Decodes the audio track of an already-local video file.
// One normalized RMS value per 100 ms, maximum 600 values.
// Caller must run this on a background thread.
std::vector<double> AnalyzeHexVideoAudioWindows(
    const std::wstring& local_path);

#endif