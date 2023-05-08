//
//  VTT.swift
//
//  Copyright © 2023 Darren Ford. All rights reserved.
//
//  MIT License
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import DSFRegex
import Foundation

/*

 WEBVTT

 00:00:01.000 --> 00:00:05.330
 Good day everyone, my name is June Doe.

 00:00:07.608 --> 00:00:15.290
 This video teaches you how to
 build a sandcastle on any beach.

 */

// https://www.w3.org/TR/webvtt1/

// 2 - ASDFASDF
// 3
//private let CueIdentifierRegex__ = try! DSFRegex(#"^(\d)(?:\s(.*))?$"#)

private let VTTTimeRegex__ = try! DSFRegex(#"(?:(\d*):)?(?:(\d*):)(\d*)\.(\d{3})\s-->\s(?:(\d*):)?(?:(\d*):)(\d*)\.(\d{3})"#)

extension Subtitles.Coder {
	/// VTT codable file
	///
	/// https://developer.mozilla.org/en-US/docs/Web/API/WebVTT_API
	public struct VTT: SubtitlesCodable {
		public static var extn: String { "vtt" }
		public static func Create() -> Self { VTT() }
	}
}

public extension Subtitles.Coder.VTT {
	func encode(subtitles: Subtitles) throws -> String {
		var result = "WEBVTT\n\n"

		subtitles.entries.forEach { entry in
			if let identifier = entry.identifier {
				result += "\(identifier)"
			}
			result += "\n"

			let s = entry.startTime
			let e = entry.endTime
			result += String(
				format: "%02d:%02d:%02d.%03d --> %02d:%02d:%02d.%03d\n",
				s.hour, s.minute, s.second, s.millisecond,
				e.hour, e.minute, e.second, e.millisecond
			)

			result += "\(entry.text)\n\n"
		}

		return result
	}

	func decode(_ content: String) throws -> Subtitles {
		let lines = content
			.components(separatedBy: .newlines)
			.enumerated()
			.map { (offset: $0.offset, element: $0.element.trimmingCharacters(in: .whitespaces)) }

		guard lines[0].element.contains("WEBVTT") else {
			throw Subtitles.SRTError.invalidFile
		}

		// Break up into sections
		var sections: [[(index: Int, line: String)]] = []

		var inSection = false
		var currentLines = [(index: Int, line: String)]()
		lines.forEach { item in
			let line = item.element.trimmingCharacters(in: .whitespaces)
			if line.isEmpty {
				if inSection == true {
					// End of section
					sections.append(currentLines)
					currentLines.removeAll()
					inSection = false
				}
				else {

				}
			}
			else {
				if inSection == false {
					inSection = true
					currentLines = [(item.offset, line)]
				}
				else {
					currentLines.append((item.offset, line))
				}
			}
		}

		if inSection {
			sections.append(currentLines)
		}

		func parseTime(index: Int, timeLine: String) throws -> (Subtitles.Time, Subtitles.Time) {
			let matches = VTTTimeRegex__.matches(for: timeLine)
			guard matches.matches.count == 1 else {
				throw Subtitles.SRTError.invalidTime(index)
			}
			let captures = matches[0].captures
			guard captures.count == 8 else {
				throw Subtitles.SRTError.invalidTime(index)
			}

			let s_hour = UInt(timeLine[captures[0]]) ?? 0
			let s_min = UInt(timeLine[captures[1]]) ?? 0

			let e_hour = UInt(timeLine[captures[4]]) ?? 0
			let e_min = UInt(timeLine[captures[5]]) ?? 0

			guard
				let s_sec = UInt(timeLine[captures[2]]),
				let s_ms = UInt(timeLine[captures[3]]),
				let e_sec = UInt(timeLine[captures[6]]),
				let e_ms = UInt(timeLine[captures[7]])
			else {
				throw Subtitles.SRTError.invalidTime(index)
			}

			let s = Subtitles.Time(hour: s_hour, minute: s_min, second: s_sec, millisecond: s_ms)
			let e = Subtitles.Time(hour: e_hour, minute: e_min, second: e_sec, millisecond: e_ms)

			return (s, e)
		}

		var results = [Subtitles.Entry]()

		for section in sections {
			guard section.count > 0 else {
				throw Subtitles.SRTError.invalidFile
			}

			var index = 0
			let line = section[index]

			if line.line.contains("WEBVTT") ||
				line.line.starts(with: "NOTE") ||
				line.line.starts(with: "STYLE") ||
				line.line.starts(with: "REGION")
			{
				// Ignore
				continue
			}

			var identifier: String?
			var times: (Subtitles.Time, Subtitles.Time)?

			// 1. Optional cue identifier (string?)
			let l1 = section[index]
			do {
				times = try parseTime(index: l1.index, timeLine: l1.line)
				index += 1
				guard index < section.count else {
					throw Subtitles.SRTError.invalidLine(line.index)
				}
			}
			catch {
				// Might have a cue identifier? Just ignore this failure
			}

			if times == nil {
				// Assume its a cue identifier
				identifier = l1.line

				index += 1
				guard index < section.count else {
					throw Subtitles.SRTError.invalidLine(line.index)
				}
				let l2 = section[index]
				times = try parseTime(index: l2.index, timeLine: l2.line)
				index += 1
			}

			guard index < section.count else {
				throw Subtitles.SRTError.invalidLine(line.index)
			}

			// next is the text
			var text = ""
			// Skip to the next blank
			while index < section.count && section[index].line.isEmpty == false {
				if !text.isEmpty {
					text += "\n"
				}
				text += section[index].line
				index += 1
			}

			let entry = Subtitles.Entry(
				identifier: identifier,
				startTime: times!.0,
				endTime: times!.1,
				text: text
			)
			results.append(entry)
		}

		return Subtitles(entries: results)
	}
}
