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

        System.assert(
            !roles.isEmpty(),
            'At least one User Role is required to create the portal test Account owner.'
        );

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

        insert new List<Account>{
            customerAccount,
            unrelatedAccount
        };

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

        insert new List<Asset>{
            customerMachine,
            unrelatedMachine
        };

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

        Case completedRequest = new Case(
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

        Case unrelatedRequest = new Case(
            AccountId=unrelatedAccount.Id,
            AssetId=unrelatedMachine.Id,
            Subject='Unrelated customer service request',
            Description='This request belongs to another customer.',
            Status='New',
            Priority='Medium',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        insert new List<Case>{
            openRequest,
            completedRequest,
            unrelatedRequest
        };

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
            Scheduled_Visit__c=System.now().addDays(3),
            Problem_Summary__c='Machine vibrates during milling.',
            Recommended_Fix_Summary__c='Inspect spindle and milling assembly before service.',
            OwnerId=accountOwner.Id
        );

        WorkOrder completedWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            CaseId=completedRequest.Id,
            Subject='Previous completed service request',
            Status=workOrderStatus,
            Priority='Low',
            Dispatch_Status__c='Completed',
            Scheduled_Visit__c=System.now().addDays(-5),
            Problem_Summary__c='Previously resolved machine issue.',
            Technician_Notes__c='Technician completed the service and verified normal machine operation.',
            OwnerId=accountOwner.Id
        );

        WorkOrder unrelatedWorkOrder = new WorkOrder(
            AccountId=unrelatedAccount.Id,
            AssetId=unrelatedMachine.Id,
            CaseId=unrelatedRequest.Id,
            Subject='Unrelated customer work order',
            Status=workOrderStatus,
            Priority='Medium',
            Dispatch_Status__c='Assigned',
            Problem_Summary__c='This work order belongs to another customer.',
            OwnerId=accountOwner.Id
        );

        insert new List<WorkOrder>{
            activeWorkOrder,
            completedWorkOrder,
            unrelatedWorkOrder
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
    static void testGetHomeDataReturnsAuthorizedRecentRecords() {
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
            CustomerPortalHomeController.HomeData homeData =
                CustomerPortalHomeController.getHomeData();
            Test.stopTest();

            System.assertNotEquals(
                null,
                homeData,
                'Home data should be returned.'
            );

            System.assertEquals(
                'Maya',
                homeData.customerFirstName,
                'The greeting should use the customer Contact first name.'
            );

            System.assertEquals(
                1,
                homeData.machineCount,
                'Only the customer authorized machine should be returned.'
            );

            System.assertEquals(
                1,
                homeData.machines.size(),
                'Only one customer machine should be visible.'
            );

            System.assertEquals(
                'Apex DWX-52D',
                homeData.machines[0].name
            );

            System.assertEquals(
                'HOME-DWX-001',
                homeData.machines[0].serialNumber
            );

            System.assertEquals(
                2,
                homeData.recentServiceRequestCount,
                'Both open and completed customer Service Requests should count as recent requests.'
            );

            System.assertEquals(
                2,
                homeData.serviceRequests.size(),
                'Both open and completed customer Service Requests should appear on Home.'
            );

            Map<String, CustomerPortalHomeController.ServiceRequestSummary>
                requestsBySubject =
                    new Map<String, CustomerPortalHomeController.ServiceRequestSummary>();

            for (
                CustomerPortalHomeController.ServiceRequestSummary serviceRequest :
                homeData.serviceRequests
            ) {
                requestsBySubject.put(
                    serviceRequest.subject,
                    serviceRequest
                );

                System.assertNotEquals(
                    null,
                    serviceRequest.caseNumber,
                    'Each Service Request should include its Case Number.'
                );

                System.assertEquals(
                    'Apex DWX-52D',
                    serviceRequest.assetName,
                    'Each Service Request should return the authorized machine.'
                );
            }

            System.assert(
                requestsBySubject.containsKey('Spindle vibration during milling'),
                'The open Service Request should be returned.'
            );

            System.assert(
                requestsBySubject.containsKey('Previous completed service request'),
                'The completed Service Request should be returned.'
            );

            System.assert(
                !requestsBySubject.containsKey('Unrelated customer service request'),
                'Service Requests belonging to another customer must not be returned.'
            );

            CustomerPortalHomeController.ServiceRequestSummary activeRequest =
                requestsBySubject.get('Spindle vibration during milling');

            System.assertEquals(
                'New',
                activeRequest.caseStatus,
                'The raw Case status should remain available when needed.'
            );

            System.assertEquals(
                'Ready_to_Assign',
                activeRequest.dispatchStatus,
                'The related Work Order dispatch status should be included in the Service Request summary.'
            );

            System.assertEquals(
                'Under Review',
                activeRequest.customerStatus,
                'Ready_to_Assign should be translated into the unified customer status.'
            );

            System.assertNotEquals(
                null,
                activeRequest.workOrderId,
                'The Service Request should include its related Work Order Id.'
            );

            System.assertNotEquals(
                null,
                activeRequest.workOrderNumber,
                'The Service Request should include its related Work Order Number.'
            );

            System.assertNotEquals(
                null,
                activeRequest.scheduledVisit,
                'The Service Request should include the scheduled visit from its related Work Order.'
            );

            System.assertEquals(
                'Medium',
                activeRequest.priority
            );

            System.assertNotEquals(
                null,
                activeRequest.createdDate
            );

            CustomerPortalHomeController.ServiceRequestSummary completedRequest =
                requestsBySubject.get('Previous completed service request');

            System.assertEquals(
                'Closed',
                completedRequest.caseStatus,
                'The completed Service Request should retain its raw Case status.'
            );

            System.assertEquals(
                'Completed',
                completedRequest.dispatchStatus,
                'The completed Service Request should include its completed Work Order state.'
            );

            System.assertEquals(
                'Completed',
                completedRequest.customerStatus,
                'A completed Work Order should produce the customer-facing Completed status.'
            );

            System.assertNotEquals(
                null,
                completedRequest.workOrderId,
                'The completed Service Request should include its related Work Order.'
            );

            System.assertNotEquals(
                null,
                completedRequest.workOrderNumber,
                'The completed Service Request should include its Work Order Number.'
            );

            System.assertNotEquals(
                null,
                completedRequest.closedDate,
                'The completed Service Request should include the Case closed date.'
            );
        }
    }

    @IsTest
    static void testServiceRequestWithoutWorkOrderUsesCaseStatus() {
        Account customerAccount = [
            SELECT Id
            FROM Account
            WHERE Name = 'MillTrack Portal Home Customer'
            LIMIT 1
        ];

        Contact customerContact = [
            SELECT Id
            FROM Contact
            WHERE Email = 'maya.portal.home@milltrack.test'
            LIMIT 1
        ];

        Asset customerMachine = [
            SELECT Id
            FROM Asset
            WHERE AccountId = :customerAccount.Id
            LIMIT 1
        ];

        User portalUser = [
            SELECT Id
            FROM User
            WHERE ContactId = :customerContact.Id
            LIMIT 1
        ];

        String caseOrigin = getFirstActivePicklistValue(Case.Origin);

        Case requestWithoutWorkOrder = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject='New request without work order',
            Description='Newly created request awaiting Work Order creation.',
            Status='New',
            Priority='Medium',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        insert requestWithoutWorkOrder;

        System.runAs(portalUser) {
            Test.startTest();
            CustomerPortalHomeController.HomeData homeData =
                CustomerPortalHomeController.getHomeData();
            Test.stopTest();

            CustomerPortalHomeController.ServiceRequestSummary matchingRequest;

            for (
                CustomerPortalHomeController.ServiceRequestSummary serviceRequest :
                homeData.serviceRequests
            ) {
                if (serviceRequest.id == requestWithoutWorkOrder.Id) {
                    matchingRequest = serviceRequest;
                    break;
                }
            }

            System.assertNotEquals(
                null,
                matchingRequest,
                'A Service Request should still appear before a Work Order has been created.'
            );

            System.assertEquals(
                'New',
                matchingRequest.caseStatus
            );

            System.assertEquals(
                'Request Received',
                matchingRequest.customerStatus,
                'Without a Work Order, the customer status should fall back to the Case lifecycle.'
            );

            System.assertEquals(
                null,
                matchingRequest.workOrderId,
                'A brand-new Service Request should not invent a Work Order relationship.'
            );

            System.assertEquals(
                null,
                matchingRequest.dispatchStatus
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

    private static String getFirstActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {
        for (
            Schema.PicklistEntry entry :
            fieldToken.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    private static String uniqueToken() {
        String token =
            String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Crypto.getRandomInteger());

        return token.replace('-', '1');
    }
}