#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Vertical phone-shaped WINDOW (width x height, logical px) - user ruling, 2026-10-09.
  // NOTE: this is the OUTER window size (CreateWindow includes title bar and borders), which is
  // why the client area is pinned to the exact device-frame size right after creation (below)
  // instead of trusting this number.
  // NOTE: changing this file needs a full rebuild - it is the C++ shell, not Dart.
  // NOTE: debug and release share this file, so `flutter build windows` output is phone-shaped too.
  // NOTE: keep comments ASCII-only on purpose - MSVC does not get /utf-8 from the template, so a
  // UTF-8 Chinese comment would be decoded with the system codepage (GBK) and may end in a
  // backslash, silently eating the following line.
  Win32Window::Size size(490, 1029);
  if (!window.Create(L"kpxx", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Pin the CLIENT area (what Dart sees as logical pixels) to exactly the device frame size, so
  // device_preview draws the simulated iPhone at fit scale 1.0 instead of shrinking it to fit
  // (with a 452 x 953 client it was 452/474 = 0.954).
  // Basis (device_preview 3.0.0 source): FitTransform uses
  //   scale = min(client.w / content.w, client.h / content.h).clamp(0, 1)
  // and the built-in iPhone 16 Pro Max frame artwork is 474 x 990 logical px
  //   (lib/src/presets.g.dart: frame size (474, 990); screen 440 x 956 inset by 17).
  // Why measure at runtime instead of hardcoding 490 x 1029: the non-client frame (title bar +
  // borders) depends on DPI, theme and window style, so measure this very window once and use the
  // measured delta; the same code then stays correct on another DPI or theme.
  {
    constexpr int kClientW = 474;  // iPhone 16 Pro Max frame width  (logical px)
    constexpr int kClientH = 990;  // iPhone 16 Pro Max frame height (logical px)
    HWND hwnd = window.GetHandle();
    RECT outer = {};
    RECT client = {};
    if (hwnd && ::GetWindowRect(hwnd, &outer) && ::GetClientRect(hwnd, &client)) {
      const int frame_w = (outer.right - outer.left) - (client.right - client.left);
      const int frame_h = (outer.bottom - outer.top) - (client.bottom - client.top);
      const HMONITOR monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
      ::SetWindowPos(hwnd, nullptr, 0, 0,
                     static_cast<int>(kClientW * scale) + frame_w,
                     static_cast<int>(kClientH * scale) + frame_h,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
