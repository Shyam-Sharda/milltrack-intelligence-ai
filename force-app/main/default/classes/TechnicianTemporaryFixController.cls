public with sharing class TechnicianTemporaryFixController {

    private static final String REQUIRED_WORK_ORDER_STATUS = 'In Progress';
    private static final String TEMPORARY_FIX_STATUS = 'Temporary Fix';
    private static final String CASE_FOLLOW_UP_STATUS = 'Follow-Up Required';
    private static final String ASSET_TEMPORARY_FIX_STATUS = 'Temporary Fix Applied';
    private static final String MAINTENANCE_TYPE = 'Temporary Repair';
    private static final String SERVICE_MANAGER_QUEUE_DEVELOPER_NAME = 'Service_Manager_Queue';
    private static final String NOTIFICATION_TYPE_DEVELOPER_NAME = 'Temporary_Repair_FollowUp';

    public class TemporaryFixContext {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Decimal currentLaborHours { get; set; }
    }

    public class SubmitResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Id maintenanceLogId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String warningMessage { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static TemporaryFixContext getTemporaryFixContext(Id workOrderId) {
        if (workOrderId == null) {
            throw handledException('A Work Order is required.');
        }

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, AssetId, Asset.Name,
                   Asset.Manufacturer__c, Asset.Model__c, Labor_Hours__c,
                   Dispatch_Status__c, OwnerId
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            throw handledException('The Work Order could not be found or is no longer accessible.');
        }

        WorkOrder workOrder = workOrders[0];

        validateEligibility(workOrder);
        getServiceManagerQueueId();

        TemporaryFixContext context = new TemporaryFixContext();
        context.workOrderId = workOrder.Id;
        context.workOrderNumber = workOrder.WorkOrderNumber;
        context.subject = workOrder.Subject;
        context.assetId = workOrder.AssetId;
        context.assetName = workOrder.AssetId != null ? workOrder.Asset.Name : null;
        context.manufacturer = workOrder.AssetId != null ? workOrder.Asset.Manufacturer__c : null;
        context.model = workOrder.AssetId != null ? workOrder.Asset.Model__c : null;
        context.currentLaborHours = workOrder.Labor_Hours__c == null ? 0 : workOrder.Labor_Hours__c;

        return context;
    }

    @AuraEnabled
    public static SubmitResult submitTemporaryFix(Id workOrderId, String visitSummary, Decimal laborHours) {
        if (workOrderId == null) {
            throw handledException('A Work Order is required.');
        }

        String cleanedSummary = String.isBlank(visitSummary) ? null : visitSummary.trim();

        if (String.isBlank(cleanedSummary)) {
            throw handledException('Visit Summary is required.');
        }

        if (laborHours == null || laborHours <= 0) {
            throw handledException('Labor Hours must be greater than 0.');
        }

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, AssetId, CaseId, OwnerId,
                   Dispatch_Status__c, Labor_Hours__c, Technician_Notes__c,
                   Service_Manager__c, Scheduled_Visit__c, Suggested_Technician__c,
                   Problem_Summary__c, Recommended_Fix_Summary__c, Recommended_Tools__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
            FOR UPDATE
        ];

        if (workOrders.isEmpty()) {
            throw handledException('The Work Order could not be found or is no longer accessible.');
        }

        WorkOrder workOrder = workOrders[0];

        validateEligibility(workOrder);

        if (workOrder.AssetId == null) {
            throw handledException('This Work Order is not linked to a machine. A temporary repair cannot be recorded.');
        }

        Id serviceManagerQueueId = getServiceManagerQueueId();

        Decimal existingLabor = workOrder.Labor_Hours__c == null ? 0 : workOrder.Labor_Hours__c;
        Decimal updatedLabor = existingLabor + laborHours;

        String temporaryFixNote = buildTemporaryFixNote(cleanedSummary, laborHours);
        String updatedTechnicianNotes = appendTechnicianNotes(workOrder.Technician_Notes__c, temporaryFixNote);

        Savepoint savepoint = Database.setSavepoint();

        try {
            Maintenance_Log__c maintenanceLog = new Maintenance_Log__c();
            maintenanceLog.Asset__c = workOrder.AssetId;
            maintenanceLog.Work_Order__c = workOrder.Id;
            maintenanceLog.Maintenance_Date__c = Date.today();
            maintenanceLog.Maintenance_Type__c = MAINTENANCE_TYPE;
            maintenanceLog.Problem_Summary__c = workOrder.Problem_Summary__c;
            maintenanceLog.Recommended_Fix_Snapshot__c = workOrder.Recommended_Fix_Summary__c;
            maintenanceLog.Tools_To_Bring_Snapshot__c = workOrder.Recommended_Tools__c;
            maintenanceLog.Summary__c = cleanedSummary;
            maintenanceLog.Technician_Notes__c = temporaryFixNote;
            maintenanceLog.Labor_Hours__c = laborHours;
            maintenanceLog.Issue_Resolved__c = false;
            maintenanceLog.Follow_Up_Required__c = true;
            maintenanceLog.Performed_By__c = UserInfo.getUserId();
            maintenanceLog.OwnerId = UserInfo.getUserId();

            Database.insert(maintenanceLog, AccessLevel.SYSTEM_MODE);

            Asset assetUpdate = new Asset(
                Id = workOrder.AssetId,
                Machine_Status__c = ASSET_TEMPORARY_FIX_STATUS,
                Last_Service_Date__c = Date.today()
            );

            Database.update(assetUpdate, AccessLevel.SYSTEM_MODE);

            WorkOrder workOrderUpdate = new WorkOrder(
                Id = workOrder.Id,
                Dispatch_Status__c = TEMPORARY_FIX_STATUS,
                OwnerId = serviceManagerQueueId,
                Scheduled_Visit__c = null,
                Suggested_Technician__c = null,
                Labor_Hours__c = updatedLabor,
                Technician_Notes__c = updatedTechnicianNotes
            );

            Database.update(workOrderUpdate, AccessLevel.SYSTEM_MODE);

            if (workOrder.CaseId != null) {
                Case caseUpdate = new Case(
                    Id = workOrder.CaseId,
                    Status = CASE_FOLLOW_UP_STATUS
                );

                Database.update(caseUpdate, AccessLevel.SYSTEM_MODE);
            }

            SubmitResult result = new SubmitResult();
            result.success = true;
            result.maintenanceLogId = maintenanceLog.Id;
            result.workOrderNumber = workOrder.WorkOrderNumber;
            result.message = 'Temporary repair recorded successfully. The Work Order has been returned for manager follow-up.';

            result.warningMessage = sendManagerNotification(
                workOrder.Service_Manager__c,
                workOrder.Id,
                workOrder.WorkOrderNumber,
                cleanedSummary
            );

            return result;

        } catch (Exception e) {
            Database.rollback(savepoint);

            if (e instanceof AuraHandledException) {
                throw e;
            }

            throw handledException('Unable to record the temporary repair: ' + e.getMessage());
        }
    }

    private static void validateEligibility(WorkOrder workOrder) {
        if (workOrder.Dispatch_Status__c != REQUIRED_WORK_ORDER_STATUS) {
            throw handledException(
                'A temporary repair can only be recorded while the Work Order is In Progress. Current status: ' +
                String.valueOf(workOrder.Dispatch_Status__c) + '.'
            );
        }

        if (workOrder.OwnerId != UserInfo.getUserId()) {
            throw handledException('Only the technician currently assigned to this Work Order can record a temporary repair.');
        }
    }

    private static Id getServiceManagerQueueId() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = :SERVICE_MANAGER_QUEUE_DEVELOPER_NAME
            LIMIT 1
        ];

        if (queues.isEmpty()) {
            throw handledException(
                'The Service Manager Queue could not be found. No repair information was submitted. Contact your Salesforce administrator.'
            );
        }

        return queues[0].Id;
    }

    private static String buildTemporaryFixNote(String visitSummary, Decimal laborHours) {
        return 'TEMPORARY REPAIR / FOLLOW-UP\n\n' +
               'Visit Summary:\n' +
               visitSummary +
               '\n\nLabor Hours:\n' +
               String.valueOf(laborHours);
    }

    private static String appendTechnicianNotes(String existingNotes, String newNote) {
        if (String.isBlank(existingNotes)) {
            return newNote;
        }

        return existingNotes + '\n\n' + newNote;
    }

    private static String sendManagerNotification(
        Id serviceManagerId,
        Id workOrderId,
        String workOrderNumber,
        String visitSummary
    ) {
        if (serviceManagerId == null) {
            return 'The temporary repair was recorded, but no individual Service Manager is assigned, so a direct notification could not be sent.';
        }

        try {
            List<CustomNotificationType> notificationTypes = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_TYPE_DEVELOPER_NAME
                LIMIT 1
            ];

            if (notificationTypes.isEmpty()) {
                return 'The temporary repair was recorded, but the Service Manager notification type could not be found.';
            }

            String technicianName = [
                SELECT Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ].Name;

            String notificationSummary = visitSummary;

            if (notificationSummary != null && notificationSummary.length() > 500) {
                notificationSummary = notificationSummary.substring(0, 497) + '...';
            }

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notificationTypes[0].Id);
            notification.setTitle('Temporary Repair Follow-Up - Work Order ' + workOrderNumber);
            notification.setBody(
                technicianName +
                ' recorded a temporary repair for Work Order ' +
                workOrderNumber +
                '.\n\nVisit Summary:\n' +
                notificationSummary +
                '\n\nThe Work Order has been returned to manager coordination for follow-up.'
            );
            notification.setTargetId(workOrderId);
            notification.send(new Set<String>{ String.valueOf(serviceManagerId) });

            return null;

        } catch (Exception e) {
            return 'The temporary repair was recorded successfully, but the Service Manager notification could not be sent.';
        }
    }

    private static AuraHandledException handledException(String message) {
        AuraHandledException exceptionValue = new AuraHandledException(message);
        exceptionValue.setMessage(message);
        return exceptionValue;
    }
}