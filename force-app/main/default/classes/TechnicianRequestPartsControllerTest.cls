@IsTest
private class TechnicianRequestPartsControllerTest {

    private static final String TEST_PROBLEM_SUMMARY =
        'Spindle bearing noise persists during milling and requires further service.';

    @TestSetup
    static void setupQueue() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = 'Service_Manager_Queue'
            LIMIT 1
        ];

        if (queues.isEmpty()) {
            Group g = new Group(
                Name = 'Service Manager Queue',
                DeveloperName = 'Service_Manager_Queue',
                Type = 'Queue'
            );
            insert g;

            insert new QueueSobject(
                QueueId = g.Id,
                SobjectType = 'WorkOrder'
            );
        }
    }

    private static Account createAccount() {
        Account a = new Account(Name = 'MillTrack Request Parts Test');
        insert a;
        return a;
    }

    private static Asset createAsset(Id accountId) {
        Asset a = new Asset(
            Name = 'Test Roland DWX-52D',
            AccountId = accountId,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D'
        );
        insert a;
        return a;
    }

    private static Case createCase(Id accountId) {
        Case c = new Case(
            AccountId = accountId,
            Subject = 'Milling machine requires service',
            Status = 'In Progress',
            Origin = 'Web',
            Work_Order_Proposal_Created__c = true
        );
        insert c;
        return c;
    }

    private static WorkOrder createWorkOrder(
        Id accountId,
        Id caseId,
        Id assetId,
        String dispatchStatus
    ) {
        WorkOrder wo = new WorkOrder(
            AccountId = accountId,
            CaseId = caseId,
            AssetId = assetId,
            Subject = 'Request Parts Test',
            Problem_Summary__c = TEST_PROBLEM_SUMMARY,
            Dispatch_Status__c = dispatchStatus,
            Labor_Hours__c = 1.25,
            Technician_Notes__c = 'Previous technician visit notes.',
            Scheduled_Visit__c = System.now().addDays(1),
            Suggested_Technician__c = UserInfo.getUserId()
        );
        insert wo;
        return wo;
    }

    private static Part_Catalog__c createPart(Boolean active) {
        Part_Catalog__c part = new Part_Catalog__c(
            Name = 'Roland Test Spindle Bearing',
            Part_Number__c = 'TEST-SPINDLE-001',
            Manufacturer__c = 'Roland',
            Compatible_Model__c = 'DWX-52D',
            Active__c = active,
            Keyword_Aliases__c = 'spindle bearing, bearing, spindle'
        );
        insert part;
        return part;
    }

    @IsTest
    static void contextAndPartSearchWork() {
        Account account = createAccount();
        Asset asset = createAsset(account.Id);
        Case c = createCase(account.Id);
        WorkOrder wo = createWorkOrder(
            account.Id,
            c.Id,
            asset.Id,
            'In Progress'
        );
        Part_Catalog__c part = createPart(true);

        Test.startTest();

        TechnicianRequestPartsController.RequestContext context =
            TechnicianRequestPartsController.getRequestContext(wo.Id);

        List<TechnicianRequestPartsController.PartOption> parts =
            TechnicianRequestPartsController.getParts(
                'spindle',
                'Roland'
            );

        Test.stopTest();

        System.assertEquals(wo.Id, context.workOrderId);
        System.assertEquals(asset.Id, context.assetId);
        System.assertEquals(1.25, context.currentLaborHours);

        System.assertEquals(1, parts.size());
        System.assertEquals(part.Id, parts[0].id);
        System.assertEquals('Roland Test Spindle Bearing', parts[0].name);
        System.assertEquals('TEST-SPINDLE-001', parts[0].partNumber);
        System.assertEquals('Roland', parts[0].manufacturer);
    }

    @IsTest
    static void submitPartsRequestCreatesCompleteTransaction() {
        Account account = createAccount();
        Asset asset = createAsset(account.Id);
        Case c = createCase(account.Id);
        WorkOrder wo = createWorkOrder(
            account.Id,
            c.Id,
            asset.Id,
            'In Progress'
        );
        Part_Catalog__c part = createPart(true);

        Id queueId = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = 'Service_Manager_Queue'
            AND Type = 'Queue'
            LIMIT 1
        ].Id;

        Test.startTest();

        TechnicianRequestPartsController.SubmitResult result =
            TechnicianRequestPartsController.submitPartsRequest(
                wo.Id,
                part.Id,
                2,
                'Bearing remains noisy after inspection.',
                'Inspected the spindle assembly and attempted reseating. The noise persisted and replacement is required before repair can be completed.',
                1.50,
                false
            );

        Test.stopTest();

        Work_Order_Part__c wop = [
            SELECT Work_Order__c,
                   Machine__c,
                   Part_Catalog__c,
                   Quantity__c,
                   Notes__c,
                   Order_Status__c,
                   Technician_Requested__c
            FROM Work_Order_Part__c
            WHERE Id = :result.workOrderPartId
        ];

        Maintenance_Log__c log = [
            SELECT Asset__c,
                   Work_Order__c,
                   Maintenance_Type__c,
                   Problem_Summary__c,
                   Summary__c,
                   Technician_Notes__c,
                   Root_Cause__c,
                   Labor_Hours__c,
                   Issue_Resolved__c,
                   Follow_Up_Required__c,
                   Performed_By__c
            FROM Maintenance_Log__c
            WHERE Id = :result.maintenanceLogId
        ];

        WorkOrder updatedWo = [
            SELECT Dispatch_Status__c,
                   OwnerId,
                   Scheduled_Visit__c,
                   Suggested_Technician__c,
                   Labor_Hours__c,
                   Technician_Notes__c
            FROM WorkOrder
            WHERE Id = :wo.Id
        ];

        Case updatedCase = [
            SELECT Status
            FROM Case
            WHERE Id = :c.Id
        ];

        Asset unchangedAsset = [
            SELECT Id, Name, AccountId
            FROM Asset
            WHERE Id = :asset.Id
        ];

        System.assertEquals(wo.Id, wop.Work_Order__c);
        System.assertEquals(asset.Id, wop.Machine__c);
        System.assertEquals(part.Id, wop.Part_Catalog__c);
        System.assertEquals(2, wop.Quantity__c);
        System.assertEquals(
            'Bearing remains noisy after inspection.',
            wop.Notes__c
        );
        System.assertEquals('Requested', wop.Order_Status__c);
        System.assertEquals(true, wop.Technician_Requested__c);

        System.assertEquals(asset.Id, log.Asset__c);
        System.assertEquals(wo.Id, log.Work_Order__c);
        System.assertEquals('Inspection', log.Maintenance_Type__c);
        System.assertEquals(
            TEST_PROBLEM_SUMMARY,
            log.Problem_Summary__c,
            'Maintenance Log should preserve the Work Order Problem Summary.'
        );
        System.assertEquals(
            'Inspected the spindle assembly and attempted reseating. The noise persisted and replacement is required before repair can be completed.',
            log.Summary__c
        );
        System.assertEquals(null, log.Root_Cause__c);
        System.assertEquals(1.50, log.Labor_Hours__c);
        System.assertEquals(false, log.Issue_Resolved__c);
        System.assertEquals(true, log.Follow_Up_Required__c);
        System.assertEquals(UserInfo.getUserId(), log.Performed_By__c);
        System.assert(log.Technician_Notes__c.contains('PARTS REQUEST'));
        System.assert(log.Technician_Notes__c.contains('Quantity: 2'));

        System.assertEquals(
            'Waiting on Parts',
            updatedWo.Dispatch_Status__c
        );
        System.assertEquals(queueId, updatedWo.OwnerId);
        System.assertEquals(null, updatedWo.Scheduled_Visit__c);
        System.assertEquals(null, updatedWo.Suggested_Technician__c);
        System.assertEquals(2.75, updatedWo.Labor_Hours__c);
        System.assert(
            updatedWo.Technician_Notes__c.contains(
                'Previous technician visit notes.'
            )
        );
        System.assert(
            updatedWo.Technician_Notes__c.contains(
                'PARTS REQUEST VISIT'
            )
        );

        System.assertEquals('Waiting on Parts', updatedCase.Status);

        System.assertEquals(asset.Id, unchangedAsset.Id);
        System.assertEquals('Test Roland DWX-52D', unchangedAsset.Name);
        System.assertEquals(account.Id, unchangedAsset.AccountId);

        System.assertEquals(
            'Waiting on Parts',
            result.workOrderStatus
        );
        System.assertEquals(
            'Waiting on Parts',
            result.caseStatus
        );

        System.assertEquals(false, result.notificationSent);
        System.assertNotEquals(null, result.notificationWarning);
    }

    @IsTest
    static void temporaryRepairCreatesTemporaryRepairMaintenanceLog() {
        Account account = createAccount();
        Asset asset = createAsset(account.Id);
        Case c = createCase(account.Id);
        WorkOrder wo = createWorkOrder(
            account.Id,
            c.Id,
            asset.Id,
            'In Progress'
        );
        Part_Catalog__c part = createPart(true);

        Test.startTest();

        TechnicianRequestPartsController.SubmitResult result =
            TechnicianRequestPartsController.submitPartsRequest(
                wo.Id,
                part.Id,
                1,
                'Replacement spindle bearing is required.',
                'A temporary adjustment reduced spindle vibration enough to leave the machine stable while the replacement part is ordered.',
                0.75,
                true
            );

        Test.stopTest();

        Maintenance_Log__c log = [
            SELECT Maintenance_Type__c,
                   Problem_Summary__c,
                   Issue_Resolved__c,
                   Follow_Up_Required__c,
                   Root_Cause__c,
                   Technician_Notes__c
            FROM Maintenance_Log__c
            WHERE Id = :result.maintenanceLogId
        ];

        System.assertEquals(
            'Temporary Repair',
            log.Maintenance_Type__c
        );
        System.assertEquals(
            TEST_PROBLEM_SUMMARY,
            log.Problem_Summary__c,
            'Temporary Repair Maintenance Log should preserve the Work Order Problem Summary.'
        );
        System.assertEquals(false, log.Issue_Resolved__c);
        System.assertEquals(true, log.Follow_Up_Required__c);
        System.assertEquals(null, log.Root_Cause__c);
        System.assert(
            log.Technician_Notes__c.contains(
                'Temporary Repair Applied: Yes'
            )
        );
    }

    @IsTest
    static void rejectsWorkOrderThatIsNotInProgress() {
        Account account = createAccount();
        Asset asset = createAsset(account.Id);
        Case c = createCase(account.Id);
        WorkOrder wo = createWorkOrder(
            account.Id,
            c.Id,
            asset.Id,
            'Assigned'
        );
        Part_Catalog__c part = createPart(true);

        Boolean threwException = false;

        Test.startTest();

        try {
            TechnicianRequestPartsController.submitPartsRequest(
                wo.Id,
                part.Id,
                1,
                'Replacement required.',
                'Inspected machine.',
                1.00,
                false
            );
        } catch (AuraHandledException e) {
            threwException = true;
        }

        Test.stopTest();

        System.assert(
            threwException,
            'A Work Order that is not In Progress must be rejected.'
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Work_Order_Part__c
                WHERE Work_Order__c = :wo.Id
            ]
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Maintenance_Log__c
                WHERE Work_Order__c = :wo.Id
            ]
        );

        WorkOrder unchangedWo = [
            SELECT Dispatch_Status__c, Labor_Hours__c
            FROM WorkOrder
            WHERE Id = :wo.Id
        ];

        System.assertEquals(
            'Assigned',
            unchangedWo.Dispatch_Status__c
        );
        System.assertEquals(1.25, unchangedWo.Labor_Hours__c);
    }

    @IsTest
    static void rejectsInvalidInputWithoutCreatingRecords() {
        Account account = createAccount();
        Asset asset = createAsset(account.Id);
        Case c = createCase(account.Id);
        WorkOrder wo = createWorkOrder(
            account.Id,
            c.Id,
            asset.Id,
            'In Progress'
        );
        Part_Catalog__c part = createPart(true);

        Boolean threwException = false;

        Test.startTest();

        try {
            TechnicianRequestPartsController.submitPartsRequest(
                wo.Id,
                part.Id,
                0,
                '',
                '',
                -1,
                false
            );
        } catch (AuraHandledException e) {
            threwException = true;
        }

        Test.stopTest();

        System.assert(
            threwException,
            'Invalid request data must be rejected.'
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Work_Order_Part__c
                WHERE Work_Order__c = :wo.Id
            ]
        );

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Maintenance_Log__c
                WHERE Work_Order__c = :wo.Id
            ]
        );
    }
}