public with sharing class ManagerServiceCalendarController {

    private static final Integer WORK_ORDER_LIMIT = 500;
    private static final Integer MAINTENANCE_LOG_LIMIT = 500;
    private static final String STATUS_ASSIGNED = 'Assigned';
    private static final String STATUS_IN_PROGRESS = 'In Progress';


    // =========================================================
    // Calendar Data
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static CalendarData getCalendarData(Integer year, Integer month) {
        validateMonth(year, month);

        Date monthStart = Date.newInstance(year, month, 1);
        Date nextMonthStart = monthStart.addMonths(1);
        Datetime monthStartDateTime = Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        Datetime nextMonthStartDateTime = Datetime.newInstance(nextMonthStart, Time.newInstance(0, 0, 0, 0));

        CalendarData result = new CalendarData();
        result.year = year;
        result.month = month;
        result.monthStart = monthStart;
        result.monthEnd = nextMonthStart.addDays(-1);
        result.events = new List<CalendarEventDTO>();

        /*
         * Maintenance Logs are authoritative for service work that
         * actually happened in the field.
         *
         * This is especially important for Temporary Fix and Request Parts
         * because those lifecycle actions may clear Scheduled_Visit__c when
         * the Work Order is handed back to manager control.
         */
        result.events.addAll(getHistoricalServiceEvents(monthStart, nextMonthStart));

        /*
         * Work Orders remain authoritative for visits that are currently
         * scheduled or actively in progress.
         */
        result.events.addAll(getScheduledServiceEvents(monthStartDateTime, nextMonthStartDateTime));

        result.events.sort();
        calculateCounts(result);

        return result;
    }


    // =========================================================
    // Scheduled / Current Work Order Events
    // =========================================================

    private static List<CalendarEventDTO> getScheduledServiceEvents(Datetime monthStart, Datetime nextMonthStart) {
        List<CalendarEventDTO> events = new List<CalendarEventDTO>();
        Set<String> scheduledStatuses = new Set<String>{STATUS_ASSIGNED, STATUS_IN_PROGRESS};

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, Priority, Status, Dispatch_Status__c, Scheduled_Visit__c,
                Work_Started_Date_Time__c, Problem_Summary__c, Recommended_Fix_Summary__c,
                AccountId, Account.Name,
                AssetId, Asset.Name, Asset.Manufacturer__c, Asset.Model__c, Asset.Serial_Number__c,
                Suggested_Technician__c, Suggested_Technician__r.Name,
                OwnerId, Owner.Name,
                CaseId, Case.CaseNumber, Case.Subject
            FROM WorkOrder
            WHERE Scheduled_Visit__c >= :monthStart
                AND Scheduled_Visit__c < :nextMonthStart
                AND Dispatch_Status__c IN :scheduledStatuses
            WITH USER_MODE
            ORDER BY Scheduled_Visit__c ASC
            LIMIT :WORK_ORDER_LIMIT
        ];

        for (WorkOrder workOrderRecord : workOrders) events.add(buildScheduledEvent(workOrderRecord));

        return events;
    }


    private static CalendarEventDTO buildScheduledEvent(WorkOrder workOrderRecord) {
        CalendarEventDTO eventRecord = new CalendarEventDTO();

        eventRecord.eventId = workOrderRecord.Id;
        eventRecord.eventKey = 'WO-' + String.valueOf(workOrderRecord.Id);
        eventRecord.sourceType = 'WORK_ORDER';
        eventRecord.workOrderId = workOrderRecord.Id;
        eventRecord.workOrderNumber = workOrderRecord.WorkOrderNumber;
        eventRecord.eventDateTime = workOrderRecord.Scheduled_Visit__c;

        if (workOrderRecord.Scheduled_Visit__c != null) eventRecord.eventDate = workOrderRecord.Scheduled_Visit__c.date();

        eventRecord.subject = safeText(workOrderRecord.Subject);
        eventRecord.priority = safeText(workOrderRecord.Priority);
        eventRecord.dispatchStatus = safeText(workOrderRecord.Dispatch_Status__c);
        eventRecord.problemSummary = safeText(workOrderRecord.Problem_Summary__c);
        eventRecord.recommendedFixSummary = safeText(workOrderRecord.Recommended_Fix_Summary__c);

        eventRecord.accountId = workOrderRecord.AccountId;
        eventRecord.accountName = workOrderRecord.Account == null ? null : workOrderRecord.Account.Name;

        eventRecord.assetId = workOrderRecord.AssetId;

        if (workOrderRecord.Asset != null) {
            eventRecord.assetName = workOrderRecord.Asset.Name;
            eventRecord.manufacturer = workOrderRecord.Asset.Manufacturer__c;
            eventRecord.model = workOrderRecord.Asset.Model__c;
            eventRecord.serialNumber = workOrderRecord.Asset.Serial_Number__c;
            eventRecord.machineLabel = buildMachineLabel(workOrderRecord.Asset.Manufacturer__c, workOrderRecord.Asset.Model__c);
        }

        eventRecord.caseId = workOrderRecord.CaseId;

        if (workOrderRecord.Case != null) {
            eventRecord.caseNumber = workOrderRecord.Case.CaseNumber;
            eventRecord.caseSubject = workOrderRecord.Case.Subject;
        }

        eventRecord.technicianId = workOrderRecord.Suggested_Technician__c;
        eventRecord.technicianName = workOrderRecord.Suggested_Technician__r == null ? null : workOrderRecord.Suggested_Technician__r.Name;

        // Suggested Technician is preferred, but Owner provides a useful fallback.
        if (String.isBlank(eventRecord.technicianName) && workOrderRecord.Owner != null) eventRecord.technicianName = workOrderRecord.Owner.Name;

        eventRecord.isScheduledEvent = true;
        eventRecord.isHistoricalEvent = false;
        eventRecord.isResolved = false;
        eventRecord.followUpRequired = false;
        eventRecord.temporaryRepair = false;

        if (workOrderRecord.Dispatch_Status__c == STATUS_IN_PROGRESS) {
            eventRecord.outcomeKey = 'IN_PROGRESS';
            eventRecord.outcomeLabel = 'In Progress';
        } else {
            eventRecord.outcomeKey = 'SCHEDULED';
            eventRecord.outcomeLabel = 'Scheduled Visit';
        }

        eventRecord.isPastDue =
            workOrderRecord.Dispatch_Status__c == STATUS_ASSIGNED
            && workOrderRecord.Scheduled_Visit__c != null
            && workOrderRecord.Scheduled_Visit__c < System.now();

        if (eventRecord.isPastDue) {
            eventRecord.outcomeKey = 'PAST_DUE';
            eventRecord.outcomeLabel = 'Past Scheduled Visit';
        }

        return eventRecord;
    }


    // =========================================================
    // Historical Maintenance Log Events
    // =========================================================

    private static List<CalendarEventDTO> getHistoricalServiceEvents(Date monthStart, Date nextMonthStart) {
        List<CalendarEventDTO> events = new List<CalendarEventDTO>();

        List<Maintenance_Log__c> maintenanceLogs = [
            SELECT Id, Name, Maintenance_Date__c, Maintenance_Type__c, Problem_Summary__c, Summary__c,
                Root_Cause__c, Parts_Used__c, Technician_Notes__c, Issue_Resolved__c, Follow_Up_Required__c,
                Performed_By__c, Performed_By__r.Name, Labor_Hours__c, CreatedDate,
                Asset__c, Asset__r.Name, Asset__r.Manufacturer__c, Asset__r.Model__c, Asset__r.Serial_Number__c,
                Work_Order__c, Work_Order__r.WorkOrderNumber, Work_Order__r.Subject, Work_Order__r.Priority,
                Work_Order__r.Dispatch_Status__c, Work_Order__r.AccountId, Work_Order__r.Account.Name,
                Work_Order__r.CaseId, Work_Order__r.Case.CaseNumber, Work_Order__r.Case.Subject,
                Work_Order__r.Suggested_Technician__c, Work_Order__r.Suggested_Technician__r.Name,
                Work_Order__r.Work_Started_Date_Time__c, Work_Order__r.Work_Ended_Date_Time__c
            FROM Maintenance_Log__c
            WHERE Maintenance_Date__c >= :monthStart
                AND Maintenance_Date__c < :nextMonthStart
            WITH USER_MODE
            ORDER BY Maintenance_Date__c DESC, CreatedDate DESC
            LIMIT :MAINTENANCE_LOG_LIMIT
        ];

        for (Maintenance_Log__c logRecord : maintenanceLogs) events.add(buildHistoricalEvent(logRecord));

        return events;
    }


    private static CalendarEventDTO buildHistoricalEvent(Maintenance_Log__c logRecord) {
        CalendarEventDTO eventRecord = new CalendarEventDTO();

        eventRecord.eventId = logRecord.Id;
        eventRecord.eventKey = 'ML-' + String.valueOf(logRecord.Id);
        eventRecord.sourceType = 'MAINTENANCE_LOG';
        eventRecord.maintenanceLogId = logRecord.Id;
        eventRecord.maintenanceLogName = logRecord.Name;
        eventRecord.eventDate = logRecord.Maintenance_Date__c;

        /*
         * Maintenance_Date__c is Date-only.
         * CreatedDate gives us a useful display timestamp for the visit event.
         */
        eventRecord.eventDateTime = logRecord.CreatedDate;

        eventRecord.maintenanceType = safeText(logRecord.Maintenance_Type__c);
        eventRecord.problemSummary = safeText(logRecord.Problem_Summary__c);
        eventRecord.repairSummary = safeText(logRecord.Summary__c);
        eventRecord.rootCause = safeText(logRecord.Root_Cause__c);
        eventRecord.partsUsed = safeText(logRecord.Parts_Used__c);
        eventRecord.technicianNotes = safeText(logRecord.Technician_Notes__c);
        eventRecord.laborHours = logRecord.Labor_Hours__c;

        eventRecord.isResolved = logRecord.Issue_Resolved__c == true;
        eventRecord.followUpRequired = logRecord.Follow_Up_Required__c == true;
        eventRecord.temporaryRepair = logRecord.Maintenance_Type__c == 'Temporary Repair';

        eventRecord.assetId = logRecord.Asset__c;

        if (logRecord.Asset__r != null) {
            eventRecord.assetName = logRecord.Asset__r.Name;
            eventRecord.manufacturer = logRecord.Asset__r.Manufacturer__c;
            eventRecord.model = logRecord.Asset__r.Model__c;
            eventRecord.serialNumber = logRecord.Asset__r.Serial_Number__c;
            eventRecord.machineLabel = buildMachineLabel(logRecord.Asset__r.Manufacturer__c, logRecord.Asset__r.Model__c);
        }

        eventRecord.technicianId = logRecord.Performed_By__c;
        eventRecord.technicianName = logRecord.Performed_By__r == null ? null : logRecord.Performed_By__r.Name;

        if (logRecord.Work_Order__r != null) {
            eventRecord.workOrderId = logRecord.Work_Order__c;
            eventRecord.workOrderNumber = logRecord.Work_Order__r.WorkOrderNumber;
            eventRecord.subject = safeText(logRecord.Work_Order__r.Subject);
            eventRecord.priority = safeText(logRecord.Work_Order__r.Priority);
            eventRecord.dispatchStatus = safeText(logRecord.Work_Order__r.Dispatch_Status__c);
            eventRecord.accountId = logRecord.Work_Order__r.AccountId;
            eventRecord.accountName = logRecord.Work_Order__r.Account == null ? null : logRecord.Work_Order__r.Account.Name;
            eventRecord.caseId = logRecord.Work_Order__r.CaseId;

            if (logRecord.Work_Order__r.Case != null) {
                eventRecord.caseNumber = logRecord.Work_Order__r.Case.CaseNumber;
                eventRecord.caseSubject = logRecord.Work_Order__r.Case.Subject;
            }

            if (String.isBlank(eventRecord.technicianName) && logRecord.Work_Order__r.Suggested_Technician__r != null) {
                eventRecord.technicianId = logRecord.Work_Order__r.Suggested_Technician__c;
                eventRecord.technicianName = logRecord.Work_Order__r.Suggested_Technician__r.Name;
            }
        }

        eventRecord.isScheduledEvent = false;
        eventRecord.isHistoricalEvent = true;
        eventRecord.isPastDue = false;

        applyHistoricalOutcome(eventRecord);

        return eventRecord;
    }


    // =========================================================
    // Historical Outcome
    // =========================================================

    private static void applyHistoricalOutcome(CalendarEventDTO eventRecord) {
        // Temporary Repair is the most specific outcome and should win visually.
        if (eventRecord.temporaryRepair) {
            eventRecord.outcomeKey = 'TEMPORARY_REPAIR';
            eventRecord.outcomeLabel = eventRecord.followUpRequired ? 'Temporary Repair · Follow-Up Required' : 'Temporary Repair';
            return;
        }

        if (eventRecord.followUpRequired) {
            eventRecord.outcomeKey = 'FOLLOW_UP';
            eventRecord.outcomeLabel = 'Follow-Up Required';
            return;
        }

        if (eventRecord.isResolved) {
            eventRecord.outcomeKey = 'COMPLETED';
            eventRecord.outcomeLabel = 'Repair Completed';
            return;
        }

        eventRecord.outcomeKey = 'SERVICE_VISIT';
        eventRecord.outcomeLabel = 'Service Visit';
    }


    // =========================================================
    // Summary Counts
    // =========================================================

    private static void calculateCounts(CalendarData result) {
        result.totalEvents = result.events.size();

        for (CalendarEventDTO eventRecord : result.events) {
            if (eventRecord == null) continue;

            if (eventRecord.outcomeKey == 'SCHEDULED') result.scheduledCount++;
            if (eventRecord.outcomeKey == 'PAST_DUE') result.pastDueCount++;
            if (eventRecord.outcomeKey == 'IN_PROGRESS') result.inProgressCount++;
            if (eventRecord.outcomeKey == 'COMPLETED') result.completedCount++;
            if (eventRecord.followUpRequired) result.followUpCount++;
            if (eventRecord.temporaryRepair) result.temporaryRepairCount++;
        }
    }


    // =========================================================
    // Validation / Helpers
    // =========================================================

    private static void validateMonth(Integer year, Integer month) {
        if (year == null || month == null || year < 1900 || year > 2200 || month < 1 || month > 12) {
            throw new AuraHandledException('A valid calendar year and month are required.');
        }
    }


    private static String buildMachineLabel(String manufacturer, String model) {
        List<String> parts = new List<String>();

        if (!String.isBlank(manufacturer)) parts.add(manufacturer.trim());
        if (!String.isBlank(model)) parts.add(model.trim());

        return parts.isEmpty() ? null : String.join(parts, ' ');
    }


    private static String safeText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }


    // =========================================================
    // Response DTO
    // =========================================================

    public class CalendarData {
        @AuraEnabled public Integer year;
        @AuraEnabled public Integer month;
        @AuraEnabled public Date monthStart;
        @AuraEnabled public Date monthEnd;

        @AuraEnabled public Integer totalEvents = 0;
        @AuraEnabled public Integer scheduledCount = 0;
        @AuraEnabled public Integer pastDueCount = 0;
        @AuraEnabled public Integer inProgressCount = 0;
        @AuraEnabled public Integer completedCount = 0;
        @AuraEnabled public Integer followUpCount = 0;
        @AuraEnabled public Integer temporaryRepairCount = 0;

        @AuraEnabled public List<CalendarEventDTO> events;
    }


    // =========================================================
    // Calendar Event DTO
    // =========================================================

    public class CalendarEventDTO implements Comparable {

        // Event
        @AuraEnabled public Id eventId;
        @AuraEnabled public String eventKey;
        @AuraEnabled public String sourceType;
        @AuraEnabled public Date eventDate;
        @AuraEnabled public Datetime eventDateTime;

        // Work Order
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String priority;
        @AuraEnabled public String dispatchStatus;

        // Maintenance Log
        @AuraEnabled public Id maintenanceLogId;
        @AuraEnabled public String maintenanceLogName;
        @AuraEnabled public String maintenanceType;
        @AuraEnabled public String repairSummary;
        @AuraEnabled public String rootCause;
        @AuraEnabled public String partsUsed;
        @AuraEnabled public String technicianNotes;
        @AuraEnabled public Decimal laborHours;

        // Customer / Machine
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String model;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String machineLabel;

        // Case
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String caseSubject;

        // Technician
        @AuraEnabled public Id technicianId;
        @AuraEnabled public String technicianName;

        // Service Context
        @AuraEnabled public String problemSummary;
        @AuraEnabled public String recommendedFixSummary;

        // Outcome
        @AuraEnabled public String outcomeKey;
        @AuraEnabled public String outcomeLabel;
        @AuraEnabled public Boolean isResolved;
        @AuraEnabled public Boolean followUpRequired;
        @AuraEnabled public Boolean temporaryRepair;
        @AuraEnabled public Boolean isScheduledEvent;
        @AuraEnabled public Boolean isHistoricalEvent;
        @AuraEnabled public Boolean isPastDue;


        // =====================================================
        // Sorting
        // =====================================================

        public Integer compareTo(Object compareTo) {
            CalendarEventDTO other = (CalendarEventDTO) compareTo;

            if (eventDateTime != null && other.eventDateTime != null) {
                if (eventDateTime < other.eventDateTime) return -1;
                if (eventDateTime > other.eventDateTime) return 1;
            }

            if (eventDate != null && other.eventDate != null) {
                if (eventDate < other.eventDate) return -1;
                if (eventDate > other.eventDate) return 1;
            }

            return 0;
        }
    }
}