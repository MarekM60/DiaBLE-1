import Foundation

//
// Some notes on the Libre Pro still to be verified
//
//
// https://github.com/bubbledevteam/bubble-client-swift/blob/master/BubbleClient/LibrePro.swift
//
//
// 22 FRAM blocks readable by ISO commands:
// 0x000:  ( 40, "Header")
// 0x028:  ( 32, "Footer")
// 0x048:  (104, "Body")
//
// header[4]: sensor state
// if state = 6:
//     header[6] = error code
//     header[7] + header[8] << 8: sensor age when error occurred [0 = unknown]
//
// footer[6] + footer[7] << 8: maximum life
//
// body[2] + body[3] << 8: sensor age
// body[4] + body[5] << 8: trend index
// body[6] + body[7] << 8: history index
// body[8...103]: 16 6-byte trend values
//
// The blocks of historic data are readable by B0/B3:
// if history index < 32 then read starting from the 22nd block
// else read starting again from the 22nd block: (((index - 32) * 6) + 22 * 8) / 8
//
// blocks 0x0406 - 0x04DD: section ending with the patch table for the commands
//                         A0 A1 A2 A4 A3 ?? E0 E1 E2
//
// The raw value is masked by 0x1FFF and needs a conversion factor of 8.5
//
// Libre Pro memory dump:
// config: 0x1A00, 64
// sram:   0x1C00, 4096


class LibrePro: Sensor {

    static func calibrationInfo(fram: Data) -> CalibrationInfo {
        let b = 14 + 42
        let i1 = readBits(fram, 26, 0, 3)
        let i2 = readBits(fram, 26, 3, 0xa)
        let i3 = readBits(fram, b, 0, 8)
        let i4 = readBits(fram, b, 8, 0xe)
        let negativei3 = readBits(fram, b, 0x21, 1) != 0
        let i5 = readBits(fram, b, 0x28, 0xc) << 2
        let i6 = readBits(fram, b, 0x34, 0xc) << 2

        return CalibrationInfo(i1: i1, i2: i2, i3: negativei3 ? -i3 : i3, i4: i4, i5: i5, i6: i6)
    }

}
