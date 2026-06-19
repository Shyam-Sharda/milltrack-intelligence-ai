@IsTest
private class CreateWorkOrderPartsTest {
    private static Account createAccount() {
        Account acct = new Account(Name = 'Test Lab');
        insert acct;
        return acct;
    }

    private static Asset createMachine(Account acct) {
        Asset machine = new Asset(
            Name = 'Roland DWX-52D',
            AccountId = acct.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Serial_Number__c = 'TEST-SN-001'
        );
        insert machine;
        return machine;
    }

    private static WorkOrder createWorkOrder(Account acct, Asset machine) {
        WorkOrder wo = new WorkOrder(
            Subject = 'Test Work Order',
            AccountId = acct.Id,
            AssetId = machine.Id,
            Status = 'New'
        );
        insert wo;
        return wo;
    }

    private static Part_Catalog__c createCatalogPart() {
        Part_Catalog__c catalogPart = new Part_Catalog__c(
            Name = 'Spindle Bearings',
            Part_Number__c = 'SB-001',
            Manufacturer__c = 'Roland',
            Compatible_Model__c = 'DWX-52D',
            Parts_Category__c = 'Spindle',
            Supplier_Name__c = 'Roland Supplier',
            Supplier_Phone__c = '555-123-4567',
            Order_URL__c = 'https://example.com/spindle-bearings',
            Active__c = true,
            Keyword_Aliases__c = 'spindle bearing bearings spindle assembly'
        );
        insert catalogPart;
        return catalogPart;
    }

    @IsTest
    static void createsMatchedWorkOrderPart() {
        Account acct = createAccount();
        Asset machine = createMachine(acct);
        WorkOrder wo = createWorkOrder(acct, machine);
        Part_Catalog__c catalogPart = createCatalogPart();

        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();
        req.workOrderId = wo.Id;
        req.machineId = machine.Id;
        req.recommendedPartsJson = '{"parts":[{"name":"Spindle Bearings","quantity":1}]}';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results[0].createdCount);
        System.assertEquals('', results[0].unmatchedParts);
        System.assert(results[0].statusMessage.contains('Created 1'));

        List<Work_Order_Part__c> createdParts = [
            SELECT Id, Work_Order__c, Machine__c, Part_Catalog__c,
                Quantity__c, Quantity_Needed__c, Supplier_Name__c,
                Supplier_Phone__c, Order_URL__c, Notes__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :wo.Id
        ];

        System.assertEquals(1, createdParts.size());
        System.assertEquals(catalogPart.Id, createdParts[0].Part_Catalog__c);
        System.assertEquals(1, createdParts[0].Quantity__c);
        System.assertEquals(1, createdParts[0].Quantity_Needed__c);
        System.assertEquals('Roland Supplier', createdParts[0].Supplier_Name__c);
        System.assertEquals('555-123-4567', createdParts[0].Supplier_Phone__c);
        System.assertEquals('https://example.com/spindle-bearings', createdParts[0].Order_URL__c);
    }

    @IsTest
    static void updatesExistingPartInsteadOfCreatingDuplicate() {
        Account acct = createAccount();
        Asset machine = createMachine(acct);
        WorkOrder wo = createWorkOrder(acct, machine);
        Part_Catalog__c catalogPart = createCatalogPart();

        Work_Order_Part__c existingPart = new Work_Order_Part__c(
            Work_Order__c = wo.Id,
            Machine__c = machine.Id,
            Part_Catalog__c = catalogPart.Id,
            Quantity__c = 1,
            Quantity_Needed__c = 1,
            Supplier_Name__c = 'Roland Supplier',
            Supplier_Phone__c = '555-123-4567',
            Order_URL__c = 'https://example.com/spindle-bearings'
        );
        insert existingPart;

        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();
        req.workOrderId = wo.Id;
        req.machineId = machine.Id;
        req.recommendedPartsJson = '{"parts":[{"name":"Spindle Bearings","quantity":2}]}';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assertEquals('', results[0].unmatchedParts);
        System.assert(results[0].statusMessage.contains('Updated 1'));

        List<Work_Order_Part__c> parts = [
            SELECT Id, Quantity__c, Quantity_Needed__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :wo.Id
        ];

        System.assertEquals(1, parts.size());
        System.assertEquals(3, parts[0].Quantity__c);
        System.assertEquals(3, parts[0].Quantity_Needed__c);
    }

    @IsTest
    static void returnsUnmatchedPartsWhenNoCatalogMatchExists() {
        Account acct = createAccount();
        Asset machine = createMachine(acct);
        WorkOrder wo = createWorkOrder(acct, machine);
        createCatalogPart();

        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();
        req.workOrderId = wo.Id;
        req.machineId = machine.Id;
        req.recommendedPartsJson = '{"parts":[{"name":"Random thingie majiggie that dosent exist","quantity":2}]}';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assertEquals('Random thingie majiggie that dosent exist', results[0].unmatchedParts);
        System.assertEquals(0,[SELECT COUNT() FROM Work_Order_Part__c WHERE Work_Order__c = :wo.Id]);
    }

    @IsTest
    static void handlesBlankJsonGracefully() {
        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();

        req.workOrderId = UserInfo.getUserId();
        req.machineId = UserInfo.getUserId();
        req.recommendedPartsJson = '';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assertEquals('', results[0].unmatchedParts);
        System.assertEquals('No recommended parts JSON provided.', results[0].statusMessage);
    }

    @IsTest
    static void handlesInvalidJsonGracefully() {
        Account acct = createAccount();
        Asset machine = createMachine(acct);
        WorkOrder wo = createWorkOrder(acct, machine);

        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();
        req.workOrderId = wo.Id;
        req.machineId = machine.Id;
        req.recommendedPartsJson = 'this is not valid json';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assertEquals('', results[0].unmatchedParts);
        System.assertEquals('No valid parts found in JSON.', results[0].statusMessage);
    }

    @IsTest
    static void handlesInvalidQuantityGracefully() {
        Account acct = createAccount();
        Asset machine = createMachine(acct);
        WorkOrder wo = createWorkOrder(acct, machine);
        createCatalogPart();

        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();
        req.workOrderId = wo.Id;
        req.machineId = machine.Id;
        req.recommendedPartsJson = '{"parts":[{"name":"Spindle Bearings","quantity":"two"}]}';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results[0].createdCount);

        Work_Order_Part__c createdPart = [
            SELECT Quantity__c, Quantity_Needed__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :wo.Id
            LIMIT 1
        ];

        System.assertEquals(1, createdPart.Quantity__c);
        System.assertEquals(1, createdPart.Quantity_Needed__c);
    }

    @IsTest
    static void handlesMissingMachineIdGracefully() {
        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();

        req.workOrderId = UserInfo.getUserId();
        req.machineId = null;
        req.recommendedPartsJson = '{"parts":[{"name":"Spindle Bearings","quantity":1}]}';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assertEquals('Missing Machine Id.', results[0].statusMessage);
    }

    @IsTest
    static void handlesMissingWorkOrderIdGracefully() {
        Account acct = createAccount();
        Asset machine = createMachine(acct);

        CreateWorkOrderParts.Request req = new CreateWorkOrderParts.Request();

        req.workOrderId = null;
        req.machineId = machine.Id;
        req.recommendedPartsJson = '{"parts":[{"name":"Spindle Bearings","quantity":1}]}';

        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assertEquals('Missing Work Order Id.', results[0].statusMessage);
    }

    @IsTest
    static void handlesNoRequestsGracefully() {
        Test.startTest();
        List<CreateWorkOrderParts.Result> results = CreateWorkOrderParts.createParts(new List<CreateWorkOrderParts.Request>());
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(0, results[0].createdCount);
        System.assertEquals('No requests were provided.', results[0].statusMessage);
    }

}
