public with sharing class ManagerDispatchTechnicianController {

    private static final String STATUS_READY_TO_ASSIGN = 'Ready_to_Assign';
    private static final String STATUS_ASSIGNED = 'Assigned';
    private static final String CASE_STATUS_SCHEDULED = 'Scheduled';
    private static final String TECHNICIAN_ROLE = 'MillTrack_Technician';

    @AuraEnabled(cacheable=true)
    public static DispatchContext getDispatchContext(Id workOrderId) {

        DispatchContext context = new DispatchContext();
        context.workOrderId = workOrderId;
        context.eligible = false;
        context.parts = new List<PartInfo>();
        context.technicians = new List<TechnicianOption>();

        if (workOrderId == null) {
            context.ineligibleReason = 'A Work Order is required.';
            return context;
        }

        List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Dispatch_Status__c,
                Priority,
                AccountId,
                Account.Name,
                AssetId,
                Asset.Name,
                Asset.Machine_Status__c,
                CaseId,
                Problem_Summary__c,
                Recommended_Fix_Summary__c,
                Suggested_Technician__c,
                Suggested_Technician__r.Name,
                Scheduled_Visit__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            context.ineligibleReason = 'The Work Order could not be found.';
            return context;
        }

        WorkOrder workOrder = workOrders[0];

        context.workOrderNumber = workOrder.WorkOrderNumber;
        context.dispatchStatus = workOrder.Dispatch_Status__c;
        context.priority = workOrder.Priority;
        context.accountId = workOrder.AccountId;
        context.accountName = workOrder.Account != null ? workOrder.Account.Name : null;
        context.assetId = workOrder.AssetId;
        context.assetName = workOrder.Asset != null ? workOrder.Asset.Name : null;
        context.assetStatus = workOrder.Asset != null
            ? workOrder.Asset.Machine_Status__c
            : null;
        context.caseId = workOrder.CaseId;
        context.problemSummary = workOrder.Problem_Summary__c;
        context.recommendedFixSummary = workOrder.Recommended_Fix_Summary__c;
        context.suggestedTechnicianId = workOrder.Suggested_Technician__c;
        context.suggestedTechnicianName =
            workOrder.Suggested_Technician__r != null
                ? workOrder.Suggested_Technician__r.Name
                : null;
        context.scheduledVisit = workOrder.Scheduled_Visit__c;

        for (Work_Order_Part__c part : [
            SELECT
                Id,
                Name,
                Part_Catalog__c,
                Part_Catalog__r.Name,
                Part_Catalog__r.Part_Number__c,
                Quantity__c,
                Order_Status__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrderId
            ORDER BY Part_Catalog__r.Name, Name
        ]) {
            PartInfo info = new PartInfo();
            info.id = part.Id;
            info.recordNumber = part.Name;
            info.catalogPartId = part.Part_Catalog__c;
            info.partName =
                part.Part_Catalog__r != null
                    ? part.Part_Catalog__r.Name
                    : part.Name;
            info.partNumber =
                part.Part_Catalog__r != null
                    ? part.Part_Catalog__r.Part_Number__c
                    : null;
            info.quantity = part.Quantity__c;
            info.status = part.Order_Status__c;

            context.parts.add(info);
        }

        for (User technician : [
            SELECT Id, Name
            FROM User
            WHERE
                IsActive = true
                AND UserRole.DeveloperName = :TECHNICIAN_ROLE
            ORDER BY Name
        ]) {
            TechnicianOption option = new TechnicianOption();
            option.id = technician.Id;
            option.name = technician.Name;

            context.technicians.add(option);
        }

        if (workOrder.Dispatch_Status__c != STATUS_READY_TO_ASSIGN) {
            context.ineligibleReason =
                'This Work Order is not Ready to Assign.';
            return context;
        }

        context.eligible = true;

        return context;
    }

    @AuraEnabled
    public static DispatchResult dispatchTechnician(
        Id workOrderId,
        Id technicianId,
        Datetime scheduledVisit
    ) {

        if (workOrderId == null) {
            throw new AuraHandledException(
                'A Work Order is required.'
            );
        }

        if (technicianId == null) {
            throw new AuraHandledException(
                'Select a technician before dispatching the Work Order.'
            );
        }

        if (scheduledVisit == null) {
            throw new AuraHandledException(
                'Select a scheduled visit date and time.'
            );
        }

        if (scheduledVisit < System.now()) {
            throw new AuraHandledException(
                'The scheduled visit must be now or in the future.'
            );
        }

        Savepoint savepoint = Database.setSavepoint();

        try {
            WorkOrder workOrder = [
                SELECT
                    Id,
                    WorkOrderNumber,
                    Dispatch_Status__c,
                    CaseId,
                    AssetId,
                    Asset.Machine_Status__c
                FROM WorkOrder
                WHERE Id = :workOrderId
                LIMIT 1
                FOR UPDATE
            ];

            if (workOrder.Dispatch_Status__c != STATUS_READY_TO_ASSIGN) {
                throw new AuraHandledException(
                    'This Work Order is no longer Ready to Assign. Refresh the Manager Operations Center and try again.'
                );
            }

            List<User> technicians = [
                SELECT Id, Name
                FROM User
                WHERE
                    Id = :technicianId
                    AND IsActive = true
                    AND UserRole.DeveloperName = :TECHNICIAN_ROLE
                LIMIT 1
            ];

            if (technicians.isEmpty()) {
                throw new AuraHandledException(
                    'The selected user is not an active MillTrack technician.'
                );
            }

            Integer outstandingPartCount = [
                SELECT COUNT()
                FROM Work_Order_Part__c
                WHERE
                    Work_Order__c = :workOrderId
                    AND Order_Status__c IN (
                        'Requested',
                        'Ordered',
                        'Shipped'
                    )
            ];

            if (outstandingPartCount > 0) {
                throw new AuraHandledException(
                    'This Work Order still has outstanding required parts and cannot be dispatched yet.'
                );
            }

            User technician = technicians[0];

            workOrder.Suggested_Technician__c = technician.Id;
            workOrder.OwnerId = technician.Id;
            workOrder.Scheduled_Visit__c = scheduledVisit;
            workOrder.Dispatch_Status__c = STATUS_ASSIGNED;

            update workOrder;

            String caseStatus;

            if (workOrder.CaseId != null) {
                Case relatedCase = [
                    SELECT Id, Status
                    FROM Case
                    WHERE Id = :workOrder.CaseId
                    LIMIT 1
                    FOR UPDATE
                ];

                relatedCase.Status = CASE_STATUS_SCHEDULED;
                update relatedCase;

                caseStatus = relatedCase.Status;
            }

            DispatchResult result = new DispatchResult();
            result.workOrderId = workOrder.Id;
            result.workOrderNumber = workOrder.WorkOrderNumber;
            result.workOrderStatus = workOrder.Dispatch_Status__c;
            result.caseStatus = caseStatus;
            result.assetStatus =
                workOrder.Asset != null
                    ? workOrder.Asset.Machine_Status__c
                    : null;
            result.technicianId = technician.Id;
            result.technicianName = technician.Name;
            result.scheduledVisit = scheduledVisit;

            return result;

        } catch (Exception ex) {
            Database.rollback(savepoint);

            if (ex instanceof AuraHandledException) {
                throw ex;
            }

            throw new AuraHandledException(
                'The technician could not be dispatched. ' +
                ex.getMessage()
            );
        }
    }

    public class DispatchContext {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String priority { get; set; }

        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }

        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String assetStatus { get; set; }

        @AuraEnabled public Id caseId { get; set; }

        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String recommendedFixSummary { get; set; }

        @AuraEnabled public Id suggestedTechnicianId { get; set; }
        @AuraEnabled public String suggestedTechnicianName { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }

        @AuraEnabled public Boolean eligible { get; set; }
        @AuraEnabled public String ineligibleReason { get; set; }

        @AuraEnabled public List<PartInfo> parts { get; set; }
        @AuraEnabled public List<TechnicianOption> technicians { get; set; }
    }

    public class TechnicianOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
    }

    public class PartInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String recordNumber { get; set; }
        @AuraEnabled public Id catalogPartId { get; set; }
        @AuraEnabled public String partName { get; set; }
        @AuraEnabled public String partNumber { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public String status { get; set; }
    }

    public class DispatchResult {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }

        @AuraEnabled public String workOrderStatus { get; set; }
        @AuraEnabled public String caseStatus { get; set; }
        @AuraEnabled public String assetStatus { get; set; }

        @AuraEnabled public Id technicianId { get; set; }
        @AuraEnabled public String technicianName { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }
    }
}