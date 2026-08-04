@IsTest
private class ManagerOperationsCenterControllerTest {

    @TestSetup
    static void createOperationsData() {
        Account testAccount = new Account(
            Name = 'MillTrack Test Dental Lab'
        );
        insert testAccount;

        Asset testAsset = new Asset(
            Name = 'MillTrack Test Milling Machine',
            AccountId = testAccount.Id,
            SerialNumber = 'MT-TEST-001',
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D'
        );
        insert testAsset;

        Case testCase = new Case(
            Subject = 'Test spindle vibration',
            Status = 'New',
            Origin = 'Web',
            Priority = 'High',
            AccountId = testAccount.Id,
            AssetId = testAsset.Id
        );
        insert testCase;

        List<WorkOrder> workOrders = new List<WorkOrder>{
            buildWorkOrder(
                'Pending manager review',
                'Pending',
                null,
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            ),
            buildWorkOrder(
                'Pre-dispatch parts required',
                'Parts to Order',
                null,
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            ),
            buildWorkOrder(
                'Waiting for ordered parts',
                'Waiting on Parts',
                null,
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            ),
            buildWorkOrder(
                'Ready for technician assignment',
                'Ready_to_Assign',
                null,
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            ),
            buildWorkOrder(
                'Repair currently in progress',
                'In Progress',
                null,
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            ),
            buildWorkOrder(
                'Temporary repair needs follow-up',
                'Temporary Fix',
                null,
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            ),
            buildWorkOrder(
                'Upcoming assigned visit',
                'Assigned',
                System.now().addDays(2),
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            ),
            buildWorkOrder(
                'Past assigned visit',
                'Assigned',
                System.now().addDays(-2),
                testAccount.Id,
                testAsset.Id,
                testCase.Id
            )
        };
        insert workOrders;

        WorkOrder waitingWorkOrder;

        for (WorkOrder workOrder : workOrders) {
            if (workOrder.Dispatch_Status__c == 'Waiting on Parts') {
                waitingWorkOrder = workOrder;
                break;
            }
        }

        System.assertNotEquals(
            null,
            waitingWorkOrder,
            'The test setup should create a Waiting on Parts Work Order.'
        );

        Part_Catalog__c catalogPart = new Part_Catalog__c(
            Name = 'Spindle Bearings',
            Part_Number__c = 'SB-001',
            Manufacturer__c = 'Roland',
            Compatible_Model__c = 'DWX-52D',
            Parts_Category__c = 'Spindle',
            Supplier_Name__c = 'Roland Supplier',
            Supplier_Phone__c = '555-123-4567',
            Order_URL__c =
                'https://example.com/spindle-bearings',
            Active__c = true,
            Keyword_Aliases__c =
                'spindle bearing bearings spindle assembly'
        );
        insert catalogPart;

        List<Work_Order_Part__c> parts = new List<Work_Order_Part__c>{
            buildWorkOrderPart(
                waitingWorkOrder.Id,
                testAsset.Id,
                catalogPart.Id,
                1,
                'Requested',
                'Technician-created test request',
                null,
                null,
                null,
                null
            ),
            buildWorkOrderPart(
                waitingWorkOrder.Id,
                testAsset.Id,
                catalogPart.Id,
                2,
                'Ordered',
                'Manager placed the supplier order',
                'Roland Supplier',
                '555-123-4567',
                'https://example.com/ordered-spindle',
                UserInfo.getUserId()
            ),
            buildWorkOrderPart(
                waitingWorkOrder.Id,
                testAsset.Id,
                catalogPart.Id,
                3,
                'Shipped',
                'Supplier dispatched the part',
                'Roland Supplier',
                '555-123-4567',
                'https://example.com/shipped-spindle',
                UserInfo.getUserId()
            ),
            buildWorkOrderPart(
                waitingWorkOrder.Id,
                testAsset.Id,
                catalogPart.Id,
                4,
                'Received',
                'Part has already been received',
                'Roland Supplier',
                '555-123-4567',
                'https://example.com/received-spindle',
                UserInfo.getUserId()
            ),
            buildWorkOrderPart(
                waitingWorkOrder.Id,
                testAsset.Id,
                catalogPart.Id,
                5,
                'Installed',
                'Part has already been installed',
                'Roland Supplier',
                '555-123-4567',
                'https://example.com/installed-spindle',
                UserInfo.getUserId()
            ),
            buildWorkOrderPart(
                waitingWorkOrder.Id,
                testAsset.Id,
                catalogPart.Id,
                6,
                'Cancelled',
                'Part request was cancelled',
                null,
                null,
                null,
                null
            )
        };
        insert parts;
    }

    @IsTest
    static void getOperationsDataClassifiesEveryQueue() {
        Test.startTest();

        ManagerOperationsCenterController.OperationsData data =
            ManagerOperationsCenterController.getOperationsData();

        Test.stopTest();

        System.assertNotEquals(
            null,
            data,
            'The controller should return an OperationsData wrapper.'
        );

        System.assertNotEquals(
            null,
            data.generatedAt,
            'The response should include its generation time.'
        );

        assertCountsMatchLists(data);

        System.assertEquals(
            1,
            data.newCasesCount,
            'The seeded New Case should be returned.'
        );

        System.assert(
            data.requiresReviewCount >= 1,
            'The seeded Pending Work Order should be returned.'
        );

        System.assert(
            data.partsToOrderCount >= 2,
            'Parts to Order should include the pre-dispatch Work Order ' +
            'and the Requested Work Order Part.'
        );

        System.assert(
            data.waitingOnPartsCount >= 2,
            'Waiting on Parts should include the Ordered and Shipped parts.'
        );

        System.assert(
            data.readyToAssignCount >= 1,
            'The Ready to Assign Work Order should be returned.'
        );

        System.assertEquals(
            1,
            data.assignedVisitsCount,
            'Only the future Assigned visit should be returned.'
        );

        System.assert(
            data.activeRepairsCount >= 2,
            'In Progress and Temporary Fix should both be active repairs.'
        );

        Case expectedCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Test spindle vibration'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem newCaseItem =
            findItemByRecordId(
                data.newCases,
                expectedCase.Id
            );

        System.assertNotEquals(
            null,
            newCaseItem,
            'The explicitly seeded New Case should be returned.'
        );

        System.assertEquals(
            'CASE',
            newCaseItem.rowType,
            'The Case row should identify its row type.'
        );

        assertAction(
            newCaseItem,
            'NAVIGATE',
            'VIEW_CASE',
            'Open Case',
            null,
            expectedCase.Id
        );

        WorkOrder pendingWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Pending manager review'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem pendingItem =
            findItemByRecordId(
                data.requiresReview,
                pendingWorkOrder.Id
            );

        System.assertNotEquals(
            null,
            pendingItem,
            'The explicitly seeded Pending Work Order should be returned.'
        );

        System.assertEquals(
            'WORK_ORDER',
            pendingItem.rowType,
            'The review row should be identified as a Work Order.'
        );

        assertAction(
            pendingItem,
            'FLOW',
            'REVIEW_WORK_ORDER',
            'Review Work Order',
            'Generate_Work_Order_Proposal_From_Case',
            pendingWorkOrder.Id
        );

        WorkOrder preDispatchWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Pre-dispatch parts required'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem preDispatchItem =
            findItemByRecordId(
                data.partsToOrder,
                preDispatchWorkOrder.Id
            );

        System.assertNotEquals(
            null,
            preDispatchItem,
            'Parts to Order should contain the pre-dispatch Work Order.'
        );

        System.assertEquals(
            'WorkOrder',
            preDispatchItem.objectApiName
        );

        System.assertEquals(
            'WORK_ORDER',
            preDispatchItem.rowType
        );

        assertAction(
            preDispatchItem,
            'FLOW',
            'ORDER_REQUIRED_PARTS',
            'Order Required Parts',
            'X13_Order_Parts_From_Work_Order',
            preDispatchWorkOrder.Id
        );

        Work_Order_Part__c requestedPartRecord = [
            SELECT Id, Work_Order__c
            FROM Work_Order_Part__c
            WHERE Order_Status__c = 'Requested'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem requestedPartItem =
            findItemByRecordId(
                data.partsToOrder,
                requestedPartRecord.Id
            );

        System.assertNotEquals(
            null,
            requestedPartItem,
            'Parts to Order should contain the technician-created request.'
        );

        System.assertEquals(
            'Work_Order_Part__c',
            requestedPartItem.objectApiName
        );

        System.assertEquals(
            'TECHNICIAN_REQUESTED_PART',
            requestedPartItem.rowType
        );

        System.assertEquals(
            requestedPartRecord.Id,
            requestedPartItem.partId,
            'The row should expose the Work Order Part ID.'
        );

        System.assertEquals(
            requestedPartRecord.Work_Order__c,
            requestedPartItem.workOrderId,
            'The row should expose the parent Work Order ID.'
        );

        System.assertEquals(
            requestedPartRecord.Work_Order__c,
            requestedPartItem.relatedRecordId,
            'The related record should be the parent Work Order.'
        );

        System.assertEquals(
            'Spindle Bearings',
            requestedPartItem.partName,
            'The Part Catalog name should be returned.'
        );

        System.assertEquals(
            Decimal.valueOf('1'),
            requestedPartItem.quantity,
            'The controller should return Quantity__c.'
        );

        System.assertEquals(
            requestedPartItem.quantity,
            requestedPartItem.quantityNeeded,
            'The compatibility quantity field should match Quantity__c.'
        );

        System.assertEquals(
            'Technician-created test request',
            requestedPartItem.notes
        );

        assertAction(
            requestedPartItem,
            'FLOW',
            'ORDER_TECHNICIAN_REQUESTED_PART',
            'Order Requested Part',
            'Order_Technician_Requested_Part',
            requestedPartRecord.Id
        );

        WorkOrder waitingWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Waiting for ordered parts'
            LIMIT 1
        ];

        System.assertEquals(
            null,
            findItemByRecordId(
                data.waitingOnParts,
                waitingWorkOrder.Id
            ),
            'The Waiting on Parts queue should not contain the parent ' +
            'Work Order as a row.'
        );

        Work_Order_Part__c orderedPartRecord = [
            SELECT Id, Work_Order__c
            FROM Work_Order_Part__c
            WHERE Order_Status__c = 'Ordered'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem orderedPartItem =
            findItemByRecordId(
                data.waitingOnParts,
                orderedPartRecord.Id
            );

        assertWaitingPartItem(
            orderedPartItem,
            orderedPartRecord,
            'Ordered'
        );

        Work_Order_Part__c shippedPartRecord = [
            SELECT Id, Work_Order__c
            FROM Work_Order_Part__c
            WHERE Order_Status__c = 'Shipped'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem shippedPartItem =
            findItemByRecordId(
                data.waitingOnParts,
                shippedPartRecord.Id
            );

        assertWaitingPartItem(
            shippedPartItem,
            shippedPartRecord,
            'Shipped'
        );

        WorkOrder readyWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Ready for technician assignment'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem readyItem =
            findItemByRecordId(
                data.readyToAssign,
                readyWorkOrder.Id
            );

        System.assertNotEquals(
            null,
            readyItem,
            'The Ready to Assign Work Order should be returned.'
        );

        System.assertEquals(
            'Ready to Assign',
            readyItem.status,
            'The LWC should receive the readable picklist label.'
        );

        assertAction(
            readyItem,
            'FLOW',
            'DISPATCH_TECHNICIAN',
            'Dispatch Technician',
            'Dispatch_Technician',
            readyWorkOrder.Id
        );

        WorkOrder upcomingAssignedWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Upcoming assigned visit'
            LIMIT 1
        ];

        ManagerOperationsCenterController.QueueItem assignedItem =
            findItemByRecordId(
                data.assignedVisits,
                upcomingAssignedWorkOrder.Id
            );

        System.assertNotEquals(
            null,
            assignedItem,
            'The upcoming Assigned visit should be returned.'
        );

        assertAction(
            assignedItem,
            'NAVIGATE',
            'VIEW_WORK_ORDER',
            'Open Work Order',
            null,
            upcomingAssignedWorkOrder.Id
        );

        System.assertEquals(
            'Upcoming assigned visit',
            assignedItem.subject,
            'The returned visit should be the future visit.'
        );

        System.assertNotEquals(
            null,
            assignedItem.scheduledVisit,
            'The upcoming visit should return its Date/Time value.'
        );

        WorkOrder pastAssignedWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Past assigned visit'
            LIMIT 1
        ];

        System.assertEquals(
            null,
            findItemByRecordId(
                data.assignedVisits,
                pastAssignedWorkOrder.Id
            ),
            'A past Assigned visit must not appear in the upcoming queue.'
        );
    }

    @IsTest
    static void excludesCompletedAndCancelledPartStatuses() {
        Test.startTest();

        ManagerOperationsCenterController.OperationsData data =
            ManagerOperationsCenterController.getOperationsData();

        Test.stopTest();

        Set<String> excludedStatuses = new Set<String>{
            'Received',
            'Installed',
            'Cancelled'
        };

        List<Work_Order_Part__c> excludedParts = [
            SELECT Id, Order_Status__c
            FROM Work_Order_Part__c
            WHERE Order_Status__c IN :excludedStatuses
        ];

        for (Work_Order_Part__c part : excludedParts) {
            System.assertEquals(
                null,
                findItemByRecordId(
                    data.partsToOrder,
                    part.Id
                ),
                part.Order_Status__c +
                ' parts must not appear in Parts to Order.'
            );

            System.assertEquals(
                null,
                findItemByRecordId(
                    data.waitingOnParts,
                    part.Id
                ),
                part.Order_Status__c +
                ' parts must not appear in Waiting on Parts.'
            );
        }
    }

    @IsTest
    static void getOperationsDataHandlesNullOptionalRelationships() {
        WorkOrder workOrderWithoutRelationships = new WorkOrder(
            Subject = 'Active repair without optional relationships',
            Status = 'New',
            Priority = 'Medium',
            Dispatch_Status__c = 'In Progress',
            Service_Manager__c = UserInfo.getUserId()
        );
        insert workOrderWithoutRelationships;

        Test.startTest();

        ManagerOperationsCenterController.OperationsData data =
            ManagerOperationsCenterController.getOperationsData();

        Test.stopTest();

        ManagerOperationsCenterController.QueueItem result =
            findItemByRecordId(
                data.activeRepairs,
                workOrderWithoutRelationships.Id
            );

        System.assertNotEquals(
            null,
            result,
            'The Work Order should be returned without Account or Asset.'
        );

        System.assertEquals(
            null,
            result.accountName,
            'A missing Account should produce a null Account name.'
        );

        System.assertEquals(
            null,
            result.assetName,
            'A missing Asset should produce a null Asset name.'
        );

        System.assertEquals(
            null,
            result.technicianName,
            'A missing Assigned Technician should produce a null name.'
        );

        assertAction(
            result,
            'NAVIGATE',
            'VIEW_WORK_ORDER',
            'Open Work Order',
            null,
            workOrderWithoutRelationships.Id
        );
    }

    @IsTest
    static void getOperationsDataReturnsInitializedEmptyQueues() {
        delete [SELECT Id FROM Work_Order_Part__c];
        delete [SELECT Id FROM WorkOrder];
        delete [SELECT Id FROM Case];

        Test.startTest();

        ManagerOperationsCenterController.OperationsData data =
            ManagerOperationsCenterController.getOperationsData();

        Test.stopTest();

        System.assertEquals(0, data.newCasesCount);
        System.assertEquals(0, data.requiresReviewCount);
        System.assertEquals(0, data.partsToOrderCount);
        System.assertEquals(0, data.waitingOnPartsCount);
        System.assertEquals(0, data.readyToAssignCount);
        System.assertEquals(0, data.assignedVisitsCount);
        System.assertEquals(0, data.activeRepairsCount);

        System.assertNotEquals(null, data.newCases);
        System.assertNotEquals(null, data.requiresReview);
        System.assertNotEquals(null, data.partsToOrder);
        System.assertNotEquals(null, data.waitingOnParts);
        System.assertNotEquals(null, data.readyToAssign);
        System.assertNotEquals(null, data.assignedVisits);
        System.assertNotEquals(null, data.activeRepairs);
    }

    private static WorkOrder buildWorkOrder(
        String subject,
        String dispatchStatus,
        Datetime scheduledVisit,
        Id accountId,
        Id assetId,
        Id caseId
    ) {
        WorkOrder workOrder = new WorkOrder(
            Subject = subject,
            Status = 'New',
            Priority = 'High',
            Dispatch_Status__c = dispatchStatus,
            AccountId = accountId,
            AssetId = assetId,
            CaseId = caseId,
            Service_Manager__c = UserInfo.getUserId(),
            Problem_Summary__c = 'Test problem summary',
            Recommended_Solution__c =
                'Test recommended solution',
            Recommended_Fix_Summary__c =
                'Test recommended repair',
            Recommended_Tools__c = 'Test service tools',
            Recommended_Parts__c = 'Test recommended parts'
        );

        if (scheduledVisit != null) {
            workOrder.Scheduled_Visit__c = scheduledVisit;
        }

        if (dispatchStatus == 'Assigned') {
            workOrder.Suggested_Technician__c =
                UserInfo.getUserId();
        }

        if (dispatchStatus == 'Temporary Fix') {
            workOrder.Technician_Notes__c =
                'Temporary repair completed for testing.';
        }

        return workOrder;
    }

    private static Work_Order_Part__c buildWorkOrderPart(
        Id workOrderId,
        Id machineId,
        Id partCatalogId,
        Decimal quantity,
        String orderStatus,
        String notes,
        String supplierName,
        String supplierPhone,
        String orderUrl,
        Id orderedById
    ) {
        Work_Order_Part__c part = new Work_Order_Part__c(
            Work_Order__c = workOrderId,
            Machine__c = machineId,
            Part_Catalog__c = partCatalogId,
            Quantity__c = quantity,
            Order_Status__c = orderStatus,
            Notes__c = notes,
            Supplier_Name__c = supplierName,
            Supplier_Phone__c = supplierPhone,
            Order_URL__c = orderUrl
        );

        if (orderedById != null) {
            part.Ordered_By__c = orderedById;
        }

        return part;
    }

    private static void assertWaitingPartItem(
        ManagerOperationsCenterController.QueueItem item,
        Work_Order_Part__c expectedPart,
        String expectedStatus
    ) {
        System.assertNotEquals(
            null,
            item,
            expectedStatus +
            ' Work Order Part should appear in Waiting on Parts.'
        );

        System.assertEquals(
            'Work_Order_Part__c',
            item.objectApiName
        );

        System.assertEquals(
            'ORDERED_PART',
            item.rowType
        );

        System.assertEquals(
            expectedStatus,
            item.status
        );

        System.assertEquals(
            expectedPart.Id,
            item.partId
        );

        System.assertEquals(
            expectedPart.Work_Order__c,
            item.workOrderId
        );

        System.assertEquals(
            expectedPart.Work_Order__c,
            item.relatedRecordId
        );

        System.assertEquals(
            'Spindle Bearings',
            item.partName
        );

        System.assertNotEquals(
            null,
            item.supplierName,
            'Ordered and Shipped rows should return supplier information.'
        );

        System.assertNotEquals(
            null,
            item.orderedByName,
            'Ordered and Shipped rows should return Ordered By.'
        );

        assertAction(
            item,
            'FLOW',
            'RECEIVE_PARTS',
            'Receive Parts',
            'Receive_Parts_From_Work_Order',
            expectedPart.Work_Order__c
        );
    }

    private static void assertCountsMatchLists(
        ManagerOperationsCenterController.OperationsData data
    ) {
        System.assertEquals(
            data.newCases.size(),
            data.newCasesCount
        );

        System.assertEquals(
            data.requiresReview.size(),
            data.requiresReviewCount
        );

        System.assertEquals(
            data.partsToOrder.size(),
            data.partsToOrderCount
        );

        System.assertEquals(
            data.waitingOnParts.size(),
            data.waitingOnPartsCount
        );

        System.assertEquals(
            data.readyToAssign.size(),
            data.readyToAssignCount
        );

        System.assertEquals(
            data.assignedVisits.size(),
            data.assignedVisitsCount
        );

        System.assertEquals(
            data.activeRepairs.size(),
            data.activeRepairsCount
        );
    }

    private static void assertAction(
        ManagerOperationsCenterController.QueueItem item,
        String expectedType,
        String expectedName,
        String expectedLabel,
        String expectedFlowApiName,
        Id expectedActionRecordId
    ) {
        System.assertEquals(
            expectedType,
            item.actionType,
            'Unexpected action type.'
        );

        System.assertEquals(
            expectedName,
            item.actionName,
            'Unexpected action name.'
        );

        System.assertEquals(
            expectedLabel,
            item.actionLabel,
            'Unexpected action label.'
        );

        System.assertEquals(
            expectedFlowApiName,
            item.flowApiName,
            'Unexpected Flow API name.'
        );

        System.assertEquals(
            expectedActionRecordId,
            item.actionRecordId,
            'The action should receive the correct record ID.'
        );
    }

    private static ManagerOperationsCenterController.QueueItem
        findItemByRecordId(
            List<ManagerOperationsCenterController.QueueItem> items,
            Id recordId
        ) {
            for (
                ManagerOperationsCenterController.QueueItem item : items
            ) {
                if (item.recordId == recordId) {
                    return item;
                }
            }

            return null;
        }
}