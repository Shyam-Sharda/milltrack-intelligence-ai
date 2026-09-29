@IsTest
private class CustomerServiceRequestDetailsControlTest {
    private static final String CUSTOMER_PROFILE_NAME = 'MillTrack Customer Portal User';
    private static final String CUSTOMER_PERMISSION_SET_LABEL = 'MillTrack Customer Portal Access';

    @TestSetup
    static void createTestData() {
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
            FirstName='MillTrack',
            LastName='Service Owner',
            Alias='mtsvc',
            Email='service.owner.' + ownerToken + '@milltrack.test',
            Username='milltrack.service.owner.' + ownerToken + '@milltrack.test',
            TimeZoneSidKey='America/Vancouver',
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
            Name='MillTrack Service Request Customer',
            OwnerId=accountOwner.Id
        );

        Account unrelatedAccount = new Account(
            Name='Unrelated Service Request Customer',
            OwnerId=accountOwner.Id
        );

        insert new List<Account>{customerAccount, unrelatedAccount};

        Contact customerContact = new Contact(
            FirstName='Maya',
            LastName='Portal Customer',
            Email='maya.service.request@milltrack.test',
            AccountId=customerAccount.Id
        );
        insert customerContact;

        Asset customerAsset = new Asset(
            Name='Roland 53DC',
            AccountId=customerAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c='MT-53DC-001',
            Machine_Status__c='Active',
            Portal_Image_Path__c='images/roland-53dc.jpg'
        );

        Asset unrelatedAsset = new Asset(
            Name='Unrelated Machine',
            AccountId=unrelatedAccount.Id,
            Manufacturer__c='Roland',
            Model__c='Other',
            Serial_Number__c='OTHER-001',
            Machine_Status__c='Active'
        );

        insert new List<Asset>{customerAsset, unrelatedAsset};

        String caseOrigin = getFirstActivePicklistValue(Case.Origin);

        Case newCase = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerAsset.Id,
            Subject='New request without work order',
            Description='Machine is producing inconsistent restoration margins.',
            Status='New',
            Priority='Medium',
            Origin=caseOrigin,
            Error_Code__c='E100',
            Work_Order_Proposal_Created__c=true
        );

        Case scheduledCase = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerAsset.Id,
            Subject='Service visit scheduled',
            Description='Machine requires onsite service.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Error_Code__c='E200',
            Work_Order_Proposal_Created__c=true
        );

        Case inProgressCase = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerAsset.Id,
            Subject='Service currently in progress',
            Description='Technician is actively repairing the machine.',
            Status='In Progress',
            Priority='High',
            Origin=caseOrigin,
            Error_Code__c='E300',
            Work_Order_Proposal_Created__c=true
        );

        Case completedCase = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerAsset.Id,
            Subject='Completed spindle repair',
            Description='Spindle vibration affected milling accuracy.',
            Status='Closed',
            Priority='Medium',
            Origin=caseOrigin,
            Error_Code__c='E400',
            Work_Order_Proposal_Created__c=true
        );

        Case unrelatedCase = new Case(
            AccountId=unrelatedAccount.Id,
            AssetId=unrelatedAsset.Id,
            Subject='Another customer request',
            Description='This record should not be available.',
            Status='New',
            Priority='Low',
            Origin=caseOrigin,
            Work_Order_Proposal_Created__c=true
        );

        insert new List<Case>{
            newCase,
            scheduledCase,
            inProgressCase,
            completedCase,
            unrelatedCase
        };

        String workOrderStatus = getFirstActivePicklistValue(WorkOrder.Status);

        WorkOrder scheduledWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            CaseId=scheduledCase.Id,
            AssetId=customerAsset.Id,
            Subject='Scheduled service visit',
            Status=workOrderStatus,
            Priority='High',
            Dispatch_Status__c='Assigned',
            Scheduled_Visit__c=System.now().addDays(2),
            Problem_Summary__c='Machine requires onsite service.',
            Recommended_Fix_Summary__c='Inspect the reported issue during the scheduled service visit.',
            OwnerId=accountOwner.Id
        );

        WorkOrder inProgressWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            CaseId=inProgressCase.Id,
            AssetId=customerAsset.Id,
            Subject='Active service visit',
            Status=workOrderStatus,
            Priority='High',
            Dispatch_Status__c='In Progress',
            Scheduled_Visit__c=System.now().addDays(-1),
            Work_Started_Date_Time__c=System.now().addHours(-2),
            Problem_Summary__c='Machine issue is currently being serviced.',
            Recommended_Fix_Summary__c='Inspect and repair the affected machine components.',
            OwnerId=accountOwner.Id
        );

        WorkOrder completedWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            CaseId=completedCase.Id,
            AssetId=customerAsset.Id,
            Subject='Completed spindle repair',
            Status=workOrderStatus,
            Priority='Medium',
            Dispatch_Status__c='Completed',
            Scheduled_Visit__c=System.now().addDays(-5),
            Work_Started_Date_Time__c=System.now().addDays(-5),
            Work_Ended_Date_Time__c=System.now().addDays(-5).addHours(3),
            Problem_Summary__c='Spindle vibration affected milling accuracy.',
            Recommended_Fix_Summary__c='Inspect and replace the worn spindle assembly.',
            Technician_Notes__c='Technician completed the repair and verified normal machine operation.',
            OwnerId=accountOwner.Id
        );

        insert new List<WorkOrder>{
            scheduledWorkOrder,
            inProgressWorkOrder,
            completedWorkOrder
        };

        Maintenance_Log__c completedMaintenanceLog = new Maintenance_Log__c(
            Asset__c=customerAsset.Id,
            Work_Order__c=completedWorkOrder.Id,
            Maintenance_Date__c=Date.today().addDays(-5),
            Maintenance_Type__c='Repair',
            Summary__c='Replaced the worn spindle assembly and recalibrated the milling unit.',
            Root_Cause__c='Spindle bearing wear caused excessive vibration.',
            Parts_Used__c='Spindle assembly',
            Labor_Hours__c=3,
            Issue_Resolved__c=true,
            Follow_Up_Required__c=false
        );
        insert completedMaintenanceLog;

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
            Username='milltrack.service.customer.' + customerToken + '@milltrack.test',
            CommunityNickname='milltrackservice' + customerToken,
            TimeZoneSidKey='America/Vancouver',
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
    static void testNullServiceRequestIdIsRejected() {
        User portalUser = getPortalUser();

        System.runAs(portalUser) {
            Boolean exceptionThrown = false;

            Test.startTest();

            try {
                CustomerServiceRequestDetailsController.getServiceRequestDetails(null);
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();

            System.assertEquals(true, exceptionThrown, 'A null Service Request ID should be rejected.');
        }
    }

    @IsTest
    static void testNewRequestWithoutWorkOrder() {
        User portalUser = getPortalUser();

        Case serviceRequest = [
            SELECT Id
            FROM Case
            WHERE Subject = 'New request without work order'
            LIMIT 1
        ];

        System.runAs(portalUser) {
            Test.startTest();

            CustomerServiceRequestDetailsController.ServiceRequestDetailsData result =
                CustomerServiceRequestDetailsController.getServiceRequestDetails(serviceRequest.Id);

            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assertNotEquals(null, result.serviceRequest);
            System.assertEquals('Request Received', result.serviceRequest.customerStatus);
            System.assertEquals('Request Received', result.progress.currentStage);
            System.assertEquals(null, result.serviceVisit);
            System.assertEquals(null, result.resolution);
            System.assertNotEquals(null, result.machine);
            System.assertEquals('Roland 53DC', result.machine.name);
            System.assertNotEquals(null, result.machine.status);
            System.assertEquals(5, result.progress.stages.size());

            CustomerServiceRequestDetailsController.ProgressStage currentStage =
                getCurrentStage(result.progress.stages);

            System.assertNotEquals(null, currentStage);
            System.assertEquals('Request Received', currentStage.label);
        }
    }

    @IsTest
    static void testAssignedWorkOrderReturnsVisitScheduled() {
        User portalUser = getPortalUser();

        Case serviceRequest = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Service visit scheduled'
            LIMIT 1
        ];

        System.runAs(portalUser) {
            Test.startTest();

            CustomerServiceRequestDetailsController.ServiceRequestDetailsData result =
                CustomerServiceRequestDetailsController.getServiceRequestDetails(serviceRequest.Id);

            Test.stopTest();

            System.assertNotEquals(null, result.serviceVisit);
            System.assertEquals('Assigned', result.serviceVisit.dispatchStatus);
            System.assertEquals('Visit Scheduled', result.serviceRequest.customerStatus);
            System.assertEquals('Visit Scheduled', result.progress.currentStage);
            System.assertNotEquals(null, result.serviceVisit.scheduledVisit);
            System.assertEquals(null, result.resolution);
            System.assertEquals(5, result.progress.stages.size());

            CustomerServiceRequestDetailsController.ProgressStage currentStage =
                getCurrentStage(result.progress.stages);

            System.assertNotEquals(null, currentStage);
            System.assertEquals('Visit Scheduled', currentStage.label);
        }
    }

    @IsTest
    static void testInProgressWorkOrderReturnsServiceInProgress() {
        User portalUser = getPortalUser();

        Case serviceRequest = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Service currently in progress'
            LIMIT 1
        ];

        System.runAs(portalUser) {
            Test.startTest();

            CustomerServiceRequestDetailsController.ServiceRequestDetailsData result =
                CustomerServiceRequestDetailsController.getServiceRequestDetails(serviceRequest.Id);

            Test.stopTest();

            System.assertNotEquals(null, result.serviceVisit);
            System.assertEquals('In Progress', result.serviceVisit.dispatchStatus);
            System.assertEquals('Service in Progress', result.serviceRequest.customerStatus);
            System.assertEquals('Service in Progress', result.progress.currentStage);
            System.assertNotEquals(null, result.serviceVisit.scheduledVisit);
            System.assertNotEquals(null, result.serviceVisit.workStartedDateTime);
            System.assertEquals(null, result.serviceVisit.workEndedDateTime);
            System.assertEquals(null, result.resolution);

            CustomerServiceRequestDetailsController.ProgressStage currentStage =
                getCurrentStage(result.progress.stages);

            System.assertNotEquals(null, currentStage);
            System.assertEquals('Service in Progress', currentStage.label);
        }
    }

    @IsTest
    static void testCompletedRequestReturnsResolution() {
        User portalUser = getPortalUser();

        Case serviceRequest = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Completed spindle repair'
            LIMIT 1
        ];

        System.runAs(portalUser) {
            Test.startTest();

            CustomerServiceRequestDetailsController.ServiceRequestDetailsData result =
                CustomerServiceRequestDetailsController.getServiceRequestDetails(serviceRequest.Id);

            Test.stopTest();

            System.assertNotEquals(null, result.serviceVisit);
            System.assertEquals('Completed', result.serviceVisit.dispatchStatus);
            System.assertEquals('Completed', result.serviceRequest.customerStatus);
            System.assertEquals('Completed', result.progress.currentStage);
            System.assertNotEquals(null, result.serviceVisit.workStartedDateTime);
            System.assertNotEquals(null, result.serviceVisit.workEndedDateTime);

            System.assertNotEquals(null, result.resolution);
            System.assertEquals(
                'Spindle bearing wear caused excessive vibration.',
                result.resolution.rootCause
            );
            System.assertEquals(
                'Replaced the worn spindle assembly and recalibrated the milling unit.',
                result.resolution.summary
            );
            System.assertEquals('Spindle assembly', result.resolution.partsUsed);
            System.assertEquals(Decimal.valueOf('3'), result.resolution.laborHours);
            System.assertEquals(true, result.resolution.issueResolved);
            System.assertEquals(false, result.resolution.followUpRequired);
            System.assertEquals('Resolved', result.resolution.outcome);

            CustomerServiceRequestDetailsController.ProgressStage currentStage =
                getCurrentStage(result.progress.stages);

            System.assertNotEquals(null, currentStage);
            System.assertEquals('Completed', currentStage.label);
        }
    }

    @IsTest
    static void testCustomerCannotAccessAnotherAccountsRequest() {
        User portalUser = getPortalUser();

        Case unrelatedCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Another customer request'
            LIMIT 1
        ];

        System.runAs(portalUser) {
            Boolean exceptionThrown = false;

            Test.startTest();

            try {
                CustomerServiceRequestDetailsController.getServiceRequestDetails(unrelatedCase.Id);
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();

            System.assertEquals(
                true,
                exceptionThrown,
                'Customer should not be able to access a Service Request belonging to another account.'
            );
        }
    }

    @IsTest
    static void testRejectsInternalUserWithoutContact() {
        User internalUser = [
            SELECT Id
            FROM User
            WHERE LastName = 'Service Owner'
            LIMIT 1
        ];

        Case serviceRequest = [
            SELECT Id
            FROM Case
            WHERE Subject = 'New request without work order'
            LIMIT 1
        ];

        System.runAs(internalUser) {
            Boolean exceptionThrown = false;

            Test.startTest();

            try {
                CustomerServiceRequestDetailsController.getServiceRequestDetails(serviceRequest.Id);
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();

            System.assertEquals(
                true,
                exceptionThrown,
                'An internal user without a Contact should not be treated as a portal customer.'
            );
        }
    }

    private static User getPortalUser() {
        return [
            SELECT Id, ContactId
            FROM User
            WHERE LastName = 'Portal Customer'
            AND ContactId != null
            LIMIT 1
        ];
    }

    private static CustomerServiceRequestDetailsController.ProgressStage getCurrentStage(
        List<CustomerServiceRequestDetailsController.ProgressStage> stages
    ) {
        for (CustomerServiceRequestDetailsController.ProgressStage stage : stages) {
            if (stage.state == 'current') {
                return stage;
            }
        }

        return null;
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField field) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    private static String uniqueToken() {
        return String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    }
}