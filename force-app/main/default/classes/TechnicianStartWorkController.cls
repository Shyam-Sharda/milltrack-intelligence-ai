public with sharing class TechnicianStartWorkController {
    public class StartWorkResult {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderStatus;
        @AuraEnabled public String caseStatus;
        @AuraEnabled public Datetime workStartedDateTime;
    }

    @AuraEnabled
    public static StartWorkResult startWork(Id workOrderId) {
        if (workOrderId == null) throw new AuraHandledException('A Work Order is required.');

        Savepoint sp = Database.setSavepoint();

        try {
            WorkOrder wo = [SELECT Id, CaseId, Dispatch_Status__c, Work_Started_Date_Time__c FROM WorkOrder WHERE Id = :workOrderId LIMIT 1 FOR UPDATE];

            if (wo.Dispatch_Status__c != 'Assigned') throw new AuraHandledException('This Work Order cannot be started right now. It may already be in progress, completed, cancelled, or not assigned yet.');

            Datetime startedAt = System.now();

            wo.Dispatch_Status__c = 'In Progress';
            wo.Work_Started_Date_Time__c = startedAt;
            update wo;

            String caseStatus;

            if (wo.CaseId != null) {
                Case relatedCase = [SELECT Id, Status FROM Case WHERE Id = :wo.CaseId LIMIT 1 FOR UPDATE];
                relatedCase.Status = 'In Progress';
                update relatedCase;
                caseStatus = relatedCase.Status;
            }

            StartWorkResult result = new StartWorkResult();
            result.workOrderId = wo.Id;
            result.workOrderStatus = wo.Dispatch_Status__c;
            result.caseStatus = caseStatus;
            result.workStartedDateTime = startedAt;
            return result;

        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('We couldn\'t start this Work Order. Please try again or contact your Service Manager.');
        }
    }
}