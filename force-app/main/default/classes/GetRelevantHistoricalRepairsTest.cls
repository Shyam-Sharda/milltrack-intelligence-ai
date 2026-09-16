@IsTest
private class GetRelevantHistoricalRepairsTest {

    // =========================================================
    // Test Data Helpers
    // =========================================================

    private static Asset createAsset(String assetName, String manufacturer, String model, String serialNumber) {
        Asset assetRecord = new Asset(Name = assetName, Manufacturer__c = manufacturer, Model__c = model, Serial_Number__c = serialNumber);
        insert assetRecord;
        return assetRecord;
    }

    private static Case createCase(String subject, String description, String errorCode) {
        Case caseRecord = new Case(
            Subject = subject,
            Description = description,
            Status = getActivePicklistValue(Schema.SObjectType.Case.fields.Status, 'New'),
            Origin = getActivePicklistValue(Schema.SObjectType.Case.fields.Origin, 'Web'),
            Error_Code__c = errorCode
        );

        insert caseRecord;
        return caseRecord;
    }

    private static WorkOrder createWorkOrder(Id assetId, Id caseId, String subject, String description, String problemSummary) {
        return createWorkOrder(assetId, caseId, subject, description, problemSummary, null);
    }

    private static WorkOrder createWorkOrder(
        Id assetId,
        Id caseId,
        String subject,
        String description,
        String problemSummary,
        String recommendedFixSummary
    ) {
        WorkOrder workOrderRecord = new WorkOrder(
            AssetId = assetId,
            CaseId = caseId,
            Subject = subject,
            Description = description,
            Problem_Summary__c = problemSummary,
            Recommended_Fix_Summary__c = recommendedFixSummary,
            Status = getActivePicklistValue(Schema.SObjectType.WorkOrder.fields.Status, 'New'),
            Dispatch_Status__c = 'Pending'
        );

        insert workOrderRecord;
        return workOrderRecord;
    }

    private static Maintenance_Log__c createMaintenanceLog(
        Id assetId,
        Id workOrderId,
        String maintenanceType,
        Boolean issueResolved,
        Boolean followUpRequired,
        String summary,
        String rootCause,
        String partsUsed,
        String technicianNotes,
        Date maintenanceDate
    ) {
        Maintenance_Log__c logRecord = new Maintenance_Log__c(
            Asset__c = assetId,
            Work_Order__c = workOrderId,
            Maintenance_Date__c = maintenanceDate,
            Maintenance_Type__c = maintenanceType,
            Issue_Resolved__c = issueResolved,
            Follow_Up_Required__c = followUpRequired,
            Summary__c = summary,
            Root_Cause__c = rootCause,
            Parts_Used__c = partsUsed,
            Technician_Notes__c = technicianNotes,
            Labor_Hours__c = 2
        );

        insert logRecord;
        return logRecord;
    }

    private static String getMaintenanceLogName(Id logId) {
        return [SELECT Name FROM Maintenance_Log__c WHERE Id = :logId LIMIT 1].Name;
    }

    /*
     * Use the preferred picklist value when available. Otherwise use
     * the first active value so tests do not depend on unrelated org config.
     */
    private static String getActivePicklistValue(Schema.DescribeFieldResult fieldDescribe, String preferredValue) {
        List<Schema.PicklistEntry> entries = fieldDescribe.getPicklistValues();
        String firstActiveValue;

        for (Schema.PicklistEntry entry : entries) {
            if (!entry.isActive()) continue;
            if (firstActiveValue == null) firstActiveValue = entry.getValue();
            if (entry.getValue() == preferredValue) return entry.getValue();
        }

        return firstActiveValue;
    }


    // =========================================================
    // Primary Historical Intelligence Test
    // =========================================================

    @IsTest
    static void returnsRelevantSuccessfulRepairsAndExcludesBadHistory() {

        Asset currentAsset = createAsset('Current DWX-52D', 'Roland', 'DWX-52D', 'CURRENT-52D-001');

        Case currentCase = createCase(
            'Spindle grinding noise',
            'Customer reports a loud grinding noise from the spindle during milling.',
            'E100'
        );

        WorkOrder currentWorkOrder = createWorkOrder(
            currentAsset.Id,
            currentCase.Id,
            'Investigate spindle grinding noise',
            'Machine produces grinding noise during operation.',
            'Abnormal spindle grinding noise during milling.'
        );

        // Relevant exact-model / exact-error precedent.
        Asset exactModelAsset = createAsset('Historical DWX-52D', 'Roland', 'DWX-52D', 'HIST-52D-001');

        Case exactMatchCase = createCase(
            'Spindle grinding during milling',
            'Spindle produced abnormal grinding noise.',
            'E100'
        );

        WorkOrder exactMatchWorkOrder = createWorkOrder(
            exactModelAsset.Id,
            exactMatchCase.Id,
            'Repair spindle grinding issue',
            'Technician investigated grinding noise.',
            'Spindle grinding and vibration during milling.'
        );

        Maintenance_Log__c exactMatchLog = createMaintenanceLog(
            exactModelAsset.Id,
            exactMatchWorkOrder.Id,
            'Repair',
            true,
            false,
            'Replaced worn spindle bearing assembly after confirming grinding noise.',
            'Spindle bearing wear caused abnormal grinding and vibration.',
            'Spindle bearing assembly',
            'Machine tested after repair and spindle noise was no longer present.',
            Date.today().addDays(-30)
        );

        // Relevant same-manufacturer precedent.
        Asset relatedAsset = createAsset('Historical Roland 53DC', 'Roland', '53DC', 'HIST-53DC-001');

        WorkOrder relatedWorkOrder = createWorkOrder(
            relatedAsset.Id,
            null,
            'Repair spindle vibration',
            'Machine had spindle vibration and unusual noise.',
            'Spindle vibration and abnormal noise.'
        );

        Maintenance_Log__c relatedLog = createMaintenanceLog(
            relatedAsset.Id,
            relatedWorkOrder.Id,
            'Repair',
            true,
            false,
            'Cleaned spindle taper and replaced worn collet.',
            'Contamination around spindle taper and worn collet.',
            'Collet',
            'Spindle vibration and noise resolved after cleaning and collet replacement.',
            Date.today().addDays(-60)
        );

        // Successful but unrelated repair.
        WorkOrder unrelatedWorkOrder = createWorkOrder(
            exactModelAsset.Id,
            null,
            'Repair coolant leak',
            'Coolant was leaking from a damaged hose.',
            'Coolant leak near pump and hose.'
        );

        Maintenance_Log__c unrelatedLog = createMaintenanceLog(
            exactModelAsset.Id,
            unrelatedWorkOrder.Id,
            'Repair',
            true,
            false,
            'Replaced coolant hose and cleaned coolant tank.',
            'Damaged coolant hose and contaminated coolant tank.',
            'Coolant hose',
            'Coolant system tested successfully after hose replacement.',
            Date.today().addDays(-15)
        );

        // Temporary / unresolved repair.
        WorkOrder temporaryWorkOrder = createWorkOrder(
            exactModelAsset.Id,
            null,
            'Temporary spindle fix',
            'Grinding spindle noise still present.',
            'Spindle grinding noise.'
        );

        Maintenance_Log__c temporaryLog = createMaintenanceLog(
            exactModelAsset.Id,
            temporaryWorkOrder.Id,
            'Temporary Repair',
            false,
            true,
            'Temporary adjustment reduced spindle grinding noise.',
            'Spindle still requires additional repair.',
            null,
            'Temporary measure only. Follow-up repair required.',
            Date.today().addDays(-5)
        );

        // Maintenance Log belonging to current Work Order must be excluded.
        Maintenance_Log__c currentWorkOrderLog = createMaintenanceLog(
            currentAsset.Id,
            currentWorkOrder.Id,
            'Repair',
            true,
            false,
            'Current spindle grinding repair record.',
            'Current spindle grinding root cause.',
            'Current spindle component',
            'This belongs to the active Work Order and must be excluded.',
            Date.today()
        );

        String exactMatchName = getMaintenanceLogName(exactMatchLog.Id);
        String relatedName = getMaintenanceLogName(relatedLog.Id);
        String unrelatedName = getMaintenanceLogName(unrelatedLog.Id);
        String temporaryName = getMaintenanceLogName(temporaryLog.Id);
        String currentWorkOrderLogName = getMaintenanceLogName(currentWorkOrderLog.Id);

        GetRelevantHistoricalRepairs.Request request = new GetRelevantHistoricalRepairs.Request();
        request.workOrderId = currentWorkOrder.Id;
        request.technicianQuery = 'The spindle is making a grinding noise. Have we successfully repaired something like this before?';
        request.maxResults = 5;

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>{request});
        Test.stopTest();

        System.assertEquals(1, results.size(), 'The invocable action should return one result for one request.');

        GetRelevantHistoricalRepairs.Result result = results[0];

        System.assertEquals(true, result.success, 'Relevant historical repairs should have been found.');
        System.assertEquals('SUCCESS', result.statusCode);
        System.assertEquals(2, result.matchCount, 'Only the two genuinely relevant successful historical repairs should be returned.');
        System.assertNotEquals(null, result.repairs, 'Structured historical repair results should also be populated.');
        System.assertEquals(2, result.repairs.size(), 'Structured results should match the historical repair count.');
        System.assertNotEquals(null, result.historicalRepairContext);

        System.assert(
            result.historicalRepairContext.contains(exactMatchName),
            'The exact-model/error-code historical repair should be returned.'
        );

        System.assert(
            result.historicalRepairContext.contains(relatedName),
            'The related successful spindle repair should be returned.'
        );

        System.assertEquals(
            false,
            result.historicalRepairContext.contains(unrelatedName),
            'An unrelated repair must not be returned solely because the machine manufacturer/model matches.'
        );

        System.assertEquals(
            false,
            result.historicalRepairContext.contains(temporaryName),
            'Temporary/unresolved repairs must not be presented as successful precedents.'
        );

        System.assertEquals(
            false,
            result.historicalRepairContext.contains(currentWorkOrderLogName),
            'Maintenance Logs from the active Work Order must be excluded.'
        );

        System.assert(
            result.historicalRepairContext.contains('supporting evidence only'),
            'Historical precedent must be explicitly described as supporting evidence rather than a diagnosis.'
        );

        System.assert(
            result.historicalRepairContext.contains('do not prove that the current machine has the same root cause'),
            'The response must explicitly prevent historical repair records from becoming an automatic diagnosis.'
        );
    }


    // =========================================================
    // Unrelated Successful Repair
    // =========================================================

    @IsTest
    static void returnsNoRelevantHistoryForUnrelatedSuccessfulRepair() {

        Asset currentAsset = createAsset('Current Spindle Machine', 'Roland', 'DWX-52D', 'CURRENT-002');

        WorkOrder currentWorkOrder = createWorkOrder(
            currentAsset.Id,
            null,
            'Investigate spindle noise',
            'Spindle is making a grinding sound.',
            'Grinding spindle noise.'
        );

        Asset historicalAsset = createAsset('Historical Coolant Machine', 'Roland', 'DWX-52D', 'HIST-002');

        WorkOrder historicalWorkOrder = createWorkOrder(
            historicalAsset.Id,
            null,
            'Repair coolant pump',
            'Coolant flow stopped.',
            'Coolant pump flow failure.'
        );

        createMaintenanceLog(
            historicalAsset.Id,
            historicalWorkOrder.Id,
            'Repair',
            true,
            false,
            'Replaced coolant pump and hose.',
            'Coolant pump motor failed.',
            'Coolant pump motor',
            'Coolant flow restored after replacement.',
            Date.today().addDays(-20)
        );

        GetRelevantHistoricalRepairs.Request request = new GetRelevantHistoricalRepairs.Request();
        request.workOrderId = currentWorkOrder.Id;
        request.technicianQuery = 'The spindle has a loud grinding noise.';

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>{request});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals(
            'NO_RELEVANT_HISTORY',
            results[0].statusCode,
            'Successful history may exist without being relevant to the current repair.'
        );
        System.assertEquals(0, results[0].matchCount);
        System.assertEquals('', results[0].historicalRepairContext);
        System.assertEquals(0, results[0].repairs.size());
    }


    // =========================================================
    // Temporary Repair Only
    // =========================================================

    @IsTest
    static void returnsNoSuccessfulHistoryWhenOnlyTemporaryRepairExists() {

        Asset currentAsset = createAsset('Current Machine', 'Roland', 'DWX-52D', 'CURRENT-003');

        WorkOrder currentWorkOrder = createWorkOrder(
            currentAsset.Id,
            null,
            'Spindle noise',
            'Spindle grinding noise.',
            'Grinding spindle noise.'
        );

        Asset historicalAsset = createAsset('Historical Machine', 'Roland', 'DWX-52D', 'HIST-003');

        WorkOrder historicalWorkOrder = createWorkOrder(
            historicalAsset.Id,
            null,
            'Temporary spindle repair',
            'Spindle grinding noise.',
            'Grinding spindle noise.'
        );

        createMaintenanceLog(
            historicalAsset.Id,
            historicalWorkOrder.Id,
            'Temporary Repair',
            false,
            true,
            'Temporary spindle adjustment.',
            'Further spindle repair required.',
            null,
            'Issue remains unresolved.',
            Date.today().addDays(-10)
        );

        GetRelevantHistoricalRepairs.Request request = new GetRelevantHistoricalRepairs.Request();
        request.workOrderId = currentWorkOrder.Id;
        request.technicianQuery = 'Have we fixed this spindle grinding issue before?';

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>{request});
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assertEquals(
            'NO_SUCCESSFUL_HISTORY',
            results[0].statusCode,
            'Temporary and unresolved repair history must not qualify as successful precedent.'
        );
        System.assertEquals(0, results[0].matchCount);
        System.assertEquals(0, results[0].repairs.size());
    }


    // =========================================================
    // Work Order Without Asset
    // =========================================================

    @IsTest
    static void handlesWorkOrderWithoutAsset() {

        WorkOrder workOrderWithoutAsset = createWorkOrder(
            null,
            null,
            'Unlinked Work Order',
            'Test Work Order without Asset.',
            'Machine issue.'
        );

        GetRelevantHistoricalRepairs.Request request = new GetRelevantHistoricalRepairs.Request();
        request.workOrderId = workOrderWithoutAsset.Id;
        request.technicianQuery = 'Have we repaired this before?';

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>{request});
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assertEquals('NO_ASSET_CONTEXT', results[0].statusCode);
        System.assertEquals(0, results[0].matchCount);
        System.assertEquals(0, results[0].repairs.size());
    }


    // =========================================================
    // Missing Work Order ID
    // =========================================================

    @IsTest
    static void handlesMissingWorkOrderId() {

        GetRelevantHistoricalRepairs.Request request = new GetRelevantHistoricalRepairs.Request();
        request.workOrderId = null;
        request.technicianQuery = 'Have we repaired something like this before?';

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>{request});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals('INVALID_REQUEST', results[0].statusCode);
        System.assertEquals(0, results[0].matchCount);
        System.assertEquals(0, results[0].repairs.size());
    }


    // =========================================================
    // Bulk Invocable Safety
    // =========================================================

    @IsTest
    static void handlesMultipleRequests() {

        Asset assetRecord = createAsset('Bulk Test Machine', 'Roland', 'DWX-52D', 'BULK-001');

        WorkOrder workOrderRecord = createWorkOrder(
            assetRecord.Id,
            null,
            'Spindle problem',
            'Spindle noise.',
            'Spindle grinding.'
        );

        GetRelevantHistoricalRepairs.Request validRequest = new GetRelevantHistoricalRepairs.Request();
        validRequest.workOrderId = workOrderRecord.Id;
        validRequest.technicianQuery = 'Spindle grinding noise';

        GetRelevantHistoricalRepairs.Request invalidRequest = new GetRelevantHistoricalRepairs.Request();
        invalidRequest.workOrderId = null;

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(
                new List<GetRelevantHistoricalRepairs.Request>{invalidRequest, validRequest}
            );
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Each invocable request should receive one result.');
        System.assertEquals('INVALID_REQUEST', results[0].statusCode);
        System.assertEquals('NO_SUCCESSFUL_HISTORY', results[1].statusCode);
    }


    // =========================================================
    // Empty Request Collection
    // =========================================================

    @IsTest
    static void handlesEmptyRequestCollection() {

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>());
        Test.stopTest();

        System.assertEquals(0, results.size());
    }


    // =========================================================
    // Technician Home / LWC Structured Results
    // =========================================================

    @IsTest
    static void returnsCompactHistoricalRepairsForLwcAndCapsAtThree() {

        Asset currentAsset = createAsset('Current LWC Machine', 'Roland', 'DWX-52D', 'LWC-CURRENT-001');

        Case currentCase = createCase(
            'Spindle grinding and vibration',
            'Customer reports spindle grinding noise and vibration during milling.',
            'E100'
        );

        WorkOrder currentWorkOrder = createWorkOrder(
            currentAsset.Id,
            currentCase.Id,
            'Investigate spindle grinding vibration',
            'Spindle produces grinding noise and vibration during milling.',
            'Grinding spindle noise and vibration during milling.'
        );

        Case historicalCase1 = createCase(
            'Spindle grinding during milling',
            'Customer reported spindle grinding noise and vibration while milling.',
            'E100'
        );

        Case historicalCase2 = createCase(
            'Spindle vibration and abnormal noise',
            'Customer reported vibration and abnormal spindle noise during operation.',
            null
        );

        Case historicalCase3 = createCase(
            'Grinding noise from spindle',
            'Customer reported a grinding noise from the spindle while milling.',
            null
        );

        Case historicalCase4 = createCase(
            'Spindle vibration during operation',
            'Customer reported spindle vibration during machine operation.',
            null
        );

        WorkOrder historicalWorkOrder1 = createWorkOrder(
            currentAsset.Id,
            historicalCase1.Id,
            'Spindle grinding during milling',
            'Spindle grinding noise and vibration were reported.',
            'Spindle grinding vibration during milling.',
            'Inspect the spindle bearing assembly and verify spindle rotation under load.'
        );

        WorkOrder historicalWorkOrder2 = createWorkOrder(
            currentAsset.Id,
            historicalCase2.Id,
            'Spindle vibration and abnormal noise',
            'Machine produced spindle vibration and grinding noise.',
            'Spindle vibration and grinding noise during operation.',
            'Inspect the spindle taper and collet, then verify spindle condition under load.'
        );

        WorkOrder historicalWorkOrder3 = createWorkOrder(
            currentAsset.Id,
            historicalCase3.Id,
            'Grinding noise from spindle',
            'Grinding spindle noise occurred while milling.',
            'Spindle grinding noise and vibration.',
            'Inspect the spindle assembly and confirm bearing condition before replacing components.'
        );

        WorkOrder historicalWorkOrder4 = createWorkOrder(
            currentAsset.Id,
            historicalCase4.Id,
            'Spindle vibration during operation',
            'Spindle vibration and grinding noise were present.',
            'Spindle grinding vibration and noise.',
            'Verify spindle alignment and inspect the spindle assembly for abnormal movement.'
        );

        createMaintenanceLog(
            currentAsset.Id,
            historicalWorkOrder1.Id,
            'Repair',
            true,
            false,
            'Resolved spindle grinding and vibration after inspecting the bearing assembly.',
            'Spindle bearing wear caused grinding and vibration.',
            'Spindle bearing assembly',
            'Spindle grinding noise and vibration were eliminated after repair.',
            Date.today().addDays(-10)
        );

        createMaintenanceLog(
            currentAsset.Id,
            historicalWorkOrder2.Id,
            'Repair',
            true,
            false,
            'Resolved spindle vibration and grinding noise after servicing the taper and collet.',
            'Spindle taper contamination contributed to vibration and grinding noise.',
            'Collet',
            'Spindle vibration and grinding noise were no longer present.',
            Date.today().addDays(-20)
        );

        createMaintenanceLog(
            currentAsset.Id,
            historicalWorkOrder3.Id,
            'Repair',
            true,
            false,
            'Resolved grinding spindle noise and vibration after spindle inspection.',
            'Spindle assembly wear caused grinding noise and vibration.',
            'Spindle assembly',
            'Machine tested successfully with no spindle grinding or vibration.',
            Date.today().addDays(-30)
        );

        createMaintenanceLog(
            currentAsset.Id,
            historicalWorkOrder4.Id,
            'Repair',
            true,
            false,
            'Resolved spindle vibration and grinding noise after alignment correction.',
            'Spindle alignment contributed to vibration and grinding noise.',
            'Alignment components',
            'Spindle vibration and grinding noise were resolved.',
            Date.today().addDays(-40)
        );

        Test.startTest();
        List<GetRelevantHistoricalRepairs.HistoricalRepairUi> repairs =
            GetRelevantHistoricalRepairs.getHistoricalRepairsForLwc(currentWorkOrder.Id, 10);
        Test.stopTest();

        System.assertEquals(3, repairs.size(), 'Technician Home must never return more than three similar repairs.');

        GetRelevantHistoricalRepairs.HistoricalRepairUi firstRepair = repairs[0];

        System.assertEquals(
            historicalWorkOrder1.Id,
            firstRepair.workOrderId,
            'The highest-ranked recent relevant repair should be returned first.'
        );

        System.assertEquals('Spindle grinding during milling', firstRepair.subject);

        System.assertEquals(
            'Spindle grinding during milling',
            firstRepair.caseSubject,
            'The Technician Home repair DTO should expose the historical Case Subject.'
        );

        System.assertEquals(
            'Inspect the spindle bearing assembly and verify spindle rotation under load.',
            firstRepair.recommendedFixSummary
        );

        System.assertNotEquals(null, firstRepair.matchedKeywords, 'Matched problem keywords should be supplied to the homepage.');
        System.assert(firstRepair.matchedKeywords.contains('spindle'), 'Matched keywords should include spindle.');
        System.assert(firstRepair.matchedKeywords.contains('grinding'), 'Matched keywords should include grinding.');

        for (GetRelevantHistoricalRepairs.HistoricalRepairUi repair : repairs) {
            System.assertNotEquals(null, repair.maintenanceLogId, 'Each UI result should identify its supporting Maintenance Log.');
            System.assertNotEquals(null, repair.workOrderId, 'Each UI result should identify its historical Work Order.');
            System.assertNotEquals(null, repair.subject, 'Each UI result should provide the historical Work Order subject.');
            System.assertNotEquals(null, repair.caseSubject, 'Each LWC repair result should provide the historical Case Subject when the historical Work Order has a Case.');
            System.assertNotEquals(null, repair.recommendedFixSummary, 'Each UI result should provide the recorded Recommended Fix Summary.');
        }
    }


    // =========================================================
    // Technician Home / LWC Missing Work Order
    // =========================================================

    @IsTest
    static void returnsEmptyLwcListWhenWorkOrderIdIsMissing() {

        Test.startTest();
        List<GetRelevantHistoricalRepairs.HistoricalRepairUi> repairs =
            GetRelevantHistoricalRepairs.getHistoricalRepairsForLwc(null, 3);
        Test.stopTest();

        System.assertNotEquals(null, repairs, 'The LWC method should return an empty list rather than null.');
        System.assertEquals(0, repairs.size(), 'No Work Order ID should produce no historical repair cards.');
    }
}