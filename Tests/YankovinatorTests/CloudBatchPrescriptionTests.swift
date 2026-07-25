// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class CloudBatchPrescriptionTests: XCTestCase {

    func testHeavyCloudModelDetection() {
        XCTAssertTrue(CloudBatchPrescription.isHeavyCloudModel("qwen3.5:397b-cloud"))
        XCTAssertFalse(CloudBatchPrescription.isHeavyCloudModel("llama3.2:3b"))
        XCTAssertFalse(CloudBatchPrescription.isHeavyCloudModel("gemma2:2b"))
    }

    func testPlanCapsWorkersForHeavyCloud() {
        let plan = CloudBatchPrescription.plan(
            model: "qwen3.5:397b-cloud",
            requestedWorkers: 10,
            ollamaTimeout: nil,
            enabled: true
        )
        XCTAssertEqual(plan.effectiveWorkers, 4)
        XCTAssertTrue(plan.appliedWorkerCap)
        XCTAssertEqual(plan.appliedTimeoutSeconds, 600)
        XCTAssertTrue(plan.skipLLMCoherenceInBatch)
    }

    func testPlanDisabledLeavesWorkers() {
        let plan = CloudBatchPrescription.plan(
            model: "qwen3.5:397b-cloud",
            requestedWorkers: 10,
            ollamaTimeout: nil,
            enabled: false
        )
        XCTAssertEqual(plan.effectiveWorkers, 10)
        XCTAssertFalse(plan.appliedWorkerCap)
    }

    func testConsumerPoolSizeWithModel() {
        XCTAssertEqual(
            ParallelJobRunner.consumerPoolSize(requestedWorkers: 10, model: "qwen3.5:397b-cloud"),
            4
        )
        XCTAssertEqual(
            ParallelJobRunner.consumerPoolSize(
                requestedWorkers: 10,
                model: "qwen3.5:397b-cloud",
                applyCloudPrescription: false
            ),
            10
        )
    }
}
