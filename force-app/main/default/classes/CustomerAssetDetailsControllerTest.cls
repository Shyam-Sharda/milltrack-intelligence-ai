@IsTest
private class CustomerAssetDetailsControllerTest {
    private static final String CUSTOMER_PROFILE_NAME = 'MillTrack Customer Portal User';
    private static final String CUSTOMER_PERMISSION_SET_LABEL = 'MillTrack Customer Portal Access';
    private static final String CUSTOMER_CONTACT_EMAIL = 'asset.details.portal@milltrack.test';
    private static final String CUSTOMER_SERIAL = 'ASSET-DETAIL-001';
    private static final String UNRELATED_SERIAL = 'ASSET-DETAIL-OTHER-001';

    @TestSetup
    static void setupData() {
        User runningUser = [
            SELECT Id, ProfileId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        List<UserRole> roles = [
            SELECT Id
            FROM UserRole
            ORDER BY Id
            LIMIT 1
        ];

        System.assert(
            !roles.isEmpty(),
            'At least one User Role is required to create the portal test Account owner.'
        );

        String ownerToken = uniqueToken();

        User accountOwner = new User(
            FirstName='Asset',
            LastName='Details Owner',
            Alias='mtadown',
            Email='asset.details.owner.' + ownerToken + '@milltrack.test',
            Username='milltrack.asset.details.owner.' + ownerToken + '@milltrack.test',
            TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US',
            ProfileId=runningUser.ProfileId,
            UserRoleId=roles[0].Id
        );

        System.runAs(runningUser) {
            insert accountOwner;
        }

        Account customerAccount = new Account(
            Name='MillTrack Asset Details Customer',
            OwnerId=accountOwner.Id
        );

        Account unrelatedAccount = new Account(
            Name='Unrelated Asset Details Customer',
            OwnerId=accountOwner.Id
        );

        insert new List<Account>{customerAccount, unrelatedAccount};

        Contact customerContact = new Contact(
            FirstName='Maya',
            LastName='Asset Customer',
            Email=CUSTOMER_CONTACT_EMAIL,
            AccountId=customerAccount.Id
        );

        insert customerContact;

        Asset customerMachine = new Asset(
            Name='Customer Roland 53DC',
            AccountId=customerAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c=CUSTOMER_SERIAL,
            Machine_Status__c='Active',
            Description='Customer-facing dental milling machine used for production.',
            Install_Date__c=Date.newInstance(2024, 10, 7),
            Warranty_Start_Date__c=Date.newInstance(2024, 10, 7),
            Warranty_End_Date__c=Date.newInstance(2029, 10, 7),
            Last_Service_Date__c=Date.newInstance(2026, 9, 8),
            Portal_Image_Path__c='images/roland-53dc.jpg',
            Portal_Manual_Path__c='Roland 53DC User Manual.pdf',
            Customer_Maintenance_List__c=
                'DAILY\n' +
                '- Clean milling chamber\n' +
                '- Check machine condition\n\n' +
                'WEEKLY\n' +
                '- Inspect collet'
        );

        Asset unrelatedMachine = new Asset(
            Name='Other Customer Roland 53DC',
            AccountId=unrelatedAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c=UNRELATED_SERIAL,
            Machine_Status__c='Active',
            Description='Machine belonging to another customer.',
            Portal_Image_Path__c='images/roland-53dc.jpg',
            Portal_Manual_Path__c='Roland 53DC User Manual.pdf',
            Customer_Maintenance_List__c='PRIVATE OTHER CUSTOMER MAINTENANCE LIST'
        );

        insert new List<Asset>{customerMachine, unrelatedMachine};

        String workOrderStatus = getFirstActivePicklistValue(WorkOrder.Status);

        WorkOrder customerWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            AssetId=customerMachine.Id,
            Subject='Customer Asset service-history test',
            Status=workOrderStatus,
            OwnerId=accountOwner.Id
        );

        WorkOrder unrelatedWorkOrder = new WorkOrder(
            AccountId=unrelatedAccount.Id,
            AssetId=unrelatedMachine.Id,
            Subject='Unrelated Asset service-history test',
            Status=workOrderStatus,
            OwnerId=accountOwner.Id
        );

        insert new List<WorkOrder>{customerWorkOrder, unrelatedWorkOrder};

        String maintenanceType = getFirstActivePicklistValue(
            Maintenance_Log__c.Maintenance_Type__c
        );

        Id currentUserId = UserInfo.getUserId();

        insert new List<Maintenance_Log__c>{
            new Maintenance_Log__c(
                Asset__c=customerMachine.Id,
                Work_Order__c=customerWorkOrder.Id,
                Performed_By__c=currentUserId,
                Maintenance_Date__c=Date.newInstance(2026, 9, 8),
                Maintenance_Type__c=maintenanceType,
                Problem_Summary__c='Machine requires follow-up service after temporary repair.',
                Summary__c='Temporary service visit',
                Root_Cause__c='Permanent follow-up work is still required.',
                Parts_Used__c='Temporary service materials',
                Labor_Hours__c=Decimal.valueOf('2.25'),
                Issue_Resolved__c=false,
                Follow_Up_Required__c=true
            ),
            new Maintenance_Log__c(
                Asset__c=customerMachine.Id,
                Work_Order__c=customerWorkOrder.Id,
                Performed_By__c=currentUserId,
                Maintenance_Date__c=Date.newInstance(2026, 8, 15),
                Maintenance_Type__c=maintenanceType,
                Problem_Summary__c='Machine performance degraded during normal milling.',
                Summary__c='Resolved service visit',
                Root_Cause__c='Routine component wear',
                Parts_Used__c='Replacement service component',
                Labor_Hours__c=Decimal.valueOf('1.50'),
                Issue_Resolved__c=true,
                Follow_Up_Required__c=false
            ),
            new Maintenance_Log__c(
                Asset__c=customerMachine.Id,
                Work_Order__c=customerWorkOrder.Id,
                Performed_By__c=currentUserId,
                Maintenance_Date__c=Date.newInstance(2026, 7, 10),
                Maintenance_Type__c=maintenanceType,
                Problem_Summary__c='Machine reached its scheduled preventive maintenance interval.',
                Summary__c='Routine maintenance visit',
                Root_Cause__c='Preventive maintenance interval reached',
                Labor_Hours__c=Decimal.valueOf('1.00'),
                Issue_Resolved__c=false,
                Follow_Up_Required__c=false
            ),
            new Maintenance_Log__c(
                Asset__c=unrelatedMachine.Id,
                Work_Order__c=unrelatedWorkOrder.Id,
                Performed_By__c=currentUserId,
                Maintenance_Date__c=Date.newInstance(2026, 9, 9),
                Maintenance_Type__c=maintenanceType,
                Problem_Summary__c='PRIVATE OTHER CUSTOMER PROBLEM SUMMARY',
                Summary__c='Private unrelated customer service visit',
                Root_Cause__c='Other customer service history',
                Labor_Hours__c=Decimal.valueOf('3.00'),
                Issue_Resolved__c=true,
                Follow_Up_Required__c=false
            )
        };

        List<Profile> customerProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = :CUSTOMER_PROFILE_NAME
            LIMIT 1
        ];

        System.assertEquals(
            1,
            customerProfiles.size(),
            'The MillTrack Customer Portal User profile was not found.'
        );

        List<PermissionSet> customerPermissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Label = :CUSTOMER_PERMISSION_SET_LABEL
            AND IsOwnedByProfile = false
            LIMIT 1
        ];

        System.assertEquals(
            1,
            customerPermissionSets.size(),
            'The MillTrack Customer Portal Access permission set was not found.'
        );

        String customerToken = uniqueToken();

        User portalUser = new User(
            FirstName='Maya',
            LastName='Asset Customer',
            Alias='mtasset',
            Email='asset.customer.' + customerToken + '@milltrack.test',
            Username='milltrack.asset.customer.' + customerToken + '@milltrack.test',
            CommunityNickname='milltrackasset' + customerToken,
            TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US',
            ProfileId=customerProfiles[0].Id,
            ContactId=customerContact.Id,
            IsActive=true
        );

        System.runAs(runningUser) {
            insert portalUser;

            PermissionSetAssignment permissionAssignment = new PermissionSetAssignment(
                AssigneeId=portalUser.Id,
                PermissionSetId=customerPermissionSets[0].Id
            );

            insert permissionAssignment;
        }
    }

    // =========================================================
    // Asset Details
    // =========================================================

    @IsTest
    static void testGetAssetDetailsReturnsAuthorizedAssetAndHistory() {
        User portalUser = getPortalUser();
        Asset customerMachine = getCustomerMachine();

        CustomerAssetDetailsController.AssetDetailsData data;

        System.runAs(portalUser) {
            Test.startTest();
            data = CustomerAssetDetailsController.getAssetDetails(customerMachine.Id);
            Test.stopTest();
        }

        System.assertNotEquals(null, data, 'Asset details should be returned.');
        System.assertNotEquals(null, data.asset, 'The authorized Asset summary should be returned.');

        System.assertEquals(customerMachine.Id, data.asset.id);
        System.assertEquals('Customer Roland 53DC', data.asset.name);
        System.assertEquals('Roland', data.asset.manufacturer);
        System.assertEquals('DWX-53DC', data.asset.model);
        System.assertEquals(CUSTOMER_SERIAL, data.asset.serialNumber);
        System.assertEquals('Active', data.asset.status);

        System.assertEquals(
            'Customer-facing dental milling machine used for production.',
            data.asset.description
        );

        System.assertEquals(Date.newInstance(2024, 10, 7), data.asset.installDate);
        System.assertEquals(Date.newInstance(2024, 10, 7), data.asset.warrantyStartDate);
        System.assertEquals(Date.newInstance(2029, 10, 7), data.asset.warrantyEndDate);
        System.assertEquals(Date.newInstance(2026, 9, 8), data.asset.lastServiceDate);

        System.assertEquals('images/roland-53dc.jpg', data.asset.portalImagePath);
        System.assertEquals('Roland 53DC User Manual.pdf', data.asset.portalManualPath);

        System.assert(
            data.asset.maintenanceList.contains('Clean milling chamber'),
            'The customer maintenance list should be returned.'
        );

        System.assertEquals(
            3,
            data.serviceHistory.size(),
            'Only service history belonging to the authorized Asset should be returned.'
        );

        CustomerAssetDetailsController.ServiceHistoryEntry latest = data.serviceHistory[0];

        System.assertNotEquals(null, latest.id);
        System.assertNotEquals(null, latest.maintenanceNumber);
        System.assertEquals(Date.newInstance(2026, 9, 8), latest.maintenanceDate);

        System.assertEquals(
            'Machine requires follow-up service after temporary repair.',
            latest.problemSummary
        );

        System.assertEquals('Temporary service visit', latest.summary);
        System.assertEquals('Permanent follow-up work is still required.', latest.rootCause);
        System.assertEquals('Temporary service materials', latest.partsUsed);
        System.assertEquals(Decimal.valueOf('2.25'), latest.laborHours);
        System.assertEquals(false, latest.issueResolved);
        System.assertEquals(true, latest.followUpRequired);
        System.assertEquals('Follow-up Required', latest.status);

        System.assertNotEquals(null, latest.workOrderId);
        System.assertNotEquals(null, latest.workOrderNumber);

        System.assertEquals(Date.newInstance(2026, 8, 15), data.serviceHistory[1].maintenanceDate);
        System.assertEquals(
            'Machine performance degraded during normal milling.',
            data.serviceHistory[1].problemSummary
        );
        System.assertEquals('Resolved', data.serviceHistory[1].status);

        System.assertEquals(Date.newInstance(2026, 7, 10), data.serviceHistory[2].maintenanceDate);
        System.assertEquals(
            'Machine reached its scheduled preventive maintenance interval.',
            data.serviceHistory[2].problemSummary
        );
        System.assertEquals('Completed', data.serviceHistory[2].status);

        for (CustomerAssetDetailsController.ServiceHistoryEntry entry : data.serviceHistory) {
            System.assertNotEquals(
                'Private unrelated customer service visit',
                entry.summary,
                'Another customer service-history record must never be returned.'
            );

            System.assertNotEquals(
                'PRIVATE OTHER CUSTOMER PROBLEM SUMMARY',
                entry.problemSummary,
                'Another customer problem summary must never be returned.'
            );
        }
    }

    @IsTest
    static void testGetAssetDetailsRejectsCrossAccountAsset() {
        User portalUser = getPortalUser();
        Asset unrelatedMachine = getUnrelatedMachine();
        Boolean exceptionThrown = false;

        System.runAs(portalUser) {
            Test.startTest();

            try {
                CustomerAssetDetailsController.getAssetDetails(unrelatedMachine.Id);
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'A customer must not be able to load another Account Asset.'
        );
    }

    @IsTest
    static void testGetAssetDetailsRejectsMissingAssetId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CustomerAssetDetailsController.getAssetDetails(null);
        } catch (AuraHandledException expectedException) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A null Asset ID must be rejected.');
    }

    // =========================================================
    // Maintenance List
    // =========================================================

    @IsTest
    static void testSaveMaintenanceListUpdatesAuthorizedAsset() {
        User portalUser = getPortalUser();
        Asset customerMachine = getCustomerMachine();

        String updatedMaintenanceList =
            'DAILY\n' +
            '- Clean milling chamber\n' +
            '- Check coolant level\n\n' +
            'WEEKLY\n' +
            '- Inspect collet\n' +
            '- Clean filters\n\n' +
            'MONTHLY\n' +
            '- Inspect spindle condition';

        CustomerAssetDetailsController.SaveMaintenanceResult result;

        System.runAs(portalUser) {
            Test.startTest();

            result = CustomerAssetDetailsController.saveMaintenanceList(
                customerMachine.Id,
                updatedMaintenanceList
            );

            Test.stopTest();
        }

        System.assertEquals(true, result.success);
        System.assertEquals(updatedMaintenanceList, result.maintenanceList);
        System.assertEquals('Maintenance list saved successfully.', result.message);

        Asset updatedAsset = [
            SELECT Customer_Maintenance_List__c
            FROM Asset
            WHERE Id = :customerMachine.Id
        ];

        System.assertEquals(
            updatedMaintenanceList,
            updatedAsset.Customer_Maintenance_List__c,
            'The authorized customer maintenance list should be updated.'
        );
    }

    @IsTest
    static void testSaveMaintenanceListNormalizesBlankValue() {
        User portalUser = getPortalUser();
        Asset customerMachine = getCustomerMachine();

        CustomerAssetDetailsController.SaveMaintenanceResult result;

        System.runAs(portalUser) {
            Test.startTest();
            result = CustomerAssetDetailsController.saveMaintenanceList(customerMachine.Id, '   ');
            Test.stopTest();
        }

        System.assertEquals(true, result.success);
        System.assertEquals(null, result.maintenanceList);

        Asset updatedAsset = [
            SELECT Customer_Maintenance_List__c
            FROM Asset
            WHERE Id = :customerMachine.Id
        ];

        System.assertEquals(
            null,
            updatedAsset.Customer_Maintenance_List__c,
            'A blank maintenance list should be stored as null.'
        );
    }

    @IsTest
    static void testSaveMaintenanceListRejectsCrossAccountAsset() {
        User portalUser = getPortalUser();
        Asset unrelatedMachine = getUnrelatedMachine();
        Boolean exceptionThrown = false;

        System.runAs(portalUser) {
            Test.startTest();

            try {
                CustomerAssetDetailsController.saveMaintenanceList(
                    unrelatedMachine.Id,
                    'Customer should not be able to write this.'
                );
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'A customer must not be able to edit another Account Asset.'
        );

        Asset unchangedAsset = [
            SELECT Customer_Maintenance_List__c
            FROM Asset
            WHERE Id = :unrelatedMachine.Id
        ];

        System.assertEquals(
            'PRIVATE OTHER CUSTOMER MAINTENANCE LIST',
            unchangedAsset.Customer_Maintenance_List__c,
            'The unrelated customer maintenance list must remain unchanged.'
        );
    }

    // =========================================================
    // Customer Context
    // =========================================================

    @IsTest
    static void testGetAssetDetailsRejectsInternalUserWithoutContact() {
        Account customerAccount = [
            SELECT OwnerId
            FROM Account
            WHERE Name = 'MillTrack Asset Details Customer'
            LIMIT 1
        ];

        User internalUser = [
            SELECT Id
            FROM User
            WHERE Id = :customerAccount.OwnerId
        ];

        Asset customerMachine = getCustomerMachine();
        Boolean exceptionThrown = false;

        System.runAs(internalUser) {
            Test.startTest();

            try {
                CustomerAssetDetailsController.getAssetDetails(customerMachine.Id);
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'An internal user without a Contact must not receive customer Asset data.'
        );
    }

    // =========================================================
    // Helpers
    // =========================================================

    private static User getPortalUser() {
        Contact customerContact = [
            SELECT Id
            FROM Contact
            WHERE Email = :CUSTOMER_CONTACT_EMAIL
            LIMIT 1
        ];

        return [
            SELECT Id
            FROM User
            WHERE ContactId = :customerContact.Id
            LIMIT 1
        ];
    }

    private static Asset getCustomerMachine() {
        return [
            SELECT Id
            FROM Asset
            WHERE Serial_Number__c = :CUSTOMER_SERIAL
            LIMIT 1
        ];
    }

    private static Asset getUnrelatedMachine() {
        return [
            SELECT Id
            FROM Asset
            WHERE Serial_Number__c = :UNRELATED_SERIAL
            LIMIT 1
        ];
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) return entry.getValue();
        }

        throw new TestDataException('An active picklist value is required for this test.');
    }

    private static String uniqueToken() {
        String token = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Crypto.getRandomInteger());

        return token.replace('-', '1');
    }

    private class TestDataException extends Exception {
    }
}