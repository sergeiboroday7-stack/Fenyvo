#include "hex_video_audio_levels_windows.h"

#include <windows.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

constexpr size_t kMaxWindows = 600;
constexpr int64_t kWindowHundredNs = 1000000;
constexpr uintmax_t kMaxFileBytes = 200ULL * 1024ULL * 1024ULL;
constexpr DWORD kMaxBufferBytes = 16 * 1024 * 1024;

bool IsAcceptableLocalFile(const std::wstring& path) {
  if (path.empty() || path.size() > 32767) return false;

  // This checks file type and size. The Flutter channel must
  // separately restrict paths to FENYVO application storage.
  std::error_code error;
  const std::filesystem::path candidate(path);

  if (!std::filesystem::is_regular_file(candidate, error) || error) {
    return false;
  }

  const auto bytes = std::filesystem::file_size(candidate, error);
  return !error && bytes > 0 && bytes <= kMaxFileBytes;
}

std::vector<double> DecodeAudio(const std::wstring& path) {
  ComPtr<IMFSourceReader> reader;
  if (FAILED(MFCreateSourceReaderFromURL(
          path.c_str(), nullptr, reader.GetAddressOf()))) {
    return {};
  }

  // Decode only the first audio stream; do not decode video frames.
  if (FAILED(reader->SetStreamSelection(
          static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE))) {
    return {};
  }

  if (FAILED(reader->SetStreamSelection(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), TRUE))) {
    return {};
  }

  ComPtr<IMFMediaType> requested;
  if (FAILED(MFCreateMediaType(requested.GetAddressOf()))) {
    return {};
  }

  if (FAILED(requested->SetGUID(
          MF_MT_MAJOR_TYPE, MFMediaType_Audio)) ||
      FAILED(requested->SetGUID(
          MF_MT_SUBTYPE, MFAudioFormat_PCM)) ||
      FAILED(reader->SetCurrentMediaType(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
          nullptr, requested.Get()))) {
    return {};
  }

  ComPtr<IMFMediaType> output;
  if (FAILED(reader->GetCurrentMediaType(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
          output.GetAddressOf()))) {
    return {};
  }

  UINT32 sample_rate = 0;
  UINT32 channels = 0;
  UINT32 bits = 0;

  if (FAILED(output->GetUINT32(
          MF_MT_AUDIO_SAMPLES_PER_SECOND, &sample_rate)) ||
      FAILED(output->GetUINT32(
          MF_MT_AUDIO_NUM_CHANNELS, &channels)) ||
      FAILED(output->GetUINT32(
          MF_MT_AUDIO_BITS_PER_SAMPLE, &bits)) ||
      sample_rate == 0 || sample_rate > 384000 ||
      channels == 0 || channels > 32 || bits != 16) {
    return {};
  }

  std::vector<double> sums(kMaxWindows, 0.0);
  std::vector<uint64_t> counts(kMaxWindows, 0);
  size_t last_window = 0;
  bool had_samples = false;

  const auto started = std::chrono::steady_clock::now();

  for (int iteration = 0; iteration < 100000; ++iteration) {
    if (std::chrono::steady_clock::now() - started >
        std::chrono::seconds(30)) {
      return {};
    }

    DWORD stream = 0;
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    ComPtr<IMFSample> sample;

    const HRESULT read_result = reader->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), 0, &stream,
        &flags, &timestamp, sample.GetAddressOf());

    if (FAILED(read_result)) return {};
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (flags & MF_SOURCE_READERF_ERROR) return {};
    if (!sample) continue;

    if (timestamp < 0 ||
        timestamp >= static_cast<LONGLONG>(
            kMaxWindows * kWindowHundredNs)) {
      break;
    }

    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(sample->ConvertToContiguousBuffer(
            buffer.GetAddressOf()))) {
      return {};
    }

    BYTE* raw = nullptr;
    DWORD max_length = 0;
    DWORD current_length = 0;

    if (FAILED(buffer->Lock(
            &raw, &max_length, &current_length))) {
      return {};
    }

    if (current_length > kMaxBufferBytes ||
        (current_length % (2 * channels)) != 0) {
      buffer->Unlock();
      return {};
    }

    const size_t frame_count =
        current_length / (2 * static_cast<size_t>(channels));

    for (size_t frame = 0; frame < frame_count; ++frame) {
      const int64_t frame_time = timestamp +
          static_cast<int64_t>(
              (frame * 10000000ULL) / sample_rate);

      if (frame_time < 0) continue;

      const size_t bucket =
          static_cast<size_t>(frame_time / kWindowHundredNs);

      if (bucket >= kMaxWindows) break;

      for (size_t channel = 0; channel < channels; ++channel) {
        const size_t offset =
            (frame * channels + channel) * 2;

        const uint16_t encoded =
            static_cast<uint16_t>(raw[offset]) |
            (static_cast<uint16_t>(raw[offset + 1]) << 8);

        const int16_t pcm = static_cast<int16_t>(encoded);
        const double value = static_cast<double>(pcm) / 32768.0;

        sums[bucket] += value * value;
        ++counts[bucket];
      }

      had_samples = true;
      last_window = std::max(last_window, bucket);
    }

    buffer->Unlock();
  }

  if (!had_samples) return {};

  std::vector<double> levels(last_window + 1, 0.0);

  for (size_t index = 0; index < levels.size(); ++index) {
    if (counts[index] > 0) {
      levels[index] = std::clamp(
          std::sqrt(sums[index] /
                    static_cast<double>(counts[index])),
          0.0, 1.0);
    }
  }

  return levels;
}

}  // namespace

std::vector<double> AnalyzeHexVideoAudioWindows(
    const std::wstring& local_path) {
  if (!IsAcceptableLocalFile(local_path)) return {};

  if (FAILED(MFStartup(MF_VERSION))) return {};

  std::vector<double> levels;

  try {
    levels = DecodeAudio(local_path);
  } catch (...) {
    levels.clear();
  }

  MFShutdown();
  return levels;
}