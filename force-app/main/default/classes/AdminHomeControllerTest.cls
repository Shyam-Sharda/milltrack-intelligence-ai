@IsTest
private class AdminHomeControllerTest {

    private static final String ACCOUNT_NAME = 'Admin Home Test Customer';
    private static final String CONTACT_EMAIL = 'admin.home.contact@milltrack.test';
    private static final String ASSET_SERIAL = 'ADMIN-HOME-001';
    private static final String CASE_SUBJECT = 'Admin Home Test Service Request';
    private static final String WORK_ORDER_SUBJECT = 'Admin Home Test Service Visit';
    private static final String PART_NUMBER = 'MT-ADMIN-100';


    // =========================================================
    // Test Setup
    // =========================================================

    @TestSetup
    static void setupData() {

        // =====================================================
        // Account
        // =====================================================

        Account customerAccount = new Account(
            Name=ACCOUNT_NAME,
            Phone='604-555-0188',
            BillingStreet='100 MillTrack Way',
            BillingCity='Vancouver',
            BillingState='British Columbia',
            BillingPostalCode='V5K 0A1',
            BillingCountry='Canada'
        );

        insert customerAccount;
        Test.setCreatedDate(customerAccount.Id, System.now().addDays(-100));


        // =====================================================
        // Contact
        // =====================================================

        Contact customerContact = new Contact(
            FirstName='Olivia',
            LastName='Chen',
            MobilePhone='604-555-0211',
            Email=CONTACT_EMAIL,
            AccountId=customerAccount.Id
        );

        insert customerContact;


        // =====================================================
        // Asset
        // =====================================================

        Asset machine = new Asset(
            Name='Admin Home Ceramill Motion 2',
            AccountId=customerAccount.Id,
            Manufacturer__c='Amann Girrbach',
            Model__c='Ceramill Motion 2',
            Serial_Number__c=ASSET_SERIAL,
            Machine_Status__c='Active'
        );

        insert machine;


        // =====================================================
        // Case
        // =====================================================

        String caseOrigin = getFirstActivePicklistValue(Case.Origin);

        Case serviceRequest = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=machine.Id,
            Subject=CASE_SUBJECT,
            Description='Test service request for the Admin Home workspace.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        insert serviceRequest;


        // =====================================================
        // Work Order
        //
        // Standard Status is populated because Salesforce
        // requires it. MillTrack workflow uses Dispatch_Status__c.
        // =====================================================

        String workOrderStatus = getFirstActivePicklistValue(WorkOrder.Status);

        WorkOrder serviceVisit = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=machine.Id,
            CaseId=serviceRequest.Id,
            Subject=WORK_ORDER_SUBJECT,
            Status=workOrderStatus,
            Dispatch_Status__c='Ready_to_Assign',
            Scheduled_Visit__c=System.now().addDays(3),
            Recommended_Fix_Summary__c='Internal test repair plan.',
            Recommended_Solution__c='Customer-safe test recommendation.'
        );

        insert serviceVisit;


        // =====================================================
        // Maintenance Log
        // =====================================================

        Maintenance_Log__c maintenanceLog = new Maintenance_Log__c(
            Maintenance_Date__c=Date.today(),
            Root_Cause__c='Calibration drift',
            Issue_Resolved__c=true,
            Follow_Up_Required__c=false,
            Maintenance_Type__c='Repair'
        );

        setNameIfWritable(maintenanceLog, 'Admin Home Maintenance');
        putIfCreateable(maintenanceLog, 'Asset__c', machine.Id);
        putIfCreateable(maintenanceLog, 'Work_Order__c', serviceVisit.Id);
        putIfCreateable(
            maintenanceLog,
            'Problem_Summary__c',
            'Machine calibration was outside the expected range.'
        );
        putIfCreateable(
            maintenanceLog,
            'Summary__c',
            'Machine calibration was reviewed and corrected.'
        );

        insert maintenanceLog;


        // =====================================================
        // Part Catalog
        // =====================================================

        Part_Catalog__c partCatalog = new Part_Catalog__c();

        setNameIfWritable(partCatalog, 'Spindle Assembly');
        putIfCreateable(partCatalog, 'Part_Number__c', PART_NUMBER);
        putTextOrPicklist(partCatalog, 'Manufacturer__c', 'Amann Girrbach');
        putTextOrPicklist(partCatalog, 'Compatible_Model__c', 'Ceramill Motion 2');

        insert partCatalog;


        // =====================================================
        // Work Order Part
        // =====================================================

        Work_Order_Part__c workOrderPart = new Work_Order_Part__c(
            Part_Catalog__c=partCatalog.Id,
            Machine__c=machine.Id,
            Work_Order__c=serviceVisit.Id
        );

        setNameIfWritable(workOrderPart, 'MT-WOP-100');
        putNumberIfCreateable(workOrderPart, 'Quantity__c', 1);

        insert workOrderPart;


        // =====================================================
        // Service Manual
        // =====================================================

        Service_Manual__c serviceManual = new Service_Manual__c();

        setNameIfWritable(serviceManual, 'Ceramill Motion 2 Service Manual');
        putTextOrPicklist(serviceManual, 'Manufacturer__c', 'Amann Girrbach');
        putTextOrPicklist(serviceManual, 'Model__c', 'Ceramill Motion 2');
        putTextOrPicklist(serviceManual, 'Document_Type__c', 'Service Manual');

        insert serviceManual;
    }


    // =========================================================
    // Full Workspace
    // =========================================================

    @IsTest
    static void testGetHomeDataReturnsWorkspaceSections() {
        Account expectedAccount = [
            SELECT Id, Name
            FROM Account
            WHERE Name = :ACCOUNT_NAME
            LIMIT 1
        ];

        Contact expectedContact = [
            SELECT Id
            FROM Contact
            WHERE Email = :CONTACT_EMAIL
            LIMIT 1
        ];

        Asset expectedAsset = [
            SELECT Id
            FROM Asset
            WHERE Serial_Number__c = :ASSET_SERIAL
            LIMIT 1
        ];

        Case expectedCase = [
            SELECT Id
            FROM Case
            WHERE Subject = :CASE_SUBJECT
            LIMIT 1
        ];

        WorkOrder expectedWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :WORK_ORDER_SUBJECT
            LIMIT 1
        ];

        Test.startTest();
        AdminHomeController.AdminHomeData data = AdminHomeController.getHomeData();
        Test.stopTest();


        // =====================================================
        // Main Wrapper
        // =====================================================

        System.assertNotEquals(null, data, 'The Admin Home payload should be returned.');
        System.assertNotEquals(null, data.recentlyViewed, 'Recently Viewed should always return a list.');
        System.assert(
            data.recentlyViewed.size() <= 6,
            'Recently Viewed should never exceed six records.'
        );


        // =====================================================
        // Customer Setup
        // =====================================================

        System.assertEquals(1, data.accounts.size());
        System.assertEquals(expectedAccount.Id, data.accounts[0].id);
        System.assertEquals(ACCOUNT_NAME, data.accounts[0].name);
        System.assertEquals('604-555-0188', data.accounts[0].phone);
        System.assertEquals(
            '100 MillTrack Way, Vancouver, British Columbia V5K 0A1, Canada',
            data.accounts[0].billingAddress
        );

        System.assertEquals(1, data.contacts.size());
        System.assertEquals(expectedContact.Id, data.contacts[0].id);
        System.assertEquals('Olivia Chen', data.contacts[0].name);
        System.assertEquals('604-555-0211', data.contacts[0].mobile);
        System.assertEquals(CONTACT_EMAIL, data.contacts[0].email);
        System.assertEquals(ACCOUNT_NAME, data.contacts[0].accountName);

        System.assertEquals(1, data.assets.size());
        System.assertEquals(expectedAsset.Id, data.assets[0].id);
        System.assertEquals('Admin Home Ceramill Motion 2', data.assets[0].name);
        System.assertEquals('Amann Girrbach', data.assets[0].manufacturer);
        System.assertEquals('Ceramill Motion 2', data.assets[0].model);
        System.assertEquals(ASSET_SERIAL, data.assets[0].serialNumber);
        System.assertEquals(ACCOUNT_NAME, data.assets[0].accountName);


        // =====================================================
        // Service Operations
        // =====================================================

        System.assertEquals(1, data.cases.size());
        System.assertEquals(expectedCase.Id, data.cases[0].id);
        System.assertEquals(ACCOUNT_NAME, data.cases[0].accountName);
        System.assertEquals('Admin Home Ceramill Motion 2', data.cases[0].assetName);
        System.assertEquals(CASE_SUBJECT, data.cases[0].subject);

        System.assertEquals(1, data.workOrders.size());
        System.assertEquals(expectedWorkOrder.Id, data.workOrders[0].id);
        System.assertEquals(WORK_ORDER_SUBJECT, data.workOrders[0].subject);
        System.assertEquals('Admin Home Ceramill Motion 2', data.workOrders[0].assetName);

        System.assertEquals(
            'Ready_to_Assign',
            data.workOrders[0].dispatchStatus,
            'The underlying MillTrack Dispatch Status should be returned.'
        );

        System.assertEquals(
            'Ready to Assign',
            data.workOrders[0].displayStatus,
            'The admin-friendly Dispatch Status label should be returned.'
        );

        System.assertNotEquals(null, data.workOrders[0].scheduledVisit);

        System.assertEquals(1, data.maintenanceLogs.size());
        System.assertEquals('Calibration drift', data.maintenanceLogs[0].rootCause);
        System.assertEquals('Issue Resolved', data.maintenanceLogs[0].outcome);


        // =====================================================
        // Parts & Knowledge
        // =====================================================

        System.assertEquals(1, data.partCatalogs.size());
        System.assertEquals(PART_NUMBER, data.partCatalogs[0].partNumber);

        System.assertEquals(1, data.workOrderParts.size());
        System.assertEquals('Spindle Assembly', data.workOrderParts[0].partCatalogName);
        System.assertEquals('Admin Home Ceramill Motion 2', data.workOrderParts[0].machineName);
        System.assertNotEquals(null, data.workOrderParts[0].workOrderNumber);

        System.assertEquals(1, data.serviceManuals.size());
        System.assertNotEquals(null, data.serviceManuals[0].title);
    }


    // =========================================================
    // Maintenance Outcome
    // =========================================================

    @IsTest
    static void testMaintenanceOutcomeShowsFollowUpRequired() {
        Asset machine = [
            SELECT Id
            FROM Asset
            WHERE Serial_Number__c = :ASSET_SERIAL
            LIMIT 1
        ];

        WorkOrder serviceVisit = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :WORK_ORDER_SUBJECT
            LIMIT 1
        ];

        Maintenance_Log__c followUpLog = new Maintenance_Log__c(
            Maintenance_Date__c=Date.today(),
            Root_Cause__c='Spindle alignment requires follow-up',
            Issue_Resolved__c=false,
            Follow_Up_Required__c=true,
            Maintenance_Type__c='Repair'
        );

        setNameIfWritable(followUpLog, 'Admin Follow Up Maintenance');
        putIfCreateable(followUpLog, 'Asset__c', machine.Id);
        putIfCreateable(followUpLog, 'Work_Order__c', serviceVisit.Id);
        putIfCreateable(
            followUpLog,
            'Problem_Summary__c',
            'Spindle alignment requires additional service.'
        );
        putIfCreateable(followUpLog, 'Summary__c', 'Follow-up service is required.');

        insert followUpLog;

        Test.startTest();
        AdminHomeController.AdminHomeData data = AdminHomeController.getHomeData();
        Test.stopTest();

        AdminHomeController.MaintenanceLogItem matchingLog;

        for (AdminHomeController.MaintenanceLogItem item : data.maintenanceLogs) {
            if (item.rootCause == 'Spindle alignment requires follow-up') {
                matchingLog = item;
                break;
            }
        }

        System.assertNotEquals(
            null,
            matchingLog,
            'The follow-up Maintenance Log should appear on Admin Home.'
        );

        System.assertEquals('Follow-Up Required', matchingLog.outcome);
    }


    // =========================================================
    // Five Record Card Limit
    // =========================================================

    @IsTest
    static void testAccountCardReturnsFiveNewestRecords() {
        List<Account> accounts = new List<Account>();

        for (Integer index = 1; index <= 6; index++) {
            accounts.add(
                new Account(
                    Name='Admin Limit Account ' + index,
                    Phone='604-555-01' + index
                )
            );
        }

        insert accounts;

        Datetime referenceDate = System.now();

        for (Integer index = 0; index < accounts.size(); index++) {
            Test.setCreatedDate(accounts[index].Id, referenceDate.addDays(-(index + 1)));
        }

        Test.startTest();
        AdminHomeController.AdminHomeData data = AdminHomeController.getHomeData();
        Test.stopTest();

        System.assertEquals(
            5,
            data.accounts.size(),
            'Admin Home cards should return no more than five records.'
        );

        Set<String> returnedNames = new Set<String>();

        for (AdminHomeController.AccountItem item : data.accounts) {
            returnedNames.add(item.name);
        }

        System.assertEquals(true, returnedNames.contains('Admin Limit Account 1'));
        System.assertEquals(true, returnedNames.contains('Admin Limit Account 5'));

        System.assertEquals(
            false,
            returnedNames.contains('Admin Limit Account 6'),
            'The oldest Account should fall outside the five-record card limit.'
        );
    }


    // =========================================================
    // Recently Viewed Limit
    // =========================================================

    @IsTest
    static void testRecentlyViewedNeverExceedsSixRecords() {
        Test.startTest();
        AdminHomeController.AdminHomeData data = AdminHomeController.getHomeData();
        Test.stopTest();

        System.assertNotEquals(null, data.recentlyViewed);

        System.assert(
            data.recentlyViewed.size() <= 6,
            'Recently Viewed should return at most six records.'
        );
    }


    // =========================================================
    // Helpers
    // =========================================================

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) return entry.getValue();
        }

        throw new TestDataException('An active picklist value is required for this test.');
    }


    private static void setNameIfWritable(SObject record, String value) {
        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fields.containsKey('Name')) return;

        Schema.DescribeFieldResult nameField = fields.get('Name').getDescribe();

        if (nameField.isCreateable() && !nameField.isAutoNumber()) {
            record.put('Name', value);
        }
    }


    private static void putIfCreateable(
        SObject record,
        String fieldApiName,
        Object value
    ) {
        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fields.containsKey(fieldApiName)) return;

        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldApiName).getDescribe();

        if (fieldDescribe.isCreateable()) record.put(fieldApiName, value);
    }


    private static void putNumberIfCreateable(
        SObject record,
        String fieldApiName,
        Decimal value
    ) {
        putIfCreateable(record, fieldApiName, value);
    }


    private static void putTextOrPicklist(
        SObject record,
        String fieldApiName,
        String preferredValue
    ) {
        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fields.containsKey(fieldApiName)) return;

        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldApiName).getDescribe();

        if (!fieldDescribe.isCreateable()) return;

        if (
            fieldDescribe.getType() == Schema.DisplayType.Picklist ||
            fieldDescribe.getType() == Schema.DisplayType.MultiPicklist
        ) {
            String valueToUse;

            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive() && entry.getValue() == preferredValue) {
                    valueToUse = entry.getValue();
                    break;
                }

                if (valueToUse == null && entry.isActive()) {
                    valueToUse = entry.getValue();
                }
            }

            if (valueToUse != null) record.put(fieldApiName, valueToUse);

            return;
        }

        record.put(fieldApiName, preferredValue);
    }


    private class TestDataException extends Exception {
    }
}