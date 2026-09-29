@IsTest
private class GetRelevantHistoricalRepairsForCaseTest {
    /*
     * ============================================================
     * TEST DATA HELPERS
     * ============================================================
     */
    private static Account createAccount(String name) {
        Account accountRecord = new Account(Name = name);
        insert accountRecord;
        return accountRecord;
    }
    private static Asset createAsset(Account accountRecord, String name, String manufacturer, String model, String serialNumber) {
        Asset assetRecord = new Asset(
            Name = name,
            AccountId = accountRecord.Id,
            Manufacturer__c = manufacturer,
            Model__c = model,
            Serial_Number__c = serialNumber,
            Machine_Status__c = 'Active'
        );
        insert assetRecord;
        return assetRecord;
    }
    private static Case createCase(
        Account accountRecord,
        Asset assetRecord,
        String subject,
        String description,
        String errorCode
    ) {
        Case caseRecord = new Case(
            AccountId = accountRecord.Id,
            AssetId = assetRecord == null ? null : assetRecord.Id,
            Subject = subject,
            Description = description,
            Status = 'New',
            Origin = 'Web',
            Priority = 'Medium',
            Error_Code__c = errorCode
        );
        insert caseRecord;
        return caseRecord;
    }
    private static WorkOrder createWorkOrder(Account accountRecord, Asset assetRecord, Case caseRecord, String subject) {
        WorkOrder workOrderRecord = new WorkOrder(
            AccountId = accountRecord.Id,
            AssetId = assetRecord.Id,
            CaseId = caseRecord.Id,
            Subject = subject,
            Description = subject,
            Status = 'New',
            Priority = 'Medium'
        );
        insert workOrderRecord;
        return workOrderRecord;
    }
    private static Maintenance_Log__c createMaintenanceLog(
        Asset assetRecord,
        WorkOrder workOrderRecord,
        Date maintenanceDate,
        String maintenanceType,
        String summary,
        String rootCause,
        String partsUsed,
        String technicianNotes,
        Boolean resolved,
        Boolean followUpRequired
    ) {
        Maintenance_Log__c logRecord = new Maintenance_Log__c(
            Asset__c = assetRecord.Id,
            Work_Order__c = workOrderRecord == null ? null : workOrderRecord.Id,
            Maintenance_Date__c = maintenanceDate,
            Maintenance_Type__c = maintenanceType,
            Summary__c = summary,
            Root_Cause__c = rootCause,
            Parts_Used__c = partsUsed,
            Technician_Notes__c = technicianNotes,
            Labor_Hours__c = 2,
            Issue_Resolved__c = resolved,
            Follow_Up_Required__c = followUpRequired
        );
        insert logRecord;
        return logRecord;
    }
    private static GetRelevantHistoricalRepairsForCase.Result runAction(Id caseId, Integer maxResults) {
        GetRelevantHistoricalRepairsForCase.Request request = new GetRelevantHistoricalRepairsForCase.Request();
        request.caseId = caseId;
        request.maxResults = maxResults;
        Test.startTest();
        List<GetRelevantHistoricalRepairsForCase.Result> results =
            GetRelevantHistoricalRepairsForCase.getRelevantHistoricalRepairsForCase(new List<GetRelevantHistoricalRepairsForCase.Request>{request});
        Test.stopTest();
        System.assertEquals(1, results.size(), 'The action should return one result for one request.');
        return results[0];
    }
    /*
     * ============================================================
     * TEST 1
     *
     * Positive same-machine / same-error-code historical match.
     * ============================================================
     */
    @IsTest
    static void testRelevantHistoricalRepairFound() {
        Account accountRecord = createAccount('Historical Repair Test Account');
        Asset assetRecord = createAsset(
            accountRecord,
            'Straumann M Series Test Mill',
            'Straumann',
            'M Series',
            'STR-TEST-001'
        );
        /*
         * Historical Case / Work Order / Maintenance Log.
         */
        Case historicalCase = createCase(
            accountRecord,
            assetRecord,
            'Coolant not flowing to milling chamber',
            'Coolant is present but is not reaching the milling chamber.',
            'COOL-101'
        );
        WorkOrder historicalWorkOrder = createWorkOrder(
                accountRecord,
                assetRecord,
                historicalCase,
                'Repair coolant flow problem'
            );
        createMaintenanceLog(
            assetRecord,
            historicalWorkOrder,
            Date.today().addDays(-60),
            'Repair',
            'Restored coolant flow after servicing coolant lines and pump.',
            'Coolant tank was extremely dirty.',
            'Coolant Pump Motor; Coolant Hose Lines',
            'Coolant flow was restored and machine operation was tested.',
            true,
            false
        );
        /*
         * Current Case being evaluated.
         */
        Case currentCase = createCase(
            accountRecord,
            assetRecord,
            'Coolant not flowing',
            'Coolant is not reaching the milling chamber.',
            'COOL-101'
        );
        GetRelevantHistoricalRepairsForCase.Result result =  runAction(currentCase.Id, 3);
        System.assertEquals(true, result.success, 'A relevant successful repair should be returned.');
        System.assertEquals('SUCCESS', result.statusCode);
        System.assertEquals(1, result.matchCount);
        System.assert(
            result.historicalRepairContext.contains('HISTORICAL REPAIR INTELLIGENCE'),
            'Historical context header should be returned.'
        );
        System.assert(
            result.historicalRepairContext.contains('Same current Asset: Yes'),
            'The historical repair should be identified as belonging to the same Asset.'
        );
        System.assert(
            result.historicalRepairContext.contains('same error code'),
            'The exact matching historical error code should be identified.'
        );
        System.assert(
            result.historicalRepairContext.contains('Coolant tank was extremely dirty'),
            'The recorded historical root cause should be returned.'
        );
        System.assert(
            result.historicalRepairContext.contains('Coolant Pump Motor'),
            'Historical parts used should be returned as evidence.'
        );
        System.assert(
            result.historicalRepairContext.contains('Coolant flow was restored'),
            'Historical technician notes should be available to the Manager.'
        );
    }
    /*
     * ============================================================
     * TEST 2
     *
     * Successful repair exists for the manufacturer, but the
     * problem itself is unrelated.
     *
     * The class must not force a historical precedent.
     * ============================================================
     */
    @IsTest
    static void testNoRelevantHistoricalRepair() {
        Account accountRecord = createAccount('No Match Test Account');
        Asset assetRecord = createAsset(
            accountRecord,
            'Roland DWX Test Mill',
            'Roland',
            'DWX-52D',
            'ROL-TEST-001'
        );
        Case historicalCase = createCase(
            accountRecord,
            assetRecord,
            'Coolant leak',
            'Coolant pump area leaking fluid.',
            null
        );
        WorkOrder historicalWorkOrder = createWorkOrder(accountRecord, assetRecord, historicalCase, 'Repair coolant leak');
        createMaintenanceLog(
            assetRecord,
            historicalWorkOrder,
            Date.today().addDays(-90),
            'Repair',
            'Repaired coolant leak.',
            'Damaged coolant connection.',
            'Coolant Hose',
            'Leak eliminated after repair.',
            true,
            false
        );
        Case currentCase = createCase(
            accountRecord,
            assetRecord,
            'Spindle noise during startup',
            'Grinding noise occurs when spindle starts rotating.',
            null
        );
        GetRelevantHistoricalRepairsForCase.Result result = runAction(currentCase.Id, 3);
        System.assertEquals(false, result.success);
        System.assertEquals(
            'NO_RELEVANT_HISTORY',
            result.statusCode,
            'Unrelated successful history must not be presented as a repair precedent.'
        );
        System.assertEquals(0, result.matchCount);
        System.assertEquals('', result.historicalRepairContext);
    }
    /*
     * ============================================================
     * TEST 3
     *
     * Temporary repair / unresolved service must never count as
     * successful historical repair intelligence.
     * ============================================================
     */
    @IsTest
    static void testTemporaryRepairExcluded() {
        Account accountRecord = createAccount('Temporary Repair Test');
        Asset assetRecord = createAsset(
            accountRecord,
            'Straumann Temporary Test Mill',
            'Straumann',
            'M Series',
            'STR-TEMP-001'
        );
        Case historicalCase = createCase(
            accountRecord,
            assetRecord,
            'Coolant flow failure',
            'Coolant is not reaching the chamber.',
            'COOL-500'
        );
        WorkOrder historicalWorkOrder = createWorkOrder(accountRecord, assetRecord, historicalCase, 'Temporary coolant repair');
        createMaintenanceLog(
            assetRecord,
            historicalWorkOrder,
            Date.today().addDays(-20),
            'Temporary Repair',
            'Temporary coolant flow restored.',
            'Cause not confirmed.',
            null,
            'Temporary solution only.',
            false,
            true
        );
        Case currentCase = createCase(
            accountRecord,
            assetRecord,
            'Coolant flow failure',
            'Coolant is not reaching the chamber.',
            'COOL-500'
        );
        GetRelevantHistoricalRepairsForCase.Result result =  runAction(currentCase.Id, 3);
        System.assertEquals(false, result.success);
        System.assertEquals(
            'NO_SUCCESSFUL_HISTORY',
            result.statusCode,
            'Temporary and unresolved repairs must be excluded from successful precedent retrieval.'
        );
        System.assertEquals(0, result.matchCount);
    }
    /*
     * ============================================================
     * TEST 4
     *
     * Historical Repair Intelligence requires the current Case
     * to contain an Asset.
     * ============================================================
     */
    @IsTest
    static void testMissingAsset() {
        Account accountRecord = createAccount('Missing Asset Test');
        Case currentCase = createCase(
            accountRecord,
            null,
            'Machine making unusual noise',
            'Customer reports abnormal noise.',
            null
        );
        GetRelevantHistoricalRepairsForCase.Result result = runAction(currentCase.Id, 3);
        System.assertEquals(false, result.success);
        System.assertEquals('NO_ASSET_CONTEXT', result.statusCode);
        System.assertEquals(0, result.matchCount);
    }
    /*
     * ============================================================
     * TEST 5
     *
     * A Maintenance Log associated with the CURRENT Case must
     * never be treated as historical evidence for that same Case.
     *
     * This protects the Flow if it is ever rerun after a Work
     * Order already exists.
     * ============================================================
     */
    @IsTest
    static void testCurrentCaseHistoryExcluded() {
        Account accountRecord = createAccount('Current Case Exclusion Test');
        Asset assetRecord = createAsset(
            accountRecord,
            'Ceramill Current Case Test',
            'Ceramill',
            'Motion 2',
            'CER-TEST-001'
        );
        Case currentCase = createCase(
            accountRecord,
            assetRecord,
            'Spindle vibration during milling',
            'Machine has strong spindle vibration during milling.',
            'VIB-100'
        );
        WorkOrder currentCaseWorkOrder = createWorkOrder(
                accountRecord,
                assetRecord,
                currentCase,
                'Spindle vibration repair'
            );
        createMaintenanceLog(
            assetRecord,
            currentCaseWorkOrder,
            Date.today(),
            'Repair',
            'Resolved spindle vibration.',
            'Spindle assembly required repair.',
            null,
            'Machine tested after repair.',
            true,
            false
        );
        GetRelevantHistoricalRepairsForCase.Result result = runAction(currentCase.Id, 3);
        System.assertEquals(false, result.success);
        System.assertEquals(
            'NO_RELEVANT_HISTORY',
            result.statusCode,
            'A repair associated with the current Case must not become historical evidence for itself.'
        );
        System.assertEquals(0, result.matchCount);
    }
    /*
     * ============================================================
     * TEST 6
     *
     * Relevant repair from a DIFFERENT Asset of the same model.
     *
     * It may be a useful precedent, but it must explicitly be
     * identified as NOT being a previous repair of the current
     * Asset.
     * ============================================================
     */
    @IsTest
    static void testDifferentAssetSameModelPrecedent() {
        Account accountRecord = createAccount('Same Model Different Asset Test');
        Asset historicalAsset = createAsset(
            accountRecord,
            'Historical Straumann Mill',
            'Straumann',
            'M Series',
            'STR-HIST-001'
        );
        Asset currentAsset = createAsset(
            accountRecord,
            'Current Straumann Mill',
            'Straumann',
            'M Series',
            'STR-CURRENT-001'
        );
        Case historicalCase = createCase(
            accountRecord,
            historicalAsset,
            'Coolant not reaching chamber',
            'Coolant flow stopped during milling.',
            'COOL-700'
        );
        WorkOrder historicalWorkOrder = createWorkOrder(accountRecord, historicalAsset, historicalCase, 'Coolant delivery repair');
        createMaintenanceLog(
            historicalAsset,
            historicalWorkOrder,
            Date.today().addDays(-45),
            'Repair',
            'Restored coolant delivery to chamber.',
            'Coolant tank contamination.',
            'Coolant Pump Motor',
            'Coolant operation verified after repair.',
            true,
            false
        );
        Case currentCase = createCase(
            accountRecord,
            currentAsset,
            'Coolant not reaching chamber',
            'Coolant flow stopped during milling.',
            'COOL-700'
        );
        GetRelevantHistoricalRepairsForCase.Result result = runAction(currentCase.Id, 3);
        System.assertEquals(true, result.success);
        System.assertEquals('SUCCESS', result.statusCode);
        System.assertEquals(1, result.matchCount);
        System.assert(
            result.historicalRepairContext.contains('Same current Asset: No'),
            'A repair from another machine must not be represented as a previous failure of the current Asset.'
        );
        System.assert(
            result.historicalRepairContext.contains('same model'),
            'The output should explain that the precedent is relevant because it is the same model.'
        );
    }
    /*
     * ============================================================
     * TEST 7
     *
     * Equivalent Roland model aliases must be treated as the same
     * physical model for cross-Asset precedent retrieval.
     *
     * Example:
     *   DWX-53DC <-> 53DC
     * ============================================================
     */
    @IsTest
    static void testEquivalentRolandModelAliasAccepted() {
        Account accountRecord = createAccount('Roland Model Alias Test');
        Asset historicalAsset = createAsset(
            accountRecord,
            'Historical Roland 53DC',
            'Roland',
            'DWX-53DC',
            'ROL-53DC-HIST'
        );
        Asset currentAsset = createAsset(
            accountRecord,
            'Current Roland 53DC',
            'Roland',
            '53DC',
            'ROL-53DC-CURRENT'
        );
        Case historicalCase = createCase(
            accountRecord,
            historicalAsset,
            'Disc changer binding during Run-in',
            'Disc changer binds near the bottom of travel and reports a collision.',
            null
        );
        WorkOrder historicalWorkOrder = createWorkOrder(
                accountRecord,
                historicalAsset,
                historicalCase,
                'Repair disc changer binding'
            );
        createMaintenanceLog(
            historicalAsset,
            historicalWorkOrder,
            Date.today().addDays(-30),
            'Repair',
            'Corrected disc changer alignment and restored normal travel.',
            'Disc changer mechanism was misaligned.',
            null,
            'Verified smooth changer movement after alignment.',
            true,
            false
        );
        Case currentCase = createCase(
            accountRecord,
            currentAsset,
            'Disc changer binding during Run-in',
            'Disc changer binds near the bottom of travel and reports a collision.',
            null
        );
        GetRelevantHistoricalRepairsForCase.Result result = runAction(currentCase.Id, 3);
        System.assertEquals(
            true,
            result.success,
            'Equivalent Roland model aliases should allow a relevant cross-Asset precedent.'
        );
        System.assertEquals('SUCCESS', result.statusCode);
        System.assertEquals(1, result.matchCount);
        System.assert(
            result.historicalRepairContext.contains('Same current Asset: No'),
            'The repair is from a different Asset and must not be represented as a previous failure of the current Asset.'
        );
        System.assert(
            result.historicalRepairContext.contains('same model'),
            'DWX-53DC and 53DC should be treated as the same normalized model.'
        );
        System.assert(
            result.historicalRepairContext.contains('Disc changer mechanism was misaligned'),
            'The matching historical repair evidence should be returned.'
        );
    }
    /*
     * ============================================================
     * TEST 8
     *
     * Same manufacturer plus strong keyword overlap is NOT enough
     * when the historical repair belongs to a different model.
     *
     * This prevents a DWX-52D correction-jig repair from becoming
     * precedent for a DWX-53DC disc-changer problem solely because
     * words such as binding, chamber, cleaning, and collision overlap.
     * ============================================================
     */
    @IsTest
    static void testDifferentModelSameManufacturerExcluded() {
        Account accountRecord = createAccount('Cross Model Exclusion Test');
        Asset historicalAsset = createAsset(
            accountRecord,
            'Historical Roland 52D',
            'Roland',
            'DWX-52D',
            'ROL-52D-HIST'
        );
        Asset currentAsset = createAsset(
            accountRecord,
            'Current Roland 53DC',
            'Roland',
            'DWX-53DC',
            'ROL-53DC-CURRENT'
        );
        Case historicalCase = createCase(
            accountRecord,
            historicalAsset,
            'Collision and binding during correction',
            'Machine binds in the chamber and reports a collision after cleaning.',
            null
        );
        WorkOrder historicalWorkOrder = createWorkOrder(
                accountRecord,
                historicalAsset,
                historicalCase,
                'Repair correction collision'
            );
        createMaintenanceLog(
            historicalAsset,
            historicalWorkOrder,
            Date.today().addDays(-20),
            'Repair',
            'Corrected binding and collision condition in the chamber.',
            'Correction jig was worn and misaligned.',
            'Correction Jig',
            'Cleaned chamber and corrected binding during machine movement.',
            true,
            false
        );
        Case currentCase = createCase(
            accountRecord,
            currentAsset,
            'Disc changer binding and collision',
            'Disc changer binds in the chamber and reports a collision after cleaning.',
            null
        );
        GetRelevantHistoricalRepairsForCase.Result result = runAction(currentCase.Id, 3);
        System.assertEquals(
            false,
            result.success,
            'A different model must not qualify solely from manufacturer and overlapping problem terms.'
        );
        System.assertEquals(
            'NO_RELEVANT_HISTORY',
            result.statusCode,
            'Cross-model Roland history should be excluded before lexical similarity can qualify it.'
        );
        System.assertEquals(0, result.matchCount);
        System.assertEquals('', result.historicalRepairContext);
    }
    /*
     * ============================================================
     * TEST 9
     *
     * Maximum result limit.
     *
     * The production class permits no more than 5 records even
     * when a larger value is requested.
     * ============================================================
     */
    @IsTest
    static void testMaximumResultsLimitedToFive() {
        Account accountRecord = createAccount('Maximum Result Test');
        Asset assetRecord = createAsset(
            accountRecord,
            'Roland Maximum Test Mill',
            'Roland',
            'DWX-52D',
            'ROL-MAX-001'
        );
        Case historicalCase = createCase(
            accountRecord,
            assetRecord,
            'Air pressure problem during milling',
            'Machine reports low air pressure while milling.',
            'AIR-100'
        );
        WorkOrder historicalWorkOrder = createWorkOrder(accountRecord, assetRecord, historicalCase, 'Air pressure repair');
        for (Integer i = 0; i < 6; i++) {
            createMaintenanceLog(
                assetRecord,
                historicalWorkOrder,
                Date.today().addDays(-(30 + i)),
                'Repair',
                'Resolved air pressure problem during milling.',
                'Air supply condition required correction.',
                null,
                'Air pressure verified after repair.',
                true,
                false
            );
        }
        Case currentCase = createCase(
            accountRecord,
            assetRecord,
            'Air pressure problem during milling',
            'Machine reports low air pressure while milling.',
            'AIR-100'
        );
        GetRelevantHistoricalRepairsForCase.Result result = runAction(currentCase.Id, 10);
        System.assertEquals(true, result.success);
        System.assertEquals('SUCCESS', result.statusCode);
        System.assertEquals(5, result.matchCount, 'The Apex action must never return more than five historical precedents.');
        System.assert(!result.historicalRepairContext.contains('6. '), 'A sixth historical repair must not appear in the returned context.');
    }
    /*
     * ============================================================
     * TEST 10
     *
     * Invalid request.
     * ============================================================
     */
    @IsTest
    static void testMissingCaseId() {
        GetRelevantHistoricalRepairsForCase.Request request = new GetRelevantHistoricalRepairsForCase.Request();
        request.caseId = null;
        request.maxResults = 3;
        Test.startTest();
        List<GetRelevantHistoricalRepairsForCase.Result> results = GetRelevantHistoricalRepairsForCase.getRelevantHistoricalRepairsForCase(
                    new List<GetRelevantHistoricalRepairsForCase.Request>{request});
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals('INVALID_REQUEST', results[0].statusCode);
        System.assertEquals(0,  results[0].matchCount);
    }
        /*
     * ============================================================
     * LWC ENDPOINT TESTS
     * ============================================================
     */
    @IsTest
    static void testLwcEndpointReturnsRelevantHistory() {
        Account accountRecord = createAccount('HRI LWC Endpoint Test');
        Asset assetRecord = createAsset(
            accountRecord,
            'LWC Historical Test Mill',
            'Roland',
            'DWX-53DC',
            'LWC-HRI-001'
        );
        Case historicalCase = createCase(
            accountRecord,
            assetRecord,
            'Disc changer binding during Run-in',
            'Disc changer binds near the bottom of travel during Run-in.',
            'COLLISION-200'
        );
        WorkOrder historicalWorkOrder = createWorkOrder(accountRecord, assetRecord, historicalCase, 'Repair disc changer binding');
        createMaintenanceLog(
            assetRecord,
            historicalWorkOrder,
            Date.today().addDays(-45),
            'Repair',
            'Corrected disc changer alignment and restored normal travel.',
            'Disc changer mechanism was misaligned.',
            'Disc Changer Alignment Component',
            'Verified smooth movement and completed Run-in successfully.',
            true,
            false
        );
        Case currentCase = createCase(
            accountRecord,
            assetRecord,
            'Disc changer binding during Run-in',
            'Disc changer binds near the bottom of travel during Run-in.',
            'COLLISION-200'
        );
        Test.startTest();
        GetRelevantHistoricalRepairsForCase.Result result = GetRelevantHistoricalRepairsForCase.getHistoricalRepairsForLwc(currentCase.Id, 3);
        Test.stopTest();
        System.assertEquals(true, result.success);
        System.assertEquals('SUCCESS', result.statusCode);
        System.assertEquals(1, result.matchCount);
        System.assertNotEquals('', result.historicalRepairContext);
        System.assert(
            result.historicalRepairContext.contains('Same current Asset: Yes'),
            'The LWC endpoint should preserve the same historical context returned to Prompt Builder.'
        );
        System.assert(
            result.historicalRepairContext.contains('Disc changer mechanism was misaligned'),
            'The Prompt Builder context should continue exposing the recorded root cause.'
        );
        System.assertNotEquals(null, result.precedents, 'The LWC endpoint should return a structured precedent collection.');
        System.assertEquals(1, result.precedents.size(), 'One relevant historical precedent should be returned.');
        GetRelevantHistoricalRepairsForCase.HistoricalPrecedentUi precedent = result.precedents[0];
        System.assertNotEquals(null, precedent.maintenanceLogId);
        System.assertNotEquals(null, precedent.maintenanceLogName);
        System.assertEquals(Date.today().addDays(-45), precedent.maintenanceDate);
        System.assertEquals(assetRecord.Id, precedent.assetId);
        System.assertEquals('Roland', precedent.manufacturer);
        System.assertEquals('DWX-53DC', precedent.model);
        System.assertEquals('LWC-HRI-001', precedent.serialNumber);
        System.assertEquals(historicalWorkOrder.Id, precedent.workOrderId);
        System.assertNotEquals(null, precedent.workOrderNumber);
        System.assertEquals(true, precedent.sameAsset);
        System.assertEquals(true, precedent.sameModel);
        System.assertEquals(
            'Disc changer binds near the bottom of travel during Run-in.',
            precedent.problemSummary,
            'The structured precedent should expose the original historical problem description.'
        );
        System.assert(
            precedent.whyRelevant.contains('same error code'),
            'Structured relevance should identify the exact matching historical error code.'
        );
        System.assert(
            precedent.whyRelevant.contains('same Asset'),
            'Structured relevance should identify that the precedent belongs to the current Asset.'
        );
        System.assertEquals(
            'Corrected disc changer alignment and restored normal travel.',
            precedent.successfulRepair
        );
        System.assertEquals('Disc changer mechanism was misaligned.', precedent.rootCause);
        System.assertEquals('Disc Changer Alignment Component', precedent.partsUsed);
        System.assertEquals(
            'Verified smooth movement and completed Run-in successfully.',
            precedent.technicianNotes
        );
        System.assertEquals(Decimal.valueOf('2'), precedent.laborHours);
        System.assertEquals('Issue resolved; no follow-up required.', precedent.outcome);
    }
    @IsTest
    static void testLwcEndpointUsesDefaultMaximum() {
        Account accountRecord = createAccount('HRI LWC Default Maximum Test');
        Asset assetRecord = createAsset(
            accountRecord,
            'LWC Default Maximum Mill',
            'Straumann',
            'M Series',
            'LWC-HRI-002'
        );
        Case historicalCase = createCase(
            accountRecord,
            assetRecord,
            'Coolant flow failure',
            'Coolant is not reaching the milling chamber.',
            'COOL-LWC-100'
        );
        WorkOrder historicalWorkOrder = createWorkOrder(accountRecord, assetRecord, historicalCase, 'Repair coolant flow');
        createMaintenanceLog(
            assetRecord,
            historicalWorkOrder,
            Date.today().addDays(-30),
            'Repair',
            'Restored coolant flow.',
            'Coolant line restriction.',
            'Coolant Hose',
            'Coolant flow verified after repair.',
            true,
            false
        );
        Case currentCase = createCase(
            accountRecord,
            assetRecord,
            'Coolant flow failure',
            'Coolant is not reaching the milling chamber.',
            'COOL-LWC-100'
        );
        Test.startTest();
        GetRelevantHistoricalRepairsForCase.Result result = GetRelevantHistoricalRepairsForCase.getHistoricalRepairsForLwc(currentCase.Id, null);
        Test.stopTest();
        System.assertEquals(true, result.success);
        System.assertEquals('SUCCESS', result.statusCode);
        System.assertEquals(1, result.matchCount);
        System.assertNotEquals(null, result.precedents);
        System.assertEquals(1, result.precedents.size());
        System.assertEquals(
            'Coolant is not reaching the milling chamber.',
            result.precedents[0].problemSummary
        );
        System.assertEquals('Coolant line restriction.', result.precedents[0].rootCause);
        System.assertEquals('Coolant Hose', result.precedents[0].partsUsed);
    }
    @IsTest
    static void testLwcEndpointRejectsMissingCaseId() {
        Test.startTest();
        GetRelevantHistoricalRepairsForCase.Result result = GetRelevantHistoricalRepairsForCase.getHistoricalRepairsForLwc(null, 3);
        Test.stopTest();
        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.statusCode);
        System.assertEquals(0, result.matchCount);
        System.assertEquals('', result.historicalRepairContext);
        System.assertNotEquals(null, result.precedents);
        System.assertEquals(0, result.precedents.size(), 'Invalid LWC requests should return an empty structured precedent list.');
    }
}
