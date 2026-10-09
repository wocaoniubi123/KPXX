// kp_avif - Windows implementation (added 2026-10-09).
//
// Contract is IDENTICAL to the iOS side (ImageIO) and to lib/kp_avif.dart:
//   channel "kp_avif", method "decodeToPng", args {"bytes": Uint8List},
//   reply = Uint8List (PNG) or **null** when it cannot be decoded.
// Every failure path returns null, never an error: the Dart callers already treat null as
// "cannot decode" and fall back to their placeholder (see lib/fetched_image.dart:330).
//
// Decoder: the system WIC (Windows Imaging Component). Measured on this machine:
//   an AVIF decodes through WIC as 1204x800 BGRA with codec name "Microsoft HEIF Decoder",
// i.e. the AVIF decoder is provided by the Store package "HEIF Image Extension".
//   * If that extension is missing, CreateDecoderFromStream fails here and we simply return
//     null, which is exactly today's behaviour on Windows (no crash, placeholder shown).
//   * No third-party decoder is bundled, so nothing is added to the app package.
//
// ASCII-only comments on purpose: MSVC does not get /utf-8 from the Flutter template, so a
// UTF-8 comment would be decoded with the system codepage and could swallow the next line.

#include "kp_avif_plugin.h"

#include <flutter/standard_method_codec.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>
#include <utility>
#include <vector>

namespace kp_avif {

namespace {

using Microsoft::WRL::ComPtr;

constexpr char kChannelName[] = "kp_avif";
constexpr char kMethodDecodeToPng[] = "decodeToPng";
constexpr char kArgBytes[] = "bytes";

// RAII for CoInitializeEx: the platform thread is normally already initialized by the runner
// (windows/runner/main.cpp does CoInitializeEx with APARTMENTTHREADED), in which case S_FALSE
// is returned and we must NOT uninitialize. This guard only uninitializes what it owns.
class ComScope {
 public:
  ComScope() : own_(SUCCEEDED(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {}
  ~ComScope() {
    if (own_) ::CoUninitialize();
  }
  ComScope(const ComScope&) = delete;
  ComScope& operator=(const ComScope&) = delete;

 private:
  bool own_;
};

// AVIF bytes -> PNG bytes. Returns false on any failure (caller replies null).
bool DecodeAvifToPng(const std::vector<uint8_t>& input, std::vector<uint8_t>* output) {
  if (input.empty()) return false;

  ComPtr<IWICImagingFactory> factory;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) {
    return false;
  }

  // 1) memory -> WIC input stream
  ComPtr<IWICStream> in_stream;
  if (FAILED(factory->CreateStream(&in_stream))) return false;
  if (FAILED(in_stream->InitializeFromMemory(
          const_cast<BYTE*>(input.data()), static_cast<DWORD>(input.size())))) {
    return false;
  }

  // 2) decode (this is where the system AVIF/HEIF decoder is used)
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(in_stream.Get(), nullptr,
                                              WICDecodeMetadataCacheOnLoad, &decoder))) {
    return false;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) return false;

  // 3) normalize to 32bpp BGRA (what the PNG encoder expects; keeps any alpha channel)
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter))) return false;
  if (FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return false;
  }

  // 4) encode PNG into a memory stream
  ComPtr<IStream> out_stream;
  if (FAILED(::CreateStreamOnHGlobal(nullptr, TRUE, &out_stream))) return false;
  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder))) return false;
  if (FAILED(encoder->Initialize(out_stream.Get(), WICBitmapEncoderNoCache))) return false;
  ComPtr<IWICBitmapFrameEncode> frame_encode;
  ComPtr<IPropertyBag2> props;
  if (FAILED(encoder->CreateNewFrame(&frame_encode, &props))) return false;
  if (FAILED(frame_encode->Initialize(props.Get()))) return false;
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(frame_encode->SetPixelFormat(&format))) return false;
  if (FAILED(frame_encode->WriteSource(converter.Get(), nullptr))) return false;
  if (FAILED(frame_encode->Commit())) return false;
  if (FAILED(encoder->Commit())) return false;
  // Best effort flush; the data is already in the HGLOBAL after Commit above.
  out_stream->Commit(STGC_DEFAULT);

  // 5) pull the bytes out of the memory stream
  HGLOBAL hglobal = nullptr;
  if (FAILED(::GetHGlobalFromStream(out_stream.Get(), &hglobal)) || hglobal == nullptr) {
    return false;
  }
  const SIZE_T size = ::GlobalSize(hglobal);
  if (size == 0) return false;
  const void* data = ::GlobalLock(hglobal);
  if (data == nullptr) return false;
  output->assign(static_cast<const uint8_t*>(data),
                 static_cast<const uint8_t*>(data) + size);
  ::GlobalUnlock(hglobal);
  return true;
}

}  // namespace

// static
void KpAvifPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<KpAvifPlugin>();
  KpAvifPlugin* plugin_pointer = plugin.get();
  channel->SetMethodCallHandler(
      [plugin_pointer](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

KpAvifPlugin::KpAvifPlugin() = default;

KpAvifPlugin::~KpAvifPlugin() = default;

void KpAvifPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() != kMethodDecodeToPng) {
    result->NotImplemented();
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (args == nullptr) {
    result->Success(flutter::EncodableValue());
    return;
  }
  const auto it = args->find(flutter::EncodableValue(kArgBytes));
  if (it == args->end()) {
    result->Success(flutter::EncodableValue());
    return;
  }
  const auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second);
  if (bytes == nullptr) {
    result->Success(flutter::EncodableValue());
    return;
  }
  std::vector<uint8_t> png;
  if (DecodeAvifToPng(*bytes, &png)) {
    result->Success(flutter::EncodableValue(std::move(png)));
  } else {
    result->Success(flutter::EncodableValue());  // null -> Dart falls back to its placeholder
  }
}

}  // namespace kp_avif
