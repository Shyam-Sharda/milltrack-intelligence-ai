@IsTest
private class ManagerOrderPartsControllerTest {

    // =========================================================
    // TEST SETUP
    // =========================================================

    @TestSetup
    static void createBaseData() {
        Account testAccount = new Account(
            Name = 'Manager Order Parts Test Lab'
        );
        insert testAccount;

        Asset testAsset = new Asset(
            Name = 'Order Parts Test DWX-52D',
            AccountId = testAccount.Id,
            SerialNumber = 'ORDER-PARTS-TEST-001',
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Machine_Status__c = 'Needs Service'
        );
        insert testAsset;

        List<Part_Catalog__c> catalogParts =
            new List<Part_Catalog__c>{
                new Part_Catalog__c(
                    Name = 'Spindle Bearing',
                    Part_Number__c = 'MOP-SP-001',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Spindle',
                    Supplier_Name__c = 'Roland Parts Supplier',
                    Supplier_Phone__c = '555-111-0001',
                    Order_URL__c = 'https://example.com/spindle-bearing',
                    Active__c = true,
                    Keyword_Aliases__c = 'spindle bearing bearings'
                ),
                new Part_Catalog__c(
                    Name = 'Coolant Filter',
                    Part_Number__c = 'MOP-CF-002',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Coolant System',
                    Supplier_Name__c = 'MillTrack Parts Supply',
                    Supplier_Phone__c = '555-111-0002',
                    Order_URL__c = 'https://example.com/coolant-filter',
                    Active__c = true,
                    Keyword_Aliases__c = 'coolant filter filtration'
                ),
                new Part_Catalog__c(
                    Name = 'Door Sensor',
                    Part_Number__c = 'MOP-DS-003',
                    Manufacturer__c = 'Roland',
                    Compatible_Model__c = 'DWX-52D',
                    Parts_Category__c = 'Calibration & Sensors',
                    Supplier_Name__c = 'Dental Machine Supply',
                    Supplier_Phone__c = '555-111-0003',
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
    static void getOrderPartsContextReturnsRequestedPartsAndCommittedState() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Context test Work Order',
            'Parts to Order',
            assetRecord
        );

        Part_Catalog__c spindlePart = getCatalogPart('MOP-SP-001');
        Part_Catalog__c coolantPart = getCatalogPart('MOP-CF-002');
        Part_Catalog__c doorPart = getCatalogPart('MOP-DS-003');

        Work_Order_Part__c requestedOne = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            spindlePart.Id,
            2,
            'Requested',
            'First requested part'
        );

        Work_Order_Part__c requestedTwo = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            coolantPart.Id,
            3,
            'Requested',
            'Second requested part'
        );

        /*
         * Snapshot supplier data onto one Requested record.
         * buildPartRow should prefer these values over the catalog.
         */
        requestedTwo.Supplier_Name__c = 'Existing Snapshot Supplier';
        requestedTwo.Supplier_Phone__c = '555-999-8888';
        requestedTwo.Order_URL__c = 'https://example.com/existing-snapshot';

        update requestedTwo;

        Work_Order_Part__c committedPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            doorPart.Id,
            1,
            'Ordered',
            'Already committed part'
        );

        committedPart.Ordered_By__c = UserInfo.getUserId();

        update committedPart;

        /*
         * Cancelled parts must not count as existing committed parts.
         */
        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            doorPart.Id,
            1,
            'Cancelled',
            'Previously cancelled part'
        );

        Test.startTest();

        ManagerOrderPartsController.OrderPartsContext context =
            ManagerOrderPartsController.getOrderPartsContext(
                workOrderRecord.Id
            );

        Test.stopTest();

        System.assertNotEquals(null, context, 'The controller should return an ordering context.');

        System.assertEquals(workOrderRecord.Id, context.workOrderId);

        System.assertNotEquals(null, context.workOrderNumber);

        System.assertEquals('Parts to Order', context.dispatchStatus);

        System.assertEquals(assetRecord.Id, context.assetId);

        System.assertEquals(assetRecord.Name, context.assetName);

        System.assertEquals(true, context.isEligible);

        System.assertEquals(2, context.requestedPartCount, 'Only Requested Work Order Parts should be returned.');

        System.assertEquals(Decimal.valueOf('5'), context.requestedUnitCount, 'Requested units should total 2 + 3.');

        System.assertEquals(true, context.hasExistingCommittedParts, 'The existing Ordered part should count as committed.');

        System.assertEquals(1, context.existingCommittedPartCount, 'Cancelled parts must not count as committed.');

        ManagerOrderPartsController.RequestedPartRow spindleRow =
            findRequestedRow(
                context.requestedParts,
                requestedOne.Id
            );

        System.assertNotEquals(null, spindleRow);

        System.assertEquals(spindlePart.Id, spindleRow.partCatalogId);

        System.assertEquals('Spindle Bearing', spindleRow.partName);

        System.assertEquals('MOP-SP-001', spindleRow.partNumber);

        System.assertEquals('Spindle', spindleRow.category);

        System.assertEquals(Decimal.valueOf('2'), spindleRow.quantity);

        System.assertEquals('Roland Parts Supplier', spindleRow.supplierName, 'Supplier information should fall back to the Part Catalog.');

        System.assertEquals('555-111-0001', spindleRow.supplierPhone);

        System.assertEquals('https://example.com/spindle-bearing', spindleRow.orderUrl);

        ManagerOrderPartsController.RequestedPartRow coolantRow =
            findRequestedRow(
                context.requestedParts,
                requestedTwo.Id
            );

        System.assertNotEquals(null, coolantRow);

        System.assertEquals('Existing Snapshot Supplier', coolantRow.supplierName, 'Existing Work Order Part snapshot data should take precedence.');

        System.assertEquals('555-999-8888', coolantRow.supplierPhone);

        System.assertEquals('https://example.com/existing-snapshot', coolantRow.orderUrl);
    }

    @IsTest
    static void getOrderPartsContextReturnsIneligibleContextForWrongStatus() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Ineligible ordering context',
            'Pending',
            assetRecord
        );

        Part_Catalog__c catalogPart = getCatalogPart('MOP-SP-001');

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            catalogPart.Id,
            1,
            'Requested',
            'Should not load while Pending'
        );

        Test.startTest();

        ManagerOrderPartsController.OrderPartsContext context =
            ManagerOrderPartsController.getOrderPartsContext(
                workOrderRecord.Id
            );

        Test.stopTest();

        System.assertEquals(false, context.isEligible);

        System.assertEquals(0, context.requestedPartCount);

        System.assertEquals(0, context.requestedParts.size());

        System.assert(context.eligibilityMessage.contains('Pending'), 'The eligibility message should identify the current status.');
    }

    @IsTest
    static void getOrderPartsContextHandlesNoRequestedParts() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Parts to Order without Requested parts',
            'Parts to Order',
            assetRecord
        );

        Test.startTest();

        ManagerOrderPartsController.OrderPartsContext context =
            ManagerOrderPartsController.getOrderPartsContext(
                workOrderRecord.Id
            );

        Test.stopTest();

        System.assertEquals(true, context.isEligible);

        System.assertEquals(0, context.requestedPartCount);

        System.assertEquals(Decimal.valueOf('0'), context.requestedUnitCount);

        System.assert(context.eligibilityMessage.contains('no Requested parts remaining'));
    }

    @IsTest
    static void getOrderPartsContextRejectsNullWorkOrderId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerOrderPartsController.getOrderPartsContext(
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A null Work Order Id should be rejected.');
    }

    // =========================================================
    // SAVE - PARTIAL ORDER
    // =========================================================

    @IsTest
    static void savePartialOrderKeepsWorkOrderInPartsToOrder() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Partial ordering test',
            'Parts to Order',
            assetRecord
        );

        Part_Catalog__c spindlePart = getCatalogPart('MOP-SP-001');
        Part_Catalog__c coolantPart = getCatalogPart('MOP-CF-002');
        Part_Catalog__c doorPart = getCatalogPart('MOP-DS-003');

        Work_Order_Part__c orderedPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            spindlePart.Id,
            1,
            'Requested',
            'Manager will order this'
        );

        Work_Order_Part__c remainingPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            coolantPart.Id,
            2,
            'Requested',
            'Manager will leave this Requested'
        );

        Work_Order_Part__c cancelledPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            doorPart.Id,
            1,
            'Requested',
            'Manager will remove this requirement'
        );

        List<ManagerOrderPartsController.PartOrderDecision> decisions =
            new List<ManagerOrderPartsController.PartOrderDecision>{
                buildDecision(
                    orderedPart.Id,
                    true,
                    true
                ),
                buildDecision(
                    remainingPart.Id,
                    true,
                    false
                ),
                buildDecision(
                    cancelledPart.Id,
                    false,
                    false
                )
            };

        Test.startTest();

        ManagerOrderPartsController.SaveOrderPartsResult result =
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                decisions
            );

        Test.stopTest();

        System.assertEquals('Parts to Order', result.workOrderStatus);

        System.assertEquals('Needs Service', result.assetStatus, 'Partial ordering must preserve the Asset machine condition.');

        System.assertEquals(false, result.allOrderingComplete);

        System.assertEquals(false, result.readyToAssign);

        System.assertEquals(1, result.orderedPartCount);

        System.assertEquals(1, result.remainingPartCount);

        System.assertEquals(1, result.cancelledPartCount);

        System.assertEquals('Complete Remaining Parts Orders', result.nextStepLabel);

        WorkOrder refreshedWorkOrder = [
            SELECT
                Dispatch_Status__c,
                Case.Status,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        System.assertEquals('Parts to Order', refreshedWorkOrder.Dispatch_Status__c);

        System.assertEquals('In Progress', refreshedWorkOrder.Case.Status, 'The Case should remain In Progress while some parts still need ordering.');

        System.assertEquals('Needs Service', refreshedWorkOrder.Asset.Machine_Status__c, 'Ordering parts must not change the machine condition.');

        Map<Id, Work_Order_Part__c> refreshedParts =
            new Map<Id, Work_Order_Part__c>([
                SELECT
                    Id,
                    Order_Status__c,
                    Ordered_By__c,
                    Supplier_Name__c,
                    Supplier_Phone__c,
                    Order_URL__c
                FROM Work_Order_Part__c
                WHERE Id IN :new Set<Id>{
                    orderedPart.Id,
                    remainingPart.Id,
                    cancelledPart.Id
                }
            ]);

        Work_Order_Part__c refreshedOrdered = refreshedParts.get(orderedPart.Id);

        System.assertEquals('Ordered', refreshedOrdered.Order_Status__c);

        System.assertEquals(UserInfo.getUserId(), refreshedOrdered.Ordered_By__c);

        System.assertEquals('Roland Parts Supplier', refreshedOrdered.Supplier_Name__c, 'Ordering should snapshot supplier data from the Part Catalog.');

        System.assertEquals('555-111-0001', refreshedOrdered.Supplier_Phone__c);

        System.assertEquals('https://example.com/spindle-bearing', refreshedOrdered.Order_URL__c);

        System.assertEquals('Requested', refreshedParts .get(remainingPart.Id) .Order_Status__c);

        System.assertEquals('Cancelled', refreshedParts .get(cancelledPart.Id) .Order_Status__c);

        System.assertEquals(null, refreshedParts .get(cancelledPart.Id) .Ordered_By__c);
    }

    // =========================================================
    // SAVE - ALL ORDERED
    // =========================================================

    @IsTest
    static void saveAllOrderedMovesWorkOrderToWaitingOnParts() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'All parts ordered test',
            'Parts to Order',
            assetRecord
        );

        Work_Order_Part__c firstPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Requested',
            'First required part'
        );

        Work_Order_Part__c secondPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-CF-002').Id,
            2,
            'Requested',
            'Second required part'
        );

        List<ManagerOrderPartsController.PartOrderDecision> decisions =
            new List<ManagerOrderPartsController.PartOrderDecision>{
                buildDecision(
                    firstPart.Id,
                    true,
                    true
                ),
                buildDecision(
                    secondPart.Id,
                    true,
                    true
                )
            };

        Test.startTest();

        ManagerOrderPartsController.SaveOrderPartsResult result =
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                decisions
            );

        Test.stopTest();

        System.assertEquals(true, result.allOrderingComplete);

        System.assertEquals(false, result.readyToAssign);

        System.assertEquals('Waiting on Parts', result.workOrderStatus);

        System.assertEquals('Needs Service', result.assetStatus, 'The Asset should remain Needs Service while the service lifecycle waits for parts.');

        System.assertEquals(2, result.orderedPartCount);

        System.assertEquals(0, result.remainingPartCount);

        System.assertEquals(0, result.cancelledPartCount);

        System.assertEquals('Waiting on Parts', result.nextStepLabel);

        WorkOrder refreshedWorkOrder = [
            SELECT
                Dispatch_Status__c,
                Case.Status,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        System.assertEquals('Waiting on Parts', refreshedWorkOrder.Dispatch_Status__c);

        System.assertEquals('Waiting on Parts', refreshedWorkOrder.Case.Status, 'Once all required parts are ordered, the Case should enter Waiting on Parts.');

        System.assertEquals('Needs Service', refreshedWorkOrder.Asset.Machine_Status__c, 'Ordering completion must not change the machine condition.');
    }

    // =========================================================
    // SAVE - ALL CANCELLED
    // =========================================================

    @IsTest
    static void saveAllCancelledMovesWorkOrderToReadyToAssign() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'All requirements removed test',
            'Parts to Order',
            assetRecord
        );

        Work_Order_Part__c firstPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Requested',
            'No longer required'
        );

        Work_Order_Part__c secondPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-CF-002').Id,
            1,
            'Requested',
            'Also no longer required'
        );

        List<ManagerOrderPartsController.PartOrderDecision> decisions =
            new List<ManagerOrderPartsController.PartOrderDecision>{
                buildDecision(
                    firstPart.Id,
                    false,
                    false
                ),
                buildDecision(
                    secondPart.Id,
                    false,
                    false
                )
            };

        Test.startTest();

        ManagerOrderPartsController.SaveOrderPartsResult result =
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                decisions
            );

        Test.stopTest();

        System.assertEquals(true, result.allOrderingComplete);

        System.assertEquals(true, result.readyToAssign);

        System.assertEquals('Ready_to_Assign', result.workOrderStatus);

        System.assertEquals('Needs Service', result.assetStatus, 'Removing all part requirements must not change the machine condition.');

        System.assertEquals(0, result.orderedPartCount);

        System.assertEquals(0, result.remainingPartCount);

        System.assertEquals(2, result.cancelledPartCount);

        System.assertEquals('Assign a Technician', result.nextStepLabel);

        WorkOrder refreshedWorkOrder = [
            SELECT
                Dispatch_Status__c,
                Case.Status,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        System.assertEquals('Ready_to_Assign', refreshedWorkOrder.Dispatch_Status__c, 'Use the exact stored Dispatch Status API value.');

        System.assertEquals('In Progress', refreshedWorkOrder.Case.Status, 'If no parts remain required, the Case should stay In Progress.');

        System.assertEquals('Needs Service', refreshedWorkOrder.Asset.Machine_Status__c, 'Ready to Assign is a Work Order state, not an Asset state.');
    }

    // =========================================================
    // SAVE - EXISTING COMMITTED PARTS
    // =========================================================

    @IsTest
    static void saveCancelledRemainingRequestHonorsExistingCommittedPart() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Existing committed lifecycle test',
            'Parts to Order',
            assetRecord
        );

        Work_Order_Part__c existingOrderedPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Ordered',
            'Ordered during an earlier manager session'
        );

        existingOrderedPart.Ordered_By__c = UserInfo.getUserId();

        update existingOrderedPart;

        Work_Order_Part__c remainingRequestedPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-CF-002').Id,
            1,
            'Requested',
            'Manager removes remaining requirement'
        );

        List<ManagerOrderPartsController.PartOrderDecision> decisions =
            new List<ManagerOrderPartsController.PartOrderDecision>{
                buildDecision(
                    remainingRequestedPart.Id,
                    false,
                    false
                )
            };

        Test.startTest();

        ManagerOrderPartsController.SaveOrderPartsResult result =
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                decisions
            );

        Test.stopTest();

        /*
         * Even though the current Requested part was cancelled,
         * the Work Order already has a real Ordered part.
         * Therefore it must wait for that part rather than become
         * Ready to Assign.
         */
        System.assertEquals('Waiting on Parts', result.workOrderStatus);

        System.assertEquals('Needs Service', result.assetStatus, 'Existing committed parts must not change the Asset machine condition.');

        System.assertEquals(true, result.allOrderingComplete);

        System.assertEquals(false, result.readyToAssign);

        System.assertEquals(1, result.cancelledPartCount);

        WorkOrder refreshedWorkOrder = [
            SELECT
                Dispatch_Status__c,
                Case.Status,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        System.assertEquals('Waiting on Parts', refreshedWorkOrder.Dispatch_Status__c);

        System.assertEquals('Waiting on Parts', refreshedWorkOrder.Case.Status, 'An already Ordered part still blocks the service on parts delivery.');

        System.assertEquals('Needs Service', refreshedWorkOrder.Asset.Machine_Status__c, 'The Asset should remain Needs Service.');

        System.assertEquals(
            'Ordered',
            [
                SELECT Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id = :existingOrderedPart.Id
            ].Order_Status__c
        );
    }

    // =========================================================
    // TECHNICIAN-REQUESTED PART CONTEXT
    // =========================================================

    @IsTest
    static void getTechnicianRequestedPartContextReturnsEligibleRequestedPart() {
        Asset assetRecord = getTestAsset();
        WorkOrder workOrderRecord = createWorkOrder('Technician requested context', 'Waiting on Parts', assetRecord);
        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id, assetRecord.Id, getCatalogPart('MOP-SP-001').Id, 2, 'Requested',
            'Technician found spindle wear during onsite repair.'
        );

        Test.startTest();
        ManagerOrderPartsController.TechnicianRequestedPartContext context = ManagerOrderPartsController.getTechnicianRequestedPartContext(partRecord.Id);
        Test.stopTest();

        System.assertEquals(true, context.isEligible);
        System.assertEquals(partRecord.Id, context.workOrderPartId);
        System.assertEquals(workOrderRecord.Id, context.workOrderId);
        System.assertNotEquals(null, context.workOrderNumber);
        System.assertEquals('Waiting on Parts', context.dispatchStatus);
        System.assertEquals(assetRecord.Id, context.assetId);
        System.assertEquals(assetRecord.Name, context.assetName);
        System.assertEquals('Manager Order Parts Test Lab', context.accountName);
        System.assertNotEquals(null, context.requestedPart);
        System.assertEquals('Spindle Bearing', context.requestedPart.partName);
        System.assertEquals('MOP-SP-001', context.requestedPart.partNumber);
        System.assertEquals(Decimal.valueOf('2'), context.requestedPart.quantity);
        System.assertEquals('Technician found spindle wear during onsite repair.', context.requestedPart.notes);
        System.assertEquals('Requested', context.requestedPart.orderStatus);
        System.assertEquals('Roland Parts Supplier', context.requestedPart.supplierName);
        System.assertEquals('555-111-0001', context.requestedPart.supplierPhone);
        System.assertEquals('https://example.com/spindle-bearing', context.requestedPart.orderUrl);
    }

    @IsTest
    static void getTechnicianRequestedPartContextRejectsWrongPartStatus() {
        Asset assetRecord = getTestAsset();
        WorkOrder workOrderRecord = createWorkOrder('Technician requested wrong part status', 'Waiting on Parts', assetRecord);
        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id, assetRecord.Id, getCatalogPart('MOP-CF-002').Id, 1, 'Ordered', 'Already ordered.'
        );

        Test.startTest();
        ManagerOrderPartsController.TechnicianRequestedPartContext context = ManagerOrderPartsController.getTechnicianRequestedPartContext(partRecord.Id);
        Test.stopTest();

        System.assertEquals(false, context.isEligible);
        System.assert(context.eligibilityMessage.contains('Ordered'));
        System.assert(context.eligibilityMessage.contains('Waiting on Parts'));
    }

    @IsTest
    static void getTechnicianRequestedPartContextRejectsWrongWorkOrderStatus() {
        Asset assetRecord = getTestAsset();
        WorkOrder workOrderRecord = createWorkOrder('Technician requested wrong Work Order status', 'Assigned', assetRecord);
        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id, assetRecord.Id, getCatalogPart('MOP-CF-002').Id, 1, 'Requested', 'Requested during repair.'
        );

        Test.startTest();
        ManagerOrderPartsController.TechnicianRequestedPartContext context = ManagerOrderPartsController.getTechnicianRequestedPartContext(partRecord.Id);
        Test.stopTest();

        System.assertEquals(false, context.isEligible);
        System.assert(context.eligibilityMessage.contains('Requested'));
        System.assert(context.eligibilityMessage.contains('Assigned'));
    }

    @IsTest
    static void getTechnicianRequestedPartContextRejectsNullId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ManagerOrderPartsController.getTechnicianRequestedPartContext(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    // =========================================================
    // TECHNICIAN-REQUESTED PART SAVE
    // =========================================================

    @IsTest
    static void orderTechnicianRequestedPartMarksPartOrderedAndPreservesLifecycle() {
        Asset assetRecord = getTestAsset();
        WorkOrder workOrderRecord = createWorkOrder('Order technician requested part', 'Waiting on Parts', assetRecord);
        update new Case(Id = workOrderRecord.CaseId, Status = 'Waiting on Parts');
        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id, assetRecord.Id, getCatalogPart('MOP-DS-003').Id, 1, 'Requested',
            'Technician needs replacement door sensor before repair can continue.'
        );

        Test.startTest();
        ManagerOrderPartsController.TechnicianRequestedPartResult result =
            ManagerOrderPartsController.orderTechnicianRequestedPart(
                partRecord.Id,
                '  Field Service Supplier  ',
                '  555-700-9000  ',
                '  https://example.com/field-order  '
            );
        Test.stopTest();

        System.assertEquals(partRecord.Id, result.workOrderPartId);
        System.assertEquals(workOrderRecord.Id, result.workOrderId);
        System.assertEquals('Waiting on Parts', result.workOrderStatus);
        System.assertEquals('Door Sensor', result.partName);
        System.assertEquals('MOP-DS-003', result.partNumber);
        System.assertEquals('Ordered', result.orderStatus);
        System.assertEquals('Field Service Supplier', result.supplierName);
        System.assertEquals('555-700-9000', result.supplierPhone);
        System.assertEquals('https://example.com/field-order', result.orderUrl);
        System.assertEquals('Wait for Part Delivery', result.nextStepLabel);

        Work_Order_Part__c refreshedPart = [
            SELECT Order_Status__c, Ordered_By__c, Supplier_Name__c, Supplier_Phone__c, Order_URL__c
            FROM Work_Order_Part__c WHERE Id = :partRecord.Id
        ];
        System.assertEquals('Ordered', refreshedPart.Order_Status__c);
        System.assertEquals(UserInfo.getUserId(), refreshedPart.Ordered_By__c);
        System.assertEquals('Field Service Supplier', refreshedPart.Supplier_Name__c);
        System.assertEquals('555-700-9000', refreshedPart.Supplier_Phone__c);
        System.assertEquals('https://example.com/field-order', refreshedPart.Order_URL__c);

        WorkOrder refreshedWorkOrder = [
            SELECT Dispatch_Status__c, Case.Status, Asset.Machine_Status__c
            FROM WorkOrder WHERE Id = :workOrderRecord.Id
        ];
        System.assertEquals('Waiting on Parts', refreshedWorkOrder.Dispatch_Status__c);
        System.assertEquals('Waiting on Parts', refreshedWorkOrder.Case.Status, 'MGR 05 must not change the Case lifecycle.');
        System.assertEquals('Needs Service', refreshedWorkOrder.Asset.Machine_Status__c, 'Ordering a technician-requested part must not change the machine condition.');
    }

    @IsTest
    static void orderTechnicianRequestedPartRejectsWrongPartStatus() {
        Asset assetRecord = getTestAsset();
        WorkOrder workOrderRecord = createWorkOrder('Order technician part wrong part status', 'Waiting on Parts', assetRecord);
        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id, assetRecord.Id, getCatalogPart('MOP-SP-001').Id, 1, 'Ordered', 'Already ordered.'
        );
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ManagerOrderPartsController.orderTechnicianRequestedPart(
                partRecord.Id, 'Supplier', '555-111-2222', 'https://example.com/order'
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void orderTechnicianRequestedPartRejectsWrongWorkOrderStatus() {
        Asset assetRecord = getTestAsset();
        WorkOrder workOrderRecord = createWorkOrder('Order technician part wrong Work Order status', 'Assigned', assetRecord);
        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id, assetRecord.Id, getCatalogPart('MOP-SP-001').Id, 1, 'Requested', 'Requested during repair.'
        );
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ManagerOrderPartsController.orderTechnicianRequestedPart(
                partRecord.Id, 'Supplier', '555-111-2222', 'https://example.com/order'
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
        System.assertEquals(
            'Requested',
            [SELECT Order_Status__c FROM Work_Order_Part__c WHERE Id = :partRecord.Id].Order_Status__c,
            'A failed MGR 05 save must leave the part unchanged.'
        );
    }

    @IsTest
    static void orderTechnicianRequestedPartRejectsMissingInputs() {
        Asset assetRecord = getTestAsset();
        WorkOrder workOrderRecord = createWorkOrder('Order technician part missing inputs', 'Waiting on Parts', assetRecord);
        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id, assetRecord.Id, getCatalogPart('MOP-SP-001').Id, 1, 'Requested', 'Requested during repair.'
        );

        Boolean nullIdRejected = false, supplierRejected = false, phoneRejected = false, urlRejected = false;

        try {
            ManagerOrderPartsController.orderTechnicianRequestedPart(null, 'Supplier', '555-111-2222', 'https://example.com/order');
        } catch (AuraHandledException e) {
            nullIdRejected = true;
        }

        try {
            ManagerOrderPartsController.orderTechnicianRequestedPart(partRecord.Id, ' ', '555-111-2222', 'https://example.com/order');
        } catch (AuraHandledException e) {
            supplierRejected = true;
        }

        try {
            ManagerOrderPartsController.orderTechnicianRequestedPart(partRecord.Id, 'Supplier', ' ', 'https://example.com/order');
        } catch (AuraHandledException e) {
            phoneRejected = true;
        }

        try {
            ManagerOrderPartsController.orderTechnicianRequestedPart(partRecord.Id, 'Supplier', '555-111-2222', ' ');
        } catch (AuraHandledException e) {
            urlRejected = true;
        }

        System.assertEquals(true, nullIdRejected);
        System.assertEquals(true, supplierRejected);
        System.assertEquals(true, phoneRejected);
        System.assertEquals(true, urlRejected);
        System.assertEquals('Requested', [SELECT Order_Status__c FROM Work_Order_Part__c WHERE Id = :partRecord.Id].Order_Status__c);
    }

    // =========================================================
    // VALIDATION
    // =========================================================

    @IsTest
    static void saveOrderingDecisionsRejectsNullInputs() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Null input validation',
            'Parts to Order',
            assetRecord
        );

        Boolean nullWorkOrderRejected = false;

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                null,
                new List<ManagerOrderPartsController.PartOrderDecision>()
            );
        } catch (AuraHandledException e) {
            nullWorkOrderRejected = true;
        }

        System.assertEquals(true, nullWorkOrderRejected);

        Boolean nullDecisionListRejected = false;

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                null
            );
        } catch (AuraHandledException e) {
            nullDecisionListRejected = true;
        }

        System.assertEquals(true, nullDecisionListRejected);
    }

    @IsTest
    static void saveOrderingDecisionsRejectsWrongWorkOrderStatus() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Wrong lifecycle status test',
            'Pending',
            assetRecord
        );

        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Requested',
            'Requested but Work Order is Pending'
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                new List<ManagerOrderPartsController.PartOrderDecision>{
                    buildDecision(
                        partRecord.Id,
                        true,
                        true
                    )
                }
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Only Parts to Order Work Orders may be saved.');
    }

    @IsTest
    static void saveOrderingDecisionsRejectsWorkOrderWithNoRequestedParts() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'No Requested parts save test',
            'Parts to Order',
            assetRecord
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                new List<ManagerOrderPartsController.PartOrderDecision>()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void saveOrderingDecisionsRejectsDuplicatePartDecision() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Duplicate decision test',
            'Parts to Order',
            assetRecord
        );

        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Requested',
            'Duplicate submission test'
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                new List<ManagerOrderPartsController.PartOrderDecision>{
                    buildDecision(
                        partRecord.Id,
                        true,
                        true
                    ),
                    buildDecision(
                        partRecord.Id,
                        true,
                        true
                    )
                }
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Duplicate Work Order Part decisions must be rejected.');
    }

    @IsTest
    static void saveOrderingDecisionsRejectsRemovedAndOrderedPart() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Contradictory decision test',
            'Parts to Order',
            assetRecord
        );

        Work_Order_Part__c partRecord = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Requested',
            'Cannot remove and order'
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                new List<ManagerOrderPartsController.PartOrderDecision>{
                    buildDecision(
                        partRecord.Id,
                        false,
                        true
                    )
                }
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A removed part cannot simultaneously be confirmed as ordered.');
    }

    @IsTest
    static void saveOrderingDecisionsRejectsStaleIncompleteSubmission() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Stale wizard submission test',
            'Parts to Order',
            assetRecord
        );

        Work_Order_Part__c firstPart = createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Requested',
            'First Requested record'
        );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-CF-002').Id,
            1,
            'Requested',
            'Second Requested record'
        );

        /*
         * Deliberately submit only one of the two currently
         * Requested records.
         */
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                new List<ManagerOrderPartsController.PartOrderDecision>{
                    buildDecision(
                        firstPart.Id,
                        true,
                        true
                    )
                }
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'The stale-browser protection should require a decision for every current Requested part.');

        /*
         * The controller uses a Savepoint/rollback, so nothing
         * should have changed after the failed request.
         */
        Integer requestedCount = [
            SELECT COUNT()
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrderRecord.Id
                AND Order_Status__c = 'Requested'
        ];

        System.assertEquals(2, requestedCount);
    }

    @IsTest
    static void saveOrderingDecisionsRejectsDecisionWithoutPartId() {
        Asset assetRecord = getTestAsset();

        WorkOrder workOrderRecord = createWorkOrder(
            'Missing decision ID test',
            'Parts to Order',
            assetRecord
        );

        createPart(
            workOrderRecord.Id,
            assetRecord.Id,
            getCatalogPart('MOP-SP-001').Id,
            1,
            'Requested',
            'Requested record'
        );

        ManagerOrderPartsController.PartOrderDecision invalidDecision = new ManagerOrderPartsController.PartOrderDecision();
        invalidDecision.keepRequired = true;
        invalidDecision.orderConfirmed = false;
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ManagerOrderPartsController.saveOrderingDecisions(
                workOrderRecord.Id,
                new List<ManagerOrderPartsController.PartOrderDecision>{
                    invalidDecision
                }
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
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
            WHERE SerialNumber = 'ORDER-PARTS-TEST-001'
            LIMIT 1
        ];
    }

    private static Part_Catalog__c getCatalogPart(String partNumber) {
        return [
            SELECT
                Id,
                Name,
                Part_Number__c,
                Supplier_Name__c,
                Supplier_Phone__c,
                Order_URL__c
            FROM Part_Catalog__c
            WHERE Part_Number__c = :partNumber
            LIMIT 1
        ];
    }

    private static WorkOrder createWorkOrder(String subject, String dispatchStatus, Asset assetRecord) {

        Case caseRecord = new Case(
            AccountId = assetRecord.AccountId,
            AssetId = assetRecord.Id,
            Subject = 'Case for ' + subject,
            Status = 'In Progress',
            Origin = 'Web',
            Priority = 'High',
            Work_Order_Proposal_Created__c = true
        );

        insert caseRecord;

        WorkOrder workOrderRecord = new WorkOrder(
            Subject = subject,
            Status = 'New',
            Priority = 'High',
            Dispatch_Status__c = dispatchStatus,
            AccountId = assetRecord.AccountId,
            AssetId = assetRecord.Id,
            CaseId = caseRecord.Id,
            Service_Manager__c = UserInfo.getUserId(),
            Problem_Summary__c = 'Manager Order Parts controller test problem.',
            Recommended_Solution__c = 'Test recommended solution.',
            Recommended_Fix_Summary__c = 'Test recommended fix.',
            Recommended_Tools__c = 'Test tools.',
            Recommended_Parts__c = 'Test recommended parts.'
        );

        insert workOrderRecord;

        return workOrderRecord;
    }

    private static Work_Order_Part__c createPart(Id workOrderId, Id assetId, Id catalogPartId, Decimal quantity, String status, String notes) {
        Work_Order_Part__c partRecord =
            new Work_Order_Part__c(
                Work_Order__c = workOrderId,
                Machine__c = assetId,
                Part_Catalog__c = catalogPartId,
                Quantity__c = quantity,
                Order_Status__c = status,
                Notes__c = notes
            );

        insert partRecord;

        return partRecord;
    }

    private static ManagerOrderPartsController.PartOrderDecision
        buildDecision(
            Id workOrderPartId,
            Boolean keepRequired,
            Boolean orderConfirmed
        ) {
            ManagerOrderPartsController.PartOrderDecision decision = new ManagerOrderPartsController.PartOrderDecision();
            decision.workOrderPartId = workOrderPartId;
            decision.keepRequired = keepRequired;
            decision.orderConfirmed = orderConfirmed;

            return decision;
        }

    private static ManagerOrderPartsController.RequestedPartRow
        findRequestedRow(
            List<ManagerOrderPartsController.RequestedPartRow> rows,
            Id workOrderPartId
        ) {
            for (
                ManagerOrderPartsController.RequestedPartRow row :
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
