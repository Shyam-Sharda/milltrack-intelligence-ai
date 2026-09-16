@IsTest
private class TechnicianStartWorkControllerTest {

    private static Account createAccount() {
        Account a = new Account(Name = 'MillTrack Start Work Test'); insert a; return a;
    }

    private static Case createCase(Id accountId) {
        Case c = new Case(AccountId = accountId, Subject = 'Milling machine requires service', Status = 'Scheduled', Origin = 'Web', Work_Order_Proposal_Created__c = true); insert c; return c;
    }

    private static WorkOrder createWorkOrder(Id accountId, Id caseId, String status) {
        WorkOrder wo = new WorkOrder(AccountId = accountId, CaseId = caseId, Subject = 'Start Work Test', Dispatch_Status__c = status); insert wo; return wo;
    }

    @IsTest
    static void startWorkSuccess() {
        Account a = createAccount(); Case c = createCase(a.Id); WorkOrder wo = createWorkOrder(a.Id, c.Id, 'Assigned');
        Id originalOwnerId = [SELECT OwnerId FROM WorkOrder WHERE Id = :wo.Id].OwnerId;

        Test.startTest();
        TechnicianStartWorkController.StartWorkResult result = TechnicianStartWorkController.startWork(wo.Id);
        Test.stopTest();

        WorkOrder updatedWo = [SELECT Dispatch_Status__c, Work_Started_Date_Time__c, OwnerId FROM WorkOrder WHERE Id = :wo.Id];
        Case updatedCase = [SELECT Status FROM Case WHERE Id = :c.Id];

        System.assertEquals('In Progress', updatedWo.Dispatch_Status__c);
        System.assertNotEquals(null, updatedWo.Work_Started_Date_Time__c);
        System.assertEquals(originalOwnerId, updatedWo.OwnerId, 'Starting work must not change ownership.');
        System.assertEquals('In Progress', updatedCase.Status);
        System.assertEquals(wo.Id, result.workOrderId);
        System.assertEquals('In Progress', result.workOrderStatus);
        System.assertEquals('In Progress', result.caseStatus);
        System.assertEquals(updatedWo.Work_Started_Date_Time__c, result.workStartedDateTime);
    }

    @IsTest
    static void rejectsNonAssignedWorkOrder() {
        Account a = createAccount(); Case c = createCase(a.Id); WorkOrder wo = createWorkOrder(a.Id, c.Id, 'In Progress');
        Boolean threwException = false;

        Test.startTest();
        try { TechnicianStartWorkController.startWork(wo.Id); } catch (AuraHandledException e) { threwException = true; }
        Test.stopTest();

        WorkOrder unchangedWo = [SELECT Dispatch_Status__c, Work_Started_Date_Time__c FROM WorkOrder WHERE Id = :wo.Id];
        Case unchangedCase = [SELECT Status FROM Case WHERE Id = :c.Id];

        System.assert(threwException, 'A non-Assigned Work Order must be rejected.');
        System.assertEquals('In Progress', unchangedWo.Dispatch_Status__c);
        System.assertEquals(null, unchangedWo.Work_Started_Date_Time__c);
        System.assertEquals('Scheduled', unchangedCase.Status);
    }

    @IsTest
    static void rejectsNullWorkOrderId() {
        Boolean threwException = false;

        Test.startTest();
        try { TechnicianStartWorkController.startWork(null); } catch (AuraHandledException e) { threwException = true; }
        Test.stopTest();

        System.assert(threwException, 'A null Work Order Id must be rejected.');
    }

    @IsTest
    static void startsWorkOrderWithoutCase() {
        Account a = createAccount(); WorkOrder wo = createWorkOrder(a.Id, null, 'Assigned');

        Test.startTest();
        TechnicianStartWorkController.StartWorkResult result = TechnicianStartWorkController.startWork(wo.Id);
        Test.stopTest();

        WorkOrder updatedWo = [SELECT Dispatch_Status__c, Work_Started_Date_Time__c FROM WorkOrder WHERE Id = :wo.Id];

        System.assertEquals('In Progress', updatedWo.Dispatch_Status__c);
        System.assertNotEquals(null, updatedWo.Work_Started_Date_Time__c);
        System.assertEquals(null, result.caseStatus);
    }
}