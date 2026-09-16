@IsTest
private class TechnicianTemporaryFixControllerTest {

    private static final String TECH_A_EMAIL = 'tempfix.tech.a@milltrack.test';
    private static final String TECH_B_EMAIL = 'tempfix.tech.b@milltrack.test';
    private static final String MANAGER_EMAIL = 'tempfix.manager@milltrack.test';
    private static final String SERVICE_MANAGER_QUEUE = 'Service_Manager_Queue';
    private static final String TEST_PROBLEM_SUMMARY = 'Front door sensor intermittently disconnects during machine vibration.';
    private static final String TEST_RECOMMENDED_FIX = 'Inspect the front door sensor connection under vibration and replace the sensor harness if the connection remains unstable.';
    private static final String TEST_RECOMMENDED_TOOLS = 'Multimeter; Torx driver set; sensor diagnostic tools';

    private class TestData {
        Id accountId, contactId, assetId, caseId, workOrderId;
        Datetime originalWorkStarted;
    }

    @TestSetup
    static void setupUsersAndQueue() {
        Id profileId = UserInfo.getProfileId();
        String uniqueKey = UserInfo.getOrganizationId() + '.' + String.valueOf(Datetime.now().getTime());

        User technicianA = buildUser('Temporary Fix Technician A', 'tfxtech', TECH_A_EMAIL, 'milltrack.tempfix.techa.' + uniqueKey + '@example.test', profileId);
        User technicianB = buildUser('Temporary Fix Technician B', 'tfxtech', TECH_B_EMAIL, 'milltrack.tempfix.techb.' + uniqueKey + '@example.test', profileId);
        User manager = buildUser('Temporary Fix Manager', 'tfxmgr', MANAGER_EMAIL, 'milltrack.tempfix.manager.' + uniqueKey + '@example.test', profileId);
        insert new List<User>{ technicianA, technicianB, manager };

        List<Group> existingQueues = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :SERVICE_MANAGER_QUEUE LIMIT 1];
        Id queueId;

        if (existingQueues.isEmpty()) {
            Group serviceManagerQueue = new Group(Name = 'Service Manager Queue', DeveloperName = SERVICE_MANAGER_QUEUE, Type = 'Queue');
            insert serviceManagerQueue;
            queueId = serviceManagerQueue.Id;
        } else {
            queueId = existingQueues[0].Id;
        }

        List<QueueSobject> queueObjects = [SELECT Id FROM QueueSobject WHERE QueueId = :queueId AND SobjectType = 'WorkOrder' LIMIT 1];
        if (queueObjects.isEmpty()) insert new QueueSobject(QueueId = queueId, SobjectType = 'WorkOrder');
    }

    @IsTest
    static void testGetTemporaryFixContextSuccess() {
        User technician = getTechnicianA(), manager = getManager();
        TestData data = createTestData(technician.Id, manager.Id, 'In Progress', true, 1.50, 'Existing technician note.');
        TechnicianTemporaryFixController.TemporaryFixContext context;

        System.runAs(technician) {
            Test.startTest();
            context = TechnicianTemporaryFixController.getTemporaryFixContext(data.workOrderId);
            Test.stopTest();
        }

        System.assertNotEquals(null, context, 'Context should be returned.');
        System.assertEquals(data.workOrderId, context.workOrderId);
        System.assertNotEquals(null, context.workOrderNumber, 'Work Order number should be returned.');
        System.assertEquals('Temporary Fix Test Work Order', context.subject);
        System.assertEquals(data.assetId, context.assetId);
        System.assertEquals('Temporary Fix Test Machine', context.assetName);
        System.assertEquals('Straumann', context.manufacturer);
        System.assertEquals('M Series', context.model);
        System.assertEquals(Decimal.valueOf('1.50'), context.currentLaborHours);
    }

    @IsTest
    static void testSubmitTemporaryFixSuccess() {
        User technician = getTechnicianA(), manager = getManager();
        TestData data = createTestData(technician.Id, manager.Id, 'In Progress', true, 1.50, 'Existing technician note.');
        String visitSummary = 'Inspected the front door sensor and found an intermittent connection. Reseated and secured the connector, restoring operation during testing. Because the connection may fail again under vibration, follow-up replacement is required.';
        TechnicianTemporaryFixController.SubmitResult result;

        System.runAs(technician) {
            Test.startTest();
            result = TechnicianTemporaryFixController.submitTemporaryFix(data.workOrderId, visitSummary, Decimal.valueOf('1.25'));
            Test.stopTest();
        }

        System.assertNotEquals(null, result, 'A submit result should be returned.');
        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.maintenanceLogId, 'The new Maintenance Log Id must be returned.');
        System.assertNotEquals(null, result.workOrderNumber);
        System.assert(result.message.contains('returned for manager follow-up'), 'Success message should explain the manager handback.');

        Id queueId = getServiceManagerQueueId();

        WorkOrder updatedWorkOrder = [
            SELECT Id, Dispatch_Status__c, OwnerId, Scheduled_Visit__c, Suggested_Technician__c,
                   Labor_Hours__c, Technician_Notes__c, Work_Started_Date_Time__c, Service_Manager__c,
                   Recommended_Fix_Summary__c, Recommended_Tools__c
            FROM WorkOrder
            WHERE Id = :data.workOrderId
        ];

        System.assertEquals('Temporary Fix', updatedWorkOrder.Dispatch_Status__c, 'Work Order should move to Temporary Fix.');
        System.assertEquals(queueId, updatedWorkOrder.OwnerId, 'Work Order ownership should return to the Service Manager Queue.');
        System.assertEquals(null, updatedWorkOrder.Scheduled_Visit__c, 'Scheduled Visit should be cleared.');
        System.assertEquals(null, updatedWorkOrder.Suggested_Technician__c, 'Suggested Technician should be cleared.');
        System.assertEquals(Decimal.valueOf('2.75'), updatedWorkOrder.Labor_Hours__c, 'Visit labor should be added to existing cumulative Work Order labor.');
        System.assert(updatedWorkOrder.Technician_Notes__c.contains('Existing technician note.'), 'Existing Work Order technician notes must be preserved.');
        System.assert(updatedWorkOrder.Technician_Notes__c.contains('TEMPORARY REPAIR / FOLLOW-UP'), 'Temporary repair heading should be appended.');
        System.assert(updatedWorkOrder.Technician_Notes__c.contains(visitSummary), 'Visit Summary should be appended to Work Order technician notes.');
        System.assertEquals(data.originalWorkStarted, updatedWorkOrder.Work_Started_Date_Time__c, 'Original Work Started timestamp must be preserved.');
        System.assertEquals(manager.Id, updatedWorkOrder.Service_Manager__c, 'Service Manager should remain unchanged.');
        System.assertEquals(TEST_RECOMMENDED_FIX, updatedWorkOrder.Recommended_Fix_Summary__c, 'Current Recommended Fix should remain unchanged during technician handback.');
        System.assertEquals(TEST_RECOMMENDED_TOOLS, updatedWorkOrder.Recommended_Tools__c, 'Current Tools should remain unchanged during technician handback.');

        Asset updatedAsset = [SELECT Machine_Status__c, Last_Service_Date__c FROM Asset WHERE Id = :data.assetId];
        System.assertEquals('Temporary Fix Applied', updatedAsset.Machine_Status__c, 'Asset should represent the physical temporary-fix condition.');
        System.assertEquals(Date.today(), updatedAsset.Last_Service_Date__c, 'Last Service Date should be updated.');

        Case updatedCase = [SELECT Status FROM Case WHERE Id = :data.caseId];
        System.assertEquals('Follow-Up Required', updatedCase.Status, 'Related Case should require follow-up.');

        Maintenance_Log__c maintenanceLog = [
            SELECT Id, Asset__c, Work_Order__c, Maintenance_Date__c, Maintenance_Type__c,
                   Problem_Summary__c, Recommended_Fix_Snapshot__c, Tools_To_Bring_Snapshot__c,
                   Summary__c, Technician_Notes__c, Labor_Hours__c, Issue_Resolved__c,
                   Follow_Up_Required__c, Performed_By__c, OwnerId, Root_Cause__c
            FROM Maintenance_Log__c
            WHERE Id = :result.maintenanceLogId
        ];

        System.assertEquals(data.assetId, maintenanceLog.Asset__c);
        System.assertEquals(data.workOrderId, maintenanceLog.Work_Order__c);
        System.assertEquals(Date.today(), maintenanceLog.Maintenance_Date__c);
        System.assertEquals('Temporary Repair', maintenanceLog.Maintenance_Type__c);
        System.assertEquals(TEST_PROBLEM_SUMMARY, maintenanceLog.Problem_Summary__c, 'Maintenance Log should preserve the Work Order Problem Summary.');
        System.assertEquals(TEST_RECOMMENDED_FIX, maintenanceLog.Recommended_Fix_Snapshot__c, 'Maintenance Log should snapshot the Recommended Fix used for this visit.');
        System.assertEquals(TEST_RECOMMENDED_TOOLS, maintenanceLog.Tools_To_Bring_Snapshot__c, 'Maintenance Log should snapshot the Tools used for this visit.');
        System.assertEquals(visitSummary, maintenanceLog.Summary__c);
        System.assertEquals(Decimal.valueOf('1.25'), maintenanceLog.Labor_Hours__c, 'Maintenance Log labor should contain only this visit.');
        System.assertEquals(false, maintenanceLog.Issue_Resolved__c);
        System.assertEquals(true, maintenanceLog.Follow_Up_Required__c);
        System.assertEquals(technician.Id, maintenanceLog.Performed_By__c);
        System.assertEquals(technician.Id, maintenanceLog.OwnerId);
        System.assertEquals(null, maintenanceLog.Root_Cause__c, 'Unresolved temporary repair should not manufacture an authoritative Root Cause.');
        System.assert(maintenanceLog.Technician_Notes__c.contains('TEMPORARY REPAIR / FOLLOW-UP'), 'Maintenance Log should contain the structured temporary repair note.');
    }

    @IsTest
    static void testSubmitTemporaryFixWithoutCase() {
        User technician = getTechnicianA(), manager = getManager();
        TestData data = createTestData(technician.Id, manager.Id, 'In Progress', false, 0, null);
        TechnicianTemporaryFixController.SubmitResult result;

        System.runAs(technician) {
            Test.startTest();
            result = TechnicianTemporaryFixController.submitTemporaryFix(data.workOrderId, 'Temporary repair completed, but additional service follow-up is required.', Decimal.valueOf('0.75'));
            Test.stopTest();
        }

        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.maintenanceLogId);

        WorkOrder updatedWorkOrder = [SELECT Dispatch_Status__c, OwnerId, Labor_Hours__c FROM WorkOrder WHERE Id = :data.workOrderId];
        System.assertEquals('Temporary Fix', updatedWorkOrder.Dispatch_Status__c);
        System.assertEquals(getServiceManagerQueueId(), updatedWorkOrder.OwnerId);
        System.assertEquals(Decimal.valueOf('0.75'), updatedWorkOrder.Labor_Hours__c);

        List<Maintenance_Log__c> maintenanceLogs = [
            SELECT Id, Problem_Summary__c, Recommended_Fix_Snapshot__c, Tools_To_Bring_Snapshot__c
            FROM Maintenance_Log__c
            WHERE Work_Order__c = :data.workOrderId
        ];

        System.assertEquals(1, maintenanceLogs.size());
        System.assertEquals(TEST_PROBLEM_SUMMARY, maintenanceLogs[0].Problem_Summary__c, 'Problem Summary should be preserved even when the Work Order has no Case.');
        System.assertEquals(TEST_RECOMMENDED_FIX, maintenanceLogs[0].Recommended_Fix_Snapshot__c, 'Recommended Fix snapshot should be preserved even when the Work Order has no Case.');
        System.assertEquals(TEST_RECOMMENDED_TOOLS, maintenanceLogs[0].Tools_To_Bring_Snapshot__c, 'Tools snapshot should be preserved even when the Work Order has no Case.');
    }

    @IsTest
    static void testRejectsNullWorkOrder() {
        User technician = getTechnicianA();
        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianTemporaryFixController.submitTemporaryFix(null, 'Valid visit summary.', Decimal.valueOf('1'));
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                System.assert(e.getMessage().contains('Work Order is required'), 'Expected null Work Order validation message.');
            }

            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown, 'Null Work Order should be rejected.');
    }

    @IsTest
    static void testRejectsNonInProgressWorkOrder() {
        User technician = getTechnicianA(), manager = getManager();
        TestData data = createTestData(technician.Id, manager.Id, 'Assigned', true, 0, null);
        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianTemporaryFixController.submitTemporaryFix(data.workOrderId, 'Temporary repair summary.', Decimal.valueOf('1'));
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                System.assert(e.getMessage().contains('In Progress'), 'Error should explain that temporary repair requires In Progress status.');
            }

            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown, 'Non-In Progress Work Order should be rejected.');
        System.assertEquals(0, [SELECT COUNT() FROM Maintenance_Log__c WHERE Work_Order__c = :data.workOrderId], 'Rejected submission must not create a Maintenance Log.');
    }

    @IsTest
    static void testRejectsBlankSummary() {
        User technician = getTechnicianA(), manager = getManager();
        TestData data = createTestData(technician.Id, manager.Id, 'In Progress', true, 0, null);
        Boolean exceptionThrown = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianTemporaryFixController.submitTemporaryFix(data.workOrderId, '   ', Decimal.valueOf('1'));
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                System.assert(e.getMessage().contains('Visit Summary is required'), 'Expected Visit Summary validation.');
            }

            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown, 'Blank Visit Summary should be rejected.');
    }

    @IsTest
    static void testRejectsInvalidLaborHours() {
        User technician = getTechnicianA(), manager = getManager();
        TestData data = createTestData(technician.Id, manager.Id, 'In Progress', true, 0, null);
        Boolean zeroRejected = false, nullRejected = false;

        System.runAs(technician) {
            Test.startTest();

            try {
                TechnicianTemporaryFixController.submitTemporaryFix(data.workOrderId, 'Valid visit summary.', 0);
            } catch (AuraHandledException e) {
                zeroRejected = true;
                System.assert(e.getMessage().contains('greater than 0'), 'Zero labor should be rejected.');
            }

            try {
                TechnicianTemporaryFixController.submitTemporaryFix(data.workOrderId, 'Valid visit summary.', null);
            } catch (AuraHandledException e) {
                nullRejected = true;
                System.assert(e.getMessage().contains('greater than 0'), 'Null labor should be rejected.');
            }

            Test.stopTest();
        }

        System.assertEquals(true, zeroRejected, 'Zero labor should be rejected.');
        System.assertEquals(true, nullRejected, 'Null labor should be rejected.');
    }

    @IsTest
    static void testRejectsNonOwnerTechnician() {
        User owningTechnician = getTechnicianA(), otherTechnician = getTechnicianB(), manager = getManager();
        TestData data = createTestData(owningTechnician.Id, manager.Id, 'In Progress', true, 0, null);
        Boolean exceptionThrown = false;

        System.runAs(otherTechnician) {
            Test.startTest();

            try {
                TechnicianTemporaryFixController.submitTemporaryFix(data.workOrderId, 'Attempted unauthorized temporary repair.', Decimal.valueOf('1'));
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown, 'A technician who does not own the Work Order must not be able to submit a temporary repair.');
        System.assertEquals(0, [SELECT COUNT() FROM Maintenance_Log__c WHERE Work_Order__c = :data.workOrderId], 'Unauthorized attempt must not create a Maintenance Log.');
    }

    private static TestData createTestData(Id technicianId, Id managerId, String dispatchStatus, Boolean createCaseRecord, Decimal existingLabor, String existingNotes) {
        Account account = new Account(Name = 'Temporary Fix Test Account');
        insert account;

        Contact contact = new Contact(LastName = 'Temporary Fix Test Contact', AccountId = account.Id);
        insert contact;

        Asset asset = new Asset(Name = 'Temporary Fix Test Machine', AccountId = account.Id, Machine_Status__c = 'Needs Service', Manufacturer__c = 'Straumann', Model__c = 'M Series', Serial_Number__c = 'TFX-001');
        insert asset;

        Id caseId;

        if (createCaseRecord) {
            Case caseRecord = new Case(AccountId = account.Id, ContactId = contact.Id, AssetId = asset.Id, Subject = 'Temporary Fix Test Case', Status = 'In Progress', Origin = getFirstActivePicklistValue(Schema.SObjectType.Case.fields.Origin), Work_Order_Proposal_Created__c = true);
            insert caseRecord;
            caseId = caseRecord.Id;
        }

        Datetime workStarted = System.now().addHours(-1);

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            ContactId = contact.Id,
            AssetId = asset.Id,
            CaseId = caseId,
            Subject = 'Temporary Fix Test Work Order',
            Problem_Summary__c = TEST_PROBLEM_SUMMARY,
            Recommended_Fix_Summary__c = TEST_RECOMMENDED_FIX,
            Recommended_Tools__c = TEST_RECOMMENDED_TOOLS,
            OwnerId = technicianId,
            Dispatch_Status__c = dispatchStatus,
            Labor_Hours__c = existingLabor,
            Technician_Notes__c = existingNotes,
            Service_Manager__c = managerId,
            Suggested_Technician__c = technicianId,
            Scheduled_Visit__c = System.now().addHours(2),
            Work_Started_Date_Time__c = workStarted
        );

        workOrder.Status = getFirstActivePicklistValue(Schema.SObjectType.WorkOrder.fields.Status);
        insert workOrder;

        TestData data = new TestData();
        data.accountId = account.Id;
        data.contactId = contact.Id;
        data.assetId = asset.Id;
        data.caseId = caseId;
        data.workOrderId = workOrder.Id;
        data.originalWorkStarted = workStarted;
        return data;
    }

    private static User buildUser(String lastName, String alias, String email, String username, Id profileId) {
        return new User(
            FirstName = 'Test',
            LastName = lastName,
            Alias = alias,
            Email = email,
            Username = username,
            CommunityNickname = alias + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    private static User getTechnicianA() { return [SELECT Id, Name FROM User WHERE Email = :TECH_A_EMAIL LIMIT 1]; }
    private static User getTechnicianB() { return [SELECT Id, Name FROM User WHERE Email = :TECH_B_EMAIL LIMIT 1]; }
    private static User getManager() { return [SELECT Id, Name FROM User WHERE Email = :MANAGER_EMAIL LIMIT 1]; }

    private static Id getServiceManagerQueueId() {
        return [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :SERVICE_MANAGER_QUEUE LIMIT 1].Id;
    }

    private static String getFirstActivePicklistValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) if (entry.isActive()) return entry.getValue();
        return null;
    }
}