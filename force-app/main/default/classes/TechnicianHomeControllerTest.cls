@IsTest
private class TechnicianHomeControllerTest {

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

    private static Datetime visitDate(Integer daysFromToday, Integer hour) {
        return Datetime.newInstance(
            Date.today().addDays(daysFromToday),
            Time.newInstance(hour, 0, 0, 0)
        );
    }

    private static Account createAccount(String name) {
        Account accountRecord = new Account(
            Name = name,
            ShippingStreet = '100 Service Avenue',
            ShippingCity = 'Vancouver',
            ShippingPostalCode = 'V6B 1A1',
            BillingStreet = '200 Billing Street',
            BillingCity = 'Burnaby',
            BillingPostalCode = 'V5G 1A1'
        );

        insert accountRecord;
        return accountRecord;
    }

    private static Contact createContact(Id accountId, String lastName) {
        Contact contactRecord = new Contact(
            AccountId = accountId,
            FirstName = 'Alex',
            LastName = lastName,
            Phone = '604-555-0100',
            Email = 'technician-test@example.com'
        );

        insert contactRecord;
        return contactRecord;
    }

    private static Asset createAsset(
        Id accountId,
        String name,
        String manufacturer,
        String model,
        String serialNumber
    ) {
        Asset assetRecord = new Asset(
            AccountId = accountId,
            Name = name,
            Manufacturer__c = manufacturer,
            Model__c = model,
            Serial_Number__c = serialNumber
        );

        insert assetRecord;
        return assetRecord;
    }

    private static Case createCase(
        Id accountId,
        Id contactId,
        String subject,
        String description,
        String errorCode
    ) {
        Case caseRecord = new Case(
            AccountId = accountId,
            ContactId = contactId,
            Subject = subject,
            Description = description,
            Status = getActivePicklistValue(
                Schema.SObjectType.Case.fields.Status,
                'New'
            ),
            Origin = getActivePicklistValue(
                Schema.SObjectType.Case.fields.Origin,
                'Web'
            ),
            Error_Code__c = errorCode
        );

        insert caseRecord;
        return caseRecord;
    }

    private static WorkOrder createWorkOrder(
        Id accountId,
        Id assetId,
        Id caseId,
        String subject,
        String dispatchStatus,
        Datetime scheduledVisit,
        Id technicianId,
        String problemSummary,
        String recommendedFixSummary,
        String recommendedTools
    ) {
        WorkOrder workOrderRecord = new WorkOrder(
            AccountId = accountId,
            AssetId = assetId,
            CaseId = caseId,
            Subject = subject,
            Status = getActivePicklistValue(
                Schema.SObjectType.WorkOrder.fields.Status,
                'New'
            ),
            Priority = 'Medium',
            Dispatch_Status__c = dispatchStatus,
            Scheduled_Visit__c = scheduledVisit,
            Suggested_Technician__c = technicianId,
            Problem_Summary__c = problemSummary,
            Recommended_Fix_Summary__c = recommendedFixSummary,
            Recommended_Tools__c = recommendedTools
        );

        insert workOrderRecord;
        return workOrderRecord;
    }

    private static Maintenance_Log__c createMaintenanceLog(
        Id assetId,
        Id workOrderId,
        String summary,
        String rootCause,
        String technicianNotes,
        Date maintenanceDate
    ) {
        WorkOrder sourceWorkOrder = [
            SELECT Problem_Summary__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];

        Maintenance_Log__c logRecord = new Maintenance_Log__c(
            Asset__c = assetId,
            Work_Order__c = workOrderId,
            Maintenance_Date__c = maintenanceDate,
            Maintenance_Type__c = 'Repair',
            Issue_Resolved__c = true,
            Follow_Up_Required__c = false,
            Problem_Summary__c = sourceWorkOrder.Problem_Summary__c,
            Summary__c = summary,
            Root_Cause__c = rootCause,
            Technician_Notes__c = technicianNotes,
            Labor_Hours__c = 2
        );

        insert logRecord;
        return logRecord;
    }

    /*
     * Creates a Service Manual record and publishes the PDF directly
     * to it. FirstPublishLocationId creates the ContentDocumentLink
     * followed by TechnicianHomeController.
     */
    private static Service_Manual__c createServiceManualWithPdf(
        String recordName,
        String fileTitle,
        String preferredManufacturer,
        String model
    ) {
        String manufacturer = getActivePicklistValue(
            Schema.SObjectType.Service_Manual__c.fields.Manufacturer__c,
            preferredManufacturer
        );

        String documentType = getActivePicklistValue(
            Schema.SObjectType.Service_Manual__c.fields.Document_Type__c,
            null
        );

        Service_Manual__c manualRecord = new Service_Manual__c(
            Manufacturer__c = manufacturer,
            Model__c = model,
            Document_Type__c = documentType
        );

        if (Schema.SObjectType.Service_Manual__c.fields.Name.isCreateable()) {
            manualRecord.put('Name', recordName);
        }

        insert manualRecord;

        ContentVersion versionRecord = new ContentVersion(
            Title = fileTitle,
            PathOnClient = fileTitle + '.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 MillTrack Technician Home Test PDF'),
            FirstPublishLocationId = manualRecord.Id
        );

        insert versionRecord;
        return manualRecord;
    }


    // =========================================================
    // In Progress Visit Wins
    // =========================================================

    @IsTest
    static void inProgressVisitWinsAndLoadsHomepageData() {
        Id technicianId = UserInfo.getUserId();

        Account accountRecord = createAccount('Precision Smile Studio');

        Contact contactRecord = createContact(
            accountRecord.Id,
            'Morgan'
        );

        Asset assetRecord = createAsset(
            accountRecord.Id,
            'DWX-52D Mill',
            'Roland',
            'DWX-52D',
            '52D-TEST-001'
        );


        // -----------------------------------------------------
        // Current active job
        // -----------------------------------------------------

        Case currentCase = createCase(
            accountRecord.Id,
            contactRecord.Id,
            'Spindle grinding noise',
            'Customer reports spindle grinding noise and vibration during milling.',
            'E100'
        );

        WorkOrder inProgressWorkOrder = createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            currentCase.Id,
            'Investigate spindle grinding noise',
            'In Progress',
            visitDate(-1, 10),
            technicianId,
            'Spindle grinding noise and vibration during milling.',
            'Inspect the spindle assembly and verify bearing condition under load.',
            'Spindle wrench, inspection mirror'
        );


        // -----------------------------------------------------
        // First upcoming job
        // -----------------------------------------------------

        Case nextCase = createCase(
            accountRecord.Id,
            contactRecord.Id,
            'Tool measurement failure',
            'Tool measurement repeatedly fails before milling and calibration.',
            null
        );

        WorkOrder nextWorkOrder = createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            nextCase.Id,
            'Inspect tool measurement failure',
            'Pending',
            visitDate(1, 9),
            technicianId,
            'Tool measurement repeatedly fails before calibration.',
            'Inspect the tool sensor and verify calibration.',
            'Multimeter'
        );


        // -----------------------------------------------------
        // Second upcoming job
        // -----------------------------------------------------

        Case laterCase = createCase(
            accountRecord.Id,
            contactRecord.Id,
            'Intermittent coolant flow',
            'Customer reports intermittent coolant flow while milling.',
            null
        );

        WorkOrder laterWorkOrder = createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            laterCase.Id,
            'Inspect coolant flow',
            'Pending',
            visitDate(2, 13),
            technicianId,
            'Coolant flow is intermittent during milling.',
            'Inspect coolant pump and hoses.',
            'Flashlight'
        );


        // -----------------------------------------------------
        // Historical precedent for active spindle job
        // -----------------------------------------------------

        Case historicalSpindleCase = createCase(
            accountRecord.Id,
            contactRecord.Id,
            'Spindle grinding during milling',
            'Machine produced spindle grinding noise and vibration during milling.',
            'E100'
        );

        WorkOrder historicalSpindleWorkOrder = createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            historicalSpindleCase.Id,
            'Spindle grinding during milling',
            'Pending',
            null,
            null,
            'Spindle grinding noise and vibration during milling.',
            'Inspect the spindle bearing assembly and verify spindle rotation.',
            'Spindle wrench'
        );

        Maintenance_Log__c historicalSpindleLog = createMaintenanceLog(
            assetRecord.Id,
            historicalSpindleWorkOrder.Id,
            'Resolved spindle grinding noise and vibration after inspecting the spindle assembly.',
            'Spindle bearing wear caused grinding noise and vibration.',
            'Spindle grinding and vibration were eliminated after repair.',
            Date.today().addDays(-30)
        );


        // -----------------------------------------------------
        // Historical precedent for upcoming tool job
        // -----------------------------------------------------

        Case historicalToolCase = createCase(
            accountRecord.Id,
            contactRecord.Id,
            'Tool measurement failure before calibration',
            'Tool measurement repeatedly failed before milling and calibration.',
            null
        );

        WorkOrder historicalToolWorkOrder = createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            historicalToolCase.Id,
            'Repair tool measurement failure',
            'Pending',
            null,
            null,
            'Tool measurement failed repeatedly before calibration.',
            'Inspect the tool measurement sensor, clean the contact area, and verify sensor alignment.',
            'Multimeter, cleaning kit'
        );

        Maintenance_Log__c historicalToolLog = createMaintenanceLog(
            assetRecord.Id,
            historicalToolWorkOrder.Id,
            'Resolved repeated tool measurement failure after servicing the tool measurement sensor.',
            'Contamination and sensor alignment caused the measurement failure.',
            'Tool measurement and calibration completed successfully after repair.',
            Date.today().addDays(-45)
        );


        // -----------------------------------------------------
        // Quick Service Manuals
        // -----------------------------------------------------

        createServiceManualWithPdf(
            'Ceramill Motion 2 Service Manual',
            'Ceramill Motion User Manual',
            'Amann Girrbach',
            'Ceramill Motion 2'
        );

        createServiceManualWithPdf(
            'Roland DWX-52D Service Manual',
            'DWX-52D User Manual',
            'Roland',
            'DWX-52D'
        );

        createServiceManualWithPdf(
            'Unrelated Service Manual',
            'Unrelated Test Manual',
            'Roland',
            'Test Model'
        );


        // -----------------------------------------------------
        // Execute
        // -----------------------------------------------------

        Test.startTest();

        TechnicianHomeController.TechnicianHomeData data =
            TechnicianHomeController.getHomeData();

        Test.stopTest();


        // -----------------------------------------------------
        // Technician
        // -----------------------------------------------------

        System.assertNotEquals(
            null,
            data,
            'Homepage data should be returned.'
        );

        System.assertEquals(
            technicianId,
            data.technicianId
        );

        System.assertNotEquals(
            null,
            data.technicianName
        );


        // -----------------------------------------------------
        // Current Visit
        // -----------------------------------------------------

        System.assertNotEquals(
            null,
            data.currentVisit
        );

        System.assertEquals(
            inProgressWorkOrder.Id,
            data.currentVisit.workOrderId,
            'An assigned In Progress Work Order must win over future scheduled visits.'
        );

        System.assertEquals(
            true,
            data.currentVisit.isInProgress
        );

        System.assertEquals(
            'In Progress',
            data.currentVisit.dispatchStatus
        );

        System.assertEquals(
            'Precision Smile Studio',
            data.currentVisit.accountName
        );

        System.assertEquals(
            'Roland DWX-52D',
            data.currentVisit.machineLabel
        );

        System.assertEquals(
            contactRecord.Id,
            data.currentVisit.contactId,
            'Case Contact should be used when Work Order Contact is empty.'
        );

        System.assertEquals(
            'Alex Morgan',
            data.currentVisit.contactName
        );

        System.assertEquals(
            '100 Service Avenue, Vancouver V6B 1A1',
            data.currentVisit.fullAddress,
            'Account Shipping Address should be used when the Work Order has no service address.'
        );



        // -----------------------------------------------------
        // Upcoming Visits
        // -----------------------------------------------------

        System.assertEquals(
            2,
            data.upcomingVisits.size(),
            'Both future assigned jobs should appear after the active job.'
        );

        System.assertEquals(
            nextWorkOrder.Id,
            data.upcomingVisits[0].workOrderId
        );

        System.assertEquals(
            laterWorkOrder.Id,
            data.upcomingVisits[1].workOrderId
        );

        System.assertEquals(
            'Tool measurement repeatedly fails before calibration.',
            data.upcomingVisits[0].problemSummary
        );

        System.assertEquals(
            'Inspect the tool sensor and verify calibration.',
            data.upcomingVisits[0].recommendedFixSummary
        );

        System.assertEquals(
            'Multimeter',
            data.upcomingVisits[0].recommendedTools
        );


        // -----------------------------------------------------
        // Current Job Similar Repairs
        // -----------------------------------------------------

        System.assertEquals(
            1,
            data.similarRepairs.size(),
            'The active spindle problem should find one relevant successful precedent.'
        );

        System.assertEquals(
            historicalSpindleWorkOrder.Id,
            data.similarRepairs[0].workOrderId
        );

        System.assertEquals(
            historicalSpindleLog.Id,
            data.similarRepairs[0].maintenanceLogId
        );

        System.assertNotEquals(
            null,
            data.similarRepairs[0].maintenanceLogName,
            'The Similar Repair should expose the Maintenance Log number.'
        );

        System.assertEquals(
            'Spindle grinding noise and vibration during milling.',
            data.similarRepairs[0].problemSummary,
            'The Similar Repair should expose the historical Maintenance Log Problem Summary.'
        );

        System.assertEquals(
            'Resolved spindle grinding noise and vibration after inspecting the spindle assembly.',
            data.similarRepairs[0].repairSummary,
            'The Similar Repair should expose the historical Maintenance Log Repair Summary.'
        );

        System.assertEquals(
            'Spindle grinding during milling',
            data.similarRepairs[0].subject
        );

        System.assertEquals(
            'Inspect the spindle bearing assembly and verify spindle rotation.',
            data.similarRepairs[0].recommendedFixSummary
        );

        System.assert(
            data.similarRepairs[0].matchedKeywords.contains('spindle'),
            'Spindle should be included among the matched terms.'
        );

        System.assert(
            data.similarRepairs[0].matchedKeywords.contains('grinding'),
            'Grinding should be included among the matched terms.'
        );

        System.assertEquals(
            'Spindle grinding during milling',
            data.similarRepairs[0].caseSubject,
            'The homepage should expose the historical Case Subject.'
        );


        // -----------------------------------------------------
        // Upcoming Job Similar Repair
        // -----------------------------------------------------

        System.assertNotEquals(
            null,
            data.upcomingVisits[0].similarRepair,
            'The tool-measurement job should retain its strongest relevant historical repair.'
        );

        System.assertNotEquals(
            null,
            data.upcomingVisits[0].similarRepairs,
            'Upcoming visits should expose their Similar Repairs collection.'
        );

        System.assertEquals(
            1,
            data.upcomingVisits[0].similarRepairs.size(),
            'This test data contains one qualifying historical repair for the upcoming job.'
        );

        System.assertEquals(
            historicalToolWorkOrder.Id,
            data.upcomingVisits[0].similarRepairs[0].workOrderId
        );

        System.assertEquals(
            historicalToolWorkOrder.Id,
            data.upcomingVisits[0].similarRepair.workOrderId
        );

        System.assertEquals(
            historicalToolLog.Id,
            data.upcomingVisits[0].similarRepair.maintenanceLogId
        );

        System.assertNotEquals(
            null,
            data.upcomingVisits[0].similarRepair.maintenanceLogName
        );

        System.assertEquals(
            'Tool measurement failed repeatedly before calibration.',
            data.upcomingVisits[0].similarRepair.problemSummary
        );

        System.assertEquals(
            'Resolved repeated tool measurement failure after servicing the tool measurement sensor.',
            data.upcomingVisits[0].similarRepair.repairSummary
        );

        System.assertEquals(
            'Repair tool measurement failure',
            data.upcomingVisits[0].similarRepair.subject
        );

        System.assertEquals(
            'Inspect the tool measurement sensor, clean the contact area, and verify sensor alignment.',
            data.upcomingVisits[0].similarRepair.recommendedFixSummary
        );

        System.assert(
            data.upcomingVisits[0].similarRepair.matchedKeywords.contains('measurement'),
            'Measurement should be included among the upcoming job matched terms.'
        );

        System.assertEquals(
            null,
            data.upcomingVisits[1].similarRepair,
            'The unrelated coolant problem should not receive a misleading historical repair.'
        );

        System.assertNotEquals(
            null,
            data.upcomingVisits[1].similarRepairs
        );

        System.assertEquals(
            0,
            data.upcomingVisits[1].similarRepairs.size(),
            'An unrelated upcoming job should have an empty Similar Repairs collection.'
        );

        System.assertEquals(
            'Tool measurement failure before calibration',
            data.upcomingVisits[0].similarRepair.caseSubject,
            'The upcoming job precedent should expose the historical Case Subject.'
        );


        // -----------------------------------------------------
        // Quick Service Manuals
        // -----------------------------------------------------

        System.assertEquals(
            2,
            data.serviceManuals.size(),
            'Only the two curated Quick Service Manuals should be returned.'
        );

        System.assertEquals(
            'Ceramill Motion User Manual',
            data.serviceManuals[0].title
        );

        System.assertEquals(
            'DWX-52D User Manual',
            data.serviceManuals[1].title
        );

        System.assertNotEquals(
            null,
            data.serviceManuals[0].contentDocumentId
        );

        System.assertNotEquals(
            null,
            data.serviceManuals[0].contentVersionId
        );

        System.assertNotEquals(
            null,
            data.serviceManuals[1].contentDocumentId
        );

        System.assertNotEquals(
            null,
            data.serviceManuals[1].contentVersionId
        );
    }


    // =========================================================
    // Next Scheduled Visit Becomes Current
    // =========================================================

    @IsTest
    static void nextScheduledVisitBecomesCurrentWhenNothingIsInProgress() {
        Id technicianId = UserInfo.getUserId();

        Account accountRecord = createAccount(
            'NorthStar Dental Milling'
        );

        Contact contactRecord = createContact(
            accountRecord.Id,
            'Patel'
        );

        Asset assetRecord = createAsset(
            accountRecord.Id,
            'Motion 2 Mill',
            'Amann Girrbach',
            'Ceramill Motion 2',
            'MOTION-TEST-001'
        );

        Case caseRecord = createCase(
            accountRecord.Id,
            contactRecord.Id,
            'Machine not homing',
            'Machine does not complete the homing sequence.',
            null
        );

        WorkOrder firstVisit = createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            caseRecord.Id,
            'Motion 2 not homing',
            'Pending',
            visitDate(1, 8),
            technicianId,
            'Machine does not complete homing.',
            'Inspect homing sensors and axis movement.',
            'Multimeter, hex keys'
        );

        firstVisit.Street = '500 Customer Road';
        firstVisit.City = 'Surrey';
        firstVisit.PostalCode = 'V3T 1A1';
        update firstVisit;

        WorkOrder secondVisit = createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            caseRecord.Id,
            'Inspect spindle cleaning issue',
            'Pending',
            visitDate(2, 11),
            technicianId,
            'Spindle requires inspection and cleaning.',
            'Inspect and clean the spindle assembly.',
            'Cleaning kit'
        );

        Test.startTest();

        TechnicianHomeController.TechnicianHomeData data =
            TechnicianHomeController.getHomeData();

        Test.stopTest();

        System.assertNotEquals(
            null,
            data.currentVisit
        );

        System.assertEquals(
            firstVisit.Id,
            data.currentVisit.workOrderId,
            'The earliest scheduled assigned visit should become the top Next Service Visit.'
        );

        System.assertEquals(
            false,
            data.currentVisit.isInProgress
        );

        System.assertEquals(
            1,
            data.upcomingVisits.size(),
            'The top Next Service Visit should not also appear in Upcoming Service Visits.'
        );

        System.assertEquals(
            secondVisit.Id,
            data.upcomingVisits[0].workOrderId
        );

        System.assertEquals(
            '500 Customer Road, Surrey V3T 1A1',
            data.currentVisit.fullAddress,
            'A Work Order service address must take priority over Account Shipping and Billing addresses.'
        );
    }


    // =========================================================
    // Upcoming Visit Limit
    // =========================================================

    @IsTest
    static void upcomingVisitsAreCappedAtThree() {
        Id technicianId = UserInfo.getUserId();

        Account accountRecord = createAccount(
            'Apex Prosthetics'
        );

        Asset assetRecord = createAsset(
            accountRecord.Id,
            'DWX Test Mill',
            'Roland',
            'DWX-52D',
            'LIMIT-001'
        );

        List<WorkOrder> workOrders = new List<WorkOrder>();

        for (Integer i = 1; i <= 7; i++) {
            workOrders.add(
                createWorkOrder(
                    accountRecord.Id,
                    assetRecord.Id,
                    null,
                    'Scheduled Visit ' + i,
                    'Pending',
                    visitDate(i, 9),
                    technicianId,
                    'Scheduled service problem ' + i,
                    'Scheduled service recommendation ' + i,
                    'Standard service tools'
                )
            );
        }

        Test.startTest();

        TechnicianHomeController.TechnicianHomeData data =
            TechnicianHomeController.getHomeData();

        Test.stopTest();

        System.assertEquals(
            workOrders[0].Id,
            data.currentVisit.workOrderId,
            'The earliest scheduled visit should become the top Next Service Visit.'
        );

        System.assertEquals(
            3,
            data.upcomingVisits.size(),
            'Technician Home should show no more than three expanded Upcoming Service Visits.'
        );

        System.assertEquals(
            workOrders[1].Id,
            data.upcomingVisits[0].workOrderId
        );

        System.assertEquals(
            workOrders[2].Id,
            data.upcomingVisits[1].workOrderId
        );

        System.assertEquals(
            workOrders[3].Id,
            data.upcomingVisits[2].workOrderId
        );
    }


    // =========================================================
    // Empty Technician Schedule
    // =========================================================

    @IsTest
    static void returnsCleanEmptyStateWhenTechnicianHasNoAssignedVisits() {
        Account accountRecord = createAccount(
            'Unassigned Customer'
        );

        Asset assetRecord = createAsset(
            accountRecord.Id,
            'Unassigned Mill',
            'Roland',
            'DWX-52D',
            'EMPTY-001'
        );

        createWorkOrder(
            accountRecord.Id,
            assetRecord.Id,
            null,
            'Unassigned Work Order',
            'Pending',
            visitDate(1, 10),
            null,
            'Unassigned service problem.',
            'Inspect the machine.',
            'Standard tools'
        );

        Test.startTest();

        TechnicianHomeController.TechnicianHomeData data =
            TechnicianHomeController.getHomeData();

        Test.stopTest();

        System.assertNotEquals(
            null,
            data
        );

        System.assertEquals(
            UserInfo.getUserId(),
            data.technicianId
        );

        System.assertEquals(
            null,
            data.currentVisit
        );

        System.assertEquals(
            0,
            data.upcomingVisits.size()
        );

        System.assertEquals(
            0,
            data.similarRepairs.size()
        );

        System.assertEquals(
            0,
            data.serviceManuals.size()
        );
    }
}