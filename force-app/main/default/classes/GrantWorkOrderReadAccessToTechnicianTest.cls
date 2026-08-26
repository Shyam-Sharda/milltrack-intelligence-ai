@IsTest
private class GrantWorkOrderReadAccessToTechnicianTest {

    private static User createTechnician() {
        String uniqueValue = String.valueOf(DateTime.now().getTime());

        User technician = new User(
            Alias = 'ttech',
            Email = 'testtechnician' + uniqueValue + '@milltrack.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Test Technician',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'testtechnician'
                + uniqueValue
                + '@milltrack.test'
        );

        insert technician;
        return technician;
    }

    private static WorkOrder createWorkOrder() {
        Account accountRecord = new Account(
            Name = 'MillTrack Sharing Test Account'
        );
        insert accountRecord;

        WorkOrder workOrderRecord = new WorkOrder(
            Subject = 'Test technician read sharing',
            AccountId = accountRecord.Id
        );

        // Avoid hardcoding an org-specific Work Order Status value.
        for (
            Schema.PicklistEntry entry :
            WorkOrder.Status.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                workOrderRecord.Status = entry.getValue();
                break;
            }
        }

        insert workOrderRecord;
        return workOrderRecord;
    }

    @IsTest
    static void grantsReadOnlyShareAsynchronously() {

        User technician = createTechnician();
        WorkOrder workOrderRecord = createWorkOrder();

        GrantWorkOrderReadAccessToTechnician.Request requestRecord =
            new GrantWorkOrderReadAccessToTechnician.Request();

        requestRecord.workOrderId = workOrderRecord.Id;
        requestRecord.technicianId = technician.Id;

        Test.startTest();

        List<GrantWorkOrderReadAccessToTechnician.Result> results =
            GrantWorkOrderReadAccessToTechnician.grantReadAccess(
                new List<GrantWorkOrderReadAccessToTechnician.Request>{
                    requestRecord
                }
            );

        // The invocable action queues the sharing work.
        System.assertEquals(
            1,
            results.size(),
            'One result should be returned.'
        );

        System.assertEquals(
            true,
            results[0].success,
            'Valid sharing request should be accepted.'
        );

        System.assertEquals(
            'QUEUED',
            results[0].statusCode,
            'Valid request should be queued for asynchronous sharing.'
        );

        System.assertEquals(
            workOrderRecord.Id,
            results[0].workOrderId
        );

        System.assertEquals(
            technician.Id,
            results[0].technicianId
        );

        Test.stopTest();

        // Test.stopTest() executes the Queueable.
        List<WorkOrderShare> shares = [
            SELECT
                ParentId,
                UserOrGroupId,
                AccessLevel,
                RowCause
            FROM WorkOrderShare
            WHERE ParentId = :workOrderRecord.Id
            AND UserOrGroupId = :technician.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(
            1,
            shares.size(),
            'Exactly one technician Manual share should exist.'
        );

        System.assertEquals(
            workOrderRecord.Id,
            shares[0].ParentId
        );

        System.assertEquals(
            technician.Id,
            shares[0].UserOrGroupId
        );

        System.assertEquals(
            'Read',
            shares[0].AccessLevel,
            'Technician access must be read-only.'
        );

        System.assertEquals(
            'Manual',
            shares[0].RowCause,
            'Technician share should use Manual row cause.'
        );
    }

    @IsTest
    static void doesNotCreateDuplicateShare() {

        User technician = createTechnician();
        WorkOrder workOrderRecord = createWorkOrder();

        // Simulate an existing post-visit read-only share.
        WorkOrderShare existingShare = new WorkOrderShare(
            ParentId = workOrderRecord.Id,
            UserOrGroupId = technician.Id,
            AccessLevel = 'Read',
            RowCause = Schema.WorkOrderShare.RowCause.Manual
        );
        insert existingShare;

        GrantWorkOrderReadAccessToTechnician.Request requestRecord =
            new GrantWorkOrderReadAccessToTechnician.Request();

        requestRecord.workOrderId = workOrderRecord.Id;
        requestRecord.technicianId = technician.Id;

        Test.startTest();

        List<GrantWorkOrderReadAccessToTechnician.Result> results =
            GrantWorkOrderReadAccessToTechnician.grantReadAccess(
                new List<GrantWorkOrderReadAccessToTechnician.Request>{
                    requestRecord
                }
            );

        // Duplicate detection now occurs inside the Queueable.
        // The invocable itself only confirms that the job was queued.
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('QUEUED', results[0].statusCode);

        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM WorkOrderShare
            WHERE ParentId = :workOrderRecord.Id
            AND UserOrGroupId = :technician.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(
            1,
            shareCount,
            'Queueable must not create a duplicate Work Order share.'
        );
    }

    @IsTest
    static void handlesMissingWorkOrderId() {

        User technician = createTechnician();

        GrantWorkOrderReadAccessToTechnician.Request requestRecord =
            new GrantWorkOrderReadAccessToTechnician.Request();

        requestRecord.technicianId = technician.Id;

        Test.startTest();

        List<GrantWorkOrderReadAccessToTechnician.Result> results =
            GrantWorkOrderReadAccessToTechnician.grantReadAccess(
                new List<GrantWorkOrderReadAccessToTechnician.Request>{
                    requestRecord
                }
            );

        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);

        System.assertEquals(
            'MISSING_WORK_ORDER',
            results[0].statusCode
        );

        System.assertEquals(
            technician.Id,
            results[0].technicianId
        );
    }

    @IsTest
    static void handlesMissingTechnicianId() {

        WorkOrder workOrderRecord = createWorkOrder();

        GrantWorkOrderReadAccessToTechnician.Request requestRecord =
            new GrantWorkOrderReadAccessToTechnician.Request();

        requestRecord.workOrderId = workOrderRecord.Id;

        Test.startTest();

        List<GrantWorkOrderReadAccessToTechnician.Result> results =
            GrantWorkOrderReadAccessToTechnician.grantReadAccess(
                new List<GrantWorkOrderReadAccessToTechnician.Request>{
                    requestRecord
                }
            );

        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);

        System.assertEquals(
            'MISSING_TECHNICIAN',
            results[0].statusCode
        );

        System.assertEquals(
            workOrderRecord.Id,
            results[0].workOrderId
        );
    }

    @IsTest
    static void handlesNullRequest() {

        Test.startTest();

        List<GrantWorkOrderReadAccessToTechnician.Result> results =
            GrantWorkOrderReadAccessToTechnician.grantReadAccess(
                new List<GrantWorkOrderReadAccessToTechnician.Request>{
                    null
                }
            );

        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);

        System.assertEquals(
            'INVALID_REQUEST',
            results[0].statusCode
        );
    }

    @IsTest
    static void handlesEmptyRequestList() {

        Test.startTest();

        List<GrantWorkOrderReadAccessToTechnician.Result> results =
            GrantWorkOrderReadAccessToTechnician.grantReadAccess(
                new List<GrantWorkOrderReadAccessToTechnician.Request>()
            );

        Test.stopTest();

        System.assertEquals(
            0,
            results.size(),
            'Empty input should return an empty result list.'
        );
    }
}