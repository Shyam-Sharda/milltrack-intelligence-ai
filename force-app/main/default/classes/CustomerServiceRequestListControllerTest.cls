@IsTest
private class CustomerServiceRequestListControllerTest {
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
            LastName='Service Request List Owner',
            Alias='mtsrlst',
            Email='service.request.owner.' + ownerToken + '@milltrack.test',
            Username='milltrack.service.request.owner.' + ownerToken + '@milltrack.test',
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
            Name='MillTrack Service Request List Customer',
            OwnerId=accountOwner.Id
        );

        Account unrelatedAccount = new Account(
            Name='Unrelated Service Request Customer',
            OwnerId=accountOwner.Id
        );

        insert new List<Account>{
            customerAccount,
            unrelatedAccount
        };

        Contact customerContact = new Contact(
            FirstName='Maya',
            LastName='Service Request Customer',
            Email='maya.service.request.list@milltrack.test',
            AccountId=customerAccount.Id
        );

        insert customerContact;

        Asset customerMachine = new Asset(
            Name='Maple Ridge Roland 53DC',
            AccountId=customerAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c='SR-LIST-001',
            Machine_Status__c='Active'
        );

        Asset unrelatedMachine = new Asset(
            Name='Unrelated Customer Machine',
            AccountId=unrelatedAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-52D',
            Serial_Number__c='SR-LIST-OTHER',
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
            Subject='Step-in cuts on restorations',
            Description='Customer reports visible step-in cuts during milling.',
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
            Description='Previous issue was resolved.',
            Status='Closed',
            Priority='Low',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        Case requestWithoutWorkOrder = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject='New request awaiting work order',
            Description='This request has not yet generated a Work Order.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        Case unrelatedRequest = new Case(
            AccountId=unrelatedAccount.Id,
            AssetId=unrelatedMachine.Id,
            Subject='Unrelated customer issue',
            Description='This request belongs to another customer.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        insert new List<Case>{
            openRequest,
            completedRequest,
            requestWithoutWorkOrder,
            unrelatedRequest
        };

        String workOrderStatus = getFirstActivePicklistValue(WorkOrder.Status);

        WorkOrder activeWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            CaseId=openRequest.Id,
            Subject='Step-in cuts on restorations',
            Status=workOrderStatus,
            Priority='Medium',
            Dispatch_Status__c='Assigned',
            Scheduled_Visit__c=System.now().addDays(2),
            Problem_Summary__c='Visible step-in cuts are appearing during milling.',
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
            Problem_Summary__c='Previously resolved service issue.',
            Technician_Notes__c='Technician completed the repair and verified normal machine operation.',
            OwnerId=accountOwner.Id
        );

        WorkOrder unrelatedWorkOrder = new WorkOrder(
            AccountId=unrelatedAccount.Id,
            AssetId=unrelatedMachine.Id,
            CaseId=unrelatedRequest.Id,
            Subject='Unrelated customer work order',
            Status=workOrderStatus,
            Priority='High',
            Dispatch_Status__c='Ready_to_Assign',
            Problem_Summary__c='This Work Order belongs to another customer.',
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
            LastName='Service Request Customer',
            Alias='mtcust',
            Email='maya.service.request.portal.' + customerToken + '@milltrack.test',
            Username='milltrack.service.request.customer.' + customerToken + '@milltrack.test',
            CommunityNickname='milltracksr' + customerToken,
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
    static void testGetServiceRequestsReturnsAuthorizedCustomerRequests() {
        Contact customerContact = [
            SELECT Id
            FROM Contact
            WHERE Email = 'maya.service.request.list@milltrack.test'
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

            List<CustomerServiceRequestListController.ServiceRequestSummary> results =
                CustomerServiceRequestListController.getServiceRequests();

            Test.stopTest();

            System.assertEquals(
                3,
                results.size(),
                'The customer should receive all Service Requests from their own Account.'
            );

            Map<String, CustomerServiceRequestListController.ServiceRequestSummary>
                requestsBySubject =
                    new Map<String, CustomerServiceRequestListController.ServiceRequestSummary>();

            for (
                CustomerServiceRequestListController.ServiceRequestSummary request :
                results
            ) {
                requestsBySubject.put(
                    request.subject,
                    request
                );

                System.assertNotEquals(
                    null,
                    request.id,
                    'Each Service Request should include the Case Id.'
                );

                System.assertNotEquals(
                    null,
                    request.caseNumber,
                    'Each Service Request should include its request number.'
                );

                System.assertEquals(
                    'Maple Ridge Roland 53DC',
                    request.assetName,
                    'Only the authorized customer machine should be returned.'
                );
            }

            System.assert(
                requestsBySubject.containsKey('Step-in cuts on restorations'),
                'The active Service Request should be returned.'
            );

            System.assert(
                requestsBySubject.containsKey('Previous completed service request'),
                'The completed Service Request should be returned.'
            );

            System.assert(
                requestsBySubject.containsKey('New request awaiting work order'),
                'A Service Request should still appear before its Work Order exists.'
            );

            System.assert(
                !requestsBySubject.containsKey('Unrelated customer issue'),
                'Service Requests belonging to another customer must not be returned.'
            );

            CustomerServiceRequestListController.ServiceRequestSummary activeRequest =
                requestsBySubject.get('Step-in cuts on restorations');

            System.assertEquals(
                'New',
                activeRequest.caseStatus,
                'The original Case status should remain available.'
            );

            System.assertEquals(
                'Assigned',
                activeRequest.dispatchStatus,
                'The related Work Order Dispatch Status should be included.'
            );

            System.assertEquals(
                'Visit Scheduled',
                activeRequest.customerStatus,
                'Assigned should be translated into the customer lifecycle.'
            );

            System.assertNotEquals(
                null,
                activeRequest.workOrderId,
                'The active Service Request should include its related Work Order Id.'
            );

            System.assertNotEquals(
                null,
                activeRequest.workOrderNumber,
                'The active Service Request should include its related Work Order Number.'
            );

            System.assertNotEquals(
                null,
                activeRequest.scheduledVisit,
                'The active Service Request should include the scheduled visit.'
            );

            System.assertEquals(
                'Medium',
                activeRequest.priority
            );

            CustomerServiceRequestListController.ServiceRequestSummary completedRequest =
                requestsBySubject.get('Previous completed service request');

            System.assertEquals(
                'Closed',
                completedRequest.caseStatus,
                'The completed request should retain the raw Case status.'
            );

            System.assertEquals(
                'Completed',
                completedRequest.dispatchStatus,
                'The completed request should include the completed Work Order state.'
            );

            System.assertEquals(
                'Completed',
                completedRequest.customerStatus,
                'Completed Work Orders should display as Completed.'
            );

            System.assertNotEquals(
                null,
                completedRequest.workOrderId,
                'The completed request should include its related Work Order.'
            );

            System.assertNotEquals(
                null,
                completedRequest.closedDate,
                'The completed request should include the Case closed date.'
            );

            CustomerServiceRequestListController.ServiceRequestSummary pendingRequest =
                requestsBySubject.get('New request awaiting work order');

            System.assertEquals(
                'New',
                pendingRequest.caseStatus
            );

            System.assertEquals(
                'Request Received',
                pendingRequest.customerStatus,
                'A request without a Work Order should fall back to the Case lifecycle.'
            );

            System.assertEquals(
                null,
                pendingRequest.workOrderId,
                'The controller should not invent a Work Order for a newly submitted request.'
            );

            System.assertEquals(
                null,
                pendingRequest.dispatchStatus
            );
        }
    }

    @IsTest
    static void testGetServiceRequestsRejectsInternalUserWithoutContact() {
        User internalUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'milltrack.service.request.owner.%'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        System.runAs(internalUser) {
            Test.startTest();

            try {
                CustomerServiceRequestListController.getServiceRequests();
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'An internal user without a Contact should not receive customer Service Request data.'
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