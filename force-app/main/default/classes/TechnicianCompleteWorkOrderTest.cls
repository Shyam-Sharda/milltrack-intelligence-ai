@IsTest
private class TechnicianCompleteWorkOrderTest {

    private static final String TECH_A_EMAIL = 'complete.tech.a@milltrack.test';
    private static final String TECH_B_EMAIL = 'complete.tech.b@milltrack.test';
    private static final String MANAGER_EMAIL = 'complete.manager@milltrack.test';
    private static final String TEST_PROBLEM_SUMMARY = 'Machine fails to complete X-axis homing and binds during travel.';

    private class TestData {
        Id accountId;
        Id contactId;
        Id assetId;
        Id caseId;
        Id workOrderId;
        Datetime originalWorkStarted;
        Datetime originalScheduledVisit;
    }

    @TestSetup
    static void setupUsers() {
        Id profileId = UserInfo.getProfileId();
        String uniqueKey = UserInfo.getOrganizationId() + '.' + String.valueOf(Datetime.now().getTime());

        User technicianA = buildUser(
            'Complete Technician A',
            'cmptech',
            TECH_A_EMAIL,
            'milltrack.complete.techa.' + uniqueKey + '@example.test',
            profileId
        );

        User technicianB = buildUser(
            'Complete Technician B',
            'cmptech',
            TECH_B_EMAIL,
            'milltrack.complete.techb.' + uniqueKey + '@example.test',
            profileId
        );

        User manager = buildUser(
            'Complete Manager',
            'cmpmgr',
            MANAGER_EMAIL,
            'milltrack.complete.manager.' + uniqueKey + '@example.test',
            profileId
        );

        insert new List<User>{ technicianA, technicianB, manager };
    }

    @IsTest
    static void testGetCompletionContextSuccess() {
        User technician = getTechnicianA();
        User manager = getManager();

        TestData data = createTestData(
            technician.Id,
            manager.Id,
            'In Progress',
            true,
            Decimal.valueOf('1.50'),
            'Existing technician note.'
        );

        TechnicianCompleteWorkOrderController.CompletionContext context;

        System.runAs(technician) {
            Test.startTest();
            context = TechnicianCompleteWorkOrderController.getCompletionContext(data.workOrderId);
            Test.stopTest();
        }

        System.assertNotEquals(null, context, 'Context should be returned.');
        System.assertEquals(data.workOrderId, context.workOrderId);
        System.assertNotEquals(null, context.workOrderNumber, 'Work Order number should be returned.');
        System.assertEquals('Complete Work Order Test', context.subject);
        System.assertEquals(data.assetId, context.assetId);
        System.assertEquals('Complete Test Machine', context.assetName);
        System.assertEquals('Roland', context.manufacturer);
        System.assertEquals('DWX-52D', context.model);
        System.assertEquals(Decimal.valueOf('1.50'), context.currentLaborHours);
    }

    @IsTest
    static void testCompleteWorkOrderSuccess() {
        User technician = getTechnicianA();
        User manager = getManager();

        TestData data = createTestData(
            technician.Id,
            manager.Id,
            'In Progress',
            true,
            Decimal.valueOf('1.50'),
            'Existing technician note.'
        );

        String repairSummary =
            'Inspected the X-axis homing system and found binding during travel. ' +
            'Replaced the damaged spindle assembly, recalibrated the axis, and completed multiple homing and milling tests successfully.';

        String rootCause =
            'Mechanical wear in the spindle assembly caused binding during X-axis homing.';

        String partsUsed =
            'Replacement spindle assembly';

        TechnicianCompleteWorkOrderController.SubmitResult result;

        System.runAs(technician) {
            Test.startTest();

            result = TechnicianCompleteWorkOrderController.completeWorkOrder(
                data.workOrderId,
                repairSummary,
                rootCause,
                partsUsed,
                Decimal.valueOf('1.25')
            );

            Test.stopTest();
        }

        System.assertNotEquals(null, result, 'A result should be returned.');
        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.maintenanceLogId, 'Maintenance Log Id must be returned.');
        System.assertNotEquals(null, result.workOrderNumber);
        System.assert(
            result.message.contains('completed successfully'),
            'Success message should confirm completion.'
        );

        WorkOrder updatedWorkOrder = [
            SELECT Id, Dispatch_Status__c, OwnerId, Suggested_Technician__c,
                   Scheduled_Visit__c, Labor_Hours__c, Technician_Notes__c,
                   Work_Started_Date_Time__c, Work_Ended_Date_Time__c,
                   Service_Manager__c
            FROM WorkOrder
            WHERE Id = :data.workOrderId
        ];

        System.assertEquals(
            'Completed',
            updatedWorkOrder.Dispatch_Status__c,
            'Work Order should move to Completed.'
        );

        System.assertEquals(
            manager.Id,
            updatedWorkOrder.OwnerId,
            'Completed Work Order ownership should return to the Service Manager.'
        );

        System.assertEquals(
            null,
            updatedWorkOrder.Suggested_Technician__c,
            'Suggested Technician should be cleared.'
        );

        System.assertEquals(
            data.originalScheduledVisit,
            updatedWorkOrder.Scheduled_Visit__c,
            'Scheduled Visit should remain preserved as historical visit information.'
        );

        System.assertEquals(
            Decimal.valueOf('2.75'),
            updatedWorkOrder.Labor_Hours__c,
            'Current visit labor should be added to cumulative Work Order labor.'
        );

        System.assert(
            updatedWorkOrder.Technician_Notes__c.contains('Existing technician note.'),
            'Existing Work Order technician notes must be preserved.'
        );

        System.assert(
            updatedWorkOrder.Technician_Notes__c.contains('COMPLETED REPAIR'),
            'Completed repair heading should be appended.'
        );

        System.assert(
            updatedWorkOrder.Technician_Notes__c.contains(repairSummary),
            'Repair Summary should be appended.'
        );

        System.assert(
            updatedWorkOrder.Technician_Notes__c.contains(rootCause),
            'Root Cause should be included in the appended note.'
        );

        System.assert(
            updatedWorkOrder.Technician_Notes__c.contains(partsUsed),
            'Parts Used should be included in the appended note.'
        );

        System.assertEquals(
            data.originalWorkStarted,
            updatedWorkOrder.Work_Started_Date_Time__c,
            'Original Work Started timestamp must be preserved.'
        );

        System.assertNotEquals(
            null,
            updatedWorkOrder.Work_Ended_Date_Time__c,
            'Work Ended Date/Time should be populated.'
        );

        System.assertEquals(
            manager.Id,
            updatedWorkOrder.Service_Manager__c,
            'Service Manager should remain unchanged.'
        );

        Asset updatedAsset = [
            SELECT Machine_Status__c, Last_Service_Date__c
            FROM Asset
            WHERE Id = :data.assetId
        ];

        System.assertEquals(
            'Active',
            updatedAsset.Machine_Status__c,
            'Successfully repaired machine should return to Active.'
        );

        System.assertEquals(
            Date.today(),
            updatedAsset.Last_Service_Date__c,
            'Last Service Date should be today.'
        );

        Case updatedCase = [
            SELECT Status
            FROM Case
            WHERE Id = :data.caseId
        ];

        System.assertEquals(
            'Closed',
            updatedCase.Status,
            'Related Case should be closed.'
        );

        Maintenance_Log__c maintenanceLog = [
            SELECT Id, Asset__c, Work_Order__c, Maintenance_Date__c,
                   Maintenance_Type__c, Problem_Summary__c, Summary__c,
                   Technician_Notes__c, Root_Cause__c, Parts_Used__c, Labor_Hours__c,
                   Issue_Resolved__c, Follow_Up_Required__c,
                   Performed_By__c, OwnerId
            FROM Maintenance_Log__c
            WHERE Id = :result.maintenanceLogId
        ];

        System.assertEquals(data.assetId, maintenanceLog.Asset__c);
        System.assertEquals(data.workOrderId, maintenanceLog.Work_Order__c);
        System.assertEquals(Date.today(), maintenanceLog.Maintenance_Date__c);

        System.assertEquals(
            'Repair',
            maintenanceLog.Maintenance_Type__c
        );

        System.assertEquals(
            TEST_PROBLEM_SUMMARY,
            maintenanceLog.Problem_Summary__c,
            'Maintenance Log should preserve the Work Order Problem Summary.'
        );

        System.assertEquals(
            repairSummary,
            maintenanceLog.Summary__c
        );

        System.assertEquals(
            rootCause,
            maintenanceLog.Root_Cause__c
        );

        System.assertEquals(
            partsUsed,
            maintenanceLog.Parts_Used__c
        );

        System.assertEquals(
            Decimal.valueOf('1.25'),
            maintenanceLog.Labor_Hours__c,
            'Maintenance Log labor must contain this visit only.'
        );

        System.assertEquals(
            true,
            maintenanceLog.Issue_Resolved__c,
            'Completed repair should be resolved.'
        );

        System.assertEquals(
            false,
            maintenanceLog.Follow_Up_Required__c,
            'Completed repair should not require follow-up.'
        );

        System.assertEquals(
            technician.Id,
            maintenanceLog.Performed_By__c,
            'Performed By should identify the completing technician.'
        );

        System.assertEquals(
            technician.Id,
            maintenanceLog.OwnerId,
            'Technician should own the created Maintenance Log.'
        );

        System.assert(
            maintenanceLog.Technician_Notes__c.contains('COMPLETED REPAIR'),
            'Maintenance Log should contain the structured completion note.'
        );
    }

    @IsTest
    static void testCompleteWithoutCaseAndWithoutParts() {
        User technician = getTechnicianA();
        User manager = getManager();

        TestData data = createTestData(
            technician.Id,
            manager.Id,
            'In Progress',
            false,
            0,
            null
        );

        TechnicianCompleteWorkOrderController.SubmitResult result;

        System.runAs(technician) {
            Test.startTest();

            result = TechnicianCompleteWorkOrderController.completeWorkOrder(
                data.workOrderId,
                'Completed repair and verified normal machine operation.',
                'Loose electrical connector caused intermittent machine operation.',
                null,
                Decimal.valueOf('0.75')
            );

            Test.stopTest();
        }

        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.maintenanceLogId);

        WorkOrder updatedWorkOrder = [
            SELECT Dispatch_Status__c, OwnerId, Labor_Hours__c,
                   Suggested_Technician__c
            FROM WorkOrder
            WHERE Id = :data.workOrderId
        ];

        System.assertEquals('Completed', updatedWorkOrder.Dispatch_Status__c);
        System.assertEquals(manager.Id, updatedWorkOrder.OwnerId);
        System.assertEquals(Decimal.valueOf('0.75'), updatedWorkOrder.Labor_Hours__c);
        System.assertEquals(null, updatedWorkOrder.Suggested_Technician__c);

        Maintenance_Log__c maintenanceLog = [
            SELECT Problem_Summary__c, Parts_Used__c, Issue_Resolved__c,
                   Follow_Up_Required__c, Technician_Notes__c
            FROM Maintenance_Log__c
            WHERE Id = :result.maintenanceLogId
        ];

        System.assertEquals(
            TEST_PROBLEM_SUMMARY,
            maintenanceLog.Problem_Summary__c,
            'Problem Summary should be preserved even when the Work Order has no Case.'
        );

        System.assertEquals(
            null,
            maintenanceLog.Parts_Used__c,
            'Parts Used should remain blank when no parts were entered.'
        );

        System.assertEquals(true, maintenanceLog.Issue_Resolved__c);
        System.assertEquals(false, maintenanceLog.Follow_Up_Required__c);

        System.assert(
            maintenanceLog.Technician_Notes__c.contains('None recorded'),
            'Structured note should state that no parts were recorded.'
        );
    }

    @IsTest
    static void testRejectsNullWorkOrder() {
        User technician = getTechnicianA();
        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianCompleteWorkOrderController.completeWorkOrder(
                    null,
                    'Valid repair summary.',
                    'Valid root cause.',
                    null,
                    Decimal.valueOf('1')
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;

                System.assert(
                    e.getMessage().contains('Work Order is required'),
                    'Expected null Work Order validation.'
                );
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Null Work Order should be rejected.'
        );
    }

    @IsTest
    static void testRejectsNonInProgressWorkOrder() {
        User technician = getTechnicianA();
        User manager = getManager();

        TestData data = createTestData(
            technician.Id,
            manager.Id,
            'Assigned',
            true,
            0,
            null
        );

        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianCompleteWorkOrderController.completeWorkOrder(
                    data.workOrderId,
                    'Valid repair summary.',
                    'Valid root cause.',
                    null,
                    Decimal.valueOf('1')
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;

                System.assert(
                    e.getMessage().contains('In Progress'),
                    'Error should explain that completion requires In Progress status.'
                );
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Non-In Progress Work Order should be rejected.'
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Maintenance_Log__c
                WHERE Work_Order__c = :data.workOrderId
            ],
            'Rejected completion must not create a Maintenance Log.'
        );
    }

    @IsTest
    static void testRejectsNonOwnerTechnician() {
        User owningTechnician = getTechnicianA();
        User otherTechnician = getTechnicianB();
        User manager = getManager();

        TestData data = createTestData(
            owningTechnician.Id,
            manager.Id,
            'In Progress',
            true,
            0,
            null
        );

        Boolean exceptionThrown = false;

        System.runAs(otherTechnician) {
            Test.startTest();

            try {
                TechnicianCompleteWorkOrderController.completeWorkOrder(
                    data.workOrderId,
                    'Unauthorized repair completion attempt.',
                    'Unauthorized root cause.',
                    null,
                    Decimal.valueOf('1')
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'A technician who does not own the Work Order must not be able to complete it.'
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Maintenance_Log__c
                WHERE Work_Order__c = :data.workOrderId
            ],
            'Unauthorized attempt must not create a Maintenance Log.'
        );
    }

    @IsTest
    static void testRejectsBlankRepairSummary() {
        User technician = getTechnicianA();
        User manager = getManager();

        TestData data = createTestData(
            technician.Id,
            manager.Id,
            'In Progress',
            true,
            0,
            null
        );

        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianCompleteWorkOrderController.completeWorkOrder(
                    data.workOrderId,
                    '   ',
                    'Valid root cause.',
                    null,
                    Decimal.valueOf('1')
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;

                System.assert(
                    e.getMessage().contains('Repair Summary is required'),
                    'Expected Repair Summary validation.'
                );
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Blank Repair Summary should be rejected.'
        );
    }

    @IsTest
    static void testRejectsBlankRootCause() {
        User technician = getTechnicianA();
        User manager = getManager();

        TestData data = createTestData(
            technician.Id,
            manager.Id,
            'In Progress',
            true,
            0,
            null
        );

        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianCompleteWorkOrderController.completeWorkOrder(
                    data.workOrderId,
                    'Valid repair summary.',
                    '   ',
                    null,
                    Decimal.valueOf('1')
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;

                System.assert(
                    e.getMessage().contains('Root Cause is required'),
                    'Expected Root Cause validation.'
                );
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Blank Root Cause should be rejected.'
        );
    }

    @IsTest
    static void testRejectsInvalidLaborHours() {
        User technician = getTechnicianA();
        User manager = getManager();

        TestData data = createTestData(
            technician.Id,
            manager.Id,
            'In Progress',
            true,
            0,
            null
        );

        Boolean zeroRejected = false;
        Boolean nullRejected = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianCompleteWorkOrderController.completeWorkOrder(
                    data.workOrderId,
                    'Valid repair summary.',
                    'Valid root cause.',
                    null,
                    0
                );
            } catch (AuraHandledException e) {
                zeroRejected = true;

                System.assert(
                    e.getMessage().contains('greater than 0'),
                    'Zero labor should be rejected.'
                );
            }

            try {
                TechnicianCompleteWorkOrderController.completeWorkOrder(
                    data.workOrderId,
                    'Valid repair summary.',
                    'Valid root cause.',
                    null,
                    null
                );
            } catch (AuraHandledException e) {
                nullRejected = true;

                System.assert(
                    e.getMessage().contains('greater than 0'),
                    'Null labor should be rejected.'
                );
            }

            Test.stopTest();
        }

        System.assertEquals(true, zeroRejected, 'Zero labor should be rejected.');
        System.assertEquals(true, nullRejected, 'Null labor should be rejected.');
    }

    @IsTest
    static void testRejectsMissingServiceManager() {
        User technician = getTechnicianA();

        TestData data = createTestData(
            technician.Id,
            null,
            'In Progress',
            true,
            0,
            null
        );

        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianCompleteWorkOrderController.getCompletionContext(
                    data.workOrderId
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;

                System.assert(
                    e.getMessage().contains('No Service Manager'),
                    'Error should explain that a Service Manager is required.'
                );
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Work Order without a Service Manager should not be completable.'
        );
    }

    private static TestData createTestData(
        Id technicianId,
        Id managerId,
        String dispatchStatus,
        Boolean createCaseRecord,
        Decimal existingLabor,
        String existingNotes
    ) {
        Account account = new Account(
            Name = 'Complete Work Order Test Account'
        );
        insert account;

        Contact contact = new Contact(
            LastName = 'Complete Work Order Contact',
            AccountId = account.Id
        );
        insert contact;

        Asset asset = new Asset(
            Name = 'Complete Test Machine',
            AccountId = account.Id,
            Machine_Status__c = 'Needs Service',
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Serial_Number__c = 'COMPLETE-001'
        );
        insert asset;

        Id caseId;

        if (createCaseRecord) {
            Case caseRecord = new Case(
                AccountId = account.Id,
                ContactId = contact.Id,
                AssetId = asset.Id,
                Subject = 'Complete Work Order Test Case',
                Status = 'In Progress',
                Origin = getFirstActivePicklistValue(
                    Schema.SObjectType.Case.fields.Origin
                ),
                Work_Order_Proposal_Created__c = true
            );

            insert caseRecord;
            caseId = caseRecord.Id;
        }

        Datetime workStarted = System.now().addHours(-2);
        Datetime scheduledVisit = System.now().addHours(-1);

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            ContactId = contact.Id,
            AssetId = asset.Id,
            CaseId = caseId,
            Subject = 'Complete Work Order Test',
            Problem_Summary__c = TEST_PROBLEM_SUMMARY,
            OwnerId = technicianId,
            Dispatch_Status__c = dispatchStatus,
            Labor_Hours__c = existingLabor,
            Technician_Notes__c = existingNotes,
            Service_Manager__c = managerId,
            Suggested_Technician__c = technicianId,
            Scheduled_Visit__c = scheduledVisit,
            Work_Started_Date_Time__c = workStarted
        );

        workOrder.Status = getFirstActivePicklistValue(
            Schema.SObjectType.WorkOrder.fields.Status
        );

        insert workOrder;

        TestData data = new TestData();
        data.accountId = account.Id;
        data.contactId = contact.Id;
        data.assetId = asset.Id;
        data.caseId = caseId;
        data.workOrderId = workOrder.Id;
        data.originalWorkStarted = workStarted;
        data.originalScheduledVisit = scheduledVisit;

        return data;
    }

    private static User buildUser(
        String lastName,
        String alias,
        String email,
        String username,
        Id profileId
    ) {
        return new User(
            FirstName = 'Test',
            LastName = lastName,
            Alias = alias,
            Email = email,
            Username = username,
            CommunityNickname =
                alias + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    private static User getTechnicianA() {
        return [
            SELECT Id, Name
            FROM User
            WHERE Email = :TECH_A_EMAIL
            LIMIT 1
        ];
    }

    private static User getTechnicianB() {
        return [
            SELECT Id, Name
            FROM User
            WHERE Email = :TECH_B_EMAIL
            LIMIT 1
        ];
    }

    private static User getManager() {
        return [
            SELECT Id, Name
            FROM User
            WHERE Email = :MANAGER_EMAIL
            LIMIT 1
        ];
    }

    private static String getFirstActivePicklistValue(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        for (
            Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }
}