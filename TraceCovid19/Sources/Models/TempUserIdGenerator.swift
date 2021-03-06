//
//  TempIdGenerator.swift
//  TraceCovid19
//
//  Created by yosawa on 2020/05/01.
//

import Foundation

final class TempIdGenerator {
    /// 区切りの時間
    private static let breakClock = "T04:00:00"
    /// 一度に生成する数
    private static let defaultGenerateCount = 3

    func createTempUserIds(startDate: Date = Date(), count: Int = defaultGenerateCount) -> [TempUserId] {
        var date = createDate(date: startDate)
        if Date() < date {
            // 開始日時が、区切り時間の関係上まだ始まっていないなら、さらにその前日を開始時間とする
            date = date.previousDate()
        }
        if date == createDate(date: date.nextDate()) {
            // タイムゾーンの関係で次の日が一致してしまうなら、次の日を開始とする
            date = date.nextDate()
        }

        var result: [TempUserId] = []
        for _ in 0..<count {
            /// 先頭の方により未来のものを追加していく
            result.insert(create(startDate: date), at: 0)
            date = date.nextDate()
        }
        return result
    }

    private func create(startDate: Date) -> TempUserId {
        let endTime = createDate(date: startDate.nextDate())
        return TempUserId(startTime: createDate(date: startDate), endTime: endTime)
    }

    private func createDate(date: Date, format: String = breakClock) -> Date {
        let dateString = date.toString(format: "yyyy/MM/dd")
        return (dateString + format).toDate(format: "yyyy/MM/dd'T'HH:mm:ss")!
    }
}

private extension Date {
    func nextDate() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: self))! // 翌日
    }

    func previousDate() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: self))! // 前日
    }
}

private extension TempUserId {
    init(startTime: Date, endTime: Date) {
        // NOTE: IDの生成ルールはUUID1+UUID2+validFrom+validToでSha256とする
        let uuid1 = UUID().uuidString
        let uuid2 = UUID().uuidString
        self.tempId = "\(uuid1)\(uuid2)\(Int(startTime.timeIntervalSince1970))\(Int(endTime.timeIntervalSince1970)))".sha256!
        print("[DEBUG] TempUserId \(startTime) \(endTime)")
        self.startTime = startTime
        self.endTime = endTime
    }
}
