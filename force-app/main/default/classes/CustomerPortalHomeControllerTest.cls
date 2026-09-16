@IsTest
private class CustomerPortalHomeControllerTest {
    private static final String CUSTOMER_PROFILE_NAME = 'MillTrack Customer Portal User';
    private static final String CUSTOMER_PERMISSION_SET_LABEL = 'MillTrack Customer Portal Access';

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

        System.assert(!roles.isEmpty(), 'At least one User Role is required to create the portal test Account owner.');

        String ownerToken = uniqueToken();

        User accountOwner = new User(
            FirstName='Portal',
            LastName='Home Owner',
            Alias='mthome',
            Email='home.owner.' + ownerToken + '@milltrack.test',
            Username='milltrack.home.owner.' + ownerToken + '@milltrack.test',
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
            Name='MillTrack Portal Home Customer',
            OwnerId=accountOwner.Id
        );

        Account unrelatedAccount = new Account(
            Name='Unrelated Portal Customer',
            OwnerId=accountOwner.Id
        );

        insert new List<Account>{customerAccount, unrelatedAccount};

        Contact customerContact = new Contact(
            FirstName='Maya',
            LastName='Portal Customer',
            Email='maya.portal.home@milltrack.test',
            AccountId=customerAccount.Id
        );

        insert customerContact;

        Asset customerMachine = new Asset(
            Name='Apex DWX-52D',
            AccountId=customerAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-52D',
            Serial_Number__c='HOME-DWX-001',
            Machine_Status__c='Active',
            Install_Date__c=Date.today().addYears(-2),
            Last_Service_Date__c=Date.today().addDays(-30)
        );

        Asset unrelatedMachine = new Asset(
            Name='Other Customer Machine',
            AccountId=unrelatedAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-52D',
            Serial_Number__c='OTHER-DWX-001',
            Machine_Status__c='Active'
        );

        insert new List<Asset>{customerMachine, unrelatedMachine};

        String caseOrigin = getFirstActivePicklistValue(Case.Origin);

        Case openRequest = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject='Spindle vibration during milling',
            Description='Customer reports vibration during milling.',
            Status='New',
            Priority='Medium',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        Case closedRequest = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject='Previous completed service request',
            Description='Previously resolved service request.',
            Status='Closed',
            Priority='Low',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        insert new List<Case>{openRequest, closedRequest};

        String workOrderStatus = getFirstActivePicklistValue(WorkOrder.Status);

        WorkOrder activeWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            CaseId=openRequest.Id,
            Subject='Spindle vibration during milling',
            Status=workOrderStatus,
            Priority='Medium',
            Dispatch_Status__c='Ready_to_Assign',
            Problem_Summary__c='Machine vibrates during milling.',
            Recommended_Fix_Summary__c='Inspect spindle and milling assembly before service.',
            OwnerId=accountOwner.Id
        );

        WorkOrder cancelledWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            CaseId=closedRequest.Id,
            Subject='Cancelled prior service',
            Status=workOrderStatus,
            Priority='Low',
            Dispatch_Status__c='Cancelled',
            Problem_Summary__c='Prior service request.',
            OwnerId=accountOwner.Id
        );

        insert new List<WorkOrder>{activeWorkOrder, cancelledWorkOrder};

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
            LastName='Portal Customer',
            Alias='mtcust',
            Email='maya.customer.' + customerToken + '@milltrack.test',
            Username='milltrack.home.customer.' + customerToken + '@milltrack.test',
            CommunityNickname='milltrackhome' + customerToken,
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

    @IsTest
    static void testGetHomeDataReturnsAuthorizedCurrentRecords() {
        Contact customerContact = [
            SELECT Id
            FROM Contact
            WHERE Email = 'maya.portal.home@milltrack.test'
            LIMIT 1
        ];

        User portalUser = [
            SELECT Id
            FROM User
            WHERE ContactId = :customerContact.Id
            LIMIT 1
        ];

        System.runAs(portalUser) {
            Test.startTest();
            CustomerPortalHomeController.HomeData homeData = CustomerPortalHomeController.getHomeData();
            Test.stopTest();

            System.assertNotEquals(null, homeData, 'Home data should be returned.');
            System.assertEquals('Maya', homeData.customerFirstName, 'The greeting should use the customer Contact first name.');

            System.assertEquals(1, homeData.machineCount, 'Only the customer authorized machine should be returned.');
            System.assertEquals(1, homeData.machines.size(), 'Only one customer machine should be visible.');
            System.assertEquals('Apex DWX-52D', homeData.machines[0].name);
            System.assertEquals('HOME-DWX-001', homeData.machines[0].serialNumber);

            System.assertEquals(1, homeData.openServiceRequestCount, 'Closed Service Requests should not count as open.');
            System.assertEquals(1, homeData.serviceRequests.size(), 'Only open Service Requests should appear on Home.');
            System.assertEquals('Spindle vibration during milling', homeData.serviceRequests[0].subject);
            System.assertEquals('New', homeData.serviceRequests[0].status);

            System.assertEquals(1, homeData.activeWorkOrderCount, 'Cancelled Work Orders should not count as active.');
            System.assertEquals(1, homeData.workOrders.size(), 'Only active Work Orders should appear on Home.');
            System.assertEquals('Spindle vibration during milling', homeData.workOrders[0].subject);
            System.assertEquals('Ready_to_Assign', homeData.workOrders[0].dispatchStatus);
            System.assertEquals(
                'Under Review',
                homeData.workOrders[0].customerStatus,
                'Internal Ready_to_Assign should be translated for the customer.'
            );
        }
    }

    @IsTest
    static void testGetHomeDataRejectsInternalUserWithoutContact() {
        User internalUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'milltrack.home.owner.%'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        System.runAs(internalUser) {
            Test.startTest();

            try {
                CustomerPortalHomeController.getHomeData();
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'An internal user without a Contact should not receive customer Home data.'
        );
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) return entry.getValue();
        }

        return null;
    }

    private static String uniqueToken() {
        String token = String.valueOf(DateTime.now().getTime()) + String.valueOf(Crypto.getRandomInteger());
        return token.replace('-', '1');
    }
}