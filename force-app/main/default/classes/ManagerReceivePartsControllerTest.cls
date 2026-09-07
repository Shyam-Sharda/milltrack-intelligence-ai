@IsTest
private class ManagerReceivePartsControllerTest {

    // =========================================================
    // TEST SETUP
    // =========================================================

    @TestSetup
    static void createBaseData() {

        Account testAccount = new Account(
            Name = 'Manager Receive Parts Test Lab'
        );
        insert testAccount;

        Asset testAsset = new Asset(
            Name = 'Receive Parts Test DWX-52D',
            AccountId = testAccount.Id,
            SerialNumber = 'RECEIVE-PARTS-TEST-001',
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Machine_Status__c = 'Needs Service'
        );
        insert testAsset;

        List<Part_Catalog__c> catalogParts =
            new List<Part_Catalog__c>{
                new Part_Catalog__c(
                    Name = 'Spindle Bearing',
                    Part_Number__c = 'MRP-SP-001',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Spindle',
                    Supplier_Name__c = 'Roland Parts Supplier',
                    Supplier_Phone__c = '555-111-1001',
                    Order_URL__c = 'https://example.com/spindle-bearing',
                    Active__c = true,
                    Keyword_Aliases__c = 'spindle bearing bearings'
                ),
                new Part_Catalog__c(
                    Name = 'Coolant Filter',
                    Part_Number__c = 'MRP-CF-002',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Coolant System',
                    Supplier_Name__c = 'MillTrack Parts Supply',
                    Supplier_Phone__c = '555-111-1002',
                    Order_URL__c = 'https://example.com/coolant-filter',
                    Active__c = true,
                    Keyword_Aliases__c = 'coolant filter filtration'
                ),
                new Part_Catalog__c(
                    Name = 'Door Sensor',
                    Part_Number__c = 'MRP-DS-003',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Calibration & Sensors',
                    Supplier_Name__c = 'Dental Machine Supply',
                    Supplier_Phone__c = '555-111-1003',
                    Order_URL__c = 'https://example.com/door-sensor',
                    Active__c = true,
                    Keyword_Aliases__c = 'door sensor switch'
                )
            };

        insert catalogParts;
    }


    // =========================================================
    // GET CONTEXT
    // =========================================================

    @IsTest
    static void getReceivePartsContextReturnsOrderedAndShippedParts() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Receive parts context test',
                'Waiting on Parts',
                assetRecord
            );

        Work_Order_Part__c orderedPart =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                2,
                'Ordered',
                'Ordered part ready for receipt'
            );

        orderedPart.Supplier_Name__c =
            'Snapshot Supplier One';

        orderedPart.Supplier_Phone__c =
            '555-900-1001';

        orderedPart.Order_URL__c =
            'https://example.com/snapshot-one';

        update orderedPart;

        Work_Order_Part__c shippedPart =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-CF-002'
                ).Id,
                3,
                'Shipped',
                'Shipped part ready for receipt'
            );

        shippedPart.Supplier_Name__c =
            'Snapshot Supplier Two';

        shippedPart.Supplier_Phone__c =
            '555-900-1002';

        shippedPart.Order_URL__c =
            'https://example.com/snapshot-two';

        update shippedPart;

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart(
                'MRP-DS-003'
            ).Id,
            1,
            'Requested',
            'Still needs to be ordered'
        );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart(
                'MRP-DS-003'
            ).Id,
            4,
            'Received',
            'Already received'
        );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart(
                'MRP-DS-003'
            ).Id,
            5,
            'Cancelled',
            'Cancelled part'
        );

        Test.startTest();

        ManagerReceivePartsController.ReceivePartsContext context =
            ManagerReceivePartsController.getReceivePartsContext(workOrderRecord.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            context
        );

        System.assertEquals(
            workOrderRecord.Id,
            context.workOrderId
        );

        System.assertNotEquals(
            null,
            context.workOrderNumber
        );

        System.assertEquals(
            'Receive parts context test',
            context.subject
        );

        System.assertEquals(
            'Waiting on Parts',
            context.dispatchStatus
        );

        System.assertEquals(
            assetRecord.Id,
            context.assetId
        );

        System.assertEquals(
            assetRecord.Name,
            context.assetName
        );

        System.assertEquals(
            'Needs Service',
            context.assetStatus
        );

        System.assertEquals(
            true,
            context.isEligible
        );

        System.assertEquals(
            true,
            context.hasReceivableParts
        );

        System.assertEquals(
            2,
            context.receivablePartCount,
            'Only Ordered and Shipped parts should be receivable.'
        );

        System.assertEquals(
            Decimal.valueOf('5'),
            context.receivableUnitCount,
            'Receivable units should total 2 + 3.'
        );

        System.assertEquals(
            3,
            context.outstandingPartCount,
            'Requested, Ordered and Shipped should all count as outstanding.'
        );

        System.assertEquals(
            Decimal.valueOf('6'),
            context.outstandingUnitCount,
            'Outstanding units should total 2 + 3 + 1.'
        );

        ManagerReceivePartsController.ReceivablePartRow orderedRow =
            findReceivableRow(
                context.receivableParts,
                orderedPart.Id
            );

        System.assertNotEquals(
            null,
            orderedRow
        );

        System.assertEquals(
            'Spindle Bearing',
            orderedRow.partName
        );

        System.assertEquals(
            'MRP-SP-001',
            orderedRow.partNumber
        );

        System.assertEquals(
            'Spindle',
            orderedRow.category
        );

        System.assertEquals(
            Decimal.valueOf('2'),
            orderedRow.quantity
        );

        System.assertEquals(
            'Snapshot Supplier One',
            orderedRow.supplierName
        );

        System.assertEquals(
            '555-900-1001',
            orderedRow.supplierPhone
        );

        System.assertEquals(
            'https://example.com/snapshot-one',
            orderedRow.orderUrl
        );

        System.assertEquals(
            'Ordered',
            orderedRow.orderStatus
        );

        ManagerReceivePartsController.ReceivablePartRow shippedRow =
            findReceivableRow(
                context.receivableParts,
                shippedPart.Id
            );

        System.assertNotEquals(
            null,
            shippedRow
        );

        System.assertEquals(
            'Shipped',
            shippedRow.orderStatus
        );
    }


    @IsTest
    static void getReceivePartsContextReturnsIneligibleForWrongStatus() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Wrong lifecycle context test',
                'Ready_to_Assign',
                assetRecord
            );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart(
                'MRP-SP-001'
            ).Id,
            1,
            'Ordered',
            'Should not be exposed for receipt'
        );

        Test.startTest();

        ManagerReceivePartsController.ReceivePartsContext context =
            ManagerReceivePartsController.getReceivePartsContext(workOrderRecord.Id);

        Test.stopTest();

        System.assertEquals(
            false,
            context.isEligible
        );

        System.assertEquals(
            false,
            context.hasReceivableParts
        );

        System.assertEquals(
            0,
            context.receivablePartCount
        );

        System.assertEquals(
            0,
            context.receivableParts.size()
        );

        System.assert(
            context.eligibilityMessage.contains(
                'Ready_to_Assign'
            ),
            'The eligibility message should identify the current lifecycle status.'
        );
    }


    @IsTest
    static void getReceivePartsContextHandlesNoReceivableParts() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'No receivable parts context',
                'Waiting on Parts',
                assetRecord
            );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart(
                'MRP-SP-001'
            ).Id,
            2,
            'Requested',
            'Requested part has not been ordered'
        );

        Test.startTest();

        ManagerReceivePartsController.ReceivePartsContext context =
            ManagerReceivePartsController.getReceivePartsContext(workOrderRecord.Id);

        Test.stopTest();

        System.assertEquals(
            true,
            context.isEligible
        );

        System.assertEquals(
            false,
            context.hasReceivableParts
        );

        System.assertEquals(
            0,
            context.receivablePartCount
        );

        System.assertEquals(
            Decimal.valueOf('0'),
            context.receivableUnitCount
        );

        System.assertEquals(
            1,
            context.outstandingPartCount
        );

        System.assertEquals(
            Decimal.valueOf('2'),
            context.outstandingUnitCount
        );

        System.assert(
            context.eligibilityMessage.contains(
                'No Ordered or Shipped parts'
            )
        );
    }


    @IsTest
    static void getReceivePartsContextRejectsNullWorkOrderId() {

        Boolean exceptionThrown =
            false;

        Test.startTest();

        try {

            ManagerReceivePartsController.getReceivePartsContext(null);

        } catch (AuraHandledException e) {

            exceptionThrown =
                true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'A null Work Order Id should be rejected.'
        );
    }


    // =========================================================
    // RECEIVE - PARTIAL DELIVERY
    // =========================================================

    @IsTest
    static void receivePartialDeliveryKeepsWorkOrderWaitingOnParts() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Partial receipt test',
                'Waiting on Parts',
                assetRecord
            );

        Work_Order_Part__c receivedNow =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                1,
                'Shipped',
                'Arrived in current delivery'
            );

        Work_Order_Part__c stillOutstanding =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-CF-002'
                ).Id,
                2,
                'Ordered',
                'Has not arrived yet'
            );

        Test.startTest();

        ManagerReceivePartsController.ReceivePartsResult result =
            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>{
                    receivedNow.Id
                }
            );

        Test.stopTest();

        System.assertEquals(
            1,
            result.receivedPartCount
        );

        System.assertEquals(
            Decimal.valueOf('1'),
            result.receivedUnitCount
        );

        System.assertEquals(
            1,
            result.outstandingPartCount
        );

        System.assertEquals(
            Decimal.valueOf('2'),
            result.outstandingUnitCount
        );

        System.assertEquals(
            false,
            result.allRequiredPartsReceived
        );

        System.assertEquals(
            false,
            result.readyToAssign
        );

        System.assertEquals(
            'Waiting on Parts',
            result.workOrderStatus
        );

        System.assertEquals(
            'Needs Service',
            result.assetStatus,
            'Receiving only part of the delivery must not change the Asset status.'
        );

        System.assertEquals(
            'Waiting on Parts',
            result.nextStepLabel
        );

        Map<Id, Work_Order_Part__c> refreshedParts =
            new Map<Id, Work_Order_Part__c>([
                SELECT
                    Id,
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id IN :new Set<Id>{
                    receivedNow.Id,
                    stillOutstanding.Id
                }
            ]);

        System.assertEquals(
            'Received',
            refreshedParts
                .get(receivedNow.Id)
                .Order_Status__c
        );

        System.assertEquals(
            'Ordered',
            refreshedParts
                .get(stillOutstanding.Id)
                .Order_Status__c
        );

        WorkOrder refreshedWorkOrder = [
            SELECT
                Dispatch_Status__c,
                Case.Status,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        System.assertEquals(
            'Waiting on Parts',
            refreshedWorkOrder.Dispatch_Status__c
        );

        System.assertEquals(
            'Waiting on Parts',
            refreshedWorkOrder.Case.Status,
            'A partial delivery should keep the related Case Waiting on Parts.'
        );

        System.assertEquals(
            'Needs Service',
            refreshedWorkOrder.Asset.Machine_Status__c,
            'A partial delivery must not change the machine condition.'
        );
    }


    // =========================================================
    // RECEIVE - REQUESTED PART STILL OUTSTANDING
    // =========================================================

    @IsTest
    static void receiveOrderedPartDoesNotAdvanceWhileRequestedPartRemains() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Requested part still outstanding test',
                'Waiting on Parts',
                assetRecord
            );

        Work_Order_Part__c arrivingPart =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                1,
                'Ordered',
                'Arriving part'
            );

        Work_Order_Part__c requestedPart =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-CF-002'
                ).Id,
                3,
                'Requested',
                'Still waiting to be ordered'
            );

        Test.startTest();

        ManagerReceivePartsController.ReceivePartsResult result =
            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>{
                    arrivingPart.Id
                }
            );

        Test.stopTest();

        System.assertEquals(
            false,
            result.allRequiredPartsReceived,
            'A Requested part must prevent Ready to Assign.'
        );

        System.assertEquals(
            1,
            result.outstandingPartCount
        );

        System.assertEquals(
            Decimal.valueOf('3'),
            result.outstandingUnitCount
        );

        System.assertEquals(
            'Waiting on Parts',
            result.workOrderStatus
        );

        System.assertEquals(
            'Needs Service',
            result.assetStatus
        );

        System.assertEquals(
            'Requested',
            [
                SELECT
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id =
                    :requestedPart.Id
            ].Order_Status__c
        );

        WorkOrder refreshedWorkOrder = [
            SELECT
                Dispatch_Status__c,
                Case.Status,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        System.assertEquals(
            'Waiting on Parts',
            refreshedWorkOrder.Dispatch_Status__c
        );

        System.assertEquals(
            'Waiting on Parts',
            refreshedWorkOrder.Case.Status
        );

        System.assertEquals(
            'Needs Service',
            refreshedWorkOrder.Asset.Machine_Status__c
        );
    }


    // =========================================================
    // RECEIVE - FINAL DELIVERY
    // =========================================================

    @IsTest
    static void receiveFinalDeliveryMovesWorkOrderToReadyToAssign() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Final receipt test',
                'Waiting on Parts',
                assetRecord
            );

        Work_Order_Part__c orderedPart =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                1,
                'Ordered',
                'Final ordered part'
            );

        Work_Order_Part__c shippedPart =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-CF-002'
                ).Id,
                2,
                'Shipped',
                'Final shipped part'
            );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart(
                'MRP-DS-003'
            ).Id,
            1,
            'Received',
            'Previously received part'
        );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart(
                'MRP-DS-003'
            ).Id,
            1,
            'Cancelled',
            'Previously cancelled part'
        );

        Test.startTest();

        ManagerReceivePartsController.ReceivePartsResult result =
            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>{
                    orderedPart.Id,
                    shippedPart.Id
                }
            );

        Test.stopTest();

        System.assertEquals(
            2,
            result.receivedPartCount
        );

        System.assertEquals(
            Decimal.valueOf('3'),
            result.receivedUnitCount
        );

        System.assertEquals(
            0,
            result.outstandingPartCount
        );

        System.assertEquals(
            Decimal.valueOf('0'),
            result.outstandingUnitCount
        );

        System.assertEquals(
            true,
            result.allRequiredPartsReceived
        );

        System.assertEquals(
            true,
            result.readyToAssign
        );

        System.assertEquals(
            'Ready_to_Assign',
            result.workOrderStatus
        );

        System.assertEquals(
            'Needs Service',
            result.assetStatus,
            'Final receipt must not change the Asset machine condition.'
        );

        System.assertEquals(
            'Assign a Technician',
            result.nextStepLabel
        );

        WorkOrder refreshedWorkOrder = [
            SELECT
                Dispatch_Status__c,
                Case.Status,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        System.assertEquals(
            'Ready_to_Assign',
            refreshedWorkOrder.Dispatch_Status__c,
            'Use the exact stored Work Order Dispatch Status value.'
        );

        System.assertEquals(
            'In Progress',
            refreshedWorkOrder.Case.Status,
            'Once every required part has arrived, the related Case should return to In Progress.'
        );

        System.assertEquals(
            'Needs Service',
            refreshedWorkOrder.Asset.Machine_Status__c,
            'Ready to Assign is a Work Order state, not an Asset state.'
        );

        Map<Id, Work_Order_Part__c> refreshedParts =
            new Map<Id, Work_Order_Part__c>([
                SELECT
                    Id,
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id IN :new Set<Id>{
                    orderedPart.Id,
                    shippedPart.Id
                }
            ]);

        System.assertEquals(
            'Received',
            refreshedParts
                .get(orderedPart.Id)
                .Order_Status__c
        );

        System.assertEquals(
            'Received',
            refreshedParts
                .get(shippedPart.Id)
                .Order_Status__c
        );
    }


    // =========================================================
    // VALIDATION
    // =========================================================

    @IsTest
    static void receivePartsRejectsNullAndEmptyInputs() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Input validation test',
                'Waiting on Parts',
                assetRecord
            );

        Boolean nullWorkOrderRejected =
            false;

        try {

            ManagerReceivePartsController.receiveParts(
                null,
                new List<Id>()
            );

        } catch (AuraHandledException e) {

            nullWorkOrderRejected =
                true;
        }

        System.assertEquals(
            true,
            nullWorkOrderRejected
        );

        Boolean nullPartListRejected =
            false;

        try {

            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                null
            );

        } catch (AuraHandledException e) {

            nullPartListRejected =
                true;
        }

        System.assertEquals(
            true,
            nullPartListRejected
        );

        Boolean emptyPartListRejected =
            false;

        try {

            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>()
            );

        } catch (AuraHandledException e) {

            emptyPartListRejected =
                true;
        }

        System.assertEquals(
            true,
            emptyPartListRejected
        );
    }


    @IsTest
    static void receivePartsRejectsDuplicatePartIds() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Duplicate receipt test',
                'Waiting on Parts',
                assetRecord
            );

        Work_Order_Part__c partRecord =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                1,
                'Ordered',
                'Duplicate selection test'
            );

        Boolean exceptionThrown =
            false;

        Test.startTest();

        try {

            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>{
                    partRecord.Id,
                    partRecord.Id
                }
            );

        } catch (AuraHandledException e) {

            exceptionThrown =
                true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Duplicate Work Order Part Ids must be rejected.'
        );

        System.assertEquals(
            'Ordered',
            [
                SELECT
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id =
                    :partRecord.Id
            ].Order_Status__c
        );
    }


    @IsTest
    static void receivePartsRejectsWrongWorkOrderStatus() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Wrong Work Order lifecycle test',
                'Ready_to_Assign',
                assetRecord
            );

        Work_Order_Part__c partRecord =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                1,
                'Ordered',
                'Cannot receive outside Waiting on Parts'
            );

        Boolean exceptionThrown =
            false;

        Test.startTest();

        try {

            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>{
                    partRecord.Id
                }
            );

        } catch (AuraHandledException e) {

            exceptionThrown =
                true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Only Waiting on Parts Work Orders may receive parts.'
        );

        System.assertEquals(
            'Ordered',
            [
                SELECT
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id =
                    :partRecord.Id
            ].Order_Status__c
        );
    }


    @IsTest
    static void receivePartsRejectsPartFromDifferentWorkOrder() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder firstWorkOrder =
            createWorkOrder(
                'First Work Order',
                'Waiting on Parts',
                assetRecord
            );

        WorkOrder secondWorkOrder =
            createWorkOrder(
                'Second Work Order',
                'Waiting on Parts',
                assetRecord
            );

        Work_Order_Part__c secondWorkOrderPart =
            createPart(
                secondWorkOrder.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                1,
                'Ordered',
                'Belongs to the second Work Order'
            );

        Boolean exceptionThrown =
            false;

        Test.startTest();

        try {

            ManagerReceivePartsController.receiveParts(
                firstWorkOrder.Id,
                new List<Id>{
                    secondWorkOrderPart.Id
                }
            );

        } catch (AuraHandledException e) {

            exceptionThrown =
                true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'A manager must not receive a part belonging to another Work Order.'
        );

        System.assertEquals(
            'Ordered',
            [
                SELECT
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id =
                    :secondWorkOrderPart.Id
            ].Order_Status__c
        );
    }


    @IsTest
    static void receivePartsRejectsNonReceivablePartStatus() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Invalid part status test',
                'Waiting on Parts',
                assetRecord
            );

        Work_Order_Part__c receivedPart =
            createPart(
                workOrderRecord.Id,
                assetRecord.Id,
                getCatalogPart(
                    'MRP-SP-001'
                ).Id,
                1,
                'Received',
                'Already received'
            );

        Boolean exceptionThrown =
            false;

        Test.startTest();

        try {

            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>{
                    receivedPart.Id
                }
            );

        } catch (AuraHandledException e) {

            exceptionThrown =
                true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Only Ordered or Shipped records may be received.'
        );

        System.assertEquals(
            'Received',
            [
                SELECT
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id =
                    :receivedPart.Id
            ].Order_Status__c
        );
    }


    @IsTest
    static void receivePartsRejectsNullPartId() {

        Asset assetRecord =
            getTestAsset();

        WorkOrder workOrderRecord =
            createWorkOrder(
                'Null Part Id test',
                'Waiting on Parts',
                assetRecord
            );

        Boolean exceptionThrown =
            false;

        Test.startTest();

        try {

            ManagerReceivePartsController.receiveParts(
                workOrderRecord.Id,
                new List<Id>{
                    null
                }
            );

        } catch (AuraHandledException e) {

            exceptionThrown =
                true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown
        );
    }


    // =========================================================
    // HELPERS
    // =========================================================

    private static Asset getTestAsset() {

        return [
            SELECT
                Id,
                Name,
                AccountId,
                Machine_Status__c
            FROM Asset
            WHERE SerialNumber =
                'RECEIVE-PARTS-TEST-001'
            LIMIT 1
        ];
    }


    private static Part_Catalog__c getCatalogPart(
        String partNumber
    ) {

        return [
            SELECT
                Id,
                Name,
                Part_Number__c,
                Parts_Category__c,
                Supplier_Name__c,
                Supplier_Phone__c,
                Order_URL__c
            FROM Part_Catalog__c
            WHERE Part_Number__c =
                :partNumber
            LIMIT 1
        ];
    }


    private static WorkOrder createWorkOrder(
        String subject,
        String dispatchStatus,
        Asset assetRecord
    ) {

        Case caseRecord =
            new Case(
                AccountId =
                    assetRecord.AccountId,

                AssetId =
                    assetRecord.Id,

                Subject =
                    'Case for ' +
                    subject,

                Status =
                    'Waiting on Parts',

                Origin =
                    'Web',

                Priority =
                    'High',

                Work_Order_Proposal_Created__c =
                    true
            );

        insert caseRecord;

        WorkOrder workOrderRecord =
            new WorkOrder(
                Subject =
                    subject,

                Status =
                    'New',

                Priority =
                    'High',

                Dispatch_Status__c =
                    dispatchStatus,

                AccountId =
                    assetRecord.AccountId,

                AssetId =
                    assetRecord.Id,

                CaseId =
                    caseRecord.Id,

                Service_Manager__c =
                    UserInfo.getUserId(),

                Problem_Summary__c =
                    'Manager Receive Parts controller test problem.',

                Recommended_Solution__c =
                    'Test recommended solution.',

                Recommended_Fix_Summary__c =
                    'Test recommended fix.',

                Recommended_Tools__c =
                    'Test tools.',

                Recommended_Parts__c =
                    'Test recommended parts.'
            );

        insert workOrderRecord;

        return workOrderRecord;
    }


    private static Work_Order_Part__c createPart(
        Id workOrderId,
        Id assetId,
        Id catalogPartId,
        Decimal quantity,
        String status,
        String notes
    ) {

        Work_Order_Part__c partRecord =
            new Work_Order_Part__c(
                Work_Order__c =
                    workOrderId,

                Machine__c =
                    assetId,

                Part_Catalog__c =
                    catalogPartId,

                Quantity__c =
                    quantity,

                Order_Status__c =
                    status,

                Notes__c =
                    notes
            );

        insert partRecord;

        return partRecord;
    }


    private static ManagerReceivePartsController.ReceivablePartRow
        findReceivableRow(
            List<ManagerReceivePartsController.ReceivablePartRow> rows,
            Id workOrderPartId
        ) {

            for (
                ManagerReceivePartsController.ReceivablePartRow row :
                rows
            ) {

                if (
                    row.workOrderPartId ==
                    workOrderPartId
                ) {

                    return row;
                }
            }

            return null;
        }
}