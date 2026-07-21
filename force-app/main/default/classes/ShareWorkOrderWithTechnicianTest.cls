@IsTest
private class ShareWorkOrderWithTechnicianTest {

    @IsTest
    static void createsShareForTechnician() {
        User tech = createUser('tech1');
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        WorkOrder wo = new WorkOrder(
            Subject = 'Test Work Order',
            AccountId = acct.Id,
            Suggested_Technician__c = tech.Id
        );
        insert wo;

        ShareWorkOrderWithTechnician.Request req = new ShareWorkOrderWithTechnician.Request();
        req.workOrderId = wo.Id;
        req.technicianId = tech.Id;

        Test.startTest();
        ShareWorkOrderWithTechnician.shareWorkOrders(
            new List<ShareWorkOrderWithTechnician.Request>{ req }
        );
        Test.stopTest();

        List<WorkOrderShare> shares = [
            SELECT Id, ParentId, UserOrGroupId, AccessLevel
            FROM WorkOrderShare
            WHERE ParentId = :wo.Id
            AND UserOrGroupId = :tech.Id
        ];

        System.assertEquals(1, shares.size(), 'Technician should receive one Work Order share.');
        System.assertEquals('Edit', shares[0].AccessLevel, 'Technician should receive Edit access.');
    }

    @IsTest
    static void preventsDuplicateShares() {
        User tech = createUser('tech2');
        Account acct = new Account(Name = 'Duplicate Test Account');
        insert acct;

        WorkOrder wo = new WorkOrder(
            Subject = 'Duplicate Share Test',
            AccountId = acct.Id,
            Suggested_Technician__c = tech.Id
        );
        insert wo;

        ShareWorkOrderWithTechnician.Request req = new ShareWorkOrderWithTechnician.Request();
        req.workOrderId = wo.Id;
        req.technicianId = tech.Id;

        Test.startTest();
        ShareWorkOrderWithTechnician.shareWorkOrders(
            new List<ShareWorkOrderWithTechnician.Request>{ req }
        );
        ShareWorkOrderWithTechnician.shareWorkOrders(
            new List<ShareWorkOrderWithTechnician.Request>{ req }
        );
        Test.stopTest();

        List<WorkOrderShare> shares = [
            SELECT Id
            FROM WorkOrderShare
            WHERE ParentId = :wo.Id
            AND UserOrGroupId = :tech.Id
        ];

        System.assertEquals(1, shares.size(), 'Duplicate shares should not be created.');
    }

    @IsTest
    static void removesOldTechnicianShareOnReassignment() {
        User oldTech = createUser('oldtech');
        User newTech = createUser('newtech');

        Account acct = new Account(Name = 'Reassignment Test Account');
        insert acct;

        WorkOrder wo = new WorkOrder(
            Subject = 'Reassignment Test',
            AccountId = acct.Id,
            Suggested_Technician__c = oldTech.Id
        );
        insert wo;

        ShareWorkOrderWithTechnician.Request firstReq = new ShareWorkOrderWithTechnician.Request();
        firstReq.workOrderId = wo.Id;
        firstReq.technicianId = oldTech.Id;

        ShareWorkOrderWithTechnician.shareWorkOrders(
            new List<ShareWorkOrderWithTechnician.Request>{ firstReq }
        );

        ShareWorkOrderWithTechnician.Request secondReq = new ShareWorkOrderWithTechnician.Request();
        secondReq.workOrderId = wo.Id;
        secondReq.technicianId = newTech.Id;
        secondReq.oldTechnicianId = oldTech.Id;

        Test.startTest();
        ShareWorkOrderWithTechnician.shareWorkOrders(
            new List<ShareWorkOrderWithTechnician.Request>{ secondReq }
        );
        Test.stopTest();

        List<WorkOrderShare> oldShares = [
            SELECT Id
            FROM WorkOrderShare
            WHERE ParentId = :wo.Id
            AND UserOrGroupId = :oldTech.Id
        ];

        List<WorkOrderShare> newShares = [
            SELECT Id, AccessLevel
            FROM WorkOrderShare
            WHERE ParentId = :wo.Id
            AND UserOrGroupId = :newTech.Id
        ];

        System.assertEquals(0, oldShares.size(), 'Old technician share should be removed.');
        System.assertEquals(1, newShares.size(), 'New technician share should be created.');
        System.assertEquals('Edit', newShares[0].AccessLevel, 'New technician should receive Edit access.');
    }

    @IsTest
    static void skipsWhenNoTechnicianProvided() {
        Account acct = new Account(Name = 'No Technician Test Account');
        insert acct;

        WorkOrder wo = new WorkOrder(
            Subject = 'No Technician Test',
            AccountId = acct.Id
        );
        insert wo;

        ShareWorkOrderWithTechnician.Request req = new ShareWorkOrderWithTechnician.Request();
        req.workOrderId = wo.Id;
        req.technicianId = null;

        Test.startTest();
        List<ShareWorkOrderWithTechnician.Result> results =
            ShareWorkOrderWithTechnician.shareWorkOrders(
                new List<ShareWorkOrderWithTechnician.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'A result should still be returned.');
        System.assertEquals('Skipped: no technician assigned.', results[0].statusMessage);
    }

    private static User createUser(String aliasSeed) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        String unique = String.valueOf(System.currentTimeMillis()) + aliasSeed;

        User u = new User(
            FirstName = 'Test',
            LastName = aliasSeed,
            Alias = aliasSeed.left(8),
            Email = unique + '@example.com',
            Username = unique + '@example.com',
            CommunityNickname = unique.left(30),
            TimeZoneSidKey = 'America/Vancouver',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );

        insert u;
        return u;
    }
}