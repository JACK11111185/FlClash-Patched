#ifndef FLUTTER_PLUGIN_TRAY_MENU_SESSION_H_
#define FLUTTER_PLUGIN_TRAY_MENU_SESSION_H_

#include <windows.h>

#include <functional>
#include <unordered_set>

namespace tray {

class TrayMenuSession {
 public:
  TrayMenuSession(HWND owner, const std::unordered_set<UINT>& persistent_items,
                  std::function<void(int)> on_selected);
  ~TrayMenuSession();

  TrayMenuSession(const TrayMenuSession&) = delete;
  TrayMenuSession& operator=(const TrayMenuSession&) = delete;

  static void Redraw(HMENU menu);

 private:
  static LRESULT CALLBACK FilterProc(int code, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK OwnerProc(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id, DWORD_PTR data);
  bool Filter(const MSG& message);

  static thread_local TrayMenuSession* current_;
  TrayMenuSession* previous_ = nullptr;
  HWND owner_;
  HHOOK hook_ = nullptr;
  HMENU selected_menu_ = nullptr;
  UINT selected_id_ = 0;
  const std::unordered_set<UINT>& persistent_items_;
  std::function<void(int)> on_selected_;
};

}  // namespace tray

#endif
