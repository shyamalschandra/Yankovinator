// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class CloudBatchPrescriptionTests: XCTestCase {

    func testCloudAndHeavyDetection() {
        XCTAssertTrue(CloudBatchPrescription.isCloudModel("gemma4:31b-cloud"))
        XCTAssertTrue(CloudBatchPrescription.isCloudModel("qwen3.5:397b-cloud"))
        XCTAssertFalse(CloudBatchPrescription.isCloudModel("llama3.2:3b"))

        XCTAssertTrue(CloudBatchPrescription.isHeavyCloudModel("qwen3.5:397b-cloud"))
        XCTAssertFalse(CloudBatchPrescription.isHeavyCloudModel("gemma4:31b-cloud"))
        XCTAssertFalse(CloudBatchPrescription.isHeavyCloudModel("llama3.2:3b"))
        XCTAssertFalse(CloudBatchPrescription.isHeavyCloudModel("gemma2:2b"))
    }

    func testPlanCapsWorkersForAnyCloudModel() {
        let gemma = CloudBatchPrescription.plan(
            model: "gemma4:31b-cloud",
            requestedWorkers: 10,
            ollamaTimeout: nil,
            enabled: true
        )
        XCTAssertEqual(gemma.effectiveWorkers, CloudBatchPrescription.cloudMaxConsumers)
        XCTAssertTrue(gemma.appliedWorkerCap)
        XCTAssertTrue(gemma.skipLLMCoherenceInBatch)
        XCTAssertNil(gemma.appliedTimeoutSeconds) // non-heavy keeps caller/default timeout path

        let heavy = CloudBatchPrescription.plan(
            model: "qwen3.5:397b-cloud",
            requestedWorkers: 100,
            ollamaTimeout: nil,
            enabled: true
        )
        XCTAssertEqual(heavy.effectiveWorkers, CloudBatchPrescription.heavyCloudMaxConsumers)
        XCTAssertTrue(heavy.appliedWorkerCap)
        XCTAssertEqual(heavy.appliedTimeoutSeconds, 600)
        XCTAssertTrue(heavy.skipLLMCoherenceInBatch)
    }

    func testPlanDisabledLeavesWorkers() {
        let plan = CloudBatchPrescription.plan(
            model: "gemma4:31b-cloud",
            requestedWorkers: 10,
            ollamaTimeout: nil,
            enabled: false
        )
        XCTAssertEqual(plan.effectiveWorkers, 10)
        XCTAssertFalse(plan.appliedWorkerCap)
    }

    func testConsumerPoolSizeWithCloudModels() {
        XCTAssertEqual(
            ParallelJobRunner.consumerPoolSize(requestedWorkers: 10, model: "gemma4:31b-cloud"),
            CloudBatchPrescription.cloudMaxConsumers
        )
        XCTAssertEqual(
            ParallelJobRunner.consumerPoolSize(requestedWorkers: 100, model: "qwen3.5:397b-cloud"),
            CloudBatchPrescription.heavyCloudMaxConsumers
        )
        XCTAssertEqual(
            ParallelJobRunner.consumerPoolSize(
                requestedWorkers: 10,
                model: "gemma4:31b-cloud",
                applyCloudPrescription: false
            ),
            10
        )
        XCTAssertEqual(
            ParallelJobRunner.consumerPoolSize(requestedWorkers: 80, consumerOverride: 48),
            48
        )
        // Local models stay uncapped by cloud prescription
        XCTAssertEqual(
            ParallelJobRunner.consumerPoolSize(requestedWorkers: 10, model: "llama3.2:3b"),
            10
        )
    }
}
