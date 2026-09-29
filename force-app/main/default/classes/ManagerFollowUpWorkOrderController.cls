public with sharing class ManagerFollowUpWorkOrderController {

    private static final String REQUIRED_STATUS = 'Temporary Fix';
    private static final String STATUS_READY_TO_ASSIGN = 'Ready_to_Assign';
    private static final String STATUS_PARTS_TO_ORDER = 'Parts to Order';
    private static final String CASE_STATUS_IN_PROGRESS = 'In Progress';
    private static final String PART_STATUS_REQUESTED = 'Requested';
    private static final String PART_STATUS_CANCELLED = 'Cancelled';

    // =========================================================
    // Load Follow-Up Data
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static FollowUpData getFollowUpData(Id workOrderId) {
        if (workOrderId == null) throw handledException('A Work Order ID is required.');

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, Priority, Dispatch_Status__c, Problem_Summary__c,
                   Recommended_Fix_Summary__c, Recommended_Tools__c, Service_Manager__c,
                   AccountId, Account.Name, AssetId, Asset.Name, Asset.Manufacturer__c,
                   Asset.Model__c, Asset.Serial_Number__c, Asset.Machine_Status__c,
                   CaseId, Case.CaseNumber, Case.Subject, Case.Status, Case.ContactId,
                   Case.Contact.Name, Case.Contact.Email, Case.Contact.Phone, Case.Contact.Title
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        if (workOrders.isEmpty()) throw handledException('The Work Order could not be found or you do not have access to it.');

        WorkOrder workOrder = workOrders[0];
        validateFollowUpStatus(workOrder);

        List<Maintenance_Log__c> logs = [
            SELECT Id, Name, Maintenance_Date__c, Maintenance_Type__c, Problem_Summary__c,
                   Recommended_Fix_Snapshot__c, Tools_To_Bring_Snapshot__c, Summary__c,
                   Technician_Notes__c, Labor_Hours__c, Issue_Resolved__c, Follow_Up_Required__c,
                   Performed_By__c, Performed_By__r.Name, CreatedDate
            FROM Maintenance_Log__c
            WHERE Work_Order__c = :workOrderId
              AND Follow_Up_Required__c = true
            WITH USER_MODE
            ORDER BY Maintenance_Date__c DESC, CreatedDate DESC
            LIMIT 1
        ];

        if (logs.isEmpty()) throw handledException('No follow-up Maintenance Log could be found for this Work Order.');

        List<Work_Order_Part__c> parts = [
            SELECT Id, Name, Part_Catalog__c, Part_Catalog__r.Name, Quantity__c, Order_Status__c,
                   Technician_Requested__c, Notes__c, CreatedDate
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrderId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];

        FollowUpData result = new FollowUpData();
        populateWorkOrderData(result, workOrder);
        populateVisitData(result, logs[0]);
        populateExistingParts(result, parts);
        return result;
    }

    // =========================================================
    // Tool Catalog
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static List<ToolOption> getToolCatalog() {
        List<Tool_Catalog__c> catalogTools = [
            SELECT Id, Name
            FROM Tool_Catalog__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT 200
        ];

        List<ToolOption> results = new List<ToolOption>();

        for (Tool_Catalog__c catalogTool : catalogTools) {
            ToolOption option = new ToolOption();
            option.id = catalogTool.Id;
            option.name = catalogTool.Name;
            results.add(option);
        }

        return results;
    }

    // =========================================================
    // Approve Follow-Up Plan
    // =========================================================

    @AuraEnabled
    public static ApprovalResult approveFollowUp(Id workOrderId, String recommendedFixSummary, String recommendedTools, String selectedPartsJson) {
        if (workOrderId == null) throw handledException('A Work Order ID is required.');

        String normalizedFix = normalizeOptionalText(recommendedFixSummary);
        String normalizedTools = normalizeAndValidateRecommendedTools(recommendedTools);

        if (String.isBlank(normalizedFix)) throw handledException('Recommended Fix Summary is required.');
        if (normalizedFix.length() > 255) throw handledException('Recommended Fix Summary must be 255 characters or fewer.');

        Map<Id, Integer> requestedParts = parseSelectedParts(selectedPartsJson);
        Boolean hasSelectedParts = !requestedParts.isEmpty();

        List<WorkOrder> workOrders = [
            SELECT Id, AssetId, CaseId, Dispatch_Status__c, Recommended_Fix_Summary__c,
                   Recommended_Tools__c, Service_Manager__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        if (workOrders.isEmpty()) throw handledException('The Work Order could not be found or you do not have access to it.');

        WorkOrder workOrder = workOrders[0];
        validateFollowUpStatus(workOrder);

        if (hasSelectedParts) {
            validateSelectedPartCatalogRecords(requestedParts.keySet());
            validateNoExistingActivePartRequests(workOrder.Id, requestedParts.keySet());
        }

        workOrder.Recommended_Fix_Summary__c = normalizedFix;
        workOrder.Recommended_Tools__c = normalizedTools;
        workOrder.Service_Manager__c = UserInfo.getUserId();
        workOrder.Dispatch_Status__c = hasSelectedParts ? STATUS_PARTS_TO_ORDER : STATUS_READY_TO_ASSIGN;

        List<Work_Order_Part__c> partRequests = new List<Work_Order_Part__c>();

        for (Id partCatalogId : requestedParts.keySet()) {
            partRequests.add(new Work_Order_Part__c(
                Work_Order__c = workOrder.Id,
                Machine__c = workOrder.AssetId,
                Part_Catalog__c = partCatalogId,
                Quantity__c = requestedParts.get(partCatalogId),
                Order_Status__c = PART_STATUS_REQUESTED
            ));
        }

        Savepoint savepointValue = Database.setSavepoint();

        try {
            Database.update(workOrder, AccessLevel.USER_MODE);

            if (workOrder.CaseId != null) {
                Case caseUpdate = new Case(Id = workOrder.CaseId, Status = CASE_STATUS_IN_PROGRESS);
                Database.update(caseUpdate, AccessLevel.USER_MODE);
            }

            if (!partRequests.isEmpty()) Database.insert(partRequests, AccessLevel.USER_MODE);

        } catch (DmlException ex) {
            Database.rollback(savepointValue);
            throw handledException('The follow-up plan could not be approved. ' + getFirstDmlMessage(ex));
        } catch (Exception ex) {
            Database.rollback(savepointValue);
            throw handledException('The follow-up plan could not be approved. ' + ex.getMessage());
        }

        ApprovalResult result = new ApprovalResult();
        result.success = true;
        result.workOrderId = workOrder.Id;
        result.dispatchStatus = workOrder.Dispatch_Status__c;
        result.requestedPartCount = partRequests.size();
        result.message = hasSelectedParts
            ? 'Follow-up plan approved. ' + partRequests.size() + ' required part request' + (partRequests.size() == 1 ? '' : 's') + ' created.'
            : 'Follow-up plan approved and the Work Order is ready to assign.';
        return result;
    }

    // =========================================================
    // Work Order / Visit / Parts DTO Population
    // =========================================================

    private static void populateWorkOrderData(FollowUpData result, WorkOrder workOrder) {
        result.workOrderId = workOrder.Id;
        result.workOrderNumber = workOrder.WorkOrderNumber;
        result.subject = workOrder.Subject;
        result.priority = workOrder.Priority;
        result.dispatchStatus = workOrder.Dispatch_Status__c;
        result.problemSummary = safeText(workOrder.Problem_Summary__c);

        result.accountId = workOrder.AccountId;
        result.accountName = workOrder.Account == null ? null : workOrder.Account.Name;
        result.assetId = workOrder.AssetId;

        if (workOrder.Asset != null) {
            result.assetName = workOrder.Asset.Name;
            result.manufacturer = workOrder.Asset.Manufacturer__c;
            result.model = workOrder.Asset.Model__c;
            result.serialNumber = workOrder.Asset.Serial_Number__c;
            result.machineStatus = workOrder.Asset.Machine_Status__c;
        }

        result.caseId = workOrder.CaseId;

        if (workOrder.Case != null) {
            result.caseNumber = workOrder.Case.CaseNumber;
            result.caseSubject = workOrder.Case.Subject;
            result.caseStatus = workOrder.Case.Status;
            result.contactId = workOrder.Case.ContactId;

            if (workOrder.Case.Contact != null) {
                result.contactName = workOrder.Case.Contact.Name;
                result.contactEmail = workOrder.Case.Contact.Email;
                result.contactPhone = workOrder.Case.Contact.Phone;
                result.contactTitle = workOrder.Case.Contact.Title;
            }
        }
    }

    private static void populateVisitData(FollowUpData result, Maintenance_Log__c log) {
        result.maintenanceLogId = log.Id;
        result.maintenanceLogNumber = log.Name;
        result.maintenanceDate = log.Maintenance_Date__c;
        result.maintenanceType = log.Maintenance_Type__c;
        result.visitProblemSummary = safeText(log.Problem_Summary__c);
        result.previousRecommendedFix = safeText(log.Recommended_Fix_Snapshot__c);
        result.previousTools = safeText(log.Tools_To_Bring_Snapshot__c);
        result.visitSummary = safeText(log.Summary__c);
        result.technicianNotes = safeText(log.Technician_Notes__c);
        result.laborHours = log.Labor_Hours__c;
        result.issueResolved = log.Issue_Resolved__c;
        result.followUpRequired = log.Follow_Up_Required__c;
        result.technicianId = log.Performed_By__c;
        result.technicianName = log.Performed_By__r == null ? null : log.Performed_By__r.Name;
    }

    private static void populateExistingParts(FollowUpData result, List<Work_Order_Part__c> parts) {
        result.existingParts = new List<ExistingPartData>();

        for (Work_Order_Part__c part : parts) {
            ExistingPartData dto = new ExistingPartData();
            dto.workOrderPartId = part.Id;
            dto.workOrderPartNumber = part.Name;
            dto.partCatalogId = part.Part_Catalog__c;
            dto.partName = part.Part_Catalog__r == null ? part.Name : part.Part_Catalog__r.Name;
            dto.quantity = part.Quantity__c;
            dto.status = part.Order_Status__c;
            dto.technicianRequested = part.Technician_Requested__c;
            dto.sourceLabel = part.Technician_Requested__c ? 'Technician Request' : 'Required Part';
            dto.notes = part.Notes__c;
            result.existingParts.add(dto);
        }
    }

    // =========================================================
    // Selected Part Parsing / Validation
    // =========================================================

    private static Map<Id, Integer> parseSelectedParts(String selectedPartsJson) {
        Map<Id, Integer> requestedParts = new Map<Id, Integer>();
        if (String.isBlank(selectedPartsJson)) return requestedParts;

        Object parsedValue;

        try {
            parsedValue = JSON.deserializeUntyped(selectedPartsJson);
        } catch (Exception ex) {
            throw handledException('The selected parts could not be processed.');
        }

        if (!(parsedValue instanceof List<Object>)) throw handledException('The selected parts are not in the expected format.');

        for (Object rawPart : (List<Object>) parsedValue) {
            if (!(rawPart instanceof Map<String, Object>)) throw handledException('One of the selected parts is not in the expected format.');

            Map<String, Object> partData = (Map<String, Object>) rawPart;
            Object rawPartCatalogId = partData.get('partCatalogId');
            Object rawQuantity = partData.get('quantity');

            if (rawPartCatalogId == null) throw handledException('A selected part is missing its Part Catalog ID.');

            Id partCatalogId;

            try {
                partCatalogId = (Id) String.valueOf(rawPartCatalogId);
            } catch (Exception ex) {
                throw handledException('A selected part has an invalid Part Catalog ID.');
            }

            Integer quantity = parseQuantity(rawQuantity);
            Integer existingQuantity = requestedParts.containsKey(partCatalogId) ? requestedParts.get(partCatalogId) : 0;
            requestedParts.put(partCatalogId, existingQuantity + quantity);
        }

        return requestedParts;
    }

    private static Integer parseQuantity(Object rawQuantity) {
        if (rawQuantity == null) throw handledException('Each selected part must have a quantity.');

        Decimal quantity;

        try {
            quantity = Decimal.valueOf(String.valueOf(rawQuantity));
        } catch (Exception ex) {
            throw handledException('Each selected part must have a valid quantity.');
        }

        if (quantity <= 0 || quantity.scale() > 0) throw handledException('Part quantities must be whole numbers greater than zero.');

        return Integer.valueOf(String.valueOf(quantity.setScale(0)));
    }

    private static void validateSelectedPartCatalogRecords(Set<Id> partCatalogIds) {
        if (partCatalogIds == null || partCatalogIds.isEmpty()) return;

        List<Part_Catalog__c> parts = [
            SELECT Id
            FROM Part_Catalog__c
            WHERE Id IN :partCatalogIds
              AND Active__c = true
            WITH USER_MODE
        ];

        Set<Id> accessibleIds = new Set<Id>();
        for (Part_Catalog__c part : parts) accessibleIds.add(part.Id);

        if (accessibleIds.size() != partCatalogIds.size()) {
            throw handledException('One or more selected parts are inactive, invalid, or no longer accessible.');
        }
    }

    private static void validateNoExistingActivePartRequests(Id workOrderId, Set<Id> partCatalogIds) {
        if (workOrderId == null || partCatalogIds == null || partCatalogIds.isEmpty()) return;

        List<Work_Order_Part__c> existingParts = [
            SELECT Id, Part_Catalog__c, Part_Catalog__r.Name, Order_Status__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrderId
              AND Part_Catalog__c IN :partCatalogIds
              AND Order_Status__c != :PART_STATUS_CANCELLED
            WITH USER_MODE
            LIMIT 1
        ];

        if (existingParts.isEmpty()) return;

        Work_Order_Part__c existingPart = existingParts[0];
        String partName = existingPart.Part_Catalog__r == null ? 'A selected part' : existingPart.Part_Catalog__r.Name;
        throw handledException(partName + ' already has an active part request for this Work Order.');
    }

    // =========================================================
    // Tool Validation / Helpers
    // =========================================================

    private static String normalizeAndValidateRecommendedTools(String value) {
        if (String.isBlank(value)) return null;

        List<String> requestedTools = new List<String>();
        Set<String> requestedToolKeys = new Set<String>();

        for (String rawTool : value.split('[\\r\\n,;]+')) {
            String toolName = rawTool == null ? null : rawTool.trim();
            if (String.isBlank(toolName)) continue;

            String toolKey = toolName.toLowerCase();
            if (requestedToolKeys.add(toolKey)) requestedTools.add(toolName);
        }

        if (requestedTools.isEmpty()) return null;

        List<Tool_Catalog__c> catalogTools = [
            SELECT Id, Name
            FROM Tool_Catalog__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT 200
        ];

        Map<String, String> catalogNamesByKey = new Map<String, String>();

        for (Tool_Catalog__c catalogTool : catalogTools) {
            if (String.isBlank(catalogTool.Name)) continue;

            String catalogName = catalogTool.Name.trim();
            catalogNamesByKey.put(catalogName.toLowerCase(), catalogName);
        }

        List<String> normalizedTools = new List<String>();
        List<String> invalidTools = new List<String>();

        for (String requestedTool : requestedTools) {
            String catalogName = catalogNamesByKey.get(requestedTool.toLowerCase());

            if (catalogName == null) invalidTools.add(requestedTool);
            else normalizedTools.add(catalogName);
        }

        if (!invalidTools.isEmpty()) {
            throw handledException(
                'One or more selected tools are not valid Tool Catalog entries: ' +
                String.join(invalidTools, ', ') + '.'
            );
        }

        return String.join(normalizedTools, '\n');
    }

    private static void validateFollowUpStatus(WorkOrder workOrder) {
        if (workOrder.Dispatch_Status__c != REQUIRED_STATUS) {
            throw handledException(
                'This Work Order is no longer awaiting follow-up review. Current status: ' +
                String.valueOf(workOrder.Dispatch_Status__c) + '.'
            );
        }
    }

    private static String safeText(String value) { return value == null ? '' : value; }
    private static String normalizeOptionalText(String value) { return String.isBlank(value) ? null : value.trim(); }
    private static String getFirstDmlMessage(DmlException ex) { return ex == null || ex.getNumDml() == 0 ? 'An unexpected save error occurred.' : ex.getDmlMessage(0); }

    private static AuraHandledException handledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    // =========================================================
    // DTOs
    // =========================================================

    public class FollowUpData {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String problemSummary { get; set; }

        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String contactEmail { get; set; }
        @AuraEnabled public String contactPhone { get; set; }
        @AuraEnabled public String contactTitle { get; set; }

        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String machineStatus { get; set; }

        @AuraEnabled public Id caseId { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String caseSubject { get; set; }
        @AuraEnabled public String caseStatus { get; set; }

        @AuraEnabled public Id maintenanceLogId { get; set; }
        @AuraEnabled public String maintenanceLogNumber { get; set; }
        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public String maintenanceType { get; set; }
        @AuraEnabled public String visitProblemSummary { get; set; }
        @AuraEnabled public String previousRecommendedFix { get; set; }
        @AuraEnabled public String previousTools { get; set; }
        @AuraEnabled public String visitSummary { get; set; }
        @AuraEnabled public String technicianNotes { get; set; }
        @AuraEnabled public Decimal laborHours { get; set; }
        @AuraEnabled public Boolean issueResolved { get; set; }
        @AuraEnabled public Boolean followUpRequired { get; set; }
        @AuraEnabled public Id technicianId { get; set; }
        @AuraEnabled public String technicianName { get; set; }

        @AuraEnabled public List<ExistingPartData> existingParts { get; set; }
    }

    public class ToolOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
    }

    public class ExistingPartData {
        @AuraEnabled public Id workOrderPartId { get; set; }
        @AuraEnabled public String workOrderPartNumber { get; set; }
        @AuraEnabled public Id partCatalogId { get; set; }
        @AuraEnabled public String partName { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean technicianRequested { get; set; }
        @AuraEnabled public String sourceLabel { get; set; }
        @AuraEnabled public String notes { get; set; }
    }

    public class ApprovalResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public Integer requestedPartCount { get; set; }
        @AuraEnabled public String message { get; set; }
    }
}