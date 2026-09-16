@IsTest
private class CustomerCaseDetailsControllerTest {

    private static final String CUSTOMER_PROFILE_NAME = 'MillTrack Customer Portal User';
    private static final String CUSTOMER_PERMISSION_SET_LABEL = 'MillTrack Customer Portal Access';

    private static final String CUSTOMER_CONTACT_EMAIL = 'case.details.portal@milltrack.test';

    private static final String CUSTOMER_SERIAL = 'CASE-DETAIL-001';
    private static final String UNRELATED_SERIAL = 'CASE-DETAIL-OTHER-001';

    private static final String PRIMARY_CASE_SUBJECT = 'Spindle vibration during production milling';
    private static final String SECONDARY_CASE_SUBJECT = 'Intermittent milling interruption';
    private static final String UNRELATED_CASE_SUBJECT = 'Private unrelated customer issue';

    private static final String OLDER_WORK_ORDER_SUBJECT = 'Initial MillTrack service review';
    private static final String LATEST_WORK_ORDER_SUBJECT = 'Current MillTrack service review';


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
            FirstName='Case',
            LastName='Details Owner',
            Alias='mtcsown',
            Email='case.details.owner.' + ownerToken + '@milltrack.test',
            Username='milltrack.case.details.owner.' + ownerToken + '@milltrack.test',
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
            Name='MillTrack Case Details Customer',
            OwnerId=accountOwner.Id
        );

        Account unrelatedAccount = new Account(
            Name='Unrelated Case Details Customer',
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
            LastName='Case Customer',
            Email=CUSTOMER_CONTACT_EMAIL,
            AccountId=customerAccount.Id
        );

        Contact unrelatedContact = new Contact(
            FirstName='Other',
            LastName='Customer',
            Email='case.details.other@milltrack.test',
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
            Name='Customer Roland 53DC',
            AccountId=customerAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c=CUSTOMER_SERIAL,
            Machine_Status__c='Active',
            Description='Customer production milling machine.',
            Install_Date__c=Date.newInstance(2024, 10, 7),
            Warranty_Start_Date__c=Date.newInstance(2024, 10, 7),
            Warranty_End_Date__c=Date.newInstance(2029, 10, 7),
            Last_Service_Date__c=Date.newInstance(2026, 9, 8),
            Portal_Image_Path__c='images/roland-53dc.jpg'
        );

        Asset unrelatedMachine = new Asset(
            Name='Other Customer Roland 53DC',
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

        Case primaryCase = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject=PRIMARY_CASE_SUBJECT,
            Description=
                'The customer reports increased spindle vibration during normal production milling.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Error_Code__c='E-421',
            Technician_Requested__c=true,
            Work_Order_Proposal_Created__c=true
        );

        Case secondaryCase = new Case(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            Subject=SECONDARY_CASE_SUBJECT,
            Description=
                'The machine intermittently pauses during the milling cycle.',
            Status='In Progress',
            Priority='Medium',
            Origin=caseOrigin,
            Error_Code__c='E-215',
            Technician_Requested__c=false,
            Work_Order_Proposal_Created__c=true
        );

        Case unrelatedCase = new Case(
            AccountId=unrelatedAccount.Id,
            ContactId=unrelatedContact.Id,
            AssetId=unrelatedMachine.Id,
            Subject=UNRELATED_CASE_SUBJECT,
            Description=
                'Private service request belonging to another customer account.',
            Status='New',
            Priority='High',
            Origin=caseOrigin,
            Error_Code__c='PRIVATE-999',
            Technician_Requested__c=true,
            Work_Order_Proposal_Created__c=true
        );

        insert new List<Case>{
            primaryCase,
            secondaryCase,
            unrelatedCase
        };


        // =====================================================
        // Related Work Orders
        //
        // WorkOrder.Status is populated only because Salesforce
        // requires the standard field on Work Order records.
        //
        // MillTrack workflow and customer-facing status use
        // Dispatch_Status__c exclusively.
        // =====================================================

        String requiredWorkOrderStatus = getFirstActivePicklistValue(WorkOrder.Status);

        WorkOrder olderWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            CaseId=primaryCase.Id,
            Subject=OLDER_WORK_ORDER_SUBJECT,
            Status=requiredWorkOrderStatus,
            Priority='High',
            Dispatch_Status__c='Pending',
            Problem_Summary__c='Initial review of reported spindle vibration.',
            OwnerId=accountOwner.Id
        );

        WorkOrder latestWorkOrder = new WorkOrder(
            AccountId=customerAccount.Id,
            ContactId=customerContact.Id,
            AssetId=customerMachine.Id,
            CaseId=primaryCase.Id,
            Subject=LATEST_WORK_ORDER_SUBJECT,
            Status=requiredWorkOrderStatus,
            Priority='High',
            Dispatch_Status__c='Ready_to_Assign',
            Problem_Summary__c='Service request is ready for technician assignment.',
            OwnerId=accountOwner.Id
        );

        insert olderWorkOrder;
        insert latestWorkOrder;

        Test.setCreatedDate(
            olderWorkOrder.Id,
            DateTime.newInstance(2026, 9, 12, 9, 0, 0)
        );

        Test.setCreatedDate(
            latestWorkOrder.Id,
            DateTime.newInstance(2026, 9, 13, 9, 0, 0)
        );


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
            LastName='Case Customer',
            Alias='mtcase',
            Email='case.customer.' + customerToken + '@milltrack.test',
            Username='milltrack.case.customer.' + customerToken + '@milltrack.test',
            CommunityNickname='milltrackcase' + customerToken,
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
    // Authorized Case Details
    // =========================================================

    @IsTest
    static void testGetCaseDetailsReturnsAuthorizedCaseMachineAndLatestServiceVisit() {
        User portalUser = getPortalUser();
        Case primaryCase = getPrimaryCase();

        WorkOrder latestWorkOrder = [
            SELECT
                Id,
                WorkOrderNumber,
                Dispatch_Status__c,
                Subject
            FROM WorkOrder
            WHERE CaseId = :primaryCase.Id
            AND Subject = :LATEST_WORK_ORDER_SUBJECT
            LIMIT 1
        ];

        WorkOrder olderWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE CaseId = :primaryCase.Id
            AND Subject = :OLDER_WORK_ORDER_SUBJECT
            LIMIT 1
        ];

        CustomerCaseDetailsController.CaseDetailsData data;

        System.runAs(portalUser) {
            Test.startTest();
            data = CustomerCaseDetailsController.getCaseDetails(primaryCase.Id);
            Test.stopTest();
        }


        // =====================================================
        // Main Response
        // =====================================================

        System.assertNotEquals(
            null,
            data,
            'Case details should be returned.'
        );

        System.assertNotEquals(
            null,
            data.serviceRequest,
            'The authorized service request should be returned.'
        );


        // =====================================================
        // Case Summary
        // =====================================================

        System.assertEquals(
            primaryCase.Id,
            data.serviceRequest.id
        );

        System.assertNotEquals(
            null,
            data.serviceRequest.caseNumber
        );

        System.assertEquals(
            'New',
            data.serviceRequest.status
        );

        System.assertEquals(
            'Request Received',
            data.serviceRequest.customerStatus
        );

        System.assertEquals(
            'High',
            data.serviceRequest.priority
        );

        System.assertEquals(
            PRIMARY_CASE_SUBJECT,
            data.serviceRequest.subject
        );

        System.assertEquals(
            'The customer reports increased spindle vibration during normal production milling.',
            data.serviceRequest.description
        );

        System.assertEquals(
            'E-421',
            data.serviceRequest.errorCode
        );

        System.assertEquals(
            true,
            data.serviceRequest.technicianRequested
        );

        System.assertNotEquals(
            null,
            data.serviceRequest.createdDate
        );

        System.assertEquals(
            null,
            data.serviceRequest.closedDate
        );

        System.assertEquals(
            primaryCase.AssetId,
            data.serviceRequest.assetId
        );


        // =====================================================
        // Related Machine
        // =====================================================

        System.assertNotEquals(
            null,
            data.machine,
            'The related customer machine should be returned.'
        );

        System.assertEquals(
            primaryCase.AssetId,
            data.machine.id
        );

        System.assertEquals(
            'Customer Roland 53DC',
            data.machine.name
        );

        System.assertEquals(
            'Roland',
            data.machine.manufacturer
        );

        System.assertEquals(
            'DWX-53DC',
            data.machine.model
        );

        System.assertEquals(
            CUSTOMER_SERIAL,
            data.machine.serialNumber
        );

        System.assertEquals(
            'Needs Service',
            data.machine.status,
            'Creating the service request should move the related machine into Needs Service.'
        );

        System.assertEquals(
            'images/roland-53dc.jpg',
            data.machine.portalImagePath
        );


        // =====================================================
        // Latest Related Work Order
        // =====================================================

        System.assertNotEquals(
            null,
            data.serviceVisit,
            'The latest related service visit should be returned.'
        );

        System.assertEquals(
            latestWorkOrder.Id,
            data.serviceVisit.id,
            'The newest Work Order should be returned.'
        );

        System.assertEquals(
            latestWorkOrder.WorkOrderNumber,
            data.serviceVisit.workOrderNumber
        );

        System.assertEquals(
            'Ready_to_Assign',
            data.serviceVisit.dispatchStatus
        );

        System.assertEquals(
            'Under Review',
            data.serviceVisit.customerStatus
        );

        System.assertEquals(
            LATEST_WORK_ORDER_SUBJECT,
            data.serviceVisit.subject
        );

        System.assertNotEquals(
            olderWorkOrder.Id,
            data.serviceVisit.id,
            'An older Work Order must not be returned instead of the latest one.'
        );
    }


    // =========================================================
    // Case Without Work Order
    // =========================================================

    @IsTest
    static void testGetCaseDetailsReturnsNullServiceVisitWhenNoWorkOrderExists() {
        User portalUser = getPortalUser();
        Case secondaryCase = getSecondaryCase();

        CustomerCaseDetailsController.CaseDetailsData data;

        System.runAs(portalUser) {
            Test.startTest();
            data = CustomerCaseDetailsController.getCaseDetails(secondaryCase.Id);
            Test.stopTest();
        }

        System.assertNotEquals(
            null,
            data,
            'The authorized Case should still load without a Work Order.'
        );

        System.assertEquals(
            secondaryCase.Id,
            data.serviceRequest.id
        );

        System.assertEquals(
            'In Progress',
            data.serviceRequest.status
        );

        System.assertEquals(
            'Service in Progress',
            data.serviceRequest.customerStatus
        );

        System.assertEquals(
            'E-215',
            data.serviceRequest.errorCode
        );

        System.assertEquals(
            false,
            data.serviceRequest.technicianRequested
        );

        System.assertNotEquals(
            null,
            data.machine,
            'The related Asset should still be returned.'
        );

        System.assertEquals(
            null,
            data.serviceVisit,
            'A Case without a Work Order should return no service visit.'
        );
    }


    // =========================================================
    // Cross-Account Security
    // =========================================================

    @IsTest
    static void testGetCaseDetailsRejectsCrossAccountCase() {
        User portalUser = getPortalUser();
        Case unrelatedCase = getUnrelatedCase();

        Boolean exceptionThrown = false;

        System.runAs(portalUser) {
            Test.startTest();

            try {
                CustomerCaseDetailsController.getCaseDetails(unrelatedCase.Id);
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'A customer must not be able to load another Account service request.'
        );
    }


    // =========================================================
    // Missing Case ID
    // =========================================================

    @IsTest
    static void testGetCaseDetailsRejectsMissingCaseId() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CustomerCaseDetailsController.getCaseDetails(null);
        } catch (AuraHandledException expectedException) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'A null Case ID must be rejected.'
        );
    }


    // =========================================================
    // Internal User Must Not Act As Customer
    // =========================================================

    @IsTest
    static void testGetCaseDetailsRejectsInternalUserWithoutContact() {
        Account customerAccount = [
            SELECT OwnerId
            FROM Account
            WHERE Name = 'MillTrack Case Details Customer'
            LIMIT 1
        ];

        User internalUser = [
            SELECT Id
            FROM User
            WHERE Id = :customerAccount.OwnerId
        ];

        Case primaryCase = getPrimaryCase();

        Boolean exceptionThrown = false;

        System.runAs(internalUser) {
            Test.startTest();

            try {
                CustomerCaseDetailsController.getCaseDetails(primaryCase.Id);
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'An internal user without a Contact must not receive customer Case data.'
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

    private static Case getPrimaryCase() {
        return [
            SELECT Id, AssetId
            FROM Case
            WHERE Subject = :PRIMARY_CASE_SUBJECT
            LIMIT 1
        ];
    }

    private static Case getSecondaryCase() {
        return [
            SELECT Id, AssetId
            FROM Case
            WHERE Subject = :SECONDARY_CASE_SUBJECT
            LIMIT 1
        ];
    }

    private static Case getUnrelatedCase() {
        return [
            SELECT Id
            FROM Case
            WHERE Subject = :UNRELATED_CASE_SUBJECT
            LIMIT 1
        ];
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) return entry.getValue();
        }

        throw new TestDataException(
            'An active picklist value is required for this test.'
        );
    }

    private static String uniqueToken() {
        String token = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Crypto.getRandomInteger());

        return token.replace('-', '1');
    }

    private class TestDataException extends Exception {
    }
}