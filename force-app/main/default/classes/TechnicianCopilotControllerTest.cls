@IsTest
private class TechnicianCopilotControllerTest {

    @TestSetup
    static void createTestData() {
        Account customerAccount = new Account(
            Name = 'MillTrack Test Dental Lab',
            Phone = '555-0100',
            BillingStreet = '100 Milling Avenue',
            BillingCity = 'Toronto',
            BillingState = 'Ontario',
            BillingPostalCode = 'M1M 1M1',
            BillingCountry = 'Canada'
        );
        insert customerAccount;

        Contact customerContact = new Contact(
            FirstName = 'Test',
            LastName = 'Customer',
            Email = 'customer@example.com',
            Phone = '555-0101',
            Title = 'Lab Manager',
            AccountId = customerAccount.Id
        );
        insert customerContact;

        Asset machine = new Asset(
            Name = 'MillTrack Test Milling Machine',
            AccountId = customerAccount.Id,
            ContactId = customerContact.Id
        );

        setFieldIfCreateable(machine, 'Serial_Number__c', 'MT-TEST-1001');

        setFieldIfCreateable(machine, 'Manufacturer__c', getUsableFieldValue(Asset.SObjectType, 'Manufacturer__c', 'Roland' ));

        setFieldIfCreateable(machine, 'Model__c', 'DWX Test Model');

        setFieldIfCreateable(machine,'Machine_Status__c', getUsableFieldValue(Asset.SObjectType, 'Machine_Status__c', 'Operational'));

        setFieldIfCreateable(machine, 'Description', 'Test dental milling equipment.');

        insert machine;

        Case serviceCase = new Case(
            Subject = 'Spindle vibration during milling',
            Description ='The customer reports vibration and reduced milling accuracy.',
            Status = getActivePicklistValue(Case.Status.getDescribe(),'New'),
            Origin = getActivePicklistValue(Case.Origin.getDescribe(), 'Web'),
            Priority = getActivePicklistValue(Case.Priority.getDescribe(), 'Medium'),
            AccountId = customerAccount.Id,
            ContactId = customerContact.Id,
            AssetId = machine.Id
        );
        insert serviceCase;

        /*
         * Previous Work Order:
         * Used only to prove that Asset maintenance history excludes the current Work Order and returns earlier repairs.
         */
        WorkOrder previousWorkOrder = buildWorkOrder(
            customerAccount.Id,
            customerContact.Id,
            serviceCase.Id,
            machine.Id,
            'Previous spindle service'
        );
        insert previousWorkOrder;

        /*
         * Current Work Order:
         * This is the record passed to TechnicianCopilotController.
         */
        WorkOrder currentWorkOrder = buildWorkOrder(
            customerAccount.Id,
            customerContact.Id,
            serviceCase.Id,
            machine.Id,
            'Diagnose spindle vibration'
        );

        setFieldIfCreateable(currentWorkOrder, 'Dispatch_Status__c',
            getUsableFieldValue(WorkOrder.SObjectType, 'Dispatch_Status__c', 'Assigned')
        );

        setFieldIfCreateable(currentWorkOrder, 'Resolution_Status__c',
            getUsableFieldValue(WorkOrder.SObjectType, 'Resolution_Status__c', null)
        );

        setFieldIfCreateable(currentWorkOrder, 'Problem_Summary__c', 'The spindle vibrates during milling operations.');
        setFieldIfCreateable(currentWorkOrder, 'Recommended_Solution__c', 'Inspect the spindle belt and bearings for wear.');
        setFieldIfCreateable(currentWorkOrder, 'Recommended_Fix_Summary__c', 'Replace the worn spindle components and verify smooth milling operation.');
        setFieldIfCreateable(currentWorkOrder, 'Recommended_Parts__c', 'Spindle bearing kit');
        setFieldIfCreateable(currentWorkOrder, 'Recommended_Tools__c', 'Torque wrench, hex key set, dial indicator');
        setFieldIfCreateable(currentWorkOrder, 'Previous_Failure__c', true);
        setFieldIfCreateable(currentWorkOrder, 'AI_Dispatch_Summary__c', 'Inspect spindle alignment, belt tension, and bearing movement.');
        setFieldIfCreateable(currentWorkOrder, 'Dispatch_Response__c', 'Likely mechanical wear in the spindle assembly.');
        setFieldIfCreateable(currentWorkOrder, 'Technician_Notes__c', 'Initial technician notes.');
        setFieldIfCreateable(currentWorkOrder, 'Labor_Hours__c', Decimal.valueOf('1.5'));
        setFieldIfCreateable(currentWorkOrder, 'Suggested_Technician__c', UserInfo.getUserId());
        setFieldIfCreateable(currentWorkOrder, 'Service_Manager__c', UserInfo.getUserId());

        insert currentWorkOrder;

        /*
         * Current Work Order activity.
         */
        SObject currentActivity = buildMaintenanceLog(
            currentWorkOrder.Id,
            machine.Id,
            'Current Work Order Inspection',
            'Inspection',
            Date.today(),
            'The technician inspected the spindle assembly.'
        );
        insert currentActivity;

        /*
         * Previous Asset repair.
         */
        SObject previousRepair = buildMaintenanceLog(
            previousWorkOrder.Id,
            machine.Id,
            'Previous Spindle Repair',
            'Corrective',
            Date.today().addDays(-90),
            'The spindle belt was replaced during a previous visit.'
        );
        insert previousRepair;

        createPartData(currentWorkOrder.Id, machine.Id);
    }


    /*
     * ============================================================
     * PRIMARY SUCCESS TEST
     * ============================================================
     */

    @IsTest
    static void getCopilotContextReturnsCompleteContext() {
        WorkOrder currentWorkOrder = [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                AccountId,
                ContactId,
                CaseId,
                AssetId
            FROM WorkOrder
            WHERE Subject = 'Diagnose spindle vibration'
            LIMIT 1
        ];

        Test.startTest();
        TechnicianCopilotController.CopilotResponse response = TechnicianCopilotController.getCopilotContext(currentWorkOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, response, 'The controller should return a response.');
        System.assertEquals(currentWorkOrder.Id, response.workOrderId, 'The response should contain the requested Work Order ID.');
        System.assertNotEquals(null, response.workOrder, 'Work Order information should be returned.');
        System.assertEquals(currentWorkOrder.Id, response.workOrder.id);
        System.assertEquals(currentWorkOrder.WorkOrderNumber, response.workOrder.workOrderNumber);
        System.assertEquals('Diagnose spindle vibration', response.workOrder.subject);
        System.assertEquals('The spindle vibrates during milling operations.', response.workOrder.problemSummary);
        System.assertEquals('Inspect the spindle belt and bearings for wear.', response.workOrder.recommendedSolution);
        System.assertEquals('Replace the worn spindle components and verify smooth milling operation.', response.workOrder.recommendedFixSummary);
        System.assertEquals('Spindle bearing kit', response.workOrder.recommendedParts);
        System.assertEquals('Torque wrench, hex key set, dial indicator', response.workOrder.recommendedTools);
        System.assertEquals('Initial technician notes.', response.workOrder.technicianNotes);
        System.assertEquals(Decimal.valueOf('1.5'), response.workOrder.laborHours);
        System.assertNotEquals(null, response.asset, 'Asset information should be returned.');
        System.assertEquals('MillTrack Test Milling Machine', response.asset.name);
        System.assertEquals('MT-TEST-1001', response.asset.serialNumber);
        System.assertNotEquals(null, response.account, 'Account information should be returned.');
        System.assertEquals('MillTrack Test Dental Lab', response.account.name);
        System.assertNotEquals(null, response.contact, 'Contact information should be returned.');
        System.assertEquals('customer@example.com', response.contact.email);
        System.assertNotEquals(null, response.caseRecord, 'Case information should be returned.');
        System.assertEquals('Spindle vibration during milling', response.caseRecord.subject);
        System.assertNotEquals(null, response.assignedTechnician, 'Assigned technician information should be returned.');
        System.assertEquals(UserInfo.getUserId(), response.assignedTechnician.id);
        System.assertNotEquals(null, response.serviceManager, 'Service manager information should be returned.');
        System.assertEquals(UserInfo.getUserId(), response.serviceManager.id);
        System.assertNotEquals(null, response.summary, 'Summary flags should be returned.');
    }


    /*
     * ============================================================
     * CURRENT WORK ORDER ACTIVITY
     * ============================================================
     */

    @IsTest
    static void returnsOnlyCurrentWorkOrderActivity() {
        WorkOrder currentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Diagnose spindle vibration'
            LIMIT 1
        ];

        Test.startTest();
        TechnicianCopilotController.CopilotResponse response = TechnicianCopilotController.getCopilotContext(currentWorkOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, response.maintenanceLogs);
        System.assertEquals(1, response.maintenanceLogs.size(), 'Current Work Order activity should contain only its own log.');
        System.assertEquals(currentWorkOrder.Id, response.maintenanceLogs[0].workOrderId);
        System.assertEquals('The technician inspected the spindle assembly.', response.maintenanceLogs[0].summary);
        System.assertEquals(true, response.summary.hasCurrentWorkOrderActivity, 'The summary should indicate current Work Order activity.');
        System.assertEquals(1, response.summary.maintenanceLogCount);
    }


    /*
     * ============================================================
     * ASSET MAINTENANCE HISTORY
     * ============================================================
     */

    @IsTest
    static void returnsPreviousAssetHistoryAndExcludesCurrentWorkOrder() {
        WorkOrder currentWorkOrder = [
            SELECT Id, AssetId
            FROM WorkOrder
            WHERE Subject = 'Diagnose spindle vibration'
            LIMIT 1
        ];

        Test.startTest();
        TechnicianCopilotController.CopilotResponse response = TechnicianCopilotController.getCopilotContext(currentWorkOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, response.assetMaintenanceHistory);
        System.assertEquals(1, response.assetMaintenanceHistory.size(), 'Asset history should include the previous repair and exclude the current Work Order activity.');

        for (TechnicianCopilotController.MaintenanceLogInfo historyItem : response.assetMaintenanceHistory) {
            System.assertNotEquals(currentWorkOrder.Id, historyItem.workOrderId, 'Current Work Order logs must not appear in previous Asset history.');
            System.assertEquals(currentWorkOrder.AssetId, historyItem.assetId, 'Each historical record should belong to the same Asset.');
        }

        System.assertEquals(true, response.summary.hasAssetMaintenanceHistory);
        System.assertEquals(1, response.summary.assetMaintenanceHistoryCount);
    }


    /*
     * ============================================================
     * WORK ORDER PARTS
     * ============================================================
     */

    @IsTest
    static void returnsWorkOrderParts() {
        WorkOrder currentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Diagnose spindle vibration'
            LIMIT 1
        ];

        Test.startTest();
        TechnicianCopilotController.CopilotResponse response = TechnicianCopilotController.getCopilotContext(currentWorkOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, response.workOrderParts);
        System.assertEquals(1, response.workOrderParts.size(), 'One Work Order Part should be returned.');

        TechnicianCopilotController.WorkOrderPartInfo partInfo = response.workOrderParts[0];

        System.assertEquals(currentWorkOrder.Id, partInfo.workOrderId);
        System.assertEquals(Decimal.valueOf('1'), partInfo.quantity);
        System.assertEquals(Decimal.valueOf('0'), partInfo.quantityUsed);
        System.assertEquals(true, response.summary.hasParts);
        System.assertEquals(1, response.summary.partCount);
    }


    /*
     * ============================================================
     * SUMMARY FLAGS
     * ============================================================
     */

    @IsTest
    static void buildsExpectedSummaryFlags() {
        WorkOrder currentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Diagnose spindle vibration'
            LIMIT 1
        ];

        Test.startTest();
        TechnicianCopilotController.CopilotResponse response = TechnicianCopilotController.getCopilotContext(currentWorkOrder.Id);
        Test.stopTest();

        TechnicianCopilotController.CopilotSummary summary = response.summary;

        System.assertEquals(true, summary.hasWorkOrder);
        System.assertEquals(true, summary.hasAsset);
        System.assertEquals(true, summary.hasCustomer);
        System.assertEquals(true, summary.hasCase);
        System.assertEquals(true, summary.hasAiDiagnosis);
        System.assertEquals(true, summary.hasIssueSummary);
        System.assertEquals(true, summary.hasRecommendedSolution);
        System.assertEquals(true, summary.hasRecommendedFixSummary);
        System.assertEquals(true, summary.hasRecommendedTools);
        System.assertEquals(true, summary.hasCurrentWorkOrderActivity);
        System.assertEquals(true, summary.hasAssetMaintenanceHistory);
        System.assertEquals(true, summary.hasParts);
    }


    /*
     * ============================================================
     * MISSING OPTIONAL RELATIONSHIPS
     * ============================================================
     */

    @IsTest
    static void handlesMissingOptionalRelatedRecords() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'MillTrack Test Dental Lab'
            LIMIT 1
        ];

        WorkOrder minimalWorkOrder = buildWorkOrder(
            accountRecord.Id,
            null,
            null,
            null,
            'Minimal Copilot Work Order'
        );
        insert minimalWorkOrder;

        Test.startTest();
        TechnicianCopilotController.CopilotResponse response = TechnicianCopilotController.getCopilotContext(minimalWorkOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertNotEquals(null, response.workOrder);
        System.assertEquals(null, response.asset, 'A missing Asset should not cause the controller to fail.');
        System.assertEquals(null, response.contact, 'A missing Contact should not cause the controller to fail.');
        System.assertEquals(null, response.caseRecord, 'A missing Case should not cause the controller to fail.');
        System.assertEquals(false, response.summary.hasAsset);
        System.assertEquals(false, response.summary.hasCase);
        System.assertEquals(false, response.summary.hasRecommendedFixSummary);
        System.assertEquals(0, response.assetMaintenanceHistory.size());
        System.assertEquals(0, response.maintenanceLogs.size());
        System.assertEquals(0, response.workOrderParts.size());
    }


    /*
     * ============================================================
     * VALIDATION
     * ============================================================
     */

    @IsTest
    static void rejectsNullWorkOrderId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            TechnicianCopilotController.getCopilotContext(null);
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A null Work Order ID should throw AuraHandledException.');
    }


    @IsTest
    static void rejectsNonWorkOrderId() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'MillTrack Test Dental Lab'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            TechnicianCopilotController.getCopilotContext(accountRecord.Id);
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A non-Work-Order ID should throw AuraHandledException.');
    }


    /*
     * ============================================================
     * READ-ONLY BEHAVIOR
     * ============================================================
     */

    @IsTest
    static void controllerDoesNotModifyWorkOrder() {
        WorkOrder currentWorkOrder = [
            SELECT Id, Subject, Description, LastModifiedDate
            FROM WorkOrder
            WHERE Subject = 'Diagnose spindle vibration'
            LIMIT 1
        ];

        String originalSubject = currentWorkOrder.Subject;
        String originalDescription = currentWorkOrder.Description;
        Datetime originalModifiedDate = currentWorkOrder.LastModifiedDate;

        Test.startTest();
        TechnicianCopilotController.getCopilotContext(currentWorkOrder.Id);
        Test.stopTest();

        WorkOrder workOrderAfterCall = [
            SELECT Subject, Description, LastModifiedDate
            FROM WorkOrder
            WHERE Id = :currentWorkOrder.Id
        ];

        System.assertEquals(originalSubject, workOrderAfterCall.Subject);
        System.assertEquals(originalDescription, workOrderAfterCall.Description);
        System.assertEquals(originalModifiedDate, workOrderAfterCall.LastModifiedDate, 'The read-only controller should not modify the Work Order.');
    }


    /*
     * ============================================================
     * TEST DATA FACTORIES
     * ============================================================
     */

    private static WorkOrder buildWorkOrder(Id accountId, Id contactId, Id caseId, Id assetId, String subject) {
        WorkOrder workOrderRecord = new WorkOrder();

        workOrderRecord.Subject = subject;
        workOrderRecord.Description = 'Test Work Order created for Technician Copilot testing.';
        workOrderRecord.Status = getActivePicklistValue(WorkOrder.Status.getDescribe(), null);
        workOrderRecord.Priority = getActivePicklistValue(WorkOrder.Priority.getDescribe(), 'Medium');
        workOrderRecord.AccountId = accountId;
        workOrderRecord.ContactId = contactId;
        workOrderRecord.CaseId = caseId;
        workOrderRecord.AssetId = assetId;

        /*
         * Some Salesforce org configurations require StartDate.
         */
        setFieldIfCreateable(workOrderRecord, 'StartDate', System.now());

        return workOrderRecord;
    }


    private static SObject buildMaintenanceLog(
        Id workOrderId,
        Id assetId,
        String recordName,
        String preferredMaintenanceType,
        Date maintenanceDate,
        String summary
    ) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get('Maintenance_Log__c');

        System.assertNotEquals(null, objectType, 'Maintenance_Log__c must exist in the org.');

        SObject maintenanceLog = objectType.newSObject();

        setNameIfWritable(maintenanceLog, recordName);
        setFieldIfCreateable(maintenanceLog, 'Work_Order__c', workOrderId);
        setFieldIfCreateable(maintenanceLog, 'Asset__c', assetId);
        setFieldIfCreateable(maintenanceLog, 'Maintenance_Date__c',maintenanceDate);
        setFieldIfCreateable(maintenanceLog,'Maintenance_Type__c',
            getUsableFieldValue(objectType, 'Maintenance_Type__c', preferredMaintenanceType));

        setFieldIfCreateable(maintenanceLog, 'Performed_By__c', UserInfo.getUserId());
        setFieldIfCreateable(maintenanceLog, 'Summary__c', summary);
        setFieldIfCreateable(maintenanceLog, 'Root_Cause__c', 'Test root cause');
        setFieldIfCreateable(maintenanceLog, 'Technician_Notes__c', 'Test technician notes');
        setFieldIfCreateable(maintenanceLog, 'Parts_Used__c', 'Test spindle component');
        setFieldIfCreateable(maintenanceLog, 'Labor_Hours__c', Decimal.valueOf('2'));
        setFieldIfCreateable(maintenanceLog, 'Issue_Resolved__c', true);
        setFieldIfCreateable(maintenanceLog, 'Follow_Up_Required__c', false);

        return maintenanceLog;
    }


    private static void createPartData(Id workOrderId, Id assetId) {
        Schema.SObjectType catalogType = Schema.getGlobalDescribe().get('Part_Catalog__c');

        System.assertNotEquals(null, catalogType, 'Part_Catalog__c must exist in the org.');

        SObject catalogPart = catalogType.newSObject();

        setNameIfWritable(catalogPart, 'Test Spindle Bearing Kit');
        setFieldIfCreateable(catalogPart, 'Description__c', 'Replacement spindle bearing kit for testing.');
        setFieldIfCreateable(catalogPart, 'Part_Number__c', 'TEST-PART-001');
        setFieldIfCreateable(catalogPart, 'Manufacturer__c', getUsableFieldValue(catalogType, 'Manufacturer__c', 'Roland'));

        insert catalogPart;

        Schema.SObjectType partType = Schema.getGlobalDescribe().get('Work_Order_Part__c');

        System.assertNotEquals(null, partType, 'Work_Order_Part__c must exist in the org.');

        SObject workOrderPart = partType.newSObject();

        setNameIfWritable(workOrderPart, 'Test Work Order Part');
        setFieldIfCreateable(workOrderPart, 'Work_Order__c', workOrderId);
        setFieldIfCreateable(workOrderPart, 'Part_Catalog__c', catalogPart.Id);
        setFieldIfCreateable(workOrderPart, 'Quantity_Needed__c', Decimal.valueOf('1'));
        setFieldIfCreateable(workOrderPart, 'Quantity__c', Decimal.valueOf('1'));
        setFieldIfCreateable(workOrderPart, 'Quantity_Used__c', Decimal.valueOf('0'));
        setFieldIfCreateable(workOrderPart, 'Order_Status__c', getUsableFieldValue(partType, 'Order_Status__c', 'Requested'));
        setFieldIfCreateable(workOrderPart, 'Ordered_By__c', UserInfo.getUserId());
        setFieldIfCreateable(workOrderPart, 'Supplier_Name__c', 'MillTrack Test Supplier');
        setFieldIfCreateable(workOrderPart, 'Supplier_Phone__c', '555-0102');
        setFieldIfCreateable(workOrderPart, 'Order_URL__c', 'https://example.com/test-part');
        setFieldIfCreateable(workOrderPart, 'Notes__c', 'Test requested component.');
        setFieldIfCreateable(workOrderPart, 'Machine__c', assetId);

        insert workOrderPart;
    }


    /*
     * ============================================================
     * DYNAMIC FIELD HELPERS
     * ============================================================
     */

    private static void setNameIfWritable(SObject record, String value) {
        Map<String, Schema.SObjectField> fieldMap =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fieldMap.containsKey('Name')) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldMap.get('Name').getDescribe();

        if (fieldDescribe.isCreateable() && !fieldDescribe.isAutoNumber()) {
            record.put('Name', value);
        }
    }


    private static void setFieldIfCreateable(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fieldMap.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();

        if (fieldDescribe.isCreateable() && !fieldDescribe.isCalculated() && !fieldDescribe.isAutoNumber()) {
            record.put(fieldApiName, value);
        }
    }


    private static Object getUsableFieldValue(Schema.SObjectType objectType, String fieldApiName, Object preferredValue) {
        if (objectType == null || String.isBlank(fieldApiName)) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
 
        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();

        if (fieldDescribe.getType() ==Schema.DisplayType.Picklist
        ) {
            return getActivePicklistValue(fieldDescribe, preferredValue == null ? null : String.valueOf(preferredValue));
        }

        return preferredValue;
    }


    private static String getActivePicklistValue(Schema.DescribeFieldResult fieldDescribe, String preferredValue) {
        if (fieldDescribe == null) {
            return preferredValue;
        }

        List<Schema.PicklistEntry> entries = fieldDescribe.getPicklistValues();

        if (!String.isBlank(preferredValue)) {
            for (Schema.PicklistEntry entry : entries) {
                if (entry.isActive() && entry.getValue() == preferredValue) {
                    return preferredValue;
                }
            }
        }

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return preferredValue;
    }
}