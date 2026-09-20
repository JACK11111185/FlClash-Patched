import AppKit

@main
enum TrayMenuTests {
    static func proxy(_ key: String, id: Int) -> [String: Any] {
        [
            "type": "checkbox", "key": key, "id": id, "label": key,
            "enabled": true, "checked": false, "usesCustomView": true,
        ]
    }

    static func group(_ name: String, items: [[String: Any]]) -> [String: Any] {
        ["type": "submenu", "label": name, "items": items, "usesCustomView": true]
    }

    static func open(_ menu: TrayMenu) {
        menu.delegate?.menuNeedsUpdate?(menu)
    }

    static func main() {
        _ = NSApplication.shared
        var selected: Int?
        let nodes = (0..<2000).map { proxy("node-\($0)", id: $0 + 2000) }
        let menu = TrayMenu(items: [
            group("first", items: nodes),
            group("second", items: nodes),
        ]) { selected = $0 }
        let first = menu.items[0].submenu as! TrayMenu
        let second = menu.items[1].submenu as! TrayMenu
        precondition(menu.numberOfItems == 2)
        precondition(first.numberOfItems == 0 && second.numberOfItems == 0,
                     "Constructing the tray must not build unopened proxy views")

        menu.update()
        precondition(first.numberOfItems == 0 && second.numberOfItems == 0,
                     "Updating the root must not populate its submenus")
        open(first)
        precondition(first.numberOfItems == nodes.count)
        precondition(second.numberOfItems == 0)
        let firstItem = first.items[0]
        precondition(firstItem.view != nil)
        open(first)
        precondition(first.items[0] === firstItem, "Reopening must reuse native views")

        let replacement = [proxy("replacement", id: 99)]
        precondition(menu.update(items: [
            group("first", items: nodes),
            group("renamed", items: replacement),
        ]))
        precondition(menu.items[1].submenu === second)
        precondition(second.numberOfItems == 0)
        precondition(first.items[0] === firstItem)

        precondition(menu.updateMenuItems([
            ["key": "replacement", "label": "latest", "checked": true, "sublabel": "42 ms"],
        ]))
        precondition(second.numberOfItems == 0, "Patching a closed menu must stay lazy")
        precondition(!menu.updateMenuItems([
            ["key": "replacement", "label": "must not apply"],
            ["key": "missing", "label": "unknown"],
        ]))
        open(second)
        precondition(second.numberOfItems == 1)
        let replacementItem = second.items[0]
        precondition(replacementItem.title == "latest")
        precondition(replacementItem.tag == 99)
        precondition(replacementItem.state == .on)
        precondition(replacementItem.view != nil)
        precondition(NSApp.sendAction(replacementItem.action!, to: replacementItem.target,
                                      from: replacementItem))
        precondition(selected == 99, "Deferred items must retain their selection IDs")
        precondition(menu.updateMenuItems([
            ["key": "replacement", "checked": false, "enabled": false],
        ]))
        precondition(replacementItem.state == .off && !replacementItem.isEnabled)
        precondition(replacementItem.action == nil)

        let nested = TrayMenu(items: [group("outer", items: [
            group("inner", items: [proxy("nested", id: 100)]),
        ])], onSelect: { _ in })
        let outer = nested.items[0].submenu as! TrayMenu
        precondition(nested.updateMenuItems([["key": "nested", "label": "patched"]]))
        precondition(outer.numberOfItems == 0)
        open(outer)
        let inner = outer.items[0].submenu as! TrayMenu
        precondition(inner.numberOfItems == 0)
        open(inner)
        precondition(inner.items[0].title == "patched")

        precondition(!menu.update(items: [group("different", items: [])]),
                     "Incompatible materialized menus still require replacement")
        print("Native menu tests passed")
    }
}
