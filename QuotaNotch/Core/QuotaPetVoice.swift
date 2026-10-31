// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The status line under the pet in the opened notch, in the pet's own words. The numbers stay
/// on the line below it.
enum QuotaPetVoice {
    enum Moment: Int, CaseIterable, Sendable { case plenty, working, waiting, low, empty, refilled }

    /// The quota part of the moment: empty at zero, low under 20%.
    static func moment(remaining: Double) -> Moment { remaining <= 0 ? .empty : remaining < 20 ? .low : .plenty }

    static func line(_ kind: QuotaPetKind, _ moment: Moment, remaining: Double, chinese: Bool) -> String {
        let t = { (zh: String, en: String) in chinese ? zh : en }
        let boxes = Int(((100 - min(100, max(0, remaining))) / 100 * 6).rounded())
        switch (kind, moment) {
        case (.pear, .plenty):
            switch QuotaPetArt.pearPressure(mood: .idle, remaining: remaining) {
            case 0: return t("毫无鸭梨", "No pressure")
            case 1: return t("有点鸭梨", "A little pressure")
            case 2: return t("鸭梨有点大", "Pressure's building")
            default: return t("鸭梨山大", "Crushing pressure")
            }
        case (.bbq, .plenty):
            switch QuotaPetArt.doneness(remaining) {
            case 0: return t("还是生的", "Still raw")
            case 1: return t("三分熟", "Medium rare")
            case 2: return t("五分熟", "Medium")
            default: return t("七分熟", "Well done")
            }
        case (.ox, .plenty):
            return boxes == 0 ? t("车是空的", "Empty cart")
                : t("车上 \(boxes) 箱活", boxes == 1 ? "1 box on the cart" : "\(boxes) boxes on the cart")
        case (.ox, .low):
            return t("车上 \(boxes) 箱，拉不动了", "\(boxes) boxes, too heavy")
        default:
            let lines = chinese ? zh[kind] : en[kind]
            return lines?[moment.rawValue] ?? ""
        }
    }

    // plenty, working, waiting, low, empty, refilled
    private static let zh: [QuotaPetKind: [String]] = [
        .mochi: ["茶还有大半杯", "边喝茶边干活", "放下茶杯等你", "茶快见底了", "茶喝光了，睡了", "续上一大杯！"],
        .bit: ["电量充足", "满负荷运行中", "哔——有任务等你", "低电量警告", "没电，关机了", "充满电了！"],
        .jelly: ["还很 Q 弹", "Q 弹地干活中", "弹起来等你", "有点瘪了", "瘪成一摊了", "又鼓起来了！"],
        .ghost: ["飘得稳稳的", "飘来飘去干活", "飘过来等你", "快透明了", "已经看不见了", "又显形了！"],
        .sprout: ["水还够喝", "努力长高中", "竖起叶子等你", "有点渴了", "渴蔫了", "浇饱了，开花了！"],
        .fish: ["正在摸鱼", "被迫游起来干活", "跳出水面等你", "水快干了", "干了，摸不动了", "换满一缸水！"],
        .pear: ["有点鸭梨", "顶着鸭梨干活", "鸭梨…等你一下", "鸭梨山大", "被鸭梨压睡了", "毫无鸭梨！"],
        .bbq: ["三分熟", "滋滋烤着", "烤好一面等你翻", "快糊了", "芭比Q了", "换一根新的！"],
        .ox: ["车上 2 箱活", "埋头拉车", "哞——等你", "拉不动了", "拉满了，趴了", "卸完货了！"]
    ]
    private static let en: [QuotaPetKind: [String]] = [
        .mochi: ["Tea's mostly full", "Sipping and working", "Cup down, waiting", "Almost out of tea", "Tea's gone, napping", "Fresh cup!"],
        .bit: ["Battery good", "Running full tilt", "Beep! Task for you", "Low battery", "Battery dead", "Fully charged!"],
        .jelly: ["Still bouncy", "Bouncing on it", "Bounced up for you", "Getting flat", "A flat puddle", "Plump again!"],
        .ghost: ["Floating steady", "Haunting the code", "Floated over to you", "Nearly see-through", "Gone invisible", "Back in view!"],
        .sprout: ["Plenty of water", "Growing hard", "Leaves up, waiting", "Getting thirsty", "Wilted", "Watered, blooming!"],
        .fish: ["Slacking off", "Forced to swim", "Jumped up for you", "Water running low", "Bowl's dry", "Fresh bowl!"],
        .pear: ["A little pressure", "Working under pressure", "Pressure… need you", "Crushing pressure", "Crushed, asleep", "No pressure!"],
        .bbq: ["Medium rare", "Sizzling away", "Flip me!", "Nearly burnt", "BBQ'd", "A fresh one!"],
        .ox: ["2 boxes on the cart", "Pulling hard", "Moo! Need you", "Too heavy", "Cart full, lying down", "All unloaded!"]
    ]
}
