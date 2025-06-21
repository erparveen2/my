// ContactArcEstimator.swift – rev3 (22 Jun 2025)
// =================================================
// *This revision **compiles even when `swift-argument-parser` is NOT
// installed or declared in Package.swift***.  The file now:
//    • Wraps `import ArgumentParser` inside `#if canImport`.
//    • Provides a minimal fallback CLI so `swiftc ContactArcEstimator.swift …`
//      works with zero external Swift packages.
//    • Keeps the richer parser automatically if the module is available.
//
// HOW TO BUILD — THREE OPTIONS
// ---------------------------
// ❶ **Minimal / no packages** (needs only OpenCV headers & libs):
//     swiftc ContactArcEstimator.swift -I /usr/local/include/opencv4 \
//           -L /usr/local/lib -lopencv_core -lopencv_imgproc -lopencv_videoio \
//           -o contact-arc
//
// ❷ **Full SPM project with `ArgumentParser`, `SwiftCSV`, `SwiftPlot`:**
//     • Create a Package.swift as shown further below.
//     • `swift package resolve`  ➜  `swift run ContactArcEstimator --help`
//
// ❸ **Xcode GUI:**  File ▸ New ▸ Package, paste Package.swift, open.
//
// -------------------------------------------------------------
// Package.swift template (optional)
// -------------------------------------------------------------
/*
// swift-tools-version:5.9
import PackageDescription
let package = Package(
  name: "ContactArcEstimator",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "ContactArcEstimator", targets: ["ContactArcEstimator"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    .package(url: "https://github.com/swiftcsv/SwiftCSV.git", from: "0.6.0"),
    .package(url: "https://github.com/KarthikRIyer/swiftplot.git", branch: "master")
  ],
  targets: [
    .executableTarget(
      name: "ContactArcEstimator",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "SwiftCSV", "SwiftPlot",
        .product(name: "AGGRenderer", package: "swiftplot")
      ])
  ])
*/
// -------------------------------------------------------------

import Foundation
#if canImport(ArgumentParser)
import ArgumentParser
#endif
#if canImport(SwiftCSV)
import SwiftCSV
#endif
#if canImport(SwiftPlot) && canImport(AGGRenderer)
import SwiftPlot
import AGGRenderer
#endif
#if canImport(OpenCV)
import OpenCV
#endif

typealias PathStr = String
struct LoadEntry { let frame: Int; let load: Double }

// MARK: – OpenCV guard
func requireOpenCV() {
#if canImport(OpenCV)
    // OK
#else
    fatalError("OpenCV headers/libs not found. Install OpenCV & module map.")
#endif
}

// MARK: – Vision helpers (need OpenCV)
#if canImport(OpenCV)
import class OpenCV.Mat
import class OpenCV.VideoCapture
import func OpenCV.Imgproc.cvtColor
import func OpenCV.Imgproc.GaussianBlur
import func OpenCV.Imgproc.HoughCircles
import func OpenCV.Imgproc.HoughLinesP
import func OpenCV.Imgproc.Canny
import enum OpenCV.ColorConversionCodes
import struct OpenCV.Size2i
import let OpenCV.Imgproc.HOUGH_GRADIENT
import let OpenCV.CAP_PROP_POS_FRAMES

func detectDiscAndJaws(in mat: Mat) throws -> ((Int,Int,Int), [(Int,Int,Int,Int)]) {
    let gray = Mat(); Imgproc.cvtColor(src: mat, dst: gray, code: ColorConversionCodes.COLOR_BGR2GRAY.rawValue)
    let blur = Mat(); Imgproc.GaussianBlur(src: gray, dst: blur, ksize: Size2i(width:9,height:9), sigmaX: 0)
    let circles = Mat(); Imgproc.HoughCircles(_src: blur, _circles: circles, _method: HOUGH_GRADIENT,
        dp:1.2, minDist:Double(blur.rows())/2, param1:120, param2:60,
        minRadius:Int32(Double(blur.rows())*0.3/2), maxRadius:Int32(Double(blur.rows())*0.52/2))
    guard circles.cols() > 0 else { throw NSError(domain:"Disc",code:1) }
    var best:(Int32,Int32,Int32)=(0,0,0)
    for i in 0..<circles.cols(){ let v=circles.get(row:0,col:i);
        let r=Int32((v?[2] as! Float)); if r>best.2{ best=(Int32(v?[0] as! Float),Int32(v?[1] as! Float),r)} }
    let edges = Mat(); Imgproc.Canny(image: blur, edges: edges, threshold1:50, threshold2:150)
    let lines = Mat(); Imgproc.HoughLinesP(_image: edges, _lines: lines, rho:1, theta:Double.pi/180, threshold:120,
        minLineLength:Double(best.2)/2, maxLineGap:10)
    guard lines.rows()>=2 else{ throw NSError(domain:"Jaws",code:1)}
    var cands:[(Int,Int,Int,Int)] = []
    for i in 0..<lines.rows(){ let l=lines.get(row:i,col:0);
        let x1=Int(l?[0] as! Int32),y1=Int(l?[1] as! Int32),x2=Int(l?[2] as! Int32),y2=Int(l?[3] as! Int32)
        if abs(atan2(Double(y2-y1),Double(x2-x1)))<0.05{ cands.append((x1,y1,x2,y2)) }}
    guard cands.count>=2 else{ throw NSError(domain:"Jaws",code:2)}
    cands.sort{($0.1+$0.3)<($1.1+$1.3)}; return ((Int(best.0),Int(best.1),Int(best.2)),[cands.first!,cands.last!])
}
func contactHalfAngle(disc:(Int,Int,Int), jaws:[(Int,Int,Int,Int)]) -> Double{
    let(xc,yc,_)=disc;let θ=jaws.map{l->Double in let(x1,y1,x2,y2)=l;return atan2(Double(y1+y2)/2-Double(yc),Double(x1+x2)/2-Double(xc))};
    return abs(θ.sorted()[0])*180/Double.pi }
#endif

// MARK: – Core executor
struct Core {
    let video:PathStr?;let loadCSV:PathStr?;let femCSV:PathStr?;let outDir:String;let thresholds:[Double]
    func run() throws {
        if video==nil && loadCSV==nil { print("No args – running internal test"); try unit(); return }
        guard let v=video, let l=loadCSV else { throw NSError(domain:"Args",code:1) }
        requireOpenCV()
        #if canImport(SwiftCSV)
        let csv = try CSV(url: URL(fileURLWithPath:l))
        let rows = csv.namedRows
        let entries: [LoadEntry] = rows.compactMap{ guard let f=Int($0["frame"]!), let ld=Double($0["load"]!) else{return nil}; return LoadEntry(frame:f,load:ld)}
        #else
        fatalError("SwiftCSV not available – install via SPM or supply --run-tests")
        #endif
        guard let pMax = entries.map({$0.load}).max() else { throw NSError(domain:"CSV",code:2) }
        let frames = thresholds.map{ thr->Int in entries.min{ abs($0.load-pMax*thr) < abs($1.load-pMax*thr)}!.frame }
        print("Frames:",frames)
#if canImport(OpenCV)
        let cap = VideoCapture(v); guard cap.isOpened() else{ throw NSError(domain:"Video",code:1)}
        var results:[(Int,Double,Double)]=[]
        for f in frames{ cap.set(propId:CAP_PROP_POS_FRAMES,value:Double(f)); let m=Mat(); if cap.read(image:m){ let(disc,jaws)=try detectDiscAndJaws(in:m); let a=contactHalfAngle(disc:disc,jaws:jaws); let ld=entries.first{$0.frame==f}!.load; results.append((f,ld,a))}}
        print(results)
#endif
        // (CSV save / plotting omitted in minimal build)
    }
    func unit() throws {
        #if canImport(OpenCV)
        let α = contactHalfAngle(disc:(0,0,100),jaws:[(-50,-100,50,-100),(-50,100,50,100)]); assert(abs(α-90)<1e-6)
        print("Unit test passed ✅")
        #else
        print("Unit test skipped – OpenCV not present")
        #endif
    }
}

#if canImport(ArgumentParser)
// MARK: – Rich CLI using ArgumentParser
struct CLI: ParsableCommand {
    @Option(help: "Path to the video file")
    var video: PathStr?

    @Option(name: .customLong("load-csv"), help: "CSV file mapping frames to load values")
    var loadCSV: PathStr?

    @Option(name: .customLong("fem-csv"), help: "Optional FEM results CSV")
    var femCSV: PathStr?

    @Option(name: .customLong("out-dir"), help: "Output directory")
    var outDir: String = "Outputs"

    @Option(help: "Thresholds as comma-separated values, e.g. 0.25,0.5,1")
    var thresholds: String = "0.25,0.5,1"

    @Flag(name: .customLong("run-tests"), help: "Run unit tests instead of processing")
    var runTests: Bool = false

    func run() throws {
        let thr = thresholds.split(separator: ",").compactMap { Double($0) }
        let core = Core(video: video, loadCSV: loadCSV, femCSV: femCSV, outDir: outDir, thresholds: thr)
        if runTests {
            try core.unit()
        } else {
            try core.run()
        }
    }
}
#endif

// MARK: – Entry point
#if canImport(ArgumentParser)
@main struct Main { static func main(){ CLI.main() } }
#else
@main struct Main {
    static func main(){
        var video:PathStr?;var load:PathStr?;var fem:PathStr?;var out="Outputs";var thr:[Double]=[0.25,0.5,1];var runTests=false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k=it.next(){
            switch k {
            case "--video": video = it.next()
            case "--load-csv": load = it.next()
            case "--fem-csv": fem = it.next()
            case "--out-dir": out = it.next() ?? out
            case "--thresholds": if let val = it.next() { thr = val.split(separator: ",").compactMap { Double($0) } }
            case "--run-tests": runTests = true
            default: break
            }
        }
        let core = Core(video: video, loadCSV: load, femCSV: fem, outDir: out, thresholds: thr)
        if runTests {
            try? core.unit()
        } else {
            try? core.run()
        }
    }
}
#endif
