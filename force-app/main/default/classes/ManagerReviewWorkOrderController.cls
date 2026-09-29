public with sharing class ManagerReviewWorkOrderController {

    private static final Set<String> ALLOWED_PRIORITIES = new Set<String>{'Low', 'Medium', 'High', 'Critical'};
    private static final String STATUS_READY_TO_ASSIGN = 'Ready_to_Assign';
    private static final String STATUS_PARTS_TO_ORDER = 'Parts to Order';
    private static final String CASE_STATUS_IN_PROGRESS = 'In Progress';
    private static final String PART_STATUS_REQUESTED = 'Requested';
    private static final String PART_STATUS_CANCELLED = 'Cancelled';

    // =========================================================
    // Load Review Data
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static ReviewData getReviewData(Id workOrderId) {
        if (workOrderId == null) throw new AuraHandledException('A Work Order ID is required.');

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, Priority, Dispatch_Status__c, Problem_Summary__c,
                   Recommended_Solution__c, Recommended_Fix_Summary__c, Recommended_Tools__c,
                   Recommended_Parts__c, Previous_Failure__c, Service_Manager__c, AccountId,
                   Account.Name, AssetId, Asset.Name, Asset.Manufacturer__c, Asset.Model__c,
                   Asset.Serial_Number__c, Asset.Machine_Status__c, CaseId, Case.CaseNumber,
                   Case.Subject, Case.Description, Case.Status, Case.Priority, Case.Error_Code__c,
                   Case.CreatedDate, Case.ContactId, Case.Contact.Name, Case.Contact.Email,
                   Case.Contact.Phone, Case.Contact.Title
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            throw new AuraHandledException('The Work Order could not be found or you do not have access to it.');
        }

        WorkOrder workOrder = workOrders[0];
        ReviewData result = new ReviewData();
        populateWorkOrderData(result, workOrder);
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
    // Approve / Save Review
    // =========================================================

    @AuraEnabled
    public static ApprovalResult approveWorkOrder(
        Id workOrderId,
        String problemSummary,
        String recommendedSolution,
        String recommendedFixSummary,
        String recommendedTools,
        String recommendedParts,
        Boolean previousFailure,
        String priority,
        String selectedPartsJson
    ) {
        if (workOrderId == null) throw new AuraHandledException('A Work Order ID is required.');
        if (String.isBlank(problemSummary)) throw new AuraHandledException('Problem Summary is required.');
        if (String.isBlank(recommendedSolution)) throw new AuraHandledException('Recommended Solution is required.');

        String normalizedFixSummary = recommendedFixSummary == null ? null : recommendedFixSummary.trim();

        if (normalizedFixSummary != null && normalizedFixSummary.length() > 255) {
            throw new AuraHandledException('Recommended Fix Summary must be 255 characters or fewer.');
        }

        if (String.isBlank(priority) || !ALLOWED_PRIORITIES.contains(priority)) {
            throw new AuraHandledException('Priority must be Low, Medium, High, or Critical.');
        }

        String normalizedRecommendedTools = normalizeAndValidateRecommendedTools(recommendedTools);
        Map<Id, Integer> requestedParts = parseSelectedParts(selectedPartsJson);
        Boolean hasSelectedParts = !requestedParts.isEmpty();

        if (hasSelectedParts) {
            validateSelectedPartCatalogRecords(requestedParts.keySet());
            validateNoExistingActivePartRequests(workOrderId, requestedParts.keySet());
        }

        List<WorkOrder> workOrders = [
            SELECT Id, AssetId, CaseId, Dispatch_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            throw new AuraHandledException('The Work Order could not be found or you do not have access to it.');
        }

        WorkOrder workOrder = workOrders[0];
        workOrder.Problem_Summary__c = problemSummary.trim();
        workOrder.Recommended_Solution__c = recommendedSolution.trim();
        workOrder.Recommended_Fix_Summary__c = normalizedFixSummary;
        workOrder.Recommended_Tools__c = normalizedRecommendedTools;
        workOrder.Recommended_Parts__c = normalizeOptionalText(recommendedParts);
        workOrder.Previous_Failure__c = previousFailure == true;
        workOrder.Priority = priority;
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

        Savepoint approvalSavepoint = Database.setSavepoint();

        try {
            Database.update(workOrder, AccessLevel.USER_MODE);

            if (workOrder.CaseId != null) {
                Case relatedCase = new Case(Id = workOrder.CaseId, Status = CASE_STATUS_IN_PROGRESS);
                Database.update(relatedCase, AccessLevel.USER_MODE);
            }

            if (!partRequests.isEmpty()) Database.insert(partRequests, AccessLevel.USER_MODE);

        } catch (DmlException ex) {
            Database.rollback(approvalSavepoint);
            throw new AuraHandledException('The Work Order could not be approved. ' + getFirstDmlMessage(ex));
        } catch (Exception ex) {
            Database.rollback(approvalSavepoint);
            throw new AuraHandledException('The Work Order could not be approved. ' + ex.getMessage());
        }

        ApprovalResult result = new ApprovalResult();
        result.success = true;
        result.workOrderId = workOrder.Id;
        result.dispatchStatus = workOrder.Dispatch_Status__c;
        result.requestedPartCount = partRequests.size();
        result.message = hasSelectedParts
            ? 'Work Order approved. ' + partRequests.size() + ' required part request' + (partRequests.size() == 1 ? '' : 's') + ' created.'
            : 'Work Order approved and ready to assign to a technician.';
        return result;
    }

    // =========================================================
    // Selected Part Parsing
    // =========================================================

    private static Map<Id, Integer> parseSelectedParts(String selectedPartsJson) {
        Map<Id, Integer> requestedParts = new Map<Id, Integer>();
        if (String.isBlank(selectedPartsJson)) return requestedParts;

        Object parsedValue;

        try {
            parsedValue = JSON.deserializeUntyped(selectedPartsJson);
        } catch (Exception ex) {
            throw new AuraHandledException('The selected parts could not be processed.');
        }

        if (!(parsedValue instanceof List<Object>)) {
            throw new AuraHandledException('The selected parts are not in the expected format.');
        }

        for (Object rawPart : (List<Object>) parsedValue) {
            if (!(rawPart instanceof Map<String, Object>)) {
                throw new AuraHandledException('One of the selected parts is not in the expected format.');
            }

            Map<String, Object> partData = (Map<String, Object>) rawPart;
            Object rawPartCatalogId = partData.get('partCatalogId');
            Object rawQuantity = partData.get('quantity');

            if (rawPartCatalogId == null) {
                throw new AuraHandledException('A selected part is missing its Part Catalog ID.');
            }

            Id partCatalogId;

            try {
                partCatalogId = (Id) String.valueOf(rawPartCatalogId);
            } catch (Exception ex) {
                throw new AuraHandledException('A selected part has an invalid Part Catalog ID.');
            }

            Integer quantity = parseQuantity(rawQuantity);
            Integer existingQuantity = requestedParts.containsKey(partCatalogId) ? requestedParts.get(partCatalogId) : 0;
            requestedParts.put(partCatalogId, existingQuantity + quantity);
        }

        return requestedParts;
    }

    private static Integer parseQuantity(Object rawQuantity) {
        if (rawQuantity == null) throw new AuraHandledException('Each selected part must have a quantity.');

        Decimal quantityDecimal;

        try {
            quantityDecimal = Decimal.valueOf(String.valueOf(rawQuantity));
        } catch (Exception ex) {
            throw new AuraHandledException('Each selected part must have a valid quantity.');
        }

        if (quantityDecimal <= 0 || quantityDecimal.scale() > 0) {
            throw new AuraHandledException('Part quantities must be whole numbers greater than zero.');
        }

        return Integer.valueOf(String.valueOf(quantityDecimal.setScale(0)));
    }

    // =========================================================
    // Selected Part Validation
    // =========================================================

    private static void validateSelectedPartCatalogRecords(Set<Id> partCatalogIds) {
        if (partCatalogIds == null || partCatalogIds.isEmpty()) return;

        List<Part_Catalog__c> catalogParts = [
            SELECT Id, Name, Active__c
            FROM Part_Catalog__c
            WHERE Id IN :partCatalogIds
              AND Active__c = true
            WITH USER_MODE
        ];

        Set<Id> accessiblePartIds = new Set<Id>();
        for (Part_Catalog__c catalogPart : catalogParts) accessiblePartIds.add(catalogPart.Id);

        if (accessiblePartIds.size() != partCatalogIds.size()) {
            throw new AuraHandledException('One or more selected parts are inactive, invalid, or no longer accessible.');
        }
    }

    private static void validateNoExistingActivePartRequests(Id workOrderId, Set<Id> partCatalogIds) {
        if (workOrderId == null || partCatalogIds == null || partCatalogIds.isEmpty()) return;

        List<Work_Order_Part__c> existingRequests = [
            SELECT Id, Part_Catalog__c, Part_Catalog__r.Name, Order_Status__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrderId
              AND Part_Catalog__c IN :partCatalogIds
              AND Order_Status__c != :PART_STATUS_CANCELLED
            WITH USER_MODE
            LIMIT 1
        ];

        if (existingRequests.isEmpty()) return;

        Work_Order_Part__c existingRequest = existingRequests[0];
        String partName = existingRequest.Part_Catalog__r == null ? 'A selected part' : existingRequest.Part_Catalog__r.Name;
        throw new AuraHandledException(partName + ' already has an active part request for this Work Order.');
    }

    // =========================================================
    // Work Order DTO Population
    // =========================================================

    private static void populateWorkOrderData(ReviewData result, WorkOrder workOrder) {
        result.workOrderId = workOrder.Id;
        result.workOrderNumber = workOrder.WorkOrderNumber;
        result.subject = workOrder.Subject;
        result.priority = workOrder.Priority;
        result.dispatchStatus = workOrder.Dispatch_Status__c;

        result.problemSummary = safeText(workOrder.Problem_Summary__c);
        result.recommendedSolution = safeText(workOrder.Recommended_Solution__c);
        result.recommendedFixSummary = safeText(workOrder.Recommended_Fix_Summary__c);
        result.recommendedTools = safeText(workOrder.Recommended_Tools__c);
        result.recommendedParts = safeText(workOrder.Recommended_Parts__c);
        result.previousFailure = workOrder.Previous_Failure__c;

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
            result.caseDescription = workOrder.Case.Description;
            result.caseStatus = workOrder.Case.Status;
            result.casePriority = workOrder.Case.Priority;
            result.errorCode = workOrder.Case.Error_Code__c;
            result.dateReported = workOrder.Case.CreatedDate;
            result.contactId = workOrder.Case.ContactId;

            if (workOrder.Case.Contact != null) {
                result.contactName = workOrder.Case.Contact.Name;
                result.contactEmail = workOrder.Case.Contact.Email;
                result.contactPhone = workOrder.Case.Contact.Phone;
                result.contactTitle = workOrder.Case.Contact.Title;
            }
        }
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

    private static String safeText(String value) { return value == null ? '' : value; }
    private static String normalizeOptionalText(String value) { return String.isBlank(value) ? null : value.trim(); }

    private static AuraHandledException handledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    private static String getFirstDmlMessage(DmlException ex) {
        return ex == null || ex.getNumDml() == 0 ? 'An unexpected save error occurred.' : ex.getDmlMessage(0);
    }

    // =========================================================
    // DTOs
    // =========================================================

    public class ReviewData {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }

        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String recommendedSolution { get; set; }
        @AuraEnabled public String recommendedFixSummary { get; set; }
        @AuraEnabled public String recommendedTools { get; set; }
        @AuraEnabled public String recommendedParts { get; set; }
        @AuraEnabled public Boolean previousFailure { get; set; }

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
        @AuraEnabled public String caseDescription { get; set; }
        @AuraEnabled public String caseStatus { get; set; }
        @AuraEnabled public String casePriority { get; set; }
        @AuraEnabled public String errorCode { get; set; }
        @AuraEnabled public Datetime dateReported { get; set; }
    }

    public class ToolOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
    }

    public class ApprovalResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public Integer requestedPartCount { get; set; }
        @AuraEnabled public String message { get; set; }
    }
}