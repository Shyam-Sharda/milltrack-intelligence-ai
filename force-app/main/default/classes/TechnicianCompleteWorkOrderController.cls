public with sharing class TechnicianCompleteWorkOrderController {

    private static final String REQUIRED_WORK_ORDER_STATUS = 'In Progress';
    private static final String COMPLETED_WORK_ORDER_STATUS = 'Completed';
    private static final String CLOSED_CASE_STATUS = 'Closed';
    private static final String ACTIVE_ASSET_STATUS = 'Active';
    private static final String MAINTENANCE_TYPE = 'Repair';

    public class CompletionContext {
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
    }

    @AuraEnabled(cacheable=true)
    public static CompletionContext getCompletionContext(Id workOrderId) {
        if (workOrderId == null) {
            throw handledException('A Work Order is required.');
        }

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, AssetId,
                   Asset.Name, Asset.Manufacturer__c, Asset.Model__c,
                   Labor_Hours__c, Dispatch_Status__c, OwnerId,
                   Service_Manager__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            throw handledException('The Work Order could not be found or is no longer accessible.');
        }

        WorkOrder workOrder = workOrders[0];

        validateEligibility(workOrder);

        if (workOrder.AssetId == null) {
            throw handledException('This Work Order is not linked to a machine. The repair cannot be completed.');
        }

        if (workOrder.Service_Manager__c == null) {
            throw handledException('No Service Manager is assigned to this Work Order. Assign a Service Manager before completing the repair.');
        }

        CompletionContext context = new CompletionContext();
        context.workOrderId = workOrder.Id;
        context.workOrderNumber = workOrder.WorkOrderNumber;
        context.subject = workOrder.Subject;
        context.assetId = workOrder.AssetId;
        context.assetName = workOrder.Asset.Name;
        context.manufacturer = workOrder.Asset.Manufacturer__c;
        context.model = workOrder.Asset.Model__c;
        context.currentLaborHours = workOrder.Labor_Hours__c == null ? 0 : workOrder.Labor_Hours__c;

        return context;
    }

    @AuraEnabled
    public static SubmitResult completeWorkOrder(
        Id workOrderId,
        String repairSummary,
        String rootCause,
        String partsUsed,
        Decimal laborHours
    ) {
        if (workOrderId == null) {
            throw handledException('A Work Order is required.');
        }

        String cleanedSummary = String.isBlank(repairSummary) ? null : repairSummary.trim();

        String cleanedRootCause = String.isBlank(rootCause) ? null : rootCause.trim();

        String cleanedPartsUsed = String.isBlank(partsUsed) ? null : partsUsed.trim();

        if (String.isBlank(cleanedSummary)) {
            throw handledException('Repair Summary is required.');
        }

        if (String.isBlank(cleanedRootCause)) {
            throw handledException('Root Cause is required.');
        }

        if (laborHours == null || laborHours <= 0) {
            throw handledException('Labor Hours must be greater than 0.');
        }

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, AssetId, CaseId,
                   OwnerId, Dispatch_Status__c, Labor_Hours__c,
                   Technician_Notes__c, Service_Manager__c,
                   Suggested_Technician__c, Scheduled_Visit__c,
                   Work_Started_Date_Time__c, Work_Ended_Date_Time__c,
                   Problem_Summary__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
            FOR UPDATE
        ];

        if (workOrders.isEmpty()) {
            throw handledException(
                'The Work Order could not be found or is no longer accessible.'
            );
        }

        WorkOrder workOrder = workOrders[0];

        /*
         * Re-check eligibility at save time.
         * This protects against stale modal state or another process changing
         * the Work Order after the technician opened the action.
         */
        validateEligibility(workOrder);

        if (workOrder.AssetId == null) {
            throw handledException(
                'This Work Order is not linked to a machine. The repair cannot be completed.'
            );
        }

        if (workOrder.Service_Manager__c == null) {
            throw handledException(
                'No Service Manager is assigned to this Work Order. Assign a Service Manager before completing the repair.'
            );
        }

        Decimal existingLabor =
            workOrder.Labor_Hours__c == null
                ? 0
                : workOrder.Labor_Hours__c;

        Decimal updatedLabor = existingLabor + laborHours;

        String completionNote = buildCompletionNote(
            cleanedSummary,
            cleanedRootCause,
            cleanedPartsUsed,
            laborHours
        );

        String updatedTechnicianNotes = appendTechnicianNotes(
            workOrder.Technician_Notes__c,
            completionNote
        );

        Savepoint savepoint = Database.setSavepoint();

        try {
            /*
             * ---------------------------------------------------------
             * 1. CREATE AUTHORITATIVE MAINTENANCE LOG
             * ---------------------------------------------------------
             *
             * Labor here is VISIT-SPECIFIC.
             * Root Cause is authoritative because the repair is resolved.
             */
            Maintenance_Log__c maintenanceLog = new Maintenance_Log__c(
                Asset__c = workOrder.AssetId,
                Work_Order__c = workOrder.Id,
                Maintenance_Date__c = Date.today(),
                Maintenance_Type__c = MAINTENANCE_TYPE,
                Problem_Summary__c = workOrder.Problem_Summary__c,
                Summary__c = cleanedSummary,
                Technician_Notes__c = completionNote,
                Root_Cause__c = cleanedRootCause,
                Parts_Used__c = cleanedPartsUsed,
                Labor_Hours__c = laborHours,
                Issue_Resolved__c = true,
                Follow_Up_Required__c = false,
                Performed_By__c = UserInfo.getUserId(),
                OwnerId = UserInfo.getUserId()
            );

            Database.insert(maintenanceLog, AccessLevel.SYSTEM_MODE);

            /*
             * ---------------------------------------------------------
             * 2. RETURN MACHINE TO ACTIVE SERVICE
             * ---------------------------------------------------------
             */
            Asset assetUpdate = new Asset(
                Id = workOrder.AssetId,
                Machine_Status__c = ACTIVE_ASSET_STATUS,
                Last_Service_Date__c = Date.today()
            );

            Database.update(assetUpdate, AccessLevel.SYSTEM_MODE);

            /*
             * ---------------------------------------------------------
             * 3. CLOSE RELATED CASE
             * ---------------------------------------------------------
             *
             * A Work Order without a Case can still be completed.
             */
            if (workOrder.CaseId != null) {
                Case caseUpdate = new Case(
                    Id = workOrder.CaseId,
                    Status = CLOSED_CASE_STATUS
                );

                Database.update(caseUpdate, AccessLevel.SYSTEM_MODE);
            }

            /*
             * ---------------------------------------------------------
             * 4. FINALIZE WORK ORDER LAST
             * ---------------------------------------------------------
             *
             * Ownership is deliberately moved away from the technician
             * only after all visit evidence and related-record updates
             * have succeeded.
             *
             * Work_Started_Date_Time__c is intentionally untouched.
             * Scheduled_Visit__c is also preserved as historical visit
             * information, matching the current Flow behavior.
             */
            WorkOrder workOrderUpdate = new WorkOrder(
                Id = workOrder.Id,
                Dispatch_Status__c = COMPLETED_WORK_ORDER_STATUS,
                Labor_Hours__c = updatedLabor,
                Technician_Notes__c = updatedTechnicianNotes,
                Work_Ended_Date_Time__c = System.now(),
                OwnerId = workOrder.Service_Manager__c,
                Suggested_Technician__c = null
            );

            Database.update(workOrderUpdate, AccessLevel.SYSTEM_MODE);

            SubmitResult result = new SubmitResult();
            result.success = true;
            result.maintenanceLogId = maintenanceLog.Id;
            result.workOrderNumber = workOrder.WorkOrderNumber;
            result.message =
                'Work Order completed successfully. The repair has been recorded and the machine has been returned to active service.';

            return result;

        } catch (Exception e) {
            Database.rollback(savepoint);

            if (e instanceof AuraHandledException) {
                throw e;
            }

            throw handledException('Unable to complete the Work Order: ' + e.getMessage());
        }
    }

    /*
     * =============================================================
     * ELIGIBILITY
     * =============================================================
     */
    private static void validateEligibility(WorkOrder workOrder) {
        if (workOrder.Dispatch_Status__c != REQUIRED_WORK_ORDER_STATUS) {
            throw handledException(
                'A Work Order can only be completed while it is In Progress. Current status: ' +
                String.valueOf(workOrder.Dispatch_Status__c) +
                '.'
            );
        }

        if (workOrder.OwnerId != UserInfo.getUserId()) {
            throw handledException('Only the technician currently assigned to this Work Order can complete the repair.');
        }
    }

    /*
     * =============================================================
     * COMPLETION NOTE
     * =============================================================
     */
    private static String buildCompletionNote(
        String repairSummary,
        String rootCause,
        String partsUsed,
        Decimal laborHours
    ) {
        String partsText =
            String.isBlank(partsUsed)
                ? 'None recorded'
                : partsUsed;

        return
            'COMPLETED REPAIR\n\n' +
            'Repair Summary:\n' +
            repairSummary +
            '\n\nRoot Cause:\n' +
            rootCause +
            '\n\nParts Used:\n' +
            partsText +
            '\n\nLabor Hours:\n' +
            String.valueOf(laborHours);
    }

    /*
     * =============================================================
     * APPEND WORK ORDER TECHNICIAN HISTORY
     * =============================================================
     */
    private static String appendTechnicianNotes(
        String existingNotes,
        String newNote
    ) {
        if (String.isBlank(existingNotes)) {
            return newNote;
        }

        return existingNotes + '\n\n' + newNote;
    }

    /*
     * =============================================================
     * FRIENDLY LWC EXCEPTIONS
     * =============================================================
     */
    private static AuraHandledException handledException(String message) {
        AuraHandledException exceptionValue = new AuraHandledException(message);

        exceptionValue.setMessage(message);

        return exceptionValue;
    }
}