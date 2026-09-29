@IsTest
private class ManagerDispatchTechnicianControllerTest {
    private static final String TECHNICIAN_ROLE = 'MillTrack_Technician';
    private static final String TECHNICIAN_LAST_NAME = 'MillTrack Dispatch Technician Test';
    private static final String SECOND_TECHNICIAN_LAST_NAME = 'MillTrack Dispatch Technician Two';
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
        User secondTechnician = new User(
            Alias = 'mtdtech2',
            Email = 'dispatch.technician2@milltrack.test',
            EmailEncodingKey = 'UTF-8',
            LastName = SECOND_TECHNICIAN_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = systemAdministratorProfile.Id,
            TimeZoneSidKey = 'America/Toronto',
            Username = 'dispatch.technician2.' + uniqueValue + '@milltrack.test',
            CommunityNickname = 'mtdtech2' + String.valueOf(DateTime.now().getTime()),
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
        insert new List<User>{
            technician,
            secondTechnician,
            nonTechnician
        };
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
        System.assert(technicianAppearsInOptions(context.technicians, technician.Id), 'The active MillTrack technician should be returned as an assignment option.');
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
        System.assertEquals(false, context.eligible, 'Temporary Fix belongs to the manager follow-up workflow and must not be directly dispatchable.');
        System.assertNotEquals(null, context.ineligibleReason);
    }
    // =========================================================
    // Technician Schedule
    // =========================================================
    @IsTest
    static void getTechnicianScheduleReturnsAssignedAndInProgressVisits() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Date monthStart = Date.today().toStartOfMonth().addMonths(1);
        Datetime assignedVisit = Datetime.newInstance(monthStart.addDays(4), Time.newInstance(9, 0, 0, 0));
        Datetime inProgressVisit = Datetime.newInstance(monthStart.addDays(8), Time.newInstance(13, 30, 0, 0));
        WorkOrder assignedWorkOrder = createScheduledVisitWorkOrder(fixture, technician.Id, assignedVisit, 'Assigned', 'Assigned schedule visit');
        WorkOrder inProgressWorkOrder = createScheduledVisitWorkOrder(fixture, technician.Id, inProgressVisit, 'In Progress', 'In progress schedule visit');
        Test.startTest();
        ManagerDispatchTechnicianController.TechnicianScheduleData schedule =
            ManagerDispatchTechnicianController.getTechnicianSchedule(technician.Id, monthStart.year(), monthStart.month(), fixture.workOrder.Id);
        Test.stopTest();
        System.assertNotEquals(null, schedule);
        System.assertEquals(technician.Id, schedule.technicianId);
        System.assertEquals(technician.Name, schedule.technicianName);
        System.assertEquals(monthStart.year(), schedule.year);
        System.assertEquals(monthStart.month(), schedule.month);
        System.assertEquals(monthStart, schedule.monthStart);
        System.assertEquals(monthStart.addMonths(1).addDays(-1), schedule.monthEnd);
        System.assertEquals(2, schedule.visits.size(), 'Assigned and In Progress visits should appear in the technician schedule.');
        System.assert(scheduleContainsWorkOrder(schedule.visits, assignedWorkOrder.Id), 'Assigned Work Order should appear in the schedule.');
        System.assert(scheduleContainsWorkOrder(schedule.visits, inProgressWorkOrder.Id), 'In Progress Work Order should appear in the schedule.');
    }
    @IsTest
    static void getTechnicianScheduleReturnsCompletedRepairsForSelectedTechnician() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        User secondTechnician = getSecondTestTechnician();
        Date monthStart = Date.today().toStartOfMonth();
        WorkOrder completedWorkOrder = createScheduledVisitWorkOrder(
            fixture,
            technician.Id,
            Datetime.newInstance(monthStart.addDays(3), Time.newInstance(9, 0, 0, 0)),
            'Completed',
            'Completed repair history'
        );
        WorkOrder otherTechnicianWorkOrder = createScheduledVisitWorkOrder(
            fixture,
            secondTechnician.Id,
            Datetime.newInstance(monthStart.addDays(5), Time.newInstance(11, 0, 0, 0)),
            'Completed',
            'Other technician completed repair'
        );
        Maintenance_Log__c completedLog = createCompletedMaintenanceLog(completedWorkOrder, fixture.asset, technician.Id, monthStart.addDays(3));
        createCompletedMaintenanceLog(otherTechnicianWorkOrder, fixture.asset, secondTechnician.Id, monthStart.addDays(5));
        Test.startTest();
        ManagerDispatchTechnicianController.TechnicianScheduleData schedule =
            ManagerDispatchTechnicianController.getTechnicianSchedule(technician.Id, monthStart.year(), monthStart.month(), fixture.workOrder.Id);
        Test.stopTest();
        System.assertEquals(1, schedule.visits.size(), 'Only the selected technician\'s completed repair should be returned.');
        System.assertEquals(completedLog.Id, schedule.visits[0].maintenanceLogId);
        System.assertEquals(completedWorkOrder.Id, schedule.visits[0].workOrderId);
        System.assertEquals('Completed', schedule.visits[0].dispatchStatus);
        System.assertEquals('Completed', schedule.visits[0].visitType);
        System.assertEquals(monthStart.addDays(3), schedule.visits[0].visitDate);
        System.assertEquals(false, schedule.visits[0].blocksScheduling, 'Historical completed repairs must not block scheduling.');
        System.assertEquals(null, schedule.visits[0].scheduledVisit);
    }
    @IsTest
    static void getTechnicianScheduleFiltersCompletedRepairsByMonth() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Date monthStart = Date.today().toStartOfMonth();
        Date previousMonthStart = monthStart.addMonths(-1);
        WorkOrder currentMonthWorkOrder = createScheduledVisitWorkOrder(
            fixture,
            technician.Id,
            Datetime.newInstance(monthStart.addDays(4), Time.newInstance(9, 0, 0, 0)),
            'Completed',
            'Current month completed repair'
        );
        WorkOrder previousMonthWorkOrder = createScheduledVisitWorkOrder(
            fixture,
            technician.Id,
            Datetime.newInstance(previousMonthStart.addDays(4), Time.newInstance(9, 0, 0, 0)),
            'Completed',
            'Previous month completed repair'
        );
        Maintenance_Log__c currentMonthLog = createCompletedMaintenanceLog(currentMonthWorkOrder, fixture.asset, technician.Id, monthStart.addDays(4));
        createCompletedMaintenanceLog(previousMonthWorkOrder, fixture.asset, technician.Id, previousMonthStart.addDays(4));
        Test.startTest();
        ManagerDispatchTechnicianController.TechnicianScheduleData schedule =
            ManagerDispatchTechnicianController.getTechnicianSchedule(technician.Id, monthStart.year(), monthStart.month(), fixture.workOrder.Id);
        Test.stopTest();
        System.assertEquals(1, schedule.visits.size());
        System.assertEquals(currentMonthLog.Id, schedule.visits[0].maintenanceLogId);
        System.assertEquals(monthStart.addDays(4), schedule.visits[0].visitDate);
    }
    @IsTest
    static void getTechnicianScheduleFiltersByMonth() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Date monthStart = Date.today().toStartOfMonth().addMonths(1);
        Date nextMonthStart = monthStart.addMonths(1);
        WorkOrder currentMonthWorkOrder = createScheduledVisitWorkOrder(
            fixture,
            technician.Id,
            Datetime.newInstance(monthStart.addDays(5), Time.newInstance(10, 0, 0, 0)),
            'Assigned',
            'Current month visit'
        );
        WorkOrder nextMonthWorkOrder = createScheduledVisitWorkOrder(
            fixture,
            technician.Id,
            Datetime.newInstance(nextMonthStart.addDays(5), Time.newInstance(10, 0, 0, 0)),
            'Assigned',
            'Next month visit'
        );
        Test.startTest();
        ManagerDispatchTechnicianController.TechnicianScheduleData schedule =
            ManagerDispatchTechnicianController.getTechnicianSchedule(technician.Id, monthStart.year(), monthStart.month(), fixture.workOrder.Id);
        Test.stopTest();
        System.assert(scheduleContainsWorkOrder(schedule.visits, currentMonthWorkOrder.Id), 'Current-month visit should be returned.');
        System.assertEquals(false, scheduleContainsWorkOrder(schedule.visits, nextMonthWorkOrder.Id), 'Next-month visit should not be returned.');
    }
    @IsTest
    static void getTechnicianScheduleExcludesCurrentWorkOrder() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Datetime visitTime = System.now().addDays(5);
        fixture.workOrder.Suggested_Technician__c = technician.Id;
        fixture.workOrder.Scheduled_Visit__c = visitTime;
        fixture.workOrder.Dispatch_Status__c = 'Assigned';
        update fixture.workOrder;
        Test.startTest();
        ManagerDispatchTechnicianController.TechnicianScheduleData schedule =
            ManagerDispatchTechnicianController.getTechnicianSchedule(technician.Id, visitTime.year(), visitTime.month(), fixture.workOrder.Id);
        Test.stopTest();
        System.assertEquals(
            false,
            scheduleContainsWorkOrder(schedule.visits, fixture.workOrder.Id),
            'The Work Order currently being dispatched should be excluded from the availability calendar.'
        );
    }
    @IsTest
    static void getTechnicianScheduleRejectsInvalidTechnician() {
        User nonTechnician = getTestNonTechnician();
        Date currentMonth = Date.today().toStartOfMonth();
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ManagerDispatchTechnicianController.getTechnicianSchedule(nonTechnician.Id, currentMonth.year(), currentMonth.month(), null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'A non-technician user should not have a technician schedule.');
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
            ManagerDispatchTechnicianController.dispatchTechnician(fixture.workOrder.Id, technician.Id, scheduledVisit);
        Test.stopTest();
        WorkOrder updatedWorkOrder = [
            SELECT
                Id,
                OwnerId,
                Suggested_Technician__c,
                Scheduled_Visit__c,
                Dispatch_Status__c
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
        System.assertEquals(technician.Id, updatedWorkOrder.Suggested_Technician__c, 'Assigned Technician should be stored on Suggested_Technician__c.');
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
    // Scheduling Conflict Tests
    // =========================================================
    @IsTest
    static void dispatchTechnicianRejectsExactScheduledTimeConflict() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Datetime existingVisit = System.now().addDays(3);
        createScheduledVisitWorkOrder(fixture, technician.Id, existingVisit, 'Assigned', 'Existing exact-time visit');
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, existingVisit, 'The exact same scheduled time should be blocked.');
    }
    @IsTest
    static void dispatchTechnicianRejectsVisit15MinutesBefore() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Datetime existingVisit = System.now().addDays(3).addMinutes(30);
        createScheduledVisitWorkOrder(fixture, technician.Id, existingVisit, 'Assigned', 'Existing visit');
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, existingVisit.addMinutes(-15), 'A visit 15 minutes before another scheduled visit should be blocked.');
    }
    @IsTest
    static void dispatchTechnicianRejectsVisit15MinutesAfter() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Datetime existingVisit = System.now().addDays(3);
        createScheduledVisitWorkOrder(fixture, technician.Id, existingVisit, 'Assigned', 'Existing visit');
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, existingVisit.addMinutes(15), 'A visit 15 minutes after another scheduled visit should be blocked.');
    }
    @IsTest
    static void dispatchTechnicianRejectsExactly30MinutesBefore() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Datetime existingVisit = System.now().addDays(3).addHours(1);
        createScheduledVisitWorkOrder(fixture, technician.Id, existingVisit, 'Assigned', 'Existing visit');
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, existingVisit.addMinutes(-30), 'Exactly 30 minutes before another visit should still be blocked.');
    }
    @IsTest
    static void dispatchTechnicianRejectsExactly30MinutesAfter() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        Datetime existingVisit = System.now().addDays(3);
        createScheduledVisitWorkOrder(fixture, technician.Id, existingVisit, 'Assigned', 'Existing visit');
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, existingVisit.addMinutes(30), 'Exactly 30 minutes after another visit should still be blocked.');
    }
    @IsTest
    static void dispatchTechnicianAllows31MinutesBefore() {
        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Received');
        User technician = getTestTechnician();
        Datetime existingVisit = System.now().addDays(3).addHours(2);
        createScheduledVisitWorkOrder(fixture, technician.Id, existingVisit, 'Assigned', 'Existing visit');
        Datetime proposedVisit = existingVisit.addMinutes(-31);
        Test.startTest();
        ManagerDispatchTechnicianController.DispatchResult result =
            ManagerDispatchTechnicianController.dispatchTechnician(fixture.workOrder.Id, technician.Id, proposedVisit);
        Test.stopTest();
        System.assertEquals('Assigned', result.workOrderStatus, 'A visit more than 30 minutes before another visit should be allowed.');
    }
    @IsTest
    static void dispatchTechnicianAllows31MinutesAfter() {
        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Received');
        User technician = getTestTechnician();
        Datetime existingVisit = System.now().addDays(3);
        createScheduledVisitWorkOrder(fixture, technician.Id, existingVisit, 'Assigned', 'Existing visit');
        Datetime proposedVisit = existingVisit.addMinutes(31);
        Test.startTest();
        ManagerDispatchTechnicianController.DispatchResult result =
            ManagerDispatchTechnicianController.dispatchTechnician(fixture.workOrder.Id, technician.Id, proposedVisit);
        Test.stopTest();
        System.assertEquals('Assigned', result.workOrderStatus, 'A visit more than 30 minutes after another visit should be allowed.');
    }
    @IsTest
    static void dispatchTechnicianIgnoresOtherTechnicianSchedule() {
        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Received');
        User technician = getTestTechnician();
        User secondTechnician = getSecondTestTechnician();
        Datetime scheduledVisit = System.now().addDays(3);
        createScheduledVisitWorkOrder(fixture, secondTechnician.Id, scheduledVisit, 'Assigned', 'Other technician visit');
        Test.startTest();
        ManagerDispatchTechnicianController.DispatchResult result =
            ManagerDispatchTechnicianController.dispatchTechnician(fixture.workOrder.Id, technician.Id, scheduledVisit);
        Test.stopTest();
        System.assertEquals('Assigned', result.workOrderStatus, 'Another technician having a visit at the same time should not block this technician.');
    }
    // =========================================================
    // Validation Tests
    // =========================================================
    @IsTest
    static void dispatchTechnicianRejectsNullWorkOrderId() {
        User technician = getTestTechnician();
        assertDispatchThrows(null, technician.Id, System.now().addDays(1), 'A null Work Order ID should be rejected.');
    }
    @IsTest
    static void dispatchTechnicianRejectsNullTechnician() {
        Fixture fixture = createFixture('Ready_to_Assign');
        assertDispatchThrows(fixture.workOrder.Id, null, System.now().addDays(1), 'A technician must be selected.');
    }
    @IsTest
    static void dispatchTechnicianRejectsNullScheduledVisit() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, null, 'A scheduled visit is required.');
    }
    @IsTest
    static void dispatchTechnicianRejectsPastScheduledVisit() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User technician = getTestTechnician();
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, System.now().addDays(-1), 'A scheduled visit in the past should be rejected.');
    }
    @IsTest
    static void dispatchTechnicianRejectsNonTechnicianUser() {
        Fixture fixture = createFixture('Ready_to_Assign');
        User nonTechnician = getTestNonTechnician();
        assertDispatchThrows(fixture.workOrder.Id, nonTechnician.Id, System.now().addDays(1), 'A user outside the MillTrack Technician role should be rejected.');
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
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, System.now().addDays(1), 'A Work Order outside Ready to Assign should be rejected.');
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
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, System.now().addDays(1), 'An outstanding Ordered part should block dispatch.');
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
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, System.now().addDays(1), 'A Requested part should block dispatch.');
    }
    @IsTest
    static void dispatchTechnicianRejectsShippedPart() {
        Fixture fixture = createFixture('Ready_to_Assign');
        createPart(fixture.workOrder.Id, fixture.asset.Id, 'Shipped');
        User technician = getTestTechnician();
        assertDispatchThrows(fixture.workOrder.Id, technician.Id, System.now().addDays(1), 'A Shipped part should block dispatch until it is received.');
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
            ManagerDispatchTechnicianController.dispatchTechnician(fixture.workOrder.Id, technician.Id, scheduledVisit);
        Test.stopTest();
        System.assertEquals('Assigned', result.workOrderStatus, 'Received and Cancelled parts should not block technician dispatch.');
    }
    // =========================================================
    // Helpers
    // =========================================================
    private static Fixture createFixture(String dispatchStatus) {
        Account account = new Account(Name = 'Dispatch Test Account');
        insert account;
        Asset asset = new Asset(Name = 'Dispatch Test Mill', AccountId = account.Id, Machine_Status__c = 'Needs Service', Manufacturer__c = 'Roland', Model__c = 'DWX-52D');
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
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                Status,
                Dispatch_Status__c,
                Priority,
                AccountId,
                AssetId,
                CaseId,
                Problem_Summary__c,
                Recommended_Fix_Summary__c
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
    private static WorkOrder createScheduledVisitWorkOrder(Fixture fixture, Id technicianId, Datetime scheduledVisit, String dispatchStatus, String subject) {
        Case scheduledCase = new Case(
            Subject = subject + ' case',
            Status = 'Scheduled',
            Origin = 'Web',
            AccountId = fixture.account.Id,
            AssetId = fixture.asset.Id,
            Work_Order_Proposal_Created__c = true
        );
        insert scheduledCase;
        WorkOrder scheduledWorkOrder = new WorkOrder(
            Subject = subject,
            Status = 'New',
            Dispatch_Status__c = dispatchStatus,
            Priority = 'Medium',
            AccountId = fixture.account.Id,
            AssetId = fixture.asset.Id,
            CaseId = scheduledCase.Id,
            Suggested_Technician__c = technicianId,
            OwnerId = technicianId,
            Scheduled_Visit__c = scheduledVisit,
            Problem_Summary__c = 'Scheduled technician availability test.',
            Recommended_Fix_Summary__c = 'Perform the approved service procedure.',
            Technician_Notes__c = 'Technician scheduling test data.'
        );
        insert scheduledWorkOrder;
        return [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                Dispatch_Status__c,
                Suggested_Technician__c,
                Scheduled_Visit__c
            FROM WorkOrder
            WHERE Id = :scheduledWorkOrder.Id
            LIMIT 1
        ];
    }
    private static Maintenance_Log__c createCompletedMaintenanceLog(WorkOrder workOrder, Asset asset, Id technicianId, Date maintenanceDate) {
        Maintenance_Log__c logRecord = new Maintenance_Log__c(
            Asset__c = asset.Id,
            Work_Order__c = workOrder.Id,
            Maintenance_Date__c = maintenanceDate,
            Maintenance_Type__c = 'Repair',
            Problem_Summary__c = 'Historical completed repair test.',
            Summary__c = 'Completed repair and verified machine operation.',
            Root_Cause__c = 'Test root cause.',
            Parts_Used__c = 'No replacement parts required',
            Labor_Hours__c = 1.5,
            Issue_Resolved__c = true,
            Follow_Up_Required__c = false,
            Performed_By__c = technicianId
        );
        insert logRecord;
        return logRecord;
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
        Work_Order_Part__c part = new Work_Order_Part__c(Work_Order__c = workOrderId, Machine__c = assetId, Part_Catalog__c = catalogPart.Id, Quantity__c = 1, Order_Status__c = orderStatus);
        insert part;
        return part;
    }
    private static User getTestTechnician() {
        return [
            SELECT Id, Name
            FROM User
            WHERE
                LastName = :TECHNICIAN_LAST_NAME
                AND IsActive = true
                AND UserRole.DeveloperName = :TECHNICIAN_ROLE
            LIMIT 1
        ];
    }
    private static User getSecondTestTechnician() {
        return [
            SELECT Id, Name
            FROM User
            WHERE
                LastName = :SECOND_TECHNICIAN_LAST_NAME
                AND IsActive = true
                AND UserRole.DeveloperName = :TECHNICIAN_ROLE
            LIMIT 1
        ];
    }
    private static User getTestNonTechnician() {
        return [
            SELECT Id, Name
            FROM User
            WHERE
                LastName = :NON_TECHNICIAN_LAST_NAME
                AND IsActive = true
            LIMIT 1
        ];
    }
    private static Boolean technicianAppearsInOptions(List<ManagerDispatchTechnicianController.TechnicianOption> options, Id technicianId) {
        for (ManagerDispatchTechnicianController.TechnicianOption option : options) {
            if (option.id == technicianId) return true;
        }
        return false;
    }
    private static Boolean scheduleContainsWorkOrder(List<ManagerDispatchTechnicianController.TechnicianScheduleVisit> visits, Id workOrderId) {
        for (ManagerDispatchTechnicianController.TechnicianScheduleVisit visit : visits) {
            if (visit.workOrderId == workOrderId) return true;
        }
        return false;
    }
    private static void assertDispatchThrows(Id workOrderId, Id technicianId, Datetime scheduledVisit, String assertionMessage) {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ManagerDispatchTechnicianController.dispatchTechnician(workOrderId, technicianId, scheduledVisit);
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
