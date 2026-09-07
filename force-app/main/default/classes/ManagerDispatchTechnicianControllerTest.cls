@IsTest
private class ManagerDispatchTechnicianControllerTest {

    private static final String TECHNICIAN_ROLE = 'MillTrack_Technician';
    private static final String TECHNICIAN_LAST_NAME = 'MillTrack Dispatch Technician Test';
    private static final String NON_TECHNICIAN_LAST_NAME = 'MillTrack Dispatch Non Technician Test';
    private static Integer partSequence = 0;

    // =========================================================
    // Test Setup
    // =========================================================

    @TestSetup
    static void setupUsers() {

        UserRole technicianRole = [
            SELECT Id
            FROM UserRole
            WHERE DeveloperName = :TECHNICIAN_ROLE
            LIMIT 1
        ];

        Profile systemAdministratorProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniqueValue = String.valueOf(DateTime.now().getTime()) + '.' + UserInfo.getOrganizationId();

        User technician = new User(
            Alias = 'mtdtech',
            Email = 'dispatch.technician@milltrack.test',
            EmailEncodingKey = 'UTF-8',
            LastName = TECHNICIAN_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = systemAdministratorProfile.Id,
            TimeZoneSidKey = 'America/Toronto',
            Username = 'dispatch.technician.' + uniqueValue + '@milltrack.test',
            CommunityNickname = 'mtdtech' + String.valueOf(DateTime.now().getTime()),
            UserRoleId = technicianRole.Id
        );

        User nonTechnician = new User(
            Alias = 'mtdnon',
            Email = 'dispatch.nontech@milltrack.test',
            EmailEncodingKey = 'UTF-8',
            LastName = NON_TECHNICIAN_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = systemAdministratorProfile.Id,
            TimeZoneSidKey = 'America/Toronto',
            Username = 'dispatch.nontech.' + uniqueValue + '@milltrack.test',
            CommunityNickname = 'mtdnon' + String.valueOf(DateTime.now().getTime())
        );

        insert new List<User>{ technician, nonTechnician };
    }

    // =========================================================
    // Context Tests
    // =========================================================

    @IsTest
    static void getDispatchContextReturnsEligibleReadyWorkOrder() {

        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Received');
        User technician = getTestTechnician();

        Test.startTest();
        ManagerDispatchTechnicianController.DispatchContext context =
            ManagerDispatchTechnicianController.getDispatchContext(fixture.workOrder.Id);
        Test.stopTest();

        System.assertEquals(true, context.eligible, 'A Ready to Assign Work Order should be eligible for dispatch.');
        System.assertEquals(null, context.ineligibleReason, 'An eligible Work Order should not return an ineligibility reason.');
        System.assertEquals(fixture.workOrder.Id, context.workOrderId);
        System.assertEquals(fixture.workOrder.WorkOrderNumber, context.workOrderNumber);
        System.assertEquals('Ready_to_Assign', context.dispatchStatus);
        System.assertEquals('Medium', context.priority);
        System.assertEquals(fixture.account.Id, context.accountId);
        System.assertEquals(fixture.account.Name, context.accountName);
        System.assertEquals(fixture.asset.Id, context.assetId);
        System.assertEquals(fixture.asset.Name, context.assetName);
        System.assertEquals('Needs Service', context.assetStatus);
        System.assertEquals(fixture.serviceCase.Id, context.caseId);
        System.assertEquals('Spindle is making an abnormal noise during operation.', context.problemSummary);
        System.assertEquals('Inspect spindle assembly and verify operation.', context.recommendedFixSummary);
        System.assertEquals(1, context.parts.size(), 'The Work Order Part should be returned.');
        System.assertEquals('Received', context.parts[0].status);
        System.assert(
            technicianAppearsInOptions(context.technicians, technician.Id),
            'The active MillTrack technician should be returned as an assignment option.'
        );
    }

    @IsTest
    static void getDispatchContextReturnsIneligibleForNullWorkOrder() {

        Test.startTest();
        ManagerDispatchTechnicianController.DispatchContext context =
            ManagerDispatchTechnicianController.getDispatchContext(null);
        Test.stopTest();

        System.assertEquals(false, context.eligible);
        System.assertNotEquals(null, context.ineligibleReason);
        System.assertEquals(0, context.parts.size());
        System.assertEquals(0, context.technicians.size());
    }

    @IsTest
    static void getDispatchContextReturnsIneligibleForWrongStatus() {

        Fixture fixture = createFixture('Parts to Order');

        Test.startTest();
        ManagerDispatchTechnicianController.DispatchContext context =
            ManagerDispatchTechnicianController.getDispatchContext(fixture.workOrder.Id);
        Test.stopTest();

        System.assertEquals(false, context.eligible, 'Parts to Order must not be dispatchable.');
        System.assertNotEquals(null, context.ineligibleReason);
    }

    @IsTest
    static void getDispatchContextRejectsTemporaryFix() {

        Fixture fixture = createFixture('Temporary Fix');

        Test.startTest();
        ManagerDispatchTechnicianController.DispatchContext context =
            ManagerDispatchTechnicianController.getDispatchContext(fixture.workOrder.Id);
        Test.stopTest();

        System.assertEquals(
            false,
            context.eligible,
            'Temporary Fix belongs to the manager follow-up workflow and must not be directly dispatchable.'
        );
        System.assertNotEquals(null, context.ineligibleReason);
    }

    // =========================================================
    // Successful Dispatch
    // =========================================================

    @IsTest
    static void dispatchTechnicianAssignsWorkOrderAndSchedulesCase() {

        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Received');

        User technician = getTestTechnician();
        Datetime scheduledVisit = System.now().addDays(2);

        Test.startTest();
        ManagerDispatchTechnicianController.DispatchResult result =
            ManagerDispatchTechnicianController.dispatchTechnician(
                fixture.workOrder.Id,
                technician.Id,
                scheduledVisit
            );
        Test.stopTest();

        WorkOrder updatedWorkOrder = [
            SELECT Id, OwnerId, Suggested_Technician__c, Scheduled_Visit__c, Dispatch_Status__c
            FROM WorkOrder
            WHERE Id = :fixture.workOrder.Id
        ];

        Case updatedCase = [
            SELECT Id, Status
            FROM Case
            WHERE Id = :fixture.serviceCase.Id
        ];

        Asset updatedAsset = [
            SELECT Id, Machine_Status__c
            FROM Asset
            WHERE Id = :fixture.asset.Id
        ];

        System.assertEquals('Assigned', updatedWorkOrder.Dispatch_Status__c, 'Dispatch should move the Work Order to Assigned.');
        System.assertEquals(
            technician.Id,
            updatedWorkOrder.Suggested_Technician__c,
            'Assigned Technician should be stored on Suggested_Technician__c.'
        );
        System.assertEquals(technician.Id, updatedWorkOrder.OwnerId, 'The technician should own the Work Order after dispatch.');
        System.assertEquals(scheduledVisit, updatedWorkOrder.Scheduled_Visit__c, 'The scheduled visit should be saved.');
        System.assertEquals('Scheduled', updatedCase.Status, 'The related Case should move to Scheduled.');
        System.assertEquals('Needs Service', updatedAsset.Machine_Status__c, 'Dispatch must not change the physical Asset condition.');

        System.assertEquals(fixture.workOrder.Id, result.workOrderId);
        System.assertEquals(fixture.workOrder.WorkOrderNumber, result.workOrderNumber);
        System.assertEquals('Assigned', result.workOrderStatus);
        System.assertEquals('Scheduled', result.caseStatus);
        System.assertEquals('Needs Service', result.assetStatus);
        System.assertEquals(technician.Id, result.technicianId);
        System.assertEquals(technician.Name, result.technicianName);
        System.assertEquals(scheduledVisit, result.scheduledVisit);
    }

    // =========================================================
    // Validation Tests
    // =========================================================

    @IsTest
    static void dispatchTechnicianRejectsNullWorkOrderId() {

        User technician = getTestTechnician();

        assertDispatchThrows(
            null,
            technician.Id,
            System.now().addDays(1),
            'A null Work Order ID should be rejected.'
        );
    }

    @IsTest
    static void dispatchTechnicianRejectsNullTechnician() {

        Fixture fixture = createFixture('Ready_to_Assign');

        assertDispatchThrows(
            fixture.workOrder.Id,
            null,
            System.now().addDays(1),
            'A technician must be selected.'
        );
    }

    @IsTest
    static void dispatchTechnicianRejectsNullScheduledVisit() {

        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();

        assertDispatchThrows(
            fixture.workOrder.Id,
            technician.Id,
            null,
            'A scheduled visit is required.'
        );
    }

    @IsTest
    static void dispatchTechnicianRejectsPastScheduledVisit() {

        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();

        assertDispatchThrows(
            fixture.workOrder.Id,
            technician.Id,
            System.now().addDays(-1),
            'A scheduled visit in the past should be rejected.'
        );
    }

    @IsTest
    static void dispatchTechnicianRejectsNonTechnicianUser() {

        Fixture fixture = createFixture('Ready_to_Assign');
        User nonTechnician = getTestNonTechnician();

        assertDispatchThrows(
            fixture.workOrder.Id,
            nonTechnician.Id,
            System.now().addDays(1),
            'A user outside the MillTrack Technician role should be rejected.'
        );

        WorkOrder unchangedWorkOrder = [
            SELECT Dispatch_Status__c, Suggested_Technician__c
            FROM WorkOrder
            WHERE Id = :fixture.workOrder.Id
        ];

        System.assertEquals('Ready_to_Assign', unchangedWorkOrder.Dispatch_Status__c);
        System.assertEquals(null, unchangedWorkOrder.Suggested_Technician__c);
    }

    @IsTest
    static void dispatchTechnicianRejectsWorkOrderNoLongerReady() {

        Fixture fixture = createFixture('Parts to Order');
        User technician = getTestTechnician();

        assertDispatchThrows(
            fixture.workOrder.Id,
            technician.Id,
            System.now().addDays(1),
            'A Work Order outside Ready to Assign should be rejected.'
        );

        WorkOrder unchangedWorkOrder = [
            SELECT Dispatch_Status__c
            FROM WorkOrder
            WHERE Id = :fixture.workOrder.Id
        ];

        System.assertEquals('Parts to Order', unchangedWorkOrder.Dispatch_Status__c);
    }

    // =========================================================
    // Parts Guardrail Tests
    // =========================================================

    @IsTest
    static void dispatchTechnicianRejectsOutstandingOrderedPart() {

        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Ordered');

        User technician = getTestTechnician();

        assertDispatchThrows(
            fixture.workOrder.Id,
            technician.Id,
            System.now().addDays(1),
            'An outstanding Ordered part should block dispatch.'
        );

        WorkOrder unchangedWorkOrder = [
            SELECT Dispatch_Status__c, Suggested_Technician__c
            FROM WorkOrder
            WHERE Id = :fixture.workOrder.Id
        ];

        Case unchangedCase = [
            SELECT Status
            FROM Case
            WHERE Id = :fixture.serviceCase.Id
        ];

        Asset unchangedAsset = [
            SELECT Machine_Status__c
            FROM Asset
            WHERE Id = :fixture.asset.Id
        ];

        System.assertEquals('Ready_to_Assign', unchangedWorkOrder.Dispatch_Status__c);
        System.assertEquals(null, unchangedWorkOrder.Suggested_Technician__c);
        System.assertEquals('In Progress', unchangedCase.Status);
        System.assertEquals('Needs Service', unchangedAsset.Machine_Status__c);
    }

    @IsTest
    static void dispatchTechnicianRejectsRequestedPart() {

        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Requested');

        User technician = getTestTechnician();

        assertDispatchThrows(
            fixture.workOrder.Id,
            technician.Id,
            System.now().addDays(1),
            'A Requested part should block dispatch.'
        );
    }

    @IsTest
    static void dispatchTechnicianRejectsShippedPart() {

        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Shipped');

        User technician = getTestTechnician();

        assertDispatchThrows(
            fixture.workOrder.Id,
            technician.Id,
            System.now().addDays(1),
            'A Shipped part should block dispatch until it is received.'
        );
    }

    @IsTest
    static void dispatchTechnicianAllowsReceivedAndCancelledParts() {

        Fixture fixture = createFixture('Ready_to_Assign');

        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Received');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Cancelled');

        User technician = getTestTechnician();
        Datetime scheduledVisit = System.now().addDays(1);

        Test.startTest();
        ManagerDispatchTechnicianController.DispatchResult result =
            ManagerDispatchTechnicianController.dispatchTechnician(
                fixture.workOrder.Id,
                technician.Id,
                scheduledVisit
            );
        Test.stopTest();

        System.assertEquals(
            'Assigned',
            result.workOrderStatus,
            'Received and Cancelled parts should not block technician dispatch.'
        );
    }

    // =========================================================
    // Helpers
    // =========================================================

    private static Fixture createFixture(String dispatchStatus) {

        Account account = new Account(Name = 'Dispatch Test Account');
        insert account;

        Asset asset = new Asset(
            Name = 'Dispatch Test Mill',
            AccountId = account.Id,
            Machine_Status__c = 'Needs Service',
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D'
        );
        insert asset;

        Case serviceCase = new Case(
            Subject = 'Dispatch technician test case',
            Status = 'In Progress',
            Origin = 'Web',
            AccountId = account.Id,
            AssetId = asset.Id,
            Work_Order_Proposal_Created__c = true
        );
        insert serviceCase;

        WorkOrder workOrder = new WorkOrder(
            Subject = 'Dispatch technician test Work Order',
            Status = 'New',
            Dispatch_Status__c = dispatchStatus,
            Priority = 'Medium',
            AccountId = account.Id,
            AssetId = asset.Id,
            CaseId = serviceCase.Id,
            Problem_Summary__c = 'Spindle is making an abnormal noise during operation.',
            Recommended_Fix_Summary__c = 'Inspect spindle assembly and verify operation.',
            Technician_Notes__c = 'Dispatch controller automated test data.'
        );
        insert workOrder;

        workOrder = [
            SELECT Id, WorkOrderNumber, Subject, Status, Dispatch_Status__c, Priority,
                AccountId, AssetId, CaseId, Problem_Summary__c, Recommended_Fix_Summary__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
            LIMIT 1
        ];

        Fixture fixture = new Fixture();
        fixture.account = account;
        fixture.asset = asset;
        fixture.serviceCase = serviceCase;
        fixture.workOrder = workOrder;

        return fixture;
    }

    private static Work_Order_Part__c createPart(Id workOrderId, Id assetId, String orderStatus) {

        partSequence++;

        Part_Catalog__c catalogPart = new Part_Catalog__c(
            Name = 'Dispatch Test Part ' + partSequence,
            Part_Number__c = 'DISPATCH-TEST-' + partSequence,
            Manufacturer__c = 'Roland',
            Compatible_Model__c = 'DWX-52D',
            Parts_Category__c = 'Calibration & Sensors',
            Active__c = true
        );
        insert catalogPart;

        Work_Order_Part__c part = new Work_Order_Part__c(
            Work_Order__c = workOrderId,
            Machine__c = assetId,
            Part_Catalog__c = catalogPart.Id,
            Quantity__c = 1,
            Order_Status__c = orderStatus
        );
        insert part;

        return part;
    }

    private static User getTestTechnician() {
        return [
            SELECT Id, Name
            FROM User
            WHERE LastName = :TECHNICIAN_LAST_NAME
                AND IsActive = true
                AND UserRole.DeveloperName = :TECHNICIAN_ROLE
            LIMIT 1
        ];
    }

    private static User getTestNonTechnician() {
        return [
            SELECT Id, Name
            FROM User
            WHERE LastName = :NON_TECHNICIAN_LAST_NAME
                AND IsActive = true
            LIMIT 1
        ];
    }

    private static Boolean technicianAppearsInOptions(
        List<ManagerDispatchTechnicianController.TechnicianOption> options,
        Id technicianId
    ) {
        for (ManagerDispatchTechnicianController.TechnicianOption option : options) {
            if (option.id == technicianId) return true;
        }

        return false;
    }

    private static void assertDispatchThrows(
        Id workOrderId,
        Id technicianId,
        Datetime scheduledVisit,
        String assertionMessage
    ) {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerDispatchTechnicianController.dispatchTechnician(
                workOrderId,
                technicianId,
                scheduledVisit
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assert(exceptionThrown, assertionMessage);
    }

    private class Fixture {
        Account account;
        Asset asset;
        Case serviceCase;
        WorkOrder workOrder;
    }
}