//
//  GraphicsRendererResolverTests.swift
//  GVEngineTests
//

import XCTest
@testable import GVEngine

final class GraphicsRendererResolverTests: XCTestCase {
    private let everything = GraphicsRendererAvailability(d3dMetal: true, dxmt: true, dxvk: true)

    func testDX12SelectsD3DMetal() {
        let renderer = GraphicsRendererResolver.resolve(
            requirements: GraphicsRequirements(directX: .direct3D12, has64BitRendererConsumer: true),
            availability: everything
        )
        XCTAssertEqual(renderer, .d3dMetal)
    }

    func testDX11SelectsD3DMetalFor64BitGame() {
        let renderer = GraphicsRendererResolver.resolve(
            requirements: GraphicsRequirements(directX: .direct3D11, has64BitRendererConsumer: true),
            availability: everything
        )
        XCTAssertEqual(renderer, .d3dMetal)
    }

    func testDX11FallsBackFromD3DMetalToDXMTThenDXVK() {
        let requirements = GraphicsRequirements(
            directX: .direct3D11, has64BitRendererConsumer: true
        )
        XCTAssertEqual(
            GraphicsRendererResolver.resolve(
                requirements: requirements,
                availability: GraphicsRendererAvailability(d3dMetal: false, dxmt: true, dxvk: true)
            ),
            .dxmt
        )
        XCTAssertEqual(
            GraphicsRendererResolver.resolve(
                requirements: requirements,
                availability: GraphicsRendererAvailability(d3dMetal: false, dxmt: false, dxvk: true)
            ),
            .dxvk
        )
    }

    func testDX12DoesNotSelectAnIncompatibleDX11Backend() {
        let renderer = GraphicsRendererResolver.resolve(
            requirements: GraphicsRequirements(directX: .direct3D12, has64BitRendererConsumer: true),
            availability: GraphicsRendererAvailability(d3dMetal: false, dxmt: true, dxvk: true)
        )
        XCTAssertEqual(renderer, .wineD3D)
    }

    func test32BitDX11SkipsD3DMetal() {
        let renderer = GraphicsRendererResolver.resolve(
            requirements: GraphicsRequirements(directX: .direct3D11, has64BitRendererConsumer: false),
            availability: everything
        )
        XCTAssertEqual(renderer, .dxmt)
    }

    func testDX9UsesWineD3DOnMacOS() {
        let renderer = GraphicsRendererResolver.resolve(
            requirements: GraphicsRequirements(directX: .direct3D9, has64BitRendererConsumer: true),
            availability: everything
        )
        XCTAssertEqual(renderer, .wineD3D)
    }

    func testManualRendererIsNeverReplacedByAutoPolicy() {
        let renderer = GraphicsRendererResolver.resolve(
            requested: .dxvk,
            inspecting: URL(fileURLWithPath: "/does/not/exist"),
            availability: everything
        )
        XCTAssertEqual(renderer, .dxvk)
    }

    func testInspectionDetectsDirectXNameCaseInsensitively() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "Game.exe")
        var bytes = Data([0x4d, 0x5a])
        bytes.append(Data(repeating: 0, count: 128))
        bytes.append(Data("D3D12.DLL".utf8))
        try bytes.write(to: executable)

        XCTAssertEqual(GraphicsRendererResolver.inspect(executable).directX, .direct3D12)
    }
}
