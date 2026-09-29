@IsTest
private class ManagerFollowUpWorkOrderControllerTest {

    private static final String WO_SUBJECT = 'Follow-Up Test Work Order';
    private static final String PROBLEM = 'Machine produces excessive vibration during milling.';
    private static final String PREVIOUS_FIX = 'Inspect the spindle and correction jig under load before replacing components.';
    private static final String PREVIOUS_TOOLS = 'Allen Keys\nMultimeter';
    private static final String LATEST_VISIT = 'Inspected the correction jig and spindle. Temporary stabilization reduced vibration, but permanent follow-up repair is required.';
    private static final String EXISTING_PART_NUMBER = 'FUP-EXIST-001';
    private static final String NEW_PART_NUMBER = 'FUP-NEW-001';

    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Follow-Up Test Dental Lab');
        insert account;

        Contact contact = new Contact(
            FirstName = 'Jamie',
            LastName = 'Followup',
            AccountId = account.Id,
            Email = 'followup@milltrack.test',
            Phone = '555-111-2222',
            Title = 'Lab Manager'
        );
        insert contact;

        Asset asset = new Asset(
            Name = 'Follow-Up Test DWX-52D',
            AccountId = account.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Serial_Number__c = 'FUP-001',
            Machine_Status__c = 'Needs Service'
        );
        insert asset;

        Case serviceCase = new Case(
            AccountId = account.Id,
            ContactId = contact.Id,
            AssetId = asset.Id,
            Subject = 'Excessive milling vibration',
            Status = 'Follow-Up Required',
            Priority = 'Medium',
            Origin = getFirstActivePicklistValue(Schema.SObjectType.Case.fields.Origin),
            Work_Order_Proposal_Created__c = true
        );
        insert serviceCase;

        asset.Machine_Status__c = 'Temporary Fix Applied';
        update asset;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            ContactId = contact.Id,
            AssetId = asset.Id,
            CaseId = serviceCase.Id,
            Subject = WO_SUBJECT,
            Priority = 'Medium',
            Dispatch_Status__c = 'Temporary Fix',
            Problem_Summary__c = PROBLEM,
            Recommended_Fix_Summary__c = PREVIOUS_FIX,
            Recommended_Tools__c = PREVIOUS_TOOLS,
            Technician_Notes__c = 'TEMPORARY REPAIR / FOLLOW-UP\n\nVisit Summary:\n' + LATEST_VISIT + '\n\nLabor Hours:\n1.5',
            Service_Manager__c = UserInfo.getUserId()
        );
        workOrder.Status = getFirstActivePicklistValue(Schema.SObjectType.WorkOrder.fields.Status);
        insert workOrder;

        Part_Catalog__c existingPart = buildCatalogPart('Existing Correction Jig', EXISTING_PART_NUMBER);
        Part_Catalog__c newPart = buildCatalogPart('Replacement Spindle Belt', NEW_PART_NUMBER);
        insert new List<Part_Catalog__c>{ existingPart, newPart };

        insert new Work_Order_Part__c(
            Work_Order__c = workOrder.Id,
            Machine__c = asset.Id,
            Part_Catalog__c = existingPart.Id,
            Quantity__c = 1,
            Order_Status__c = 'Received',
            Technician_Requested__c = false,
            Notes__c = 'Part received before the previous technician visit.'
        );

        insert new List<Tool_Catalog__c>{
            new Tool_Catalog__c(Name = 'Multimeter'),
            new Tool_Catalog__c(Name = 'Allen Keys'),
            new Tool_Catalog__c(Name = 'Phillips Head Screwdriver')
        };

        Maintenance_Log__c olderLog = new Maintenance_Log__c(
            Asset__c = asset.Id,
            Work_Order__c = workOrder.Id,
            Maintenance_Date__c = Date.today().addDays(-3),
            Maintenance_Type__c = 'Temporary Repair',
            Problem_Summary__c = PROBLEM,
            Recommended_Fix_Snapshot__c = 'Older repair recommendation.',
            Tools_To_Bring_Snapshot__c = 'Older tools',
            Summary__c = 'Earlier temporary visit.',
            Technician_Notes__c = 'Earlier follow-up evidence.',
            Labor_Hours__c = 1,
            Issue_Resolved__c = false,
            Follow_Up_Required__c = true,
            Performed_By__c = UserInfo.getUserId()
        );

        Maintenance_Log__c latestLog = new Maintenance_Log__c(
            Asset__c = asset.Id,
            Work_Order__c = workOrder.Id,
            Maintenance_Date__c = Date.today().addDays(-1),
            Maintenance_Type__c = 'Temporary Repair',
            Problem_Summary__c = PROBLEM,
            Recommended_Fix_Snapshot__c = PREVIOUS_FIX,
            Tools_To_Bring_Snapshot__c = PREVIOUS_TOOLS,
            Summary__c = LATEST_VISIT,
            Technician_Notes__c = 'TEMPORARY REPAIR / FOLLOW-UP\n\nVisit Summary:\n' + LATEST_VISIT,
            Labor_Hours__c = Decimal.valueOf('1.50'),
            Issue_Resolved__c = false,
            Follow_Up_Required__c = true,
            Performed_By__c = UserInfo.getUserId()
        );

        insert new List<Maintenance_Log__c>{ olderLog, latestLog };
    }

    @IsTest
    static void testGetToolCatalogReturnsAlphabeticalTools() {
        Test.startTest();
        List<ManagerFollowUpWorkOrderController.ToolOption> tools = ManagerFollowUpWorkOrderController.getToolCatalog();
        Test.stopTest();

        System.assertEquals(3, tools.size(), 'The Tool Catalog should return all test tools.');
        System.assertEquals('Allen Keys', tools[0].name);
        System.assertEquals('Multimeter', tools[1].name);
        System.assertEquals('Phillips Head Screwdriver', tools[2].name);

        for (ManagerFollowUpWorkOrderController.ToolOption tool : tools) {
            System.assertNotEquals(null, tool.id, 'Each tool should include its Tool Catalog ID.');
            System.assertNotEquals(null, tool.name, 'Each tool should include its Tool Catalog name.');
        }
    }

    @IsTest
    static void testGetFollowUpDataReturnsLatestVisit() {
        WorkOrder workOrder = getWorkOrder();

        Test.startTest();
        ManagerFollowUpWorkOrderController.FollowUpData data = ManagerFollowUpWorkOrderController.getFollowUpData(workOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, data);
        System.assertEquals(workOrder.Id, data.workOrderId);
        System.assertNotEquals(null, data.workOrderNumber);
        System.assertEquals(WO_SUBJECT, data.subject);
        System.assertEquals('Medium', data.priority);
        System.assertEquals('Temporary Fix', data.dispatchStatus);
        System.assertEquals(PROBLEM, data.problemSummary);
        System.assertEquals('Follow-Up Test Dental Lab', data.accountName);
        System.assertEquals('Excessive milling vibration', data.caseSubject);
        System.assertEquals('Follow-Up Required', data.caseStatus);
        System.assertEquals('Jamie Followup', data.contactName);
        System.assertEquals('Follow-Up Test DWX-52D', data.assetName);
        System.assertEquals('Roland', data.manufacturer);
        System.assertEquals('DWX-52D', data.model);
        System.assertEquals('FUP-001', data.serialNumber);
        System.assertEquals('Temporary Fix Applied', data.machineStatus);
        System.assertNotEquals(null, data.maintenanceLogId);
        System.assertEquals(Date.today().addDays(-1), data.maintenanceDate);
        System.assertEquals('Temporary Repair', data.maintenanceType);
        System.assertEquals(PROBLEM, data.visitProblemSummary);
        System.assertEquals(PREVIOUS_FIX, data.previousRecommendedFix);
        System.assertEquals(PREVIOUS_TOOLS, data.previousTools);
        System.assertEquals(LATEST_VISIT, data.visitSummary);
        System.assertEquals(Decimal.valueOf('1.50'), data.laborHours);
        System.assertEquals(false, data.issueResolved);
        System.assertEquals(true, data.followUpRequired);
        System.assertNotEquals(null, data.technicianName);
        System.assertEquals(1, data.existingParts.size(), 'Existing Work Order parts should be returned.');
        System.assertEquals('Existing Correction Jig', data.existingParts[0].partName);
        System.assertEquals(Decimal.valueOf('1'), data.existingParts[0].quantity);
        System.assertEquals('Received', data.existingParts[0].status);
        System.assertEquals(false, data.existingParts[0].technicianRequested);
        System.assertEquals('Required Part', data.existingParts[0].sourceLabel);
    }

    @IsTest
    static void testApproveFollowUpWithoutParts() {
        WorkOrder workOrder = getWorkOrder();
        Id assetId = workOrder.AssetId;
        String newFix = 'Replace the worn correction jig, recalibrate the machine, and verify milling stability under load.';
        String submittedTools = 'allen keys\nMULTIMETER\nAllen Keys';
        String expectedTools = 'Allen Keys\nMultimeter';

        Test.startTest();
        ManagerFollowUpWorkOrderController.ApprovalResult result =
            ManagerFollowUpWorkOrderController.approveFollowUp(workOrder.Id, newFix, submittedTools, '[]');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Ready_to_Assign', result.dispatchStatus);
        System.assertEquals(0, result.requestedPartCount);
        System.assert(result.message.contains('ready to assign'));

        WorkOrder updated = [
            SELECT Dispatch_Status__c, Recommended_Fix_Summary__c, Recommended_Tools__c, Service_Manager__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];

        System.assertEquals('Ready_to_Assign', updated.Dispatch_Status__c);
        System.assertEquals(newFix, updated.Recommended_Fix_Summary__c);
        System.assertEquals(expectedTools, updated.Recommended_Tools__c, 'Tools should be deduplicated and normalized to Tool Catalog names.');
        System.assertEquals(UserInfo.getUserId(), updated.Service_Manager__c);

        Case serviceCase = [SELECT Status FROM Case WHERE Id = :workOrder.CaseId];
        System.assertEquals('In Progress', serviceCase.Status);

        Asset asset = [SELECT Machine_Status__c FROM Asset WHERE Id = :assetId];
        System.assertEquals('Temporary Fix Applied', asset.Machine_Status__c, 'Manager approval must not change the physical machine state.');
        System.assertEquals(1, [SELECT COUNT() FROM Work_Order_Part__c WHERE Work_Order__c = :workOrder.Id], 'No new part request should be created.');

        Maintenance_Log__c visit = [
            SELECT Recommended_Fix_Snapshot__c, Tools_To_Bring_Snapshot__c
            FROM Maintenance_Log__c
            WHERE Work_Order__c = :workOrder.Id
              AND Maintenance_Date__c = :Date.today().addDays(-1)
            LIMIT 1
        ];

        System.assertEquals(PREVIOUS_FIX, visit.Recommended_Fix_Snapshot__c, 'Previous visit snapshot must remain unchanged.');
        System.assertEquals(PREVIOUS_TOOLS, visit.Tools_To_Bring_Snapshot__c, 'Previous tool snapshot must remain unchanged.');
    }

    @IsTest
    static void testApproveFollowUpWithParts() {
        WorkOrder workOrder = getWorkOrder();
        Part_Catalog__c selectedPart = getCatalogPart(NEW_PART_NUMBER);

        String selectedPartsJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'partCatalogId' => selectedPart.Id, 'quantity' => 2 }
        });

        Test.startTest();
        ManagerFollowUpWorkOrderController.ApprovalResult result = ManagerFollowUpWorkOrderController.approveFollowUp(
            workOrder.Id,
            'Replace the spindle belt and verify spindle stability under milling load.',
            'Phillips Head Screwdriver\nMultimeter',
            selectedPartsJson
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Parts to Order', result.dispatchStatus);
        System.assertEquals(1, result.requestedPartCount);

        WorkOrder updated = [
            SELECT Dispatch_Status__c, Recommended_Fix_Summary__c, Recommended_Tools__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];

        System.assertEquals('Parts to Order', updated.Dispatch_Status__c);
        System.assertEquals('Replace the spindle belt and verify spindle stability under milling load.', updated.Recommended_Fix_Summary__c);
        System.assertEquals('Phillips Head Screwdriver\nMultimeter', updated.Recommended_Tools__c);

        Case serviceCase = [SELECT Status FROM Case WHERE Id = :workOrder.CaseId];
        System.assertEquals('In Progress', serviceCase.Status);

        Asset asset = [SELECT Machine_Status__c FROM Asset WHERE Id = :workOrder.AssetId];
        System.assertEquals('Temporary Fix Applied', asset.Machine_Status__c);

        Work_Order_Part__c newRequest = [
            SELECT Work_Order__c, Machine__c, Part_Catalog__c, Quantity__c, Order_Status__c, Technician_Requested__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrder.Id
              AND Part_Catalog__c = :selectedPart.Id
            LIMIT 1
        ];

        System.assertEquals(workOrder.Id, newRequest.Work_Order__c);
        System.assertEquals(workOrder.AssetId, newRequest.Machine__c);
        System.assertEquals(selectedPart.Id, newRequest.Part_Catalog__c);
        System.assertEquals(Decimal.valueOf('2'), newRequest.Quantity__c);
        System.assertEquals('Requested', newRequest.Order_Status__c);
        System.assertEquals(false, newRequest.Technician_Requested__c);
    }

    @IsTest
    static void testRejectsInvalidToolCatalogEntry() {
        WorkOrder workOrder = getWorkOrder();
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerFollowUpWorkOrderController.approveFollowUp(
                workOrder.Id,
                'Complete the permanent follow-up repair.',
                'Allen Keys\nImaginary Laser Wrench',
                '[]'
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('not valid Tool Catalog entries'), 'Expected invalid Tool Catalog validation.');
            System.assert(e.getMessage().contains('Imaginary Laser Wrench'), 'The invalid tool should be identified in the error.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A non-catalog tool must be rejected.');

        WorkOrder unchanged = [SELECT Dispatch_Status__c, Recommended_Tools__c FROM WorkOrder WHERE Id = :workOrder.Id];
        System.assertEquals('Temporary Fix', unchanged.Dispatch_Status__c);
        System.assertEquals(PREVIOUS_TOOLS, unchanged.Recommended_Tools__c, 'Rejected approval must not modify the saved tools.');
    }

    @IsTest
    static void testRejectsDuplicateActivePartRequest() {
        WorkOrder workOrder = getWorkOrder();
        Part_Catalog__c selectedPart = getCatalogPart(NEW_PART_NUMBER);

        insert new Work_Order_Part__c(
            Work_Order__c = workOrder.Id,
            Machine__c = workOrder.AssetId,
            Part_Catalog__c = selectedPart.Id,
            Quantity__c = 1,
            Order_Status__c = 'Requested',
            Technician_Requested__c = false
        );

        String selectedPartsJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'partCatalogId' => selectedPart.Id, 'quantity' => 1 }
        });

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerFollowUpWorkOrderController.approveFollowUp(
                workOrder.Id,
                'Replace the spindle belt.',
                'Allen Keys',
                selectedPartsJson
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('already has an active part request'), 'Expected duplicate part request validation.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);

        WorkOrder unchanged = [SELECT Dispatch_Status__c FROM WorkOrder WHERE Id = :workOrder.Id];
        System.assertEquals('Temporary Fix', unchanged.Dispatch_Status__c, 'Rejected approval must not advance the Work Order.');
    }

    @IsTest
    static void testRejectsStaleWorkOrder() {
        WorkOrder workOrder = getWorkOrder();
        workOrder.Dispatch_Status__c = 'Ready_to_Assign';
        update workOrder;

        Boolean loadRejected = false;
        Boolean approvalRejected = false;

        Test.startTest();

        try {
            ManagerFollowUpWorkOrderController.getFollowUpData(workOrder.Id);
        } catch (AuraHandledException e) {
            loadRejected = true;
            System.assert(e.getMessage().contains('no longer awaiting follow-up review'));
        }

        try {
            ManagerFollowUpWorkOrderController.approveFollowUp(
                workOrder.Id,
                'Updated follow-up repair.',
                'Allen Keys',
                '[]'
            );
        } catch (AuraHandledException e) {
            approvalRejected = true;
            System.assert(e.getMessage().contains('no longer awaiting follow-up review'));
        }

        Test.stopTest();

        System.assertEquals(true, loadRejected, 'A stale Work Order should not load into the follow-up wizard.');
        System.assertEquals(true, approvalRejected, 'A stale Work Order should not be approved.');
    }

    @IsTest
    static void testRejectsBlankAndLongRecommendedFix() {
        WorkOrder workOrder = getWorkOrder();
        Boolean blankRejected = false;
        Boolean longRejected = false;

        String longFix = '';
        while (longFix.length() <= 255) longFix += 'Follow-up repair instruction ';

        Test.startTest();

        try {
            ManagerFollowUpWorkOrderController.approveFollowUp(workOrder.Id, '   ', 'Allen Keys', '[]');
        } catch (AuraHandledException e) {
            blankRejected = true;
            System.assert(e.getMessage().contains('Recommended Fix Summary is required'));
        }

        try {
            ManagerFollowUpWorkOrderController.approveFollowUp(workOrder.Id, longFix, 'Allen Keys', '[]');
        } catch (AuraHandledException e) {
            longRejected = true;
            System.assert(e.getMessage().contains('255 characters or fewer'));
        }

        Test.stopTest();

        System.assertEquals(true, blankRejected);
        System.assertEquals(true, longRejected);
    }

    @IsTest
    static void testRejectsInvalidPartQuantity() {
        WorkOrder workOrder = getWorkOrder();
        Part_Catalog__c selectedPart = getCatalogPart(NEW_PART_NUMBER);

        String selectedPartsJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'partCatalogId' => selectedPart.Id, 'quantity' => 0 }
        });

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerFollowUpWorkOrderController.approveFollowUp(
                workOrder.Id,
                'Replace the spindle belt.',
                'Allen Keys',
                selectedPartsJson
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('whole numbers greater than zero'));
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    private static WorkOrder getWorkOrder() {
        return [
            SELECT Id, AssetId, CaseId, Dispatch_Status__c
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];
    }

    private static Part_Catalog__c getCatalogPart(String partNumber) {
        return [
            SELECT Id, Name, Part_Number__c
            FROM Part_Catalog__c
            WHERE Part_Number__c = :partNumber
            LIMIT 1
        ];
    }

    private static Part_Catalog__c buildCatalogPart(String name, String partNumber) {
        return new Part_Catalog__c(
            Name = name,
            Part_Number__c = partNumber,
            Manufacturer__c = 'Roland',
            Compatible_Model__c = 'DWX-52D',
            Parts_Category__c = 'Spindle',
            Supplier_Name__c = 'MillTrack Test Supplier',
            Supplier_Phone__c = '555-123-4567',
            Order_URL__c = 'https://example.com/' + partNumber.toLowerCase(),
            Active__c = true,
            Keyword_Aliases__c = 'follow up repair replacement service part'
        );
    }

    private static String getFirstActivePicklistValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) return entry.getValue();
        }

        return null;
    }
}
