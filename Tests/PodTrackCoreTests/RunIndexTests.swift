import XCTest
@testable import PodTrackCore

final class RunIndexTests: XCTestCase {
    private func fixtureRun(height: Double?, car: String = "Hot Wheels") -> RunSession {
        let input = SimulatedTrack.generate(drop:height ?? 0.42,includeJump:false,profile:.raisedFinish)
        return .init(source:.simulation,metadata:.init(carName:car,verticalDrop:height),
                     calibration:input.calibration,samples:input.samples)
    }

    /// Quote-aware reader, so a comma inside a name cannot pass as a column separator.
    private func rows(_ csv: String) -> [[String]] {
        csv.split(separator:"\n",omittingEmptySubsequences:true).map { line in
            var fields: [String] = [], field = "", quoted = false, index = line.startIndex
            while index < line.endIndex {
                let character = line[index]
                if quoted {
                    if character == "\"" {
                        let next = line.index(after:index)
                        if next < line.endIndex, line[next] == "\"" { field.append("\""); index = next }
                        else { quoted = false }
                    } else { field.append(character) }
                } else if character == "\"" { quoted = true }
                else if character == "," { fields.append(field); field = "" }
                else { field.append(character) }
                index = line.index(after:index)
            }
            fields.append(field)
            return fields
        }
    }

    func testIndexCarriesEachRunsOwnUnitsAndLeavesRawOnlyEstimatesEmpty() throws {
        let measured = fixtureRun(height:0.58,car:"Car A")
        let relative = fixtureRun(height:nil,car:"Car B")
        var rawOnly = fixtureRun(height:0.58,car:"Car C")
        rawOnly.calibration = nil
        let entries = [RunIndexEntry(run:measured,result:try AnalysisPipeline.analyze(measured),status:"3D path ready"),
                       RunIndexEntry(run:relative,result:try AnalysisPipeline.analyze(relative),status:"Relative 3D shape"),
                       RunIndexEntry(run:rawOnly,result:nil,status:"Raw only · no calibration")]
        let table = rows(CSVExporter.runIndex(entries,method:.old))
        let header = table[0]
        XCTAssertEqual(table.count,4)
        let unitColumn = try XCTUnwrap(header.firstIndex(of:"distance_unit"))
        let lengthColumn = try XCTUnwrap(header.firstIndex(of:"estimated_path_length"))
        let speedColumn = try XCTUnwrap(header.firstIndex(of:"estimated_top_speed"))
        let heightColumn = try XCTUnwrap(header.firstIndex(of:"entered_height_h_cm"))
        XCTAssertEqual(table[1][unitColumn],"m")
        XCTAssertEqual(table[2][unitColumn],"u")
        XCTAssertEqual(Double(table[1][heightColumn]),58)
        // A run normalized to one relative unit must not be reported in metres.
        XCTAssertEqual(try XCTUnwrap(Double(table[2][lengthColumn])),1,accuracy:1e-9)
        XCTAssertEqual(Double(table[3][heightColumn]),58)
        // No reconstruction: estimates stay empty instead of carrying a substituted value.
        XCTAssertEqual(table[3][unitColumn],"")
        XCTAssertEqual(table[3][lengthColumn],"")
        XCTAssertEqual(table[3][speedColumn],"")
        XCTAssertEqual(table[3][try XCTUnwrap(header.firstIndex(of:"status"))],"Raw only · no calibration")
    }

    func testIndexIdentifiesEveryRunAndItsAlgorithm() throws {
        let run = fixtureRun(height:0.58)
        let result = try AnalysisPipeline.analyze(run)
        let table = rows(CSVExporter.runIndex([.init(run:run,result:result,status:"3D path ready")],method:.old))
        let header = table[0], row = table[1]
        XCTAssertEqual(row[try XCTUnwrap(header.firstIndex(of:"run_id"))],run.id.uuidString)
        XCTAssertEqual(row[try XCTUnwrap(header.firstIndex(of:"algorithm"))],"Old")
        XCTAssertEqual(row[try XCTUnwrap(header.firstIndex(of:"algorithm_version"))],"0.4.0-heuristic")
        XCTAssertEqual(row[try XCTUnwrap(header.firstIndex(of:"recorded_from"))],"simulation")
        XCTAssertEqual(Int(row[try XCTUnwrap(header.firstIndex(of:"samples"))]),run.samples.count)
    }

    func testCommasAndQuotesInNamesStayInsideOneColumn() throws {
        var run = fixtureRun(height:0.58)
        run.metadata.carName = "Car \"A\", red"
        run.metadata.trackName = "Loop, big"
        let table = rows(CSVExporter.runIndex([.init(run:run,result:nil,status:"Raw only")],method:.improved))
        XCTAssertEqual(table[1].count,table[0].count)
        XCTAssertEqual(table[1][try XCTUnwrap(table[0].firstIndex(of:"car"))],"Car \"A\", red")
        XCTAssertEqual(table[1][try XCTUnwrap(table[0].firstIndex(of:"track"))],"Loop, big")
    }
}
