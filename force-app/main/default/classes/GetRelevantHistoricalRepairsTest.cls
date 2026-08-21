@IsTest
private class GetRelevantHistoricalRepairsTest {

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
        WorkOrder workOrderRecord = new WorkOrder(
            AssetId = assetId,
            CaseId = caseId,
            Subject = subject,
            Description = description,
            Problem_Summary__c = problemSummary,
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
     * Use the preferred value when it exists.
     * Otherwise use the first active picklist value so the test does not
     * unnecessarily depend on unrelated standard Salesforce configuration.
     */
    private static String getActivePicklistValue(Schema.DescribeFieldResult fieldDescribe, String preferredValue) {
        List<Schema.PicklistEntry> entries = fieldDescribe.getPicklistValues();

        String firstActiveValue;

        for (Schema.PicklistEntry entry : entries) {

            if (!entry.isActive()) {
                continue;
            }

            if (firstActiveValue == null) {
                firstActiveValue = entry.getValue();
            }

            if (entry.getValue() == preferredValue) {
                return entry.getValue();
            }
        }

        return firstActiveValue;
    }


    /*
     * ------------------------------------------------------------
     * Primary Historical Intelligence Test
     * ------------------------------------------------------------
     */

    @IsTest
    static void returnsRelevantSuccessfulRepairsAndExcludesBadHistory() {

        /*
         * CURRENT REPAIR
         *
         * Roland DWX-52D
         * Current problem = spindle grinding/noise.
         */
        Asset currentAsset = createAsset(
            'Current DWX-52D',
            'Roland',
            'DWX-52D',
            'CURRENT-52D-001'
        );

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


        /*
         * --------------------------------------------------------
         * HISTORICAL REPAIR #1
         *
         * Same manufacturer + exact same model + matching error
         * code + matching spindle/grinding symptom.
         *
         * This SHOULD be returned.
         * --------------------------------------------------------
         */
        Asset exactModelAsset = createAsset(
            'Historical DWX-52D',
            'Roland',
            'DWX-52D',
            'HIST-52D-001'
        );

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


        /*
         * --------------------------------------------------------
         * HISTORICAL REPAIR #2
         *
         * Same manufacturer, different model, but still a genuinely
         * related spindle/noise repair.
         *
         * This SHOULD also be returned, but should normally rank
         * below the exact-model/error-code repair.
         * --------------------------------------------------------
         */
        Asset relatedAsset = createAsset(
            'Historical Roland 53DC',
            'Roland',
            '53DC',
            'HIST-53DC-001'
        );

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


        /*
         * --------------------------------------------------------
         * UNRELATED SUCCESSFUL REPAIR
         *
         * Same manufacturer/model but coolant problem only.
         *
         * This MUST NOT be returned merely because the equipment
         * happens to match.
         * --------------------------------------------------------
         */
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


        /*
         * --------------------------------------------------------
         * TEMPORARY REPAIR
         *
         * Very strong wording match, but it was NOT resolved and
         * requires follow-up.
         *
         * It MUST NOT become a successful precedent.
         * --------------------------------------------------------
         */
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


        /*
         * --------------------------------------------------------
         * CURRENT WORK ORDER LOG
         *
         * This is intentionally made to look extremely relevant.
         *
         * Historical Repair Intelligence MUST NOT use the current
         * Work Order as evidence for itself.
         * --------------------------------------------------------
         */
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


        /*
         * Capture Auto Number names for output assertions.
         */
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
        System.assertNotEquals(null, result.historicalRepairContext);
        System.assert(result.historicalRepairContext.contains(exactMatchName), 'The exact-model/error-code historical repair should be returned.');
        System.assert(result.historicalRepairContext.contains(relatedName), 'The related successful spindle repair should be returned.');
        System.assertEquals(false, result.historicalRepairContext.contains(unrelatedName), 'An unrelated repair must not be returned solely because the machine manufacturer/model matches.');
        System.assertEquals(false, result.historicalRepairContext.contains(temporaryName), 'Temporary/unresolved repairs must not be presented as successful precedents.');
        System.assertEquals(false, result.historicalRepairContext.contains(currentWorkOrderLogName), 'Maintenance Logs from the active Work Order must be excluded.');
        System.assert(
            result.historicalRepairContext.contains('supporting evidence only'),
            'Historical precedent must be explicitly described as supporting evidence rather than a diagnosis.'
        );
        System.assert(
            result.historicalRepairContext.contains('do not prove that the current machine has the same root cause'),
            'The response must explicitly prevent historical repair records from becoming an automatic diagnosis.'
        );
    }


    @IsTest
    static void returnsNoRelevantHistoryForUnrelatedSuccessfulRepair() {

        Asset currentAsset = createAsset(
            'Current Spindle Machine',
            'Roland',
            'DWX-52D',
            'CURRENT-002'
        );

        WorkOrder currentWorkOrder = createWorkOrder(
            currentAsset.Id,
            null,
            'Investigate spindle noise',
            'Spindle is making a grinding sound.',
            'Grinding spindle noise.'
        );


        Asset historicalAsset = createAsset(
            'Historical Coolant Machine',
            'Roland',
            'DWX-52D',
            'HIST-002'
        );

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
        System.assertEquals('NO_RELEVANT_HISTORY', results[0].statusCode, 'Successful history may exist without being relevant to the current repair.');
        System.assertEquals(0, results[0].matchCount);
        System.assertEquals('',  results[0].historicalRepairContext);
    }


    @IsTest
    static void returnsNoSuccessfulHistoryWhenOnlyTemporaryRepairExists() {

        Asset currentAsset = createAsset(
            'Current Machine',
            'Roland',
            'DWX-52D',
            'CURRENT-003'
        );

        WorkOrder currentWorkOrder = createWorkOrder(
            currentAsset.Id,
            null,
            'Spindle noise',
            'Spindle grinding noise.',
            'Grinding spindle noise.'
        );


        Asset historicalAsset = createAsset(
            'Historical Machine',
            'Roland',
            'DWX-52D',
            'HIST-003'
        );

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
        System.assertEquals('NO_SUCCESSFUL_HISTORY', results[0].statusCode, 'Temporary and unresolved repair history must not qualify as successful precedent.');
        System.assertEquals(0, results[0].matchCount);
    }


    /*
     * ------------------------------------------------------------
     * Work Order exists but has no Asset.
     * ------------------------------------------------------------
     */

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
    }


    /*
     * ------------------------------------------------------------
     * Missing Work Order ID.
     * ------------------------------------------------------------
     */

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
    }


    /*
     * ------------------------------------------------------------
     * Bulk invocable safety.
     *
     * The method accepts List<Request>, so make sure multiple
     * independent requests produce corresponding independent
     * results in the correct order.
     * ------------------------------------------------------------
     */

    @IsTest
    static void handlesMultipleRequests() {

        Asset assetRecord = createAsset(
            'Bulk Test Machine',
            'Roland',
            'DWX-52D',
            'BULK-001'
        );

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
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>{invalidRequest, validRequest});
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Each invocable request should receive one result.');
        System.assertEquals('INVALID_REQUEST', results[0].statusCode);
        System.assertEquals('NO_SUCCESSFUL_HISTORY', results[1].statusCode);
    }


    /*
     * ------------------------------------------------------------
     * Empty request collection.
     * ------------------------------------------------------------
     */

    @IsTest
    static void handlesEmptyRequestCollection() {

        Test.startTest();
        List<GetRelevantHistoricalRepairs.Result> results =
            GetRelevantHistoricalRepairs.getRelevantHistoricalRepairs(new List<GetRelevantHistoricalRepairs.Request>());
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}