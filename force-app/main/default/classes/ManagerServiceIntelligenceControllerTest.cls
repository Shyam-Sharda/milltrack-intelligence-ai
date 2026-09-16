@IsTest
private class ManagerServiceIntelligenceControllerTest {

    // =========================================================
    // Helpers
    // =========================================================

    private static String getActivePicklistValue(Schema.DescribeFieldResult fieldDescribe, String preferredValue) {
        String firstActiveValue;

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (!entry.isActive()) continue;
            if (firstActiveValue == null) firstActiveValue = entry.getValue();
            if (entry.getValue() == preferredValue) return entry.getValue();
        }

        return firstActiveValue;
    }


    private static Account createAccount(String name) {
        Account accountRecord = new Account(Name = name);
        insert accountRecord;
        return accountRecord;
    }


    private static Contact createContact(Id accountId, String lastName) {
        Contact contactRecord = new Contact(AccountId = accountId, FirstName = 'Alex', LastName = lastName, Phone = '604-555-0100', Email = lastName.toLowerCase() + '@example.com');
        insert contactRecord;
        return contactRecord;
    }


    private static Asset createAsset(Id accountId, String name, String manufacturer, String model, String serialNumber) {
        Asset assetRecord = new Asset(AccountId = accountId, Name = name, Manufacturer__c = manufacturer, Model__c = model, Serial_Number__c = serialNumber);
        insert assetRecord;
        return assetRecord;
    }


    private static Case createCase(Id accountId, Id contactId, Id assetId, String subject) {
        Case caseRecord = new Case(
            AccountId = accountId,
            ContactId = contactId,
            AssetId = assetId,
            Subject = subject,
            Status = getActivePicklistValue(Schema.SObjectType.Case.fields.Status, 'New'),
            Origin = getActivePicklistValue(Schema.SObjectType.Case.fields.Origin, 'Web'),
            Priority = 'Medium'
        );

        insert caseRecord;
        return caseRecord;
    }


    private static WorkOrder createWorkOrder(Id accountId, Id assetId, Id caseId, String subject) {
        WorkOrder workOrderRecord = new WorkOrder(
            AccountId = accountId,
            AssetId = assetId,
            CaseId = caseId,
            Subject = subject,
            Status = getActivePicklistValue(Schema.SObjectType.WorkOrder.fields.Status, 'New'),
            Priority = 'Medium',
            Dispatch_Status__c = getActivePicklistValue(Schema.SObjectType.WorkOrder.fields.Dispatch_Status__c, 'Pending'),
            Problem_Summary__c = 'Machine demonstrates a repeatable service symptom during milling.',
            Recommended_Fix_Summary__c = 'Inspect the affected machine assembly and verify the underlying cause.',
            Technician_Notes__c = 'Technician findings documented for service intelligence testing.'
        );

        insert workOrderRecord;
        return workOrderRecord;
    }


    private static Maintenance_Log__c createMaintenanceLog(
        Id assetId,
        Id workOrderId,
        Date maintenanceDate,
        String maintenanceType,
        Boolean resolved,
        Boolean followUp,
        Decimal laborHours,
        String summary,
        String rootCause
    ) {
        Maintenance_Log__c logRecord = new Maintenance_Log__c(
            Asset__c = assetId,
            Work_Order__c = workOrderId,
            Maintenance_Date__c = maintenanceDate,
            Maintenance_Type__c = getActivePicklistValue(Schema.SObjectType.Maintenance_Log__c.fields.Maintenance_Type__c, maintenanceType),
            Problem_Summary__c = 'Machine demonstrates a repeatable service symptom during milling.',
            Summary__c = summary,
            Root_Cause__c = rootCause,
            Technician_Notes__c = 'Technician documented the service visit and resulting findings.',
            Issue_Resolved__c = resolved,
            Follow_Up_Required__c = followUp,
            Performed_By__c = UserInfo.getUserId(),
            Labor_Hours__c = laborHours
        );

        insert logRecord;
        return logRecord;
    }


    private static ManagerServiceIntelligenceController.ModelServiceDTO findModel(List<ManagerServiceIntelligenceController.ModelServiceDTO> models, String expectedLabel) {
        for (ManagerServiceIntelligenceController.ModelServiceDTO modelRecord : models) {
            if (modelRecord.machineLabel == expectedLabel) return modelRecord;
        }

        return null;
    }


    // =========================================================
    // Main Intelligence Test
    // =========================================================

    @IsTest
    static void returnsRankedMachineServiceIntelligence() {
        Account accountA = createAccount('Precision Dental Studio');
        Account accountB = createAccount('Apex Prosthetics');

        Contact contactA = createContact(accountA.Id, 'Morgan');
        Contact contactB = createContact(accountB.Id, 'Taylor');

        Asset rolandAsset = createAsset(accountA.Id, 'DWX-52D Mill', 'Roland', 'DWX-52D', 'DWX52D-TEST-001');
        Asset motionAsset = createAsset(accountB.Id, 'Ceramill Motion 2', 'Amann Girrbach', 'Ceramill Motion 2', 'MOTION2-TEST-001');

        Case rolandCaseOne = createCase(accountA.Id, contactA.Id, rolandAsset.Id, 'Spindle vibration during milling');
        Case rolandCaseTwo = createCase(accountA.Id, contactA.Id, rolandAsset.Id, 'Calibration drift affecting restorations');
        Case motionCase = createCase(accountB.Id, contactB.Id, motionAsset.Id, 'Tool sensor intermittently fails');

        WorkOrder rolandWorkOrderOne = createWorkOrder(accountA.Id, rolandAsset.Id, rolandCaseOne.Id, 'Repair spindle vibration');
        WorkOrder rolandWorkOrderTwo = createWorkOrder(accountA.Id, rolandAsset.Id, rolandCaseTwo.Id, 'Correct calibration drift');
        WorkOrder motionWorkOrder = createWorkOrder(accountB.Id, motionAsset.Id, motionCase.Id, 'Inspect tool sensor');

        Maintenance_Log__c rolandFirstVisit = createMaintenanceLog(
            rolandAsset.Id,
            rolandWorkOrderOne.Id,
            Date.today().addDays(-20),
            'Repair',
            true,
            false,
            2,
            'Adjusted the spindle assembly and verified improved milling performance.',
            'Spindle alignment was outside normal tolerance.'
        );

        Maintenance_Log__c rolandReturnVisit = createMaintenanceLog(
            rolandAsset.Id,
            rolandWorkOrderOne.Id,
            Date.today().addDays(-10),
            'Temporary Repair',
            false,
            true,
            1.5,
            'Applied a temporary spindle adjustment while awaiting additional service.',
            'Further spindle wear was identified during follow-up inspection.'
        );

        Maintenance_Log__c rolandLatestVisit = createMaintenanceLog(
            rolandAsset.Id,
            rolandWorkOrderTwo.Id,
            Date.today().addDays(-5),
            'Repair',
            true,
            false,
            3,
            'Recalibrated the machine and confirmed restoration accuracy.',
            'Machine calibration had drifted outside acceptable limits.'
        );

        Maintenance_Log__c motionFirstVisit = createMaintenanceLog(
            motionAsset.Id,
            motionWorkOrder.Id,
            Date.today().addDays(-15),
            'Inspection',
            false,
            false,
            2,
            'Inspected the tool sensor and reproduced the intermittent failure.',
            'Sensor behavior remained intermittent during testing.'
        );

        Maintenance_Log__c motionLatestVisit = createMaintenanceLog(
            motionAsset.Id,
            motionWorkOrder.Id,
            Date.today().addDays(-3),
            'Inspection',
            false,
            true,
            1,
            'Confirmed the sensor requires additional follow-up service.',
            'Sensor signal remained unstable under repeated testing.'
        );

        Test.startTest();
        ManagerServiceIntelligenceController.ServiceIntelligenceData data = ManagerServiceIntelligenceController.getServiceIntelligence(90);
        Test.stopTest();

        System.assertNotEquals(null, data, 'Service intelligence data should be returned.');
        System.assertEquals(90, data.daysBack);
        System.assertEquals(Date.today().addDays(-89), data.startDate);
        System.assertEquals(Date.today(), data.endDate);

        System.assertEquals(5, data.totalServiceVisits, 'Five Maintenance Logs should count as five service visits.');
        System.assertEquals(3, data.totalIssues, 'Repeated visits on the same Work Order should count as one issue.');
        System.assertEquals(Decimal.valueOf('9.5'), data.totalLaborHours, 'Labor hours should be summed across all visits.');
        System.assertEquals(2, data.totalFollowUps, 'Two visits require follow-up.');
        System.assertEquals(2, data.totalResolvedVisits, 'Two visits were resolved.');
        System.assertEquals(2, data.modelCount, 'Two machine models should be represented.');
        System.assertEquals(2, data.models.size());

        ManagerServiceIntelligenceController.ModelServiceDTO rolandModel = findModel(data.models, 'Roland DWX-52D');
        ManagerServiceIntelligenceController.ModelServiceDTO motionModel = findModel(data.models, 'Amann Girrbach Ceramill Motion 2');

        System.assertNotEquals(null, rolandModel, 'Roland DWX-52D should be included.');
        System.assertNotEquals(null, motionModel, 'Ceramill Motion 2 should be included.');

        System.assertEquals(1, rolandModel.rank, 'The model with the most service visits should rank first.');
        System.assertEquals(3, rolandModel.serviceVisitCount);
        System.assertEquals(2, rolandModel.issueCount, 'Three visits belong to only two unique Work Orders.');
        System.assertEquals(Decimal.valueOf('6.5'), rolandModel.laborHours);
        System.assertEquals(1, rolandModel.followUpCount);
        System.assertEquals(2, rolandModel.resolvedCount);
        System.assertEquals(0, rolandModel.otherVisitCount);
        System.assertEquals(Decimal.valueOf('100.0'), rolandModel.serviceLoadPercent);

        System.assertEquals(rolandLatestVisit.Id, rolandModel.latestMaintenanceLogId, 'Newest Roland Maintenance Log should be returned.');
        System.assertNotEquals(null, rolandModel.latestMaintenanceLogName, 'Latest Maintenance Log display name should be populated.');
        System.assertEquals(Date.today().addDays(-5), rolandModel.latestMaintenanceDate);
        System.assertEquals(rolandWorkOrderTwo.Id, rolandModel.latestWorkOrderId);
        System.assertNotEquals(null, rolandModel.latestWorkOrderNumber);
        System.assertEquals('Precision Dental Studio', rolandModel.latestAccountName);
        System.assertEquals(rolandCaseTwo.Id, rolandModel.latestCaseId);
        System.assertNotEquals(null, rolandModel.latestCaseNumber);
        System.assertEquals('Calibration drift affecting restorations', rolandModel.latestCaseSubject);
        System.assertEquals(UserInfo.getName(), rolandModel.latestTechnicianName);
        System.assertEquals(true, rolandModel.latestWasResolved);
        System.assertEquals(false, rolandModel.latestRequiresFollowUp);
        System.assertEquals('RESOLVED', rolandModel.latestOutcomeKey);
        System.assertEquals('Resolved', rolandModel.latestOutcomeLabel);
        System.assertEquals('Recalibrated the machine and confirmed restoration accuracy.', rolandModel.latestRepairSummary);

        System.assertEquals(2, motionModel.rank);
        System.assertEquals(2, motionModel.serviceVisitCount);
        System.assertEquals(1, motionModel.issueCount, 'Both Motion 2 visits belong to the same Work Order.');
        System.assertEquals(Decimal.valueOf('3'), motionModel.laborHours);
        System.assertEquals(1, motionModel.followUpCount);
        System.assertEquals(0, motionModel.resolvedCount);
        System.assertEquals(1, motionModel.otherVisitCount);
        System.assertEquals(Decimal.valueOf('66.7'), motionModel.serviceLoadPercent);

        System.assertEquals(motionLatestVisit.Id, motionModel.latestMaintenanceLogId);
        System.assertEquals(motionWorkOrder.Id, motionModel.latestWorkOrderId);
        System.assertEquals(true, motionModel.latestRequiresFollowUp);
        System.assertEquals(false, motionModel.latestWasResolved);
        System.assertEquals('FOLLOW_UP', motionModel.latestOutcomeKey);
        System.assertEquals('Follow-Up Required', motionModel.latestOutcomeLabel);

        System.assertNotEquals(null, rolandFirstVisit.Id);
        System.assertNotEquals(null, rolandReturnVisit.Id);
        System.assertNotEquals(null, motionFirstVisit.Id);
    }


    // =========================================================
    // Date Filtering
    // =========================================================

    @IsTest
    static void filtersServiceActivityOutsideSelectedRange() {
        Account accountRecord = createAccount('Reporting Range Dental');
        Contact contactRecord = createContact(accountRecord.Id, 'Range');
        Asset assetRecord = createAsset(accountRecord.Id, 'DWX-53DC Mill', 'Roland', 'DWX-53DC', 'DWX53DC-RANGE-001');

        Case recentCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Recent service issue');
        Case oldCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Old service issue');

        WorkOrder recentWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, recentCase.Id, 'Recent repair');
        WorkOrder oldWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, oldCase.Id, 'Old repair');

        Maintenance_Log__c recentLog = createMaintenanceLog(
            assetRecord.Id,
            recentWorkOrder.Id,
            Date.today().addDays(-10),
            'Repair',
            true,
            false,
            2,
            'Recent repair completed.',
            'Recent service cause.'
        );

        Maintenance_Log__c oldLog = createMaintenanceLog(
            assetRecord.Id,
            oldWorkOrder.Id,
            Date.today().addDays(-120),
            'Repair',
            true,
            false,
            4,
            'Older repair completed.',
            'Older service cause.'
        );

        Test.startTest();
        ManagerServiceIntelligenceController.ServiceIntelligenceData data = ManagerServiceIntelligenceController.getServiceIntelligence(30);
        Test.stopTest();

        System.assertEquals(30, data.daysBack);
        System.assertEquals(Date.today().addDays(-29), data.startDate);
        System.assertEquals(1, data.totalServiceVisits, 'Only the visit inside the selected 30-day period should be returned.');
        System.assertEquals(1, data.totalIssues);
        System.assertEquals(Decimal.valueOf('2'), data.totalLaborHours);
        System.assertEquals(1, data.models.size());
        System.assertEquals(recentLog.Id, data.models[0].latestMaintenanceLogId);
        System.assertNotEquals(oldLog.Id, data.models[0].latestMaintenanceLogId);
    }


    // =========================================================
    // Default Period
    // =========================================================

    @IsTest
    static void defaultsToNinetyDaysWhenPeriodIsNull() {
        Test.startTest();
        ManagerServiceIntelligenceController.ServiceIntelligenceData data = ManagerServiceIntelligenceController.getServiceIntelligence(null);
        Test.stopTest();

        System.assertEquals(90, data.daysBack, 'Null reporting period should default to 90 days.');
        System.assertEquals(Date.today().addDays(-89), data.startDate);
        System.assertEquals(Date.today(), data.endDate);
        System.assertNotEquals(null, data.models);
    }


    // =========================================================
    // Empty Result
    // =========================================================

    @IsTest
    static void returnsEmptyIntelligenceWhenNoLogsExist() {
        Test.startTest();
        ManagerServiceIntelligenceController.ServiceIntelligenceData data = ManagerServiceIntelligenceController.getServiceIntelligence(1);
        Test.stopTest();

        System.assertNotEquals(null, data);
        System.assertEquals(0, data.totalServiceVisits);
        System.assertEquals(0, data.totalIssues);
        System.assertEquals(Decimal.valueOf('0'), data.totalLaborHours);
        System.assertEquals(0, data.totalFollowUps);
        System.assertEquals(0, data.totalResolvedVisits);
        System.assertEquals(0, data.modelCount);
        System.assertEquals(0, data.models.size());
    }


    // =========================================================
    // Validation
    // =========================================================

    @IsTest
    static void rejectsZeroDayReportingPeriod() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerServiceIntelligenceController.getServiceIntelligence(0);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A reporting period below one day should be rejected.');
    }


    @IsTest
    static void rejectsReportingPeriodAboveMaximum() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerServiceIntelligenceController.getServiceIntelligence(3651);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Reporting periods above the supported maximum should be rejected.');
    }
}