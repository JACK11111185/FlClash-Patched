#include "tray_menu_session.h"

#include <commctrl.h>

#include <utility>

namespace tray {

thread_local TrayMenuSession* TrayMenuSession::current_ = nullptr;

TrayMenuSession::TrayMenuSession(
    HWND owner, const std::unordered_set<UINT>& persistent_items,
    std::function<void(int)> on_selected)
    : owner_(owner),
      persistent_items_(persistent_items),
      on_selected_(std::move(on_selected)) {
  if (!::SetWindowSubclass(owner_, OwnerProc, reinterpret_cast<UINT_PTR>(this),
                           reinterpret_cast<DWORD_PTR>(this))) {
    return;
  }
  hook_ = ::SetWindowsHookExW(WH_MSGFILTER, FilterProc, nullptr,
                              ::GetCurrentThreadId());
  if (hook_ == nullptr) {
    ::RemoveWindowSubclass(owner_, OwnerProc, reinterpret_cast<UINT_PTR>(this));
    return;
  }
  previous_ = current_;
  current_ = this;
}

TrayMenuSession::~TrayMenuSession() {
  if (hook_ != nullptr) {
    ::UnhookWindowsHookEx(hook_);
    current_ = previous_;
    ::RemoveWindowSubclass(owner_, OwnerProc, reinterpret_cast<UINT_PTR>(this));
  }
}

LRESULT CALLBACK TrayMenuSession::OwnerProc(HWND window, UINT message,
                                            WPARAM wparam, LPARAM lparam,
                                            UINT_PTR id, DWORD_PTR data) {
  auto* session = reinterpret_cast<TrayMenuSession*>(data);
  if (message == WM_MENUSELECT) {
    const UINT flags = HIWORD(wparam);
    session->selected_menu_ = (flags == 0xffff || (flags & MF_POPUP) != 0)
                                  ? nullptr
                                  : reinterpret_cast<HMENU>(lparam);
    session->selected_id_ = LOWORD(wparam);
  } else if (message == WM_NCDESTROY) {
    session->selected_menu_ = nullptr;
    ::RemoveWindowSubclass(window, OwnerProc, id);
  }
  return ::DefSubclassProc(window, message, wparam, lparam);
}

bool TrayMenuSession::Filter(const MSG& message) {
  const bool mouse =
      message.message == WM_LBUTTONUP || message.message == WM_RBUTTONUP;
  const bool keyboard =
      message.message == WM_KEYDOWN &&
      (message.wParam == VK_RETURN || message.wParam == VK_SPACE);
  if ((!mouse && !keyboard) || selected_menu_ == nullptr ||
      persistent_items_.count(selected_id_) == 0) {
    return false;
  }
  MENUITEMINFOW item{};
  item.cbSize = sizeof(item);
  item.fMask = MIIM_STATE | MIIM_SUBMENU;
  if (!::GetMenuItemInfoW(selected_menu_, selected_id_, FALSE, &item) ||
      item.hSubMenu != nullptr) {
    return false;
  }
  if (mouse) {
    const int position =
        ::MenuItemFromPoint(nullptr, selected_menu_, message.pt);
    if (position < 0 ||
        ::GetMenuItemID(selected_menu_, position) != selected_id_) {
      return false;
    }
  }
  if ((item.fState & (MFS_DISABLED | MFS_GRAYED)) == 0 &&
      (!keyboard || (message.lParam & (1LL << 30)) == 0)) {
    on_selected_(static_cast<int>(selected_id_));
  }
  return true;
}

LRESULT CALLBACK TrayMenuSession::FilterProc(int code, WPARAM wparam,
                                             LPARAM lparam) {
  if (code == MSGF_MENU && current_ != nullptr &&
      current_->Filter(*reinterpret_cast<const MSG*>(lparam))) {
    return 1;
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
}

void TrayMenuSession::Redraw(HMENU menu) {
  ::EnumThreadWindows(
      ::GetCurrentThreadId(),
      [](HWND window, LPARAM data) -> BOOL {
        MENUBARINFO info{};
        info.cbSize = sizeof(info);
        if (::GetMenuBarInfo(window, OBJID_CLIENT, 0, &info) &&
            info.hMenu == reinterpret_cast<HMENU>(data)) {
          ::RedrawWindow(window, nullptr, nullptr,
                         RDW_INVALIDATE | RDW_UPDATENOW | RDW_FRAME);
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(menu));
}

}  // namespace tray
