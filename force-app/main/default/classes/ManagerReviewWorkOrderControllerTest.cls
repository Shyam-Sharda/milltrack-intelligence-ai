@IsTest
private class ManagerReviewWorkOrderControllerTest {

    private static final String WO_SUBJECT = 'Inspect disc changer binding';

    @TestSetup
    static void createTestData() {
        Account accountRecord = new Account(Name = 'Manager Review Test Account');
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Sarah',
            LastName = 'Mitchell',
            AccountId = accountRecord.Id,
            Email = 'sarah.mitchell@example.com',
            Phone = '613-555-0199',
            Title = 'Operations Manager'
        );
        insert contactRecord;

        Asset assetRecord = new Asset(
            Name = 'Manager Review Test Mill',
            AccountId = accountRecord.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-53DC',
            Serial_Number__c = 'MRW-TEST-001',
            Machine_Status__c = 'Active'
        );
        insert assetRecord;

        Case caseRecord = new Case(
            AccountId = accountRecord.Id,
            ContactId = contactRecord.Id,
            AssetId = assetRecord.Id,
            Subject = 'Disc changer binding during Run-in',
            Description = 'The disc changer binds near the bottom of travel during Run-in.',
            Status = 'New',
            Origin = 'Web',
            Priority = 'High',
            Error_Code__c = 'COLLISION-001'
        );
        insert caseRecord;

        WorkOrder workOrder = new WorkOrder(
            AccountId = accountRecord.Id,
            AssetId = assetRecord.Id,
            CaseId = caseRecord.Id,
            Subject = WO_SUBJECT,
            Description = 'Manager review test Work Order',
            Status = 'New',
            Priority = 'High',
            Dispatch_Status__c = 'Pending',
            Problem_Summary__c = 'Disc changer binds near the bottom of its travel during Run-in.',
            Recommended_Solution__c = 'Inspect the changer mechanism, verify alignment, and test movement before replacing components.',
            Recommended_Fix_Summary__c = 'Inspect and correct disc changer alignment, then verify normal movement.',
            Recommended_Parts__c = 'None identified',
            Previous_Failure__c = false
        );
        insert workOrder;

        Part_Catalog__c catalogPart = new Part_Catalog__c(
            Name = 'Disc Changer Spindle Component',
            Part_Number__c = 'MRW-SP-001',
            Manufacturer__c = 'Roland',
            Compatible_Model__c = 'DWX-53DC',
            Parts_Category__c = 'Spindle',
            Supplier_Name__c = 'MillTrack Test Supplier',
            Supplier_Phone__c = '613-555-0100',
            Order_URL__c = 'https://example.com/disc-changer-component',
            Active__c = true,
            Keyword_Aliases__c = 'disc changer spindle component'
        );
        insert catalogPart;

        insert new List<Tool_Catalog__c>{
            new Tool_Catalog__c(Name = 'Multimeter'),
            new Tool_Catalog__c(Name = 'Allen Keys'),
            new Tool_Catalog__c(Name = 'Phillips Head Screwdriver')
        };
    }

    // =========================================================
    // Tool Catalog
    // =========================================================

    @IsTest
    static void getToolCatalogReturnsAlphabeticalTools() {
        Test.startTest();
        List<ManagerReviewWorkOrderController.ToolOption> tools = ManagerReviewWorkOrderController.getToolCatalog();
        Test.stopTest();

        System.assertEquals(3, tools.size(), 'All Tool Catalog records should be returned.');
        System.assertEquals('Allen Keys', tools[0].name);
        System.assertEquals('Multimeter', tools[1].name);
        System.assertEquals('Phillips Head Screwdriver', tools[2].name);

        for (ManagerReviewWorkOrderController.ToolOption tool : tools) {
            System.assertNotEquals(null, tool.id, 'Each tool should include its Tool Catalog ID.');
            System.assertNotEquals(null, tool.name, 'Each tool should include its name.');
        }
    }

    // =========================================================
    // Load Review Data
    // =========================================================

    @IsTest
    static void getReviewDataReturnsExpectedContext() {
        WorkOrder workOrder = [
            SELECT Id, WorkOrderNumber, AccountId, AssetId, Asset.Machine_Status__c, CaseId
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];

        Test.startTest();
        ManagerReviewWorkOrderController.ReviewData result = ManagerReviewWorkOrderController.getReviewData(workOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Review data should be returned.');
        System.assertEquals(workOrder.Id, result.workOrderId);
        System.assertEquals(workOrder.WorkOrderNumber, result.workOrderNumber);
        System.assertEquals(WO_SUBJECT, result.subject);
        System.assertEquals('High', result.priority);
        System.assertEquals('Pending', result.dispatchStatus);
        System.assertEquals('Disc changer binds near the bottom of its travel during Run-in.', result.problemSummary);
        System.assertEquals('Inspect the changer mechanism, verify alignment, and test movement before replacing components.', result.recommendedSolution);
        System.assertEquals('Inspect and correct disc changer alignment, then verify normal movement.', result.recommendedFixSummary);
        System.assertEquals('', result.recommendedTools, 'A newly generated Work Order should begin with no Recommended Tools.');
        System.assertEquals('None identified', result.recommendedParts);
        System.assertEquals(false, result.previousFailure);
        System.assertEquals(workOrder.AccountId, result.accountId);
        System.assertEquals('Manager Review Test Account', result.accountName);
        System.assertNotEquals(null, result.contactId);
        System.assertEquals('Sarah Mitchell', result.contactName);
        System.assertEquals('sarah.mitchell@example.com', result.contactEmail);
        System.assertEquals('613-555-0199', result.contactPhone);
        System.assertEquals('Operations Manager', result.contactTitle);
        System.assertEquals(workOrder.AssetId, result.assetId);
        System.assertEquals('Manager Review Test Mill', result.assetName);
        System.assertEquals('Roland', result.manufacturer);
        System.assertEquals('DWX-53DC', result.model);
        System.assertEquals('MRW-TEST-001', result.serialNumber);
        System.assertEquals(workOrder.Asset.Machine_Status__c, result.machineStatus, 'The controller should return the current Asset machine status.');
        System.assertEquals(workOrder.CaseId, result.caseId);
        System.assertNotEquals(null, result.caseNumber);
        System.assertEquals('Disc changer binding during Run-in', result.caseSubject);
        System.assertEquals('High', result.casePriority);
        System.assertEquals('COLLISION-001', result.errorCode);
        System.assertNotEquals(null, result.dateReported);
    }

    // =========================================================
    // Approve - Ready to Assign
    // =========================================================

    @IsTest
    static void approveWorkOrderSetsReadyToAssign() {
        WorkOrder workOrder = [
            SELECT Id, CaseId, AssetId, Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];

        String machineStatusBefore = workOrder.Asset.Machine_Status__c;
        String submittedTools = 'allen keys\nMULTIMETER\nAllen Keys';
        String expectedTools = 'Allen Keys\nMultimeter';

        Test.startTest();
        ManagerReviewWorkOrderController.ApprovalResult result = ManagerReviewWorkOrderController.approveWorkOrder(
            workOrder.Id,
            'Updated manager-reviewed problem summary.',
            'Inspect the changer mechanism and verify alignment before replacing components.',
            'Correct changer alignment and verify movement.',
            submittedTools,
            'None identified',
            true,
            'Critical',
            '[]'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(workOrder.Id, result.workOrderId);
        System.assertEquals('Ready_to_Assign', result.dispatchStatus);
        System.assertEquals(0, result.requestedPartCount);
        System.assert(result.message.contains('ready'), 'The response should explain that the Work Order is ready for assignment.');

        WorkOrder updatedWorkOrder = [
            SELECT Problem_Summary__c, Recommended_Solution__c, Recommended_Fix_Summary__c,
                   Recommended_Tools__c, Recommended_Parts__c, Previous_Failure__c, Priority,
                   Dispatch_Status__c, Service_Manager__c, Case.Status, Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];

        System.assertEquals('Updated manager-reviewed problem summary.', updatedWorkOrder.Problem_Summary__c);
        System.assertEquals('Inspect the changer mechanism and verify alignment before replacing components.', updatedWorkOrder.Recommended_Solution__c);
        System.assertEquals('Correct changer alignment and verify movement.', updatedWorkOrder.Recommended_Fix_Summary__c);
        System.assertEquals(expectedTools, updatedWorkOrder.Recommended_Tools__c, 'Tools should be deduplicated and normalized to Tool Catalog names.');
        System.assertEquals('None identified', updatedWorkOrder.Recommended_Parts__c);
        System.assertEquals(true, updatedWorkOrder.Previous_Failure__c);
        System.assertEquals('Critical', updatedWorkOrder.Priority);
        System.assertEquals('Ready_to_Assign', updatedWorkOrder.Dispatch_Status__c);
        System.assertEquals(UserInfo.getUserId(), updatedWorkOrder.Service_Manager__c);
        System.assertEquals('In Progress', updatedWorkOrder.Case.Status, 'Approving the Work Order should move the related Case to In Progress.');
        System.assertEquals(machineStatusBefore, updatedWorkOrder.Asset.Machine_Status__c, 'Review approval must not change the Asset machine status.');

        Integer partRequestCount = [SELECT COUNT() FROM Work_Order_Part__c WHERE Work_Order__c = :workOrder.Id];
        System.assertEquals(0, partRequestCount, 'No Work Order Parts should be created when no parts are selected.');
    }

    // =========================================================
    // Approve - Parts Required
    // =========================================================

    @IsTest
    static void approveWorkOrderSetsPartsToOrder() {
        WorkOrder workOrder = [
            SELECT Id, CaseId, AssetId, Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];

        Part_Catalog__c catalogPart = [
            SELECT Id, Name
            FROM Part_Catalog__c
            WHERE Part_Number__c = 'MRW-SP-001'
            LIMIT 1
        ];

        String machineStatusBefore = workOrder.Asset.Machine_Status__c;
        String selectedPartsJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'partCatalogId' => catalogPart.Id, 'quantity' => 2 }
        });

        Test.startTest();
        ManagerReviewWorkOrderController.ApprovalResult result = ManagerReviewWorkOrderController.approveWorkOrder(
            workOrder.Id,
            'Changer movement is restricted during Run-in.',
            'Inspect the changer assembly and replace the damaged component only if confirmed.',
            'Inspect changer and replace damaged component if required.',
            'Phillips Head Screwdriver',
            'Disc changer spindle component',
            false,
            'High',
            selectedPartsJson
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Parts to Order', result.dispatchStatus);
        System.assertEquals(1, result.requestedPartCount);
        System.assert(result.message.contains('required part request'), 'The response should explain that a required part request was created.');

        WorkOrder updatedWorkOrder = [
            SELECT Dispatch_Status__c, Recommended_Tools__c, Recommended_Parts__c, Case.Status, Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];

        System.assertEquals('Parts to Order', updatedWorkOrder.Dispatch_Status__c);
        System.assertEquals('Phillips Head Screwdriver', updatedWorkOrder.Recommended_Tools__c);
        System.assertEquals('Disc changer spindle component', updatedWorkOrder.Recommended_Parts__c);
        System.assertEquals('In Progress', updatedWorkOrder.Case.Status, 'Review approval should move the Case to In Progress before parts ordering.');
        System.assertEquals(machineStatusBefore, updatedWorkOrder.Asset.Machine_Status__c, 'Requesting parts during manager review must not change the Asset status.');

        List<Work_Order_Part__c> partRequests = [
            SELECT Id, Work_Order__c, Machine__c, Part_Catalog__c, Quantity__c, Order_Status__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrder.Id
        ];

        System.assertEquals(1, partRequests.size(), 'Exactly one Work Order Part request should be created.');
        System.assertEquals(catalogPart.Id, partRequests[0].Part_Catalog__c);
        System.assertEquals(2, partRequests[0].Quantity__c);
        System.assertEquals('Requested', partRequests[0].Order_Status__c);
        System.assertEquals(workOrder.AssetId, partRequests[0].Machine__c);
    }

    // =========================================================
    // Tool Validation
    // =========================================================

    @IsTest
    static void approveWorkOrderRejectsInvalidToolCatalogEntry() {
        WorkOrder workOrder = [SELECT Id, Dispatch_Status__c FROM WorkOrder WHERE Subject = :WO_SUBJECT LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.approveWorkOrder(
                workOrder.Id,
                'Reviewed problem summary.',
                'Reviewed recommended solution.',
                'Reviewed fix summary.',
                'Allen Keys\nImaginary Laser Wrench',
                'None identified',
                false,
                'Medium',
                '[]'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            System.assert(ex.getMessage().contains('not valid Tool Catalog entries'), 'Expected invalid Tool Catalog validation.');
            System.assert(ex.getMessage().contains('Imaginary Laser Wrench'), 'The invalid tool should be identified in the error.');
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A non-catalog tool must be rejected.');

        WorkOrder unchanged = [SELECT Dispatch_Status__c, Recommended_Tools__c FROM WorkOrder WHERE Id = :workOrder.Id];
        System.assertEquals('Pending', unchanged.Dispatch_Status__c);
        System.assertEquals(null, unchanged.Recommended_Tools__c, 'Rejected approval must not populate Recommended Tools.');
    }

    // =========================================================
    // Optional Text Normalization
    // =========================================================

    @IsTest
    static void approveWorkOrderClearsBlankOptionalFields() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder WHERE Subject = :WO_SUBJECT LIMIT 1];

        Test.startTest();
        ManagerReviewWorkOrderController.approveWorkOrder(
            workOrder.Id,
            'Reviewed problem summary.',
            'Reviewed recommended solution.',
            'Reviewed fix summary.',
            '   ',
            '',
            false,
            'Medium',
            '[]'
        );
        Test.stopTest();

        WorkOrder updatedWorkOrder = [
            SELECT Recommended_Tools__c, Recommended_Parts__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];

        System.assertEquals(null, updatedWorkOrder.Recommended_Tools__c);
        System.assertEquals(null, updatedWorkOrder.Recommended_Parts__c);
    }

    // =========================================================
    // Validation
    // =========================================================

    @IsTest
    static void getReviewDataRejectsNullId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.getReviewData(null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'A null Work Order ID should be rejected.');
    }

    @IsTest
    static void approveWorkOrderRejectsNullId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.approveWorkOrder(
                null,
                'Problem',
                'Solution',
                'Fix',
                'Allen Keys',
                'Parts',
                false,
                'Medium',
                '[]'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Approval should reject a null Work Order ID.');
    }

    @IsTest
    static void approveWorkOrderRejectsBlankProblemSummary() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder WHERE Subject = :WO_SUBJECT LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.approveWorkOrder(
                workOrder.Id,
                '',
                'Recommended solution',
                'Recommended fix',
                'Allen Keys',
                'Parts',
                false,
                'Medium',
                '[]'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Problem Summary is required.');
    }

    @IsTest
    static void approveWorkOrderRejectsBlankRecommendedSolution() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder WHERE Subject = :WO_SUBJECT LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.approveWorkOrder(
                workOrder.Id,
                'Problem summary',
                '',
                'Recommended fix',
                'Allen Keys',
                'Parts',
                false,
                'Medium',
                '[]'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Recommended Solution is required.');
    }

    @IsTest
    static void approveWorkOrderRejectsLongFixSummary() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder WHERE Subject = :WO_SUBJECT LIMIT 1];
        String longFixSummary = '';
        while (longFixSummary.length() <= 255) longFixSummary += '0123456789';

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.approveWorkOrder(
                workOrder.Id,
                'Problem summary',
                'Recommended solution',
                longFixSummary,
                'Allen Keys',
                'Parts',
                false,
                'Medium',
                '[]'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Fix Summary values over 255 characters must be rejected.');
    }

    @IsTest
    static void approveWorkOrderRejectsInvalidPriority() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder WHERE Subject = :WO_SUBJECT LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.approveWorkOrder(
                workOrder.Id,
                'Problem summary',
                'Recommended solution',
                'Recommended fix',
                'Allen Keys',
                'Parts',
                false,
                'Urgent',
                '[]'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Unsupported priority values must be rejected.');
    }

    @IsTest
    static void approveWorkOrderRejectsMalformedSelectedPartsJson() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder WHERE Subject = :WO_SUBJECT LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerReviewWorkOrderController.approveWorkOrder(
                workOrder.Id,
                'Problem summary',
                'Recommended solution',
                'Recommended fix',
                'Allen Keys',
                'Parts',
                false,
                'Medium',
                '{not-valid-json}'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Malformed selected-parts JSON should be rejected.');
    }
}
