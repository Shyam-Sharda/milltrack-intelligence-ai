/**
 * Supplies customer-safe Maintenance Log history for an Asset displayed in the MillTrack Experience Cloud portal.
 */
public with sharing class CustomerAssetServiceHistoryController {
    private static final Integer MAX_RECORDS = 50;

    @AuraEnabled(cacheable=true)
    public static List<ServiceHistoryEntry> getServiceHistory(Id assetId) {
        if (assetId == null) {
            throw new AuraHandledException('An Asset ID is required.');
        }

        List<Maintenance_Log__c> maintenanceLogs = [
            SELECT
                Id,
                Name,
                Maintenance_Date__c,
                Maintenance_Type__c,
                Summary__c,
                Root_Cause__c,
                Parts_Used__c,
                Labor_Hours__c,
                Work_Order__c,
                Work_Order__r.WorkOrderNumber,
                Issue_Resolved__c,
                Follow_Up_Required__c
            FROM Maintenance_Log__c
            WHERE Asset__c = :assetId
            WITH USER_MODE
            ORDER BY Maintenance_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :MAX_RECORDS
        ];

        List<ServiceHistoryEntry> serviceHistory = new List<ServiceHistoryEntry>();

        for (Maintenance_Log__c maintenanceLog : maintenanceLogs) {
            serviceHistory.add(new ServiceHistoryEntry(maintenanceLog));
        }

        return serviceHistory;
    }

    public class ServiceHistoryEntry {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String maintenanceNumber { get; set; }
        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public String maintenanceType { get; set; }
        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public String rootCause { get; set; }
        @AuraEnabled public String partsUsed { get; set; }
        @AuraEnabled public Decimal laborHours { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public Boolean issueResolved { get; set; }
        @AuraEnabled public Boolean followUpRequired { get; set; }
        @AuraEnabled public String status { get; set; }

        public ServiceHistoryEntry(Maintenance_Log__c maintenanceLog) {
            id = maintenanceLog.Id;
            maintenanceNumber = maintenanceLog.Name;
            maintenanceDate = maintenanceLog.Maintenance_Date__c;
            maintenanceType = maintenanceLog.Maintenance_Type__c;
            summary = maintenanceLog.Summary__c;
            rootCause = maintenanceLog.Root_Cause__c;
            partsUsed = maintenanceLog.Parts_Used__c;
            laborHours = maintenanceLog.Labor_Hours__c;
            workOrderId = maintenanceLog.Work_Order__c;
            workOrderNumber = maintenanceLog.Work_Order__r == null ? null : maintenanceLog.Work_Order__r.WorkOrderNumber;
            issueResolved = maintenanceLog.Issue_Resolved__c;
            followUpRequired = maintenanceLog.Follow_Up_Required__c;
            status = determineStatus(issueResolved, followUpRequired);
        }
    }

    private static String determineStatus(Boolean issueResolved, Boolean followUpRequired) {
        if (followUpRequired == true) {
            return 'Follow-up Required';
        }

        if (issueResolved == true) {
            return 'Resolved';
        }

        return 'Completed';
    }
}