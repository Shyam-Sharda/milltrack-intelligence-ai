@IsTest
private class CustomerWorkOrderDetailsControllerTest {

    private static final String CUSTOMER_PROFILE_NAME = 'MillTrack Customer Portal User';
    private static final String CUSTOMER_PERMISSION_SET_LABEL = 'MillTrack Customer Portal Access';

    private static final String CUSTOMER_CONTACT_EMAIL = 'workorder.details.portal@milltrack.test';

    private static final String CUSTOMER_ACCOUNT_NAME = 'MillTrack Work Order Details Customer';
    private static final String UNRELATED_ACCOUNT_NAME = 'Unrelated Work Order Details Customer';

    private static final String CUSTOMER_SERIAL = 'WO-DETAIL-001';
    private static final String UNRELATED_SERIAL = 'WO-DETAIL-OTHER-001';

    private static final String CASE_SUBJECT = 'Machine cutting restorations in the wrong position';
    private static final String UNRELATED_CASE_SUBJECT = 'Private unrelated customer machine issue';

    private static final String WORK_ORDER_SUBJECT_PREFIX = 'Customer Work Order Details - ';
    private static final String CASELESS_WORK_ORDER_SUBJECT = 'Customer Work Order Without Case';
    private static final String UNRELATED_WORK_ORDER_SUBJECT = 'Private Unrelated Work Order';


    // =========================================================
    // Test Setup
    // =========================================================

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
            FirstName='Work Order',
            LastName='Details Owner',
            Alias='mtwoown',
            Email='workorder.details.owner.' + ownerToken + '@milltrack.test',
            Username='milltrack.workorder.details.owner.' + ownerToken + '@milltrack.test',
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


        // =====================================================
        // Accounts
        // =====================================================

        Account customerAccount = new Account(
            Name=CUSTOMER_ACCOUNT_NAME,
            OwnerId=accountOwner.Id
        );

        Account unrelatedAccount = new Account(
            Name=UNRELATED_ACCOUNT_NAME,
            OwnerId=accountOwner.Id
        );

        insert new List<Account>{
            customerAccount,
            unrelatedAccount
        };


        // =====================================================
        // Contacts
        // =====================================================

        Contact customerContact = new Contact(
            FirstName='Maya',
            LastName='Work Order Customer',
            Email=CUSTOMER_CONTACT_EMAIL,
            AccountId=customerAccount.Id
        );

        Contact unrelatedContact = new Contact(
            FirstName='Other',
            LastName='Work Order Customer',
            Email='workorder.details.other@milltrack.test',
            AccountId=unrelatedAccount.Id
        );

        insert new List<Contact>{
            customerContact,
            unrelatedContact
        };


        // =====================================================
        // Assets
        // =====================================================

        Asset customerMachine = new Asset(
            Name='Precision Ceramill Motion 2',
            AccountId=customerAccount.Id,
            Manufacturer__c='Amann Girrbach',
            Model__c='Ceramill Motion 2',
            Serial_Number__c=CUSTOMER_SERIAL,
            Machine_Status__c='Active',
            Description='Primary customer milling machine.',
            Portal_Image_Path__c='images/ceramill-motion-2.jpg'
        );

        Asset unrelatedMachine = new Asset(
            Name='Private Customer Machine',
            AccountId=unrelatedAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c=UNRELATED_SERIAL,
            Machine_Status__c='Active',
            Description='Machine belonging to another MillTrack customer.',
            Portal_Image_Path__c='images/roland-53dc.jpg'
        );

        insert new List<Asset>{
            customerMachine,
            unrelatedMachine
        };


        // =====================================================
        // Cases
        // =====================================================

        String caseOrigin = getFirstActivePicklistValue(Case.Origin);

        Case customerCase = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject=CASE_SUBJECT,
            Description='Restorations are being cut in an incorrect position during milling.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Error_Code__c='E-451',
            Technician_Requested__c=true,
            Work_Order_Proposal_Created__c=true
        );

        Case unrelatedCase = new Case(
            AccountId=unrelatedAccount.Id,
            ContactId=unrelatedContact.Id,
            AssetId=unrelatedMachine.Id,
            Subject=UNRELATED_CASE_SUBJECT,
            Description='Private service request for another customer.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Error_Code__c='PRIVATE-451',
            Technician_Requested__c=true,
            Work_Order_Proposal_Created__c=true
        );

        insert new List<Case>{
            customerCase,
            unrelatedCase
        };


        // =====================================================
        // Work Orders
        //
        // WorkOrder.Status is populated only because Salesforce
        // requires its standard Status field.
        //
        // MillTrack business logic and customer-facing status use
        // Dispatch_Status__c exclusively.
        // =====================================================

        String requiredWorkOrderStatus = getFirstActivePicklistValue(WorkOrder.Status);

        List<String> dispatchStatuses = new List<String>{
            'Pending',
            'Parts to Order',
            'Waiting on Parts',
            'Ready_to_Assign',
            'Assigned',
            'In Progress',
            'Temporary Fix',
            'Completed',
            'Cancelled'
        };

        List<WorkOrder> workOrders = new List<WorkOrder>();

        for (String dispatchStatus : dispatchStatuses) {
            WorkOrder workOrderRecord = new WorkOrder(
                AccountId=customerAccount.Id,
                ContactId=customerContact.Id,
                AssetId=customerMachine.Id,
                CaseId=customerCase.Id,
                Subject=WORK_ORDER_SUBJECT_PREFIX + dispatchStatus,
                Status=requiredWorkOrderStatus,
                Priority='High',
                Dispatch_Status__c=dispatchStatus,
                Recommended_Solution__c = 
                    'Inspect machine calibration, material positioning, and milling alignment before the next production run.',
                OwnerId=accountOwner.Id
            );

            if (
                dispatchStatus == 'Assigned' ||
                dispatchStatus == 'In Progress' ||
                dispatchStatus == 'Temporary Fix' ||
                dispatchStatus == 'Completed'
            ) {
                workOrderRecord.Scheduled_Visit__c = DateTime.now().addDays(3);
            }

            if (
                dispatchStatus == 'In Progress' ||
                dispatchStatus == 'Temporary Fix' ||
                dispatchStatus == 'Completed'
            ) {
                workOrderRecord.Work_Started_Date_Time__c = DateTime.now().addHours(-2);
            }

            if (dispatchStatus == 'Completed') {
                workOrderRecord.Work_Ended_Date_Time__c = DateTime.now().addHours(-1);
            }

            if (
                dispatchStatus == 'Temporary Fix' ||
                dispatchStatus == 'Completed'
            ) {
                workOrderRecord.Technician_Notes__c =
                    'Test technician notes for ' + dispatchStatus + '.';
            }

            workOrders.add(workOrderRecord);
        }

        insert workOrders;


        // =====================================================
        // Authorized Work Order Without Case
        // =====================================================

        WorkOrder caselessWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject=CASELESS_WORK_ORDER_SUBJECT,
            Status=requiredWorkOrderStatus,
            Priority='Medium',
            Dispatch_Status__c='Pending',
            Recommended_Solution__c=
                'Review machine calibration and positioning before continuing production.',
            OwnerId=accountOwner.Id
        );

        insert caselessWorkOrder;


        // =====================================================
        // Cross-Account Work Order
        // =====================================================

        WorkOrder unrelatedWorkOrder = new WorkOrder(
            AccountId=unrelatedAccount.Id,
            ContactId=unrelatedContact.Id,
            AssetId=unrelatedMachine.Id,
            CaseId=unrelatedCase.Id,
            Subject=UNRELATED_WORK_ORDER_SUBJECT,
            Status=requiredWorkOrderStatus,
            Priority='High',
            Dispatch_Status__c='Ready_to_Assign',
            Recommended_Solution__c='PRIVATE OTHER CUSTOMER AI SOLUTION',
            OwnerId=accountOwner.Id
        );

        insert unrelatedWorkOrder;


        // =====================================================
        // Customer Portal User
        // =====================================================

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
            LastName='Work Order Customer',
            Alias='mtwocst',
            Email='workorder.customer.' + customerToken + '@milltrack.test',
            Username='milltrack.workorder.customer.' + customerToken + '@milltrack.test',
            CommunityNickname='milltrackwo' + customerToken,
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
    // Authorized Work Order Details
    // =========================================================

    @IsTest
    static void testGetWorkOrderDetailsReturnsAuthorizedData() {
        User portalUser = getPortalUser();
        WorkOrder workOrderRecord = getWorkOrderByDispatchStatus('Ready_to_Assign');

        WorkOrder expectedWorkOrder = [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                AssetId,
                CaseId,
                Dispatch_Status__c,
                Recommended_Solution__c,
                Scheduled_Visit__c,
                Work_Started_Date_Time__c,
                Work_Ended_Date_Time__c,
                CreatedDate
            FROM WorkOrder
            WHERE Id = :workOrderRecord.Id
        ];

        Asset expectedAsset = [
            SELECT
                Id,
                Name,
                Manufacturer__c,
                Model__c,
                Serial_Number__c,
                Machine_Status__c,
                Portal_Image_Path__c
            FROM Asset
            WHERE Id = :expectedWorkOrder.AssetId
        ];

        Case expectedCase = [
            SELECT
                Id,
                CaseNumber,
                Subject,
                Status,
                Priority,
                CreatedDate
            FROM Case
            WHERE Id = :expectedWorkOrder.CaseId
        ];

        CustomerWorkOrderDetailsController.WorkOrderDetailsData data;

        System.runAs(portalUser) {
            Test.startTest();
            data = CustomerWorkOrderDetailsController.getWorkOrderDetails(expectedWorkOrder.Id);
            Test.stopTest();
        }


        // =====================================================
        // Main Response
        // =====================================================

        System.assertNotEquals(
            null,
            data,
            'Work Order details should be returned.'
        );

        System.assertNotEquals(
            null,
            data.serviceVisit,
            'The service visit summary should be returned.'
        );

        System.assertNotEquals(
            null,
            data.progress,
            'Customer progress should be returned.'
        );

        System.assertNotEquals(
            null,
            data.machine,
            'The affected machine should be returned.'
        );

        System.assertNotEquals(
            null,
            data.serviceRequest,
            'The originating service request should be returned.'
        );


        // =====================================================
        // Service Visit
        // =====================================================

        System.assertEquals(
            expectedWorkOrder.Id,
            data.serviceVisit.id
        );

        System.assertEquals(
            expectedWorkOrder.WorkOrderNumber,
            data.serviceVisit.workOrderNumber
        );

        System.assertEquals(
            WORK_ORDER_SUBJECT_PREFIX + 'Ready_to_Assign',
            data.serviceVisit.subject
        );

        System.assertEquals(
            'Ready_to_Assign',
            data.serviceVisit.dispatchStatus
        );

        System.assertEquals(
            expectedWorkOrder.Recommended_Solution__c,
            data.serviceVisit.recommendedSolution
        );

        System.assertEquals(
            expectedWorkOrder.Scheduled_Visit__c,
            data.serviceVisit.scheduledVisit
        );

        System.assertEquals(
            expectedWorkOrder.Work_Started_Date_Time__c,
            data.serviceVisit.workStartedDateTime
        );

        System.assertEquals(
            expectedWorkOrder.Work_Ended_Date_Time__c,
            data.serviceVisit.workEndedDateTime
        );

        System.assertEquals(
            expectedWorkOrder.CreatedDate,
            data.serviceVisit.createdDate
        );

        System.assertEquals(
            expectedWorkOrder.AssetId,
            data.serviceVisit.assetId
        );

        System.assertEquals(
            expectedWorkOrder.CaseId,
            data.serviceVisit.caseId
        );


        // =====================================================
        // Progress
        // =====================================================

        System.assertEquals(
            'Ready_to_Assign',
            data.progress.dispatchStatus
        );

        System.assertEquals(
            'Under Review',
            data.progress.currentStage
        );

        System.assertEquals(
            false,
            data.progress.isCancelled
        );

        System.assertEquals(
            false,
            data.progress.showPartsStage
        );

        System.assertEquals(
            6,
            data.progress.stages.size()
        );

        System.assertEquals(
            1,
            countStagesWithState(data.progress.stages, 'current')
        );

        System.assertEquals(
            true,
            containsStage(data.progress.stages, 'Under Review')
        );


        // =====================================================
        // Machine
        // =====================================================

        System.assertEquals(
            expectedAsset.Id,
            data.machine.id
        );

        System.assertEquals(
            expectedAsset.Name,
            data.machine.name
        );

        System.assertEquals(
            expectedAsset.Manufacturer__c,
            data.machine.manufacturer
        );

        System.assertEquals(
            expectedAsset.Model__c,
            data.machine.model
        );

        System.assertEquals(
            expectedAsset.Serial_Number__c,
            data.machine.serialNumber
        );

        System.assertEquals(
            expectedAsset.Machine_Status__c,
            data.machine.status
        );

        System.assertEquals(
            expectedAsset.Portal_Image_Path__c,
            data.machine.portalImagePath
        );


        // =====================================================
        // Related Service Request
        // =====================================================

        System.assertEquals(
            expectedCase.Id,
            data.serviceRequest.id
        );

        System.assertEquals(
            expectedCase.CaseNumber,
            data.serviceRequest.caseNumber
        );

        System.assertEquals(
            expectedCase.Subject,
            data.serviceRequest.subject
        );

        System.assertEquals(
            expectedCase.Status,
            data.serviceRequest.status
        );

        System.assertEquals(
            getExpectedCustomerCaseStatus(expectedCase.Status),
            data.serviceRequest.customerStatus
        );

        System.assertEquals(
            expectedCase.Priority,
            data.serviceRequest.priority
        );

        System.assertEquals(
            expectedCase.CreatedDate,
            data.serviceRequest.createdDate
        );
    }


    // =========================================================
    // Every Dispatch Status
    // =========================================================

    @IsTest
    static void testGetWorkOrderDetailsMapsEveryDispatchStatus() {
        User portalUser = getPortalUser();

        Map<String, String> expectedStageByStatus = new Map<String, String>{
            'Pending' => 'Request Received',
            'Parts to Order' => 'Waiting on Parts',
            'Waiting on Parts' => 'Waiting on Parts',
            'Ready_to_Assign' => 'Under Review',
            'Assigned' => 'Visit Scheduled',
            'In Progress' => 'Service in Progress',
            'Temporary Fix' => 'Service in Progress',
            'Completed' => 'Completed',
            'Cancelled' => 'Service Cancelled'
        };

        String subjectPattern = WORK_ORDER_SUBJECT_PREFIX + '%';

        List<WorkOrder> workOrders = [
            SELECT
                Id,
                Dispatch_Status__c,
                Scheduled_Visit__c,
                Work_Started_Date_Time__c,
                Work_Ended_Date_Time__c
            FROM WorkOrder
            WHERE Subject LIKE :subjectPattern
            ORDER BY Dispatch_Status__c
        ];

        System.assertEquals(
            9,
            workOrders.size(),
            'The setup should create one customer Work Order for every Dispatch Status.'
        );

        System.runAs(portalUser) {
            Test.startTest();

            for (WorkOrder workOrderRecord : workOrders) {
                CustomerWorkOrderDetailsController.WorkOrderDetailsData data =
                    CustomerWorkOrderDetailsController.getWorkOrderDetails(workOrderRecord.Id);

                String dispatchStatus = workOrderRecord.Dispatch_Status__c;

                Boolean expectsPartsStage =
                    dispatchStatus == 'Parts to Order' ||
                    dispatchStatus == 'Waiting on Parts';

                Boolean expectsCancellation =
                    dispatchStatus == 'Cancelled';

                System.assertEquals(
                    dispatchStatus,
                    data.progress.dispatchStatus,
                    'Incorrect Dispatch Status returned for ' + dispatchStatus + '.'
                );

                System.assertEquals(
                    expectedStageByStatus.get(dispatchStatus),
                    data.progress.currentStage,
                    'Incorrect customer stage for ' + dispatchStatus + '.'
                );

                System.assertEquals(
                    expectsPartsStage,
                    data.progress.showPartsStage,
                    'Incorrect parts-stage visibility for ' + dispatchStatus + '.'
                );

                System.assertEquals(
                    expectsCancellation,
                    data.progress.isCancelled,
                    'Incorrect cancellation result for ' + dispatchStatus + '.'
                );

                System.assert(
                    String.isNotBlank(data.progress.message),
                    'Every Dispatch Status should return a customer-safe progress message.'
                );

                System.assertEquals(
                    expectsPartsStage ? 7 : 6,
                    data.progress.stages.size(),
                    'Incorrect number of progress stages for ' + dispatchStatus + '.'
                );

                System.assertEquals(
                    expectsPartsStage,
                    containsStage(data.progress.stages, 'Waiting on Parts'),
                    'Waiting on Parts should only appear when applicable.'
                );

                System.assertEquals(
                    expectsCancellation ? 0 : 1,
                    countStagesWithState(data.progress.stages, 'current'),
                    'The progress tracker should have the correct current-stage count.'
                );


                // =============================================
                // Lifecycle Timing Fields
                // =============================================

                if (dispatchStatus == 'Assigned') {
                    System.assertNotEquals(
                        null,
                        data.serviceVisit.scheduledVisit,
                        'Assigned visits should return the scheduled visit date.'
                    );
                }

                if (
                    dispatchStatus == 'In Progress' ||
                    dispatchStatus == 'Temporary Fix'
                ) {
                    System.assertNotEquals(
                        null,
                        data.serviceVisit.workStartedDateTime,
                        dispatchStatus + ' should return a work started date/time.'
                    );
                }

                if (dispatchStatus == 'Completed') {
                    System.assertNotEquals(
                        null,
                        data.serviceVisit.workStartedDateTime,
                        'Completed visits should return a work started date/time.'
                    );

                    System.assertNotEquals(
                        null,
                        data.serviceVisit.workEndedDateTime,
                        'Completed visits should return a work ended date/time.'
                    );
                }
            }

            Test.stopTest();
        }
    }


    // =========================================================
    // Work Order Without Case
    // =========================================================

    @IsTest
    static void testGetWorkOrderDetailsAllowsAuthorizedWorkOrderWithoutCase() {
        User portalUser = getPortalUser();

        WorkOrder caselessWorkOrder = [
            SELECT Id, AssetId
            FROM WorkOrder
            WHERE Subject = :CASELESS_WORK_ORDER_SUBJECT
            LIMIT 1
        ];

        CustomerWorkOrderDetailsController.WorkOrderDetailsData data;

        System.runAs(portalUser) {
            Test.startTest();
            data = CustomerWorkOrderDetailsController.getWorkOrderDetails(caselessWorkOrder.Id);
            Test.stopTest();
        }

        System.assertNotEquals(
            null,
            data,
            'The authorized Work Order should still load without a Case.'
        );

        System.assertNotEquals(
            null,
            data.serviceVisit
        );

        System.assertNotEquals(
            null,
            data.progress
        );

        System.assertNotEquals(
            null,
            data.machine
        );

        System.assertEquals(
            null,
            data.serviceRequest,
            'A Work Order without a Case should return no related service request.'
        );
    }


    // =========================================================
    // Cross-Account Security
    // =========================================================

    @IsTest
    static void testGetWorkOrderDetailsRejectsCrossAccountWorkOrder() {
        User portalUser = getPortalUser();

        WorkOrder unrelatedWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :UNRELATED_WORK_ORDER_SUBJECT
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        System.runAs(portalUser) {
            Test.startTest();

            try {
                CustomerWorkOrderDetailsController.getWorkOrderDetails(
                    unrelatedWorkOrder.Id
                );
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'A customer must not be able to load another Account Work Order.'
        );
    }


    // =========================================================
    // Missing / Wrong Record ID
    // =========================================================

    @IsTest
    static void testGetWorkOrderDetailsRejectsMissingOrWrongRecordId() {
        User portalUser = getPortalUser();

        Account customerAccount = [
            SELECT Id
            FROM Account
            WHERE Name = :CUSTOMER_ACCOUNT_NAME
            LIMIT 1
        ];

        Boolean missingIdWasRejected = false;
        Boolean wrongObjectIdWasRejected = false;

        System.runAs(portalUser) {
            Test.startTest();

            try {
                CustomerWorkOrderDetailsController.getWorkOrderDetails(null);
            } catch (AuraHandledException expectedException) {
                missingIdWasRejected = true;
            }

            try {
                CustomerWorkOrderDetailsController.getWorkOrderDetails(
                    customerAccount.Id
                );
            } catch (AuraHandledException expectedException) {
                wrongObjectIdWasRejected = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            missingIdWasRejected,
            'A missing Work Order ID should be rejected.'
        );

        System.assertEquals(
            true,
            wrongObjectIdWasRejected,
            'An ID belonging to another object should be rejected.'
        );
    }


    // =========================================================
    // Internal User Must Not Act As Customer
    // =========================================================

    @IsTest
    static void testGetWorkOrderDetailsRejectsInternalUserWithoutContact() {
        Account customerAccount = [
            SELECT OwnerId
            FROM Account
            WHERE Name = :CUSTOMER_ACCOUNT_NAME
            LIMIT 1
        ];

        User internalUser = [
            SELECT Id
            FROM User
            WHERE Id = :customerAccount.OwnerId
        ];

        WorkOrder workOrderRecord =
            getWorkOrderByDispatchStatus('Ready_to_Assign');

        Boolean exceptionThrown = false;

        System.runAs(internalUser) {
            Test.startTest();

            try {
                CustomerWorkOrderDetailsController.getWorkOrderDetails(
                    workOrderRecord.Id
                );
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'An internal user without a Contact must not receive customer Work Order data.'
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


    private static WorkOrder getWorkOrderByDispatchStatus(String dispatchStatus) {
        String subject = WORK_ORDER_SUBJECT_PREFIX + dispatchStatus;

        return [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :subject
            LIMIT 1
        ];
    }


    private static Boolean containsStage(
        List<CustomerWorkOrderDetailsController.ProgressStage> stages,
        String expectedLabel
    ) {
        for (
            CustomerWorkOrderDetailsController.ProgressStage stage :
            stages
        ) {
            if (stage.label == expectedLabel) {
                return true;
            }
        }

        return false;
    }


    private static Integer countStagesWithState(
        List<CustomerWorkOrderDetailsController.ProgressStage> stages,
        String expectedState
    ) {
        Integer matchingStages = 0;

        for (
            CustomerWorkOrderDetailsController.ProgressStage stage :
            stages
        ) {
            if (stage.state == expectedState) {
                matchingStages++;
            }
        }

        return matchingStages;
    }


    private static String getExpectedCustomerCaseStatus(String status) {
        if (String.isBlank(status)) return 'Request Received';

        switch on status {
            when 'New' {
                return 'Request Received';
            }

            when 'Scheduled' {
                return 'Visit Scheduled';
            }

            when 'In Progress' {
                return 'Service in Progress';
            }

            when 'Waiting on Parts' {
                return 'Waiting on Parts';
            }

            when 'Follow-Up Required' {
                return 'Follow-Up Required';
            }

            when 'Closed' {
                return 'Completed';
            }

            when else {
                return status;
            }
        }
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

        throw new TestDataException(
            'An active picklist value is required for this test.'
        );
    }


    private static String uniqueToken() {
        String token =
            String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Crypto.getRandomInteger());

        return token.replace('-', '1');
    }


    private class TestDataException extends Exception {
    }
}