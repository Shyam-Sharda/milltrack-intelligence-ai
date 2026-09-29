public with sharing class ManagerDispatchTechnicianController {
    private static final String STATUS_READY_TO_ASSIGN = 'Ready_to_Assign';
    private static final String STATUS_ASSIGNED = 'Assigned';
    private static final String STATUS_IN_PROGRESS = 'In Progress';
    private static final String CASE_STATUS_SCHEDULED = 'Scheduled';
    private static final String TECHNICIAN_ROLE = 'MillTrack_Technician';
    private static final Integer SCHEDULE_BUFFER_MINUTES = 30;
    // =========================================================
    // Dispatch Context
    // =========================================================
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
        context.suggestedTechnicianName =workOrder.Suggested_Technician__r != null ? workOrder.Suggested_Technician__r.Name : null;
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
            info.partName =part.Part_Catalog__r != null ? part.Part_Catalog__r.Name : part.Name;
            info.partNumber =part.Part_Catalog__r != null ? part.Part_Catalog__r.Part_Number__c : null;
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
            context.ineligibleReason = 'This Work Order is not Ready to Assign.';
            return context;
        }
        context.eligible = true;
        return context;
    }
    // =========================================================
    // Technician Availability Calendar
    // =========================================================
    @AuraEnabled(cacheable=true)
    public static TechnicianScheduleData getTechnicianSchedule(Id technicianId, Integer year, Integer month, Id excludedWorkOrderId) {
        if (technicianId == null) throw new AuraHandledException('Select a technician before viewing availability.');
        if (year == null || month == null || year < 1900 || year > 2200 || month < 1 || month > 12) {
            throw new AuraHandledException('A valid calendar year and month are required.');
        }
        List<User> technicians = [
            SELECT Id, Name
            FROM User
            WHERE Id = :technicianId
                AND IsActive = true
                AND UserRole.DeveloperName = :TECHNICIAN_ROLE
            LIMIT 1
        ];
        if (technicians.isEmpty()) throw new AuraHandledException('The selected user is not an active MillTrack technician.');
        Date monthStart = Date.newInstance(year, month, 1);
        Date nextMonthStart = monthStart.addMonths(1);
        Datetime monthStartDateTime = Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        Datetime nextMonthStartDateTime = Datetime.newInstance(nextMonthStart, Time.newInstance(0, 0, 0, 0));
        Set<String> activeStatuses = new Set<String>{STATUS_ASSIGNED, STATUS_IN_PROGRESS};
        TechnicianScheduleData result = new TechnicianScheduleData();
        result.technicianId = technicians[0].Id;
        result.technicianName = technicians[0].Name;
        result.year = year;
        result.month = month;
        result.monthStart = monthStart;
        result.monthEnd = nextMonthStart.addDays(-1);
        result.visits = new List<TechnicianScheduleVisit>();
        // Scheduled and in-progress visits come from Work Orders.
        List<WorkOrder> scheduledVisits = [
            SELECT Id, WorkOrderNumber, Subject, Dispatch_Status__c, Scheduled_Visit__c,
                AccountId, Account.Name,
                AssetId, Asset.Name, Asset.Manufacturer__c, Asset.Model__c,
                Suggested_Technician__c
            FROM WorkOrder
            WHERE Suggested_Technician__c = :technicianId
                AND Scheduled_Visit__c >= :monthStartDateTime
                AND Scheduled_Visit__c < :nextMonthStartDateTime
                AND Dispatch_Status__c IN :activeStatuses
            ORDER BY Scheduled_Visit__c ASC
        ];
        for (WorkOrder scheduledVisit : scheduledVisits) {
            if (excludedWorkOrderId != null && scheduledVisit.Id == excludedWorkOrderId) continue;
            TechnicianScheduleVisit visit = new TechnicianScheduleVisit();
            visit.workOrderId = scheduledVisit.Id;
            visit.workOrderNumber = scheduledVisit.WorkOrderNumber;
            visit.subject = scheduledVisit.Subject;
            visit.dispatchStatus = scheduledVisit.Dispatch_Status__c;
            visit.visitType = scheduledVisit.Dispatch_Status__c == STATUS_IN_PROGRESS ? 'In Progress' : 'Scheduled';
            visit.scheduledVisit = scheduledVisit.Scheduled_Visit__c;
            visit.visitDate = scheduledVisit.Scheduled_Visit__c != null ? scheduledVisit.Scheduled_Visit__c.date() : null;
            visit.blocksScheduling = true;
            visit.accountId = scheduledVisit.AccountId;
            visit.accountName = scheduledVisit.Account != null ? scheduledVisit.Account.Name : null;
            visit.assetId = scheduledVisit.AssetId;
            visit.assetName = scheduledVisit.Asset != null ? scheduledVisit.Asset.Name : null;
            if (scheduledVisit.Asset != null) {
                visit.machineLabel = buildMachineLabel(scheduledVisit.Asset.Manufacturer__c, scheduledVisit.Asset.Model__c, scheduledVisit.Asset.Name);
            }
            result.visits.add(visit);
        }
        // Completed historical repairs come from Maintenance Logs.
        List<Maintenance_Log__c> completedRepairs = [
            SELECT Id, Name, Maintenance_Date__c, Maintenance_Type__c, Summary__c, Issue_Resolved__c,
                Performed_By__c,
                Work_Order__c, Work_Order__r.WorkOrderNumber, Work_Order__r.Subject,
                Work_Order__r.AccountId, Work_Order__r.Account.Name,
                Asset__c, Asset__r.Name, Asset__r.Manufacturer__c, Asset__r.Model__c
            FROM Maintenance_Log__c
            WHERE Performed_By__c = :technicianId
                AND Maintenance_Date__c >= :monthStart
                AND Maintenance_Date__c < :nextMonthStart
                AND Issue_Resolved__c = true
            ORDER BY Maintenance_Date__c ASC, CreatedDate ASC
        ];
        for (Maintenance_Log__c completedRepair : completedRepairs) {
            TechnicianScheduleVisit visit = new TechnicianScheduleVisit();
            visit.maintenanceLogId = completedRepair.Id;
            visit.workOrderId = completedRepair.Work_Order__c;
            visit.workOrderNumber = completedRepair.Work_Order__r != null ? completedRepair.Work_Order__r.WorkOrderNumber : null;
            visit.subject = completedRepair.Work_Order__r != null ? completedRepair.Work_Order__r.Subject : completedRepair.Summary__c;
            visit.dispatchStatus = 'Completed';
            visit.visitType = 'Completed';
            visit.visitDate = completedRepair.Maintenance_Date__c;
            visit.scheduledVisit = null;
            visit.blocksScheduling = false;
            visit.accountId = completedRepair.Work_Order__r != null ? completedRepair.Work_Order__r.AccountId : null;
            visit.accountName = completedRepair.Work_Order__r != null && completedRepair.Work_Order__r.Account != null
                ? completedRepair.Work_Order__r.Account.Name
                : null;
            visit.assetId = completedRepair.Asset__c;
            visit.assetName = completedRepair.Asset__r != null ? completedRepair.Asset__r.Name : null;
            if (completedRepair.Asset__r != null) {
                visit.machineLabel = buildMachineLabel(completedRepair.Asset__r.Manufacturer__c, completedRepair.Asset__r.Model__c, completedRepair.Asset__r.Name);
            }
            result.visits.add(visit);
        }
        return result;
    }
    // =========================================================
    // Dispatch Technician
    // =========================================================
    @AuraEnabled
    public static DispatchResult dispatchTechnician(Id workOrderId, Id technicianId, Datetime scheduledVisit) {
        if (workOrderId == null) {
            throw new AuraHandledException('A Work Order is required.');
        }
        if (technicianId == null) {
            throw new AuraHandledException('Select a technician before dispatching the Work Order.');
        }
        if (scheduledVisit == null) {
            throw new AuraHandledException('Select a scheduled visit date and time.');
        }
        if (scheduledVisit < System.now()) {
            throw new AuraHandledException('The scheduled visit must be now or in the future.');
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
                throw new AuraHandledException('This Work Order is no longer Ready to Assign. Refresh the Manager Operations Center and try again.');
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
                throw new AuraHandledException('The selected user is not an active MillTrack technician.');
            }
            validateTechnicianAvailability(workOrderId, technicianId, scheduledVisit);
            Integer outstandingPartCount = [
                SELECT COUNT()
                FROM Work_Order_Part__c
                WHERE
                    Work_Order__c = :workOrderId
                    AND Order_Status__c IN ('Requested', 'Ordered', 'Shipped')
            ];
            if (outstandingPartCount > 0) {
                throw new AuraHandledException('This Work Order still has outstanding required parts and cannot be dispatched yet.');
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
            result.assetStatus =workOrder.Asset != null ? workOrder.Asset.Machine_Status__c : null;
            result.technicianId = technician.Id;
            result.technicianName = technician.Name;
            result.scheduledVisit = scheduledVisit;
            return result;
        } catch (Exception ex) {
            Database.rollback(savepoint);
            if (ex instanceof AuraHandledException) {
                throw ex;
            }
            throw new AuraHandledException('The technician could not be dispatched. ' + ex.getMessage());
        }
    }
    // =========================================================
    // Schedule Conflict Validation
    // =========================================================
    private static void validateTechnicianAvailability(Id workOrderId, Id technicianId, Datetime scheduledVisit) {
        Datetime bufferStart =
            scheduledVisit.addMinutes(-SCHEDULE_BUFFER_MINUTES);
        Datetime bufferEnd =
            scheduledVisit.addMinutes(SCHEDULE_BUFFER_MINUTES);
        Set<String> activeStatuses = new Set<String>{ STATUS_ASSIGNED, STATUS_IN_PROGRESS };
        List<WorkOrder> conflicts = [
            SELECT
                Id,
                WorkOrderNumber,
                Scheduled_Visit__c,
                Account.Name,
                Asset.Name
            FROM WorkOrder
            WHERE
                Suggested_Technician__c = :technicianId
                AND Id != :workOrderId
                AND Dispatch_Status__c IN :activeStatuses
                AND Scheduled_Visit__c >= :bufferStart
                AND Scheduled_Visit__c <= :bufferEnd
            ORDER BY Scheduled_Visit__c ASC
            LIMIT 1
        ];
        if (conflicts.isEmpty()) {
            return;
        }
        WorkOrder conflict = conflicts[0];
        String conflictTime =
            conflict.Scheduled_Visit__c != null
                ? conflict.Scheduled_Visit__c.format('MMM d, yyyy h:mm a')
                : 'the selected time';
        String conflictContext = '';
        if (conflict.Account != null) {
            conflictContext += ' for ' + conflict.Account.Name;
        }
        if (conflict.Asset != null) {
            conflictContext += ' (' + conflict.Asset.Name + ')';
        }
        throw new AuraHandledException(
            'Scheduling conflict: this technician already has ' +
            conflict.WorkOrderNumber +
            ' scheduled for ' +
            conflictTime +
            conflictContext +
            '. Choose a time more than 30 minutes before or after the existing visit.'
        );
    }
    // =========================================================
    // Helpers
    // =========================================================
    private static String buildMachineLabel(String manufacturer, String model, String fallbackName) {
        List<String> labelParts = new List<String>();
        if (!String.isBlank(manufacturer)) {
            labelParts.add(manufacturer.trim());
        }
        if (!String.isBlank(model)) {
            labelParts.add(model.trim());
        }
        if (!labelParts.isEmpty()) {
            return String.join(labelParts, ' ');
        }
        return fallbackName;
    }
    // =========================================================
    // Response Wrappers
    // =========================================================
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
    public class TechnicianScheduleData {
        @AuraEnabled public Id technicianId { get; set; }
        @AuraEnabled public String technicianName { get; set; }
        @AuraEnabled public Integer year { get; set; }
        @AuraEnabled public Integer month { get; set; }
        @AuraEnabled public Date monthStart { get; set; }
        @AuraEnabled public Date monthEnd { get; set; }
        @AuraEnabled public List<TechnicianScheduleVisit> visits { get; set; }
    }
    public class TechnicianScheduleVisit {
        @AuraEnabled public Id maintenanceLogId { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String visitType { get; set; }
        @AuraEnabled public Date visitDate { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }
        @AuraEnabled public Boolean blocksScheduling { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String machineLabel { get; set; }
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
