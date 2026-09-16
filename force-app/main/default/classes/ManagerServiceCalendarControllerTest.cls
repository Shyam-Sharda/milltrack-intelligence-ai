@IsTest
private class ManagerServiceCalendarControllerTest {

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
        Contact contactRecord = new Contact(AccountId = accountId, FirstName = 'Alex', LastName = lastName, Phone = '604-555-0100', Email = 'manager-calendar-test@example.com');
        insert contactRecord;
        return contactRecord;
    }


    private static Asset createAsset(Id accountId, String name, String manufacturer, String model, String serialNumber) {
        Asset assetRecord = new Asset(AccountId = accountId, Name = name, Manufacturer__c = manufacturer, Model__c = model, Serial_Number__c = serialNumber);
        insert assetRecord;
        return assetRecord;
    }


    private static Case createCase(Id accountId, Id contactId, Id assetId, String subject, String status) {
        Case caseRecord = new Case(
            AccountId = accountId,
            ContactId = contactId,
            AssetId = assetId,
            Subject = subject,
            Status = getActivePicklistValue(Schema.SObjectType.Case.fields.Status, status),
            Origin = getActivePicklistValue(Schema.SObjectType.Case.fields.Origin, 'Web'),
            Priority = 'Medium'
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
        Id technicianId
    ) {
        WorkOrder workOrderRecord = new WorkOrder(
            AccountId = accountId,
            AssetId = assetId,
            CaseId = caseId,
            Subject = subject,
            Status = getActivePicklistValue(Schema.SObjectType.WorkOrder.fields.Status, 'New'),
            Priority = 'Medium',
            Dispatch_Status__c = dispatchStatus,
            Scheduled_Visit__c = scheduledVisit,
            Suggested_Technician__c = technicianId,
            Problem_Summary__c = 'Machine demonstrates a repeatable service symptom during normal milling operation.',
            Recommended_Fix_Summary__c = 'Inspect the affected assembly and verify the condition before replacing parts.'
        );

        if (dispatchStatus == 'Completed' || dispatchStatus == 'Temporary Fix') workOrderRecord.Technician_Notes__c = 
        'Technician documented the service visit and findings for calendar testing.';

        insert workOrderRecord;
        return workOrderRecord;
    }


    private static Maintenance_Log__c createMaintenanceLog(
        Id assetId,
        Id workOrderId,
        Date maintenanceDate,
        String maintenanceType,
        Boolean issueResolved,
        Boolean followUpRequired,
        String repairSummary,
        String rootCause,
        Id technicianId,
        Decimal laborHours
    ) {
        Maintenance_Log__c logRecord = new Maintenance_Log__c(
            Asset__c = assetId,
            Work_Order__c = workOrderId,
            Maintenance_Date__c = maintenanceDate,
            Maintenance_Type__c = getActivePicklistValue(Schema.SObjectType.Maintenance_Log__c.fields.Maintenance_Type__c, maintenanceType),
            Problem_Summary__c = 'Machine demonstrates a repeatable service symptom during normal milling operation.',
            Summary__c = repairSummary,
            Root_Cause__c = rootCause,
            Issue_Resolved__c = issueResolved,
            Follow_Up_Required__c = followUpRequired,
            Performed_By__c = technicianId,
            Labor_Hours__c = laborHours
        );

        insert logRecord;
        return logRecord;
    }


    private static Datetime dateTimeOn(Date targetDate, Integer hour) {
        return Datetime.newInstance(targetDate, Time.newInstance(hour, 0, 0, 0));
    }


    private static ManagerServiceCalendarController.CalendarEventDTO findEvent(List<ManagerServiceCalendarController.CalendarEventDTO> events, String eventKey) {
        for (ManagerServiceCalendarController.CalendarEventDTO eventRecord : events) {
            if (eventRecord.eventKey == eventKey) return eventRecord;
        }

        return null;
    }


    // =========================================================
    // Main Calendar Data
    // =========================================================

    @IsTest
    static void returnsScheduledCurrentAndHistoricalVisitsForMonth() {
        Id technicianId = UserInfo.getUserId();

        Date monthStart = Date.today().toStartOfMonth().addMonths(1);
        Date scheduledDate = monthStart.addDays(5);
        Date inProgressDate = monthStart.addDays(8);
        Date completedDate = monthStart.addDays(10);
        Date temporaryDate = monthStart.addDays(12);
        Date followUpDate = monthStart.addDays(14);

        Account accountRecord = createAccount('Precision Dental Studio');
        Contact contactRecord = createContact(accountRecord.Id, 'Morgan');
        Asset assetRecord = createAsset(accountRecord.Id, 'DWX-52D Mill', 'Roland', 'DWX-52D', '52D-CAL-001');

        Case scheduledCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Scheduled spindle inspection', 'Scheduled');
        Case inProgressCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Active coolant repair', 'In Progress');
        Case completedCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Completed calibration repair', 'Closed');
        Case temporaryCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Temporary repair requiring return visit', 'Follow-Up Required');
        Case followUpCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Unresolved service visit', 'Follow-Up Required');

        WorkOrder scheduledWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, scheduledCase.Id, 'Inspect spindle vibration', 'Assigned', dateTimeOn(scheduledDate, 9), technicianId);
        WorkOrder inProgressWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, inProgressCase.Id, 'Repair coolant flow issue', 'In Progress', dateTimeOn(inProgressDate, 11), technicianId);
        WorkOrder completedWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, completedCase.Id, 'Complete calibration repair', 'Completed', null, technicianId);
        WorkOrder temporaryWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, temporaryCase.Id, 'Apply temporary spindle repair', 'Temporary Fix', null, technicianId);
        WorkOrder followUpWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, followUpCase.Id, 'Inspect unresolved tool sensor issue', 'Temporary Fix', null, technicianId);

        Maintenance_Log__c completedLog = createMaintenanceLog(
            assetRecord.Id,
            completedWorkOrder.Id,
            completedDate,
            'Repair',
            true,
            false,
            'Recalibrated the machine and verified successful milling operation.',
            'Calibration drift caused inaccurate milling.',
            technicianId,
            2
        );

        Maintenance_Log__c temporaryLog = createMaintenanceLog(
            assetRecord.Id,
            temporaryWorkOrder.Id,
            temporaryDate,
            'Temporary Repair',
            false,
            true,
            'Applied a temporary adjustment so production could continue until the follow-up visit.',
            null,
            technicianId,
            1.5
        );

        Maintenance_Log__c followUpLog = createMaintenanceLog(
            assetRecord.Id,
            followUpWorkOrder.Id,
            followUpDate,
            'Inspection',
            false,
            true,
            'Inspected the tool sensor and confirmed additional service is required.',
            null,
            technicianId,
            1
        );

        Test.startTest();
        ManagerServiceCalendarController.CalendarData data = ManagerServiceCalendarController.getCalendarData(monthStart.year(), monthStart.month());
        Test.stopTest();

        System.assertNotEquals(null, data, 'Calendar data should be returned.');
        System.assertEquals(monthStart.year(), data.year);
        System.assertEquals(monthStart.month(), data.month);
        System.assertEquals(monthStart, data.monthStart);
        System.assertEquals(monthStart.addMonths(1).addDays(-1), data.monthEnd);

        System.assertEquals(5, data.totalEvents, 'The calendar should contain two Work Order events and three Maintenance Log events.');
        System.assertEquals(1, data.scheduledCount, 'One Assigned visit should be counted as scheduled.');
        System.assertEquals(1, data.inProgressCount, 'One In Progress visit should be counted.');
        System.assertEquals(1, data.completedCount, 'One resolved Maintenance Log should be counted as completed.');
        System.assertEquals(2, data.followUpCount, 'Temporary repair and unresolved inspection both require follow-up.');
        System.assertEquals(1, data.temporaryRepairCount, 'Only the Temporary Repair Maintenance Log should count as a temporary repair.');

        ManagerServiceCalendarController.CalendarEventDTO scheduledEvent = findEvent(data.events, 'WO-' + scheduledWorkOrder.Id);
        System.assertNotEquals(null, scheduledEvent, 'Assigned Work Order should appear on the calendar.');
        System.assertEquals('WORK_ORDER', scheduledEvent.sourceType);
        System.assertEquals('SCHEDULED', scheduledEvent.outcomeKey);
        System.assertEquals('Scheduled Visit', scheduledEvent.outcomeLabel);
        System.assertEquals(scheduledDate, scheduledEvent.eventDate);
        System.assertEquals('Precision Dental Studio', scheduledEvent.accountName);
        System.assertEquals('Roland DWX-52D', scheduledEvent.machineLabel);
        System.assertEquals(UserInfo.getName(), scheduledEvent.technicianName);
        System.assertEquals(false, scheduledEvent.isHistoricalEvent);
        System.assertEquals(true, scheduledEvent.isScheduledEvent);

        ManagerServiceCalendarController.CalendarEventDTO inProgressEvent = findEvent(data.events, 'WO-' + inProgressWorkOrder.Id);
        System.assertNotEquals(null, inProgressEvent, 'In Progress Work Order should appear on the calendar.');
        System.assertEquals('IN_PROGRESS', inProgressEvent.outcomeKey);
        System.assertEquals('In Progress', inProgressEvent.outcomeLabel);

        ManagerServiceCalendarController.CalendarEventDTO completedEvent = findEvent(data.events, 'ML-' + completedLog.Id);
        System.assertNotEquals(null, completedEvent, 'Completed Maintenance Log should appear on the calendar.');
        System.assertEquals('MAINTENANCE_LOG', completedEvent.sourceType);
        System.assertEquals('COMPLETED', completedEvent.outcomeKey);
        System.assertEquals('Repair Completed', completedEvent.outcomeLabel);
        System.assertEquals(true, completedEvent.isResolved);
        System.assertEquals(false, completedEvent.followUpRequired);
        System.assertEquals('Recalibrated the machine and verified successful milling operation.', completedEvent.repairSummary);
        System.assertEquals('Calibration drift caused inaccurate milling.', completedEvent.rootCause);
        System.assertEquals(Decimal.valueOf('2'), completedEvent.laborHours);
        System.assertEquals(completedWorkOrder.Id, completedEvent.workOrderId);
        System.assertEquals(completedCase.Id, completedEvent.caseId, 'Historical event should retain the related Service Case.');
        System.assertNotEquals(null, completedEvent.caseNumber, 'Historical event should expose the related Case Number.');
        System.assertEquals(true, completedEvent.isHistoricalEvent);

        ManagerServiceCalendarController.CalendarEventDTO temporaryEvent = findEvent(data.events, 'ML-' + temporaryLog.Id);
        System.assertNotEquals(null, temporaryEvent, 'Temporary Repair Maintenance Log should appear on the calendar.');
        System.assertEquals('TEMPORARY_REPAIR', temporaryEvent.outcomeKey);
        System.assertEquals('Temporary Repair · Follow-Up Required', temporaryEvent.outcomeLabel);
        System.assertEquals(true, temporaryEvent.temporaryRepair);
        System.assertEquals(true, temporaryEvent.followUpRequired);
        System.assertEquals(false, temporaryEvent.isResolved);

        ManagerServiceCalendarController.CalendarEventDTO followUpEvent = findEvent(data.events, 'ML-' + followUpLog.Id);
        System.assertNotEquals(null, followUpEvent, 'Unresolved follow-up Maintenance Log should appear on the calendar.');
        System.assertEquals('FOLLOW_UP', followUpEvent.outcomeKey);
        System.assertEquals('Follow-Up Required', followUpEvent.outcomeLabel);
        System.assertEquals(true, followUpEvent.followUpRequired);
        System.assertEquals(false, followUpEvent.temporaryRepair);
    }


    // =========================================================
    // Month Filtering
    // =========================================================

    @IsTest
    static void onlyReturnsEventsInsideRequestedMonth() {
        Id technicianId = UserInfo.getUserId();

        Date monthStart = Date.today().toStartOfMonth();
        Date nextMonthStart = monthStart.addMonths(1);

        Account accountRecord = createAccount('Monthly Filter Dental');
        Contact contactRecord = createContact(accountRecord.Id, 'Monthly');
        Asset assetRecord = createAsset(accountRecord.Id, 'Motion 2 Mill', 'Amann Girrbach', 'Ceramill Motion 2', 'MOTION-CAL-001');

        Case currentMonthCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Current month visit', 'Scheduled');
        Case nextMonthCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Next month visit', 'Scheduled');

        WorkOrder currentMonthWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, currentMonthCase.Id, 'Current month scheduled visit', 'Assigned', dateTimeOn(monthStart.addDays(3), 10), technicianId);
        WorkOrder nextMonthWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, nextMonthCase.Id, 'Next month scheduled visit', 'Assigned', dateTimeOn(nextMonthStart.addDays(3), 10), technicianId);

        Test.startTest();
        ManagerServiceCalendarController.CalendarData data = ManagerServiceCalendarController.getCalendarData(monthStart.year(), monthStart.month());
        Test.stopTest();

        System.assertNotEquals(null, findEvent(data.events, 'WO-' + currentMonthWorkOrder.Id), 'Current-month visit should be returned.');
        System.assertEquals(null, findEvent(data.events, 'WO-' + nextMonthWorkOrder.Id), 'Next-month visit should not be returned.');
    }


    // =========================================================
    // Past Due Assigned Visit
    // =========================================================

    @IsTest
    static void marksPastAssignedVisitAsPastDue() {
        Id technicianId = UserInfo.getUserId();

        Date previousMonthStart = Date.today().toStartOfMonth().addMonths(-1);
        Date pastVisitDate = previousMonthStart.addDays(10);

        Account accountRecord = createAccount('Past Visit Dental');
        Contact contactRecord = createContact(accountRecord.Id, 'PastVisit');
        Asset assetRecord = createAsset(accountRecord.Id, 'Past DWX Mill', 'Roland', 'DWX-52D', 'PAST-CAL-001');
        Case caseRecord = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Past assigned technician visit', 'Scheduled');

        WorkOrder workOrderRecord = createWorkOrder(accountRecord.Id, assetRecord.Id, caseRecord.Id, 'Past scheduled service visit', 'Assigned', dateTimeOn(pastVisitDate, 9), technicianId);

        Test.startTest();
        ManagerServiceCalendarController.CalendarData data = ManagerServiceCalendarController.getCalendarData(previousMonthStart.year(), previousMonthStart.month());
        Test.stopTest();

        ManagerServiceCalendarController.CalendarEventDTO eventRecord = findEvent(data.events, 'WO-' + workOrderRecord.Id);

        System.assertNotEquals(null, eventRecord, 'Past Assigned Work Order should remain visible.');
        System.assertEquals(true, eventRecord.isPastDue);
        System.assertEquals('PAST_DUE', eventRecord.outcomeKey);
        System.assertEquals('Past Scheduled Visit', eventRecord.outcomeLabel);
        System.assertEquals(1, data.pastDueCount);
        System.assertEquals(0, data.scheduledCount);
    }


    // =========================================================
    // Event Ordering
    // =========================================================

    @IsTest
    static void sortsScheduledEventsChronologically() {
        Id technicianId = UserInfo.getUserId();

        Date futureMonthStart = Date.today().toStartOfMonth().addMonths(2);
        Date firstDate = futureMonthStart.addDays(4);
        Date secondDate = futureMonthStart.addDays(8);

        Account accountRecord = createAccount('Calendar Sorting Dental');
        Contact contactRecord = createContact(accountRecord.Id, 'Sorting');
        Asset assetRecord = createAsset(accountRecord.Id, 'Sorting Mill', 'Roland', 'DWX-52D', 'SORT-CAL-001');

        Case laterCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Later calendar visit', 'Scheduled');
        Case earlierCase = createCase(accountRecord.Id, contactRecord.Id, assetRecord.Id, 'Earlier calendar visit', 'Scheduled');

        WorkOrder laterWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, laterCase.Id, 'Later visit', 'Assigned', dateTimeOn(secondDate, 14), technicianId);
        WorkOrder earlierWorkOrder = createWorkOrder(accountRecord.Id, assetRecord.Id, earlierCase.Id, 'Earlier visit', 'Assigned', dateTimeOn(firstDate, 9), technicianId);

        Test.startTest();
        ManagerServiceCalendarController.CalendarData data = ManagerServiceCalendarController.getCalendarData(futureMonthStart.year(), futureMonthStart.month());
        Test.stopTest();

        System.assertEquals(2, data.events.size());
        System.assertEquals(earlierWorkOrder.Id, data.events[0].workOrderId, 'Earlier visit should sort first.');
        System.assertEquals(laterWorkOrder.Id, data.events[1].workOrderId, 'Later visit should sort second.');
    }


    // =========================================================
    // Empty Month
    // =========================================================

    @IsTest
    static void returnsEmptyCalendarWhenMonthHasNoEvents() {
        Date emptyMonth = Date.newInstance(2099, 6, 1);

        Test.startTest();
        ManagerServiceCalendarController.CalendarData data = ManagerServiceCalendarController.getCalendarData(emptyMonth.year(), emptyMonth.month());
        Test.stopTest();

        System.assertNotEquals(null, data);
        System.assertEquals(0, data.totalEvents);
        System.assertEquals(0, data.scheduledCount);
        System.assertEquals(0, data.pastDueCount);
        System.assertEquals(0, data.inProgressCount);
        System.assertEquals(0, data.completedCount);
        System.assertEquals(0, data.followUpCount);
        System.assertEquals(0, data.temporaryRepairCount);
        System.assertEquals(0, data.events.size());
    }


    // =========================================================
    // Validation
    // =========================================================

    @IsTest
    static void rejectsInvalidCalendarMonth() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerServiceCalendarController.getCalendarData(2026, 13);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Month 13 should be rejected.');
    }


    @IsTest
    static void rejectsInvalidCalendarYear() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerServiceCalendarController.getCalendarData(1800, 6);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Years outside the supported range should be rejected.');
    }
}