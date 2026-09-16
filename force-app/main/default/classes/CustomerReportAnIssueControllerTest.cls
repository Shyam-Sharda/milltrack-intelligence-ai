@IsTest
private class CustomerReportAnIssueControllerTest {
    private static final String CUSTOMER_PROFILE_NAME = 'MillTrack Customer Portal User';
    private static final String CUSTOMER_PERMISSION_SET_LABEL = 'MillTrack Customer Portal Access';
    private static final String SERVICE_MANAGER_QUEUE = 'Service_Manager_Queue';

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
            LastName='Report Issue Owner',
            Alias='mtrpt',
            Email='report.owner.' + ownerToken + '@milltrack.test',
            Username='milltrack.report.owner.' + ownerToken + '@milltrack.test',
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
            Name='MillTrack Report Issue Customer',
            OwnerId=accountOwner.Id
        );

        Account unrelatedAccount = new Account(
            Name='Unrelated Report Issue Customer',
            OwnerId=accountOwner.Id
        );

        insert new List<Account>{
            customerAccount,
            unrelatedAccount
        };

        Contact customerContact = new Contact(
            FirstName='Maya',
            LastName='Report Customer',
            Email='maya.report.issue@milltrack.test',
            AccountId=customerAccount.Id
        );

        insert customerContact;

        Asset authorizedMachine = new Asset(
            Name='Customer DWX-53DC',
            AccountId=customerAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c='REPORT-DWX-001',
            Machine_Status__c='Active',
            Install_Date__c=Date.today().addYears(-1),
            Last_Service_Date__c=Date.today().addDays(-60),
            Portal_Image_Path__c='images/roland-53dc.jpg',
            Portal_Manual_Path__c='manuals/roland-53dc-manual.pdf'
        );

        Asset unrelatedMachine = new Asset(
            Name='Other Customer Machine',
            AccountId=unrelatedAccount.Id,
            Manufacturer__c='Roland',
            Model__c='DWX-53DC',
            Serial_Number__c='REPORT-OTHER-001',
            Machine_Status__c='Active',
            Portal_Image_Path__c='images/unrelated-machine.jpg',
            Portal_Manual_Path__c='manuals/unrelated-machine-manual.pdf'
        );

        insert new List<Asset>{
            authorizedMachine,
            unrelatedMachine
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
            LastName='Report Customer',
            Alias='mtrcust',
            Email='maya.report.customer.' + customerToken + '@milltrack.test',
            Username='milltrack.report.customer.' + customerToken + '@milltrack.test',
            CommunityNickname='milltrackreport' + customerToken,
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

            PermissionSetAssignment permissionAssignment =
                new PermissionSetAssignment(
                    AssigneeId=portalUser.Id,
                    PermissionSetId=customerPermissionSets[0].Id
                );

            insert permissionAssignment;
        }
    }

    @IsTest
    static void testGetReportIssueDataReturnsAuthorizedMachines() {
        User portalUser = getPortalUser();

        System.runAs(portalUser) {
            Test.startTest();

            CustomerReportAnIssueController.ReportIssueData reportData =
                CustomerReportAnIssueController.getReportIssueData();

            Test.stopTest();

            System.assertNotEquals(
                null,
                reportData,
                'Report Issue data should be returned.'
            );

            System.assertEquals(
                'Maya',
                reportData.customerFirstName,
                'Customer first name should come from the authenticated Contact.'
            );

            System.assertEquals(
                1,
                reportData.machines.size(),
                'Only machines belonging to the authenticated customer Account should be returned.'
            );

            System.assertEquals(
                'Customer DWX-53DC',
                reportData.machines[0].name
            );

            System.assertEquals(
                'REPORT-DWX-001',
                reportData.machines[0].serialNumber
            );

            System.assertEquals(
                'images/roland-53dc.jpg',
                reportData.machines[0].portalImagePath,
                'The authorized Asset image path should be returned.'
            );

            System.assertEquals(
                'manuals/roland-53dc-manual.pdf',
                reportData.machines[0].portalManualPath,
                'The authorized Asset manual path should be returned.'
            );

            System.assertNotEquals(
                'images/unrelated-machine.jpg',
                reportData.machines[0].portalImagePath,
                'Media from another customer Asset must not be returned.'
            );

            System.assertEquals(
                'Medium',
                reportData.defaultPriority,
                'Medium should remain the preferred default priority when available.'
            );

            System.assert(
                !reportData.priorities.isEmpty(),
                'At least one supported Case priority should be returned.'
            );
        }
    }

    @IsTest
    static void testSubmitServiceRequestCreatesAuthorizedCase() {
        User portalUser = getPortalUser();

        Contact customerContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Email = 'maya.report.issue@milltrack.test'
            LIMIT 1
        ];

        Asset authorizedMachine = [
            SELECT Id
            FROM Asset
            WHERE Serial_Number__c = 'REPORT-DWX-001'
            LIMIT 1
        ];

        CustomerReportAnIssueController.SubmissionResult result;

        System.runAs(portalUser) {
            Test.startTest();

            result = CustomerReportAnIssueController.submitServiceRequest(
                authorizedMachine.Id,
                'Spindle stops during milling',
                'The machine stops approximately five minutes into the milling cycle.',
                '1006',
                'High',
                true
            );

            Test.stopTest();

            System.assertEquals(
                true,
                result.success,
                'The authorized service request should be created successfully.'
            );

            System.assertNotEquals(
                null,
                result.caseId,
                'The created Case Id should be returned.'
            );

            System.assert(
                !String.isBlank(result.caseNumber),
                'The created Case number should be returned.'
            );
        }

        Case createdCase = [
            SELECT
                Id,
                CaseNumber,
                AccountId,
                ContactId,
                AssetId,
                Subject,
                Description,
                Error_Code__c,
                Priority,
                Status,
                Origin,
                OwnerId,
                Technician_Requested__c
            FROM Case
            WHERE Id = :result.caseId
            LIMIT 1
        ];

        System.assertEquals(
            customerContact.AccountId,
            createdCase.AccountId
        );

        System.assertEquals(
            customerContact.Id,
            createdCase.ContactId
        );

        System.assertEquals(
            authorizedMachine.Id,
            createdCase.AssetId
        );

        System.assertEquals(
            'Spindle stops during milling',
            createdCase.Subject
        );

        System.assertEquals(
            'The machine stops approximately five minutes into the milling cycle.',
            createdCase.Description
        );

        System.assertEquals(
            '1006',
            createdCase.Error_Code__c
        );

        System.assertEquals(
            'High',
            createdCase.Priority
        );

        System.assertEquals(
            'New',
            createdCase.Status
        );

        System.assertEquals(
            'Web',
            createdCase.Origin
        );

        System.assertEquals(
            true,
            createdCase.Technician_Requested__c
        );

        List<Group> serviceManagerQueues = [
            SELECT Id, DeveloperName, Type
            FROM Group
            WHERE Id = :createdCase.OwnerId
            AND Type = 'Queue'
            LIMIT 1
        ];

        System.assertEquals(
            1,
            serviceManagerQueues.size(),
            'The created Case should be owned by a Queue.'
        );

        System.assertEquals(
            SERVICE_MANAGER_QUEUE,
            serviceManagerQueues[0].DeveloperName,
            'The Case should be routed to the Service Manager Queue.'
        );
    }

    @IsTest
    static void testSubmitRejectsCrossAccountAsset() {
        User portalUser = getPortalUser();

        Asset unrelatedMachine = [
            SELECT Id
            FROM Asset
            WHERE Serial_Number__c = 'REPORT-OTHER-001'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        System.runAs(portalUser) {
            Test.startTest();

            try {
                CustomerReportAnIssueController.submitServiceRequest(
                    unrelatedMachine.Id,
                    'Unauthorized machine test',
                    'This request should never be created.',
                    null,
                    'Medium',
                    false
                );
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'A customer must not be able to submit a request for another Account Asset.'
        );

        Integer unauthorizedCases = [
            SELECT COUNT()
            FROM Case
            WHERE Subject = 'Unauthorized machine test'
        ];

        System.assertEquals(
            0,
            unauthorizedCases,
            'No Case should be created for an unauthorized Asset.'
        );
    }

    @IsTest
    static void testSubmitRequiresDescription() {
        User portalUser = getPortalUser();

        Asset authorizedMachine = [
            SELECT Id
            FROM Asset
            WHERE Serial_Number__c = 'REPORT-DWX-001'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        System.runAs(portalUser) {
            Test.startTest();

            try {
                CustomerReportAnIssueController.submitServiceRequest(
                    authorizedMachine.Id,
                    'Missing description test',
                    null,
                    null,
                    'Medium',
                    false
                );
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Description should be required before submitting a service request.'
        );
    }

    @IsTest
    static void testGetReportIssueDataRejectsInternalUserWithoutContact() {
        User internalUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'milltrack.report.owner.%'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        System.runAs(internalUser) {
            Test.startTest();

            try {
                CustomerReportAnIssueController.getReportIssueData();
            } catch (AuraHandledException expectedException) {
                exceptionThrown = true;
            }

            Test.stopTest();
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'An internal user without customer Contact context should not receive Report an Issue data.'
        );
    }

    private static User getPortalUser() {
        Contact customerContact = [
            SELECT Id
            FROM Contact
            WHERE Email = 'maya.report.issue@milltrack.test'
            LIMIT 1
        ];

        return [
            SELECT Id
            FROM User
            WHERE ContactId = :customerContact.Id
            LIMIT 1
        ];
    }

    private static String uniqueToken() {
        String token =
            String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Crypto.getRandomInteger());

        return token.replace('-', '1');
    }
}