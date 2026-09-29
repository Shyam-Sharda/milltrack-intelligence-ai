/**
 * Data controller for the Manager Operations Center Lightning Web Component.
 *
 * The controller is intentionally read-only. Manager actions are performed by
 * guided LWC wizards, Screen Flows, or record navigation launched by the LWC.
 */
public with sharing class ManagerOperationsCenterController {
    private static final Integer CASE_ROW_LIMIT = 200;
    private static final Integer WORK_ORDER_ROW_LIMIT = 500;
    private static final Integer PART_ROW_LIMIT = 300;
    private static final String STATUS_READY_TO_ASSIGN = 'Ready_to_Assign';
    private static final String LABEL_READY_TO_ASSIGN = 'Ready to Assign';
    // Returns all Manager Operations Center queues in one cacheable response.
    @AuraEnabled(cacheable=true)
    public static OperationsData getOperationsData() {
        try {
            OperationsData data = new OperationsData();
            loadNewCases(data);
            loadWorkOrderQueues(data);
            loadAssignedVisits(data);
            loadPartQueues(data);
            data.openServiceCasesCount = countOpenServiceCases();
            data.calculateCounts();
            data.generatedAt = System.now();
            return data;
        } catch (Exception ex) {
            throw new AuraHandledException(
                'The Manager Operations Center could not be loaded. ' +
                'Confirm that the Service Manager permission set provides ' +
                'access to the required Case, Work Order, Work Order Part, ' +
                'Account, Asset, Part Catalog, and User fields.'
            );
        }
    }
    private static void loadNewCases(OperationsData data) {
        List<Case> cases = [
            SELECT
                Id,
                CaseNumber,
                Subject,
                Status,
                Priority,
                AccountId,
                Account.Name,
                AssetId,
                Asset.Name,
                OwnerId,
                Owner.Name,
                CreatedDate
            FROM Case
            WHERE Status = 'New'
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT :CASE_ROW_LIMIT
        ];
        Set<Id> caseIds = new Set<Id>();
        for (Case serviceCase : cases) {
            caseIds.add(serviceCase.Id);
        }
        Map<Id, WorkOrder> activeWorkOrderByCaseId = getActiveWorkOrdersByCaseId(caseIds);
        for (Case serviceCase : cases) {
            QueueItem item = toQueueItem(serviceCase);
            WorkOrder relatedWorkOrder = activeWorkOrderByCaseId.get(serviceCase.Id);
            if (relatedWorkOrder != null) {
                item.workOrderId = relatedWorkOrder.Id;
                item.relatedRecordId = relatedWorkOrder.Id;
                item.relatedRecordNumber = relatedWorkOrder.WorkOrderNumber;
                item.workOrderSubject = relatedWorkOrder.Subject;
            }
            data.newCases.add(item);
        }
    }
    private static Map<Id, WorkOrder> getActiveWorkOrdersByCaseId(Set<Id> caseIds) {
        Map<Id, WorkOrder> workOrderByCaseId = new Map<Id, WorkOrder>();
        if (caseIds == null || caseIds.isEmpty()) return workOrderByCaseId;
        Set<String> terminalStatuses = new Set<String>{'Completed', 'Cancelled'};
        List<WorkOrder> activeWorkOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                CaseId,
                Dispatch_Status__c,
                CreatedDate
            FROM WorkOrder
            WHERE CaseId IN :caseIds
                AND (
                    Dispatch_Status__c = null
                    OR Dispatch_Status__c NOT IN :terminalStatuses
                )
            WITH USER_MODE
            ORDER BY CreatedDate DESC, WorkOrderNumber DESC
        ];
        /*
         * MillTrack currently treats one active Work Order as the primary
         * service Work Order for a Case. Salesforce technically permits
         * multiple Work Orders per Case, so if duplicates ever exist this
         * method deterministically exposes the newest active Work Order.
         */
        for (WorkOrder workOrder : activeWorkOrders) {
            if (workOrder.CaseId != null && !workOrderByCaseId.containsKey(workOrder.CaseId)) {
                workOrderByCaseId.put(workOrder.CaseId, workOrder);
            }
        }
        return workOrderByCaseId;
    }
    private static Integer countOpenServiceCases() {
        return [
            SELECT COUNT()
            FROM Case
            WHERE IsClosed = false
            WITH USER_MODE
        ];
    }
    private static Integer countDistinctWorkOrders(List<QueueItem> items) {
        Set<Id> workOrderIds = new Set<Id>();
        if (items == null) return 0;
        for (QueueItem item : items) {
            if (item == null) continue;
            Id workOrderId = item.workOrderId;
            if (workOrderId == null && item.objectApiName == 'WorkOrder') workOrderId = item.recordId;
            if (workOrderId != null) workOrderIds.add(workOrderId);
        }
        return workOrderIds.size();
    }
    // Loads queues that continue to use Work Order rows.
    private static void loadWorkOrderQueues(OperationsData data) {
        Set<String> queueStatuses = new Set<String>{'Pending', 'Parts to Order', 'Ready_to_Assign', 'In Progress', 'Temporary Fix'};
        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, Priority, Dispatch_Status__c, AccountId, Account.Name,
                   AssetId, Asset.Name, Suggested_Technician__c, Suggested_Technician__r.Name,
                   Scheduled_Visit__c, Service_Manager__c, OwnerId, Owner.Name, CreatedDate, LastModifiedDate
            FROM WorkOrder
            WHERE Dispatch_Status__c IN :queueStatuses
            WITH USER_MODE
            ORDER BY LastModifiedDate ASC
            LIMIT :WORK_ORDER_ROW_LIMIT
        ];
        Set<Id> partsToOrderWorkOrderIds = new Set<Id>();
        for (WorkOrder workOrder : workOrders) {
            if (workOrder.Dispatch_Status__c == 'Parts to Order') partsToOrderWorkOrderIds.add(workOrder.Id);
        }
        Map<Id, List<Work_Order_Part__c>> requestedPartsByWorkOrderId = getRequestedPartsByWorkOrderId(partsToOrderWorkOrderIds);
        for (WorkOrder workOrder : workOrders) {
            QueueItem item = toQueueItem(workOrder);
            if (workOrder.Dispatch_Status__c == 'Pending') {
                data.requiresReview.add(item);
            } else if (workOrder.Dispatch_Status__c == 'Temporary Fix') {
                data.followUpRequired.add(item);
            } else if (workOrder.Dispatch_Status__c == 'Parts to Order') {
                applyPartSummary(item, requestedPartsByWorkOrderId.get(workOrder.Id));
                data.partsToOrder.add(item);
            } else if (workOrder.Dispatch_Status__c == 'Ready_to_Assign') {
                data.readyToAssign.add(item);
            } else if (workOrder.Dispatch_Status__c == 'In Progress') {
                data.activeRepairs.add(item);
            }
        }
    }
    private static Map<Id, List<Work_Order_Part__c>> getRequestedPartsByWorkOrderId(Set<Id> workOrderIds) {
        Map<Id, List<Work_Order_Part__c>> partsByWorkOrderId = new Map<Id, List<Work_Order_Part__c>>();
        if (workOrderIds == null || workOrderIds.isEmpty()) return partsByWorkOrderId;
        List<Work_Order_Part__c> requestedParts = [
            SELECT Id, Name, Work_Order__c, Part_Catalog__c, Part_Catalog__r.Name,
                   Part_Catalog__r.Part_Number__c, Quantity__c, Order_Status__c, Technician_Requested__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c IN :workOrderIds
              AND Order_Status__c = 'Requested'
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT :PART_ROW_LIMIT
        ];
        for (Work_Order_Part__c part : requestedParts) {
            if (!partsByWorkOrderId.containsKey(part.Work_Order__c)) {
                partsByWorkOrderId.put(part.Work_Order__c, new List<Work_Order_Part__c>());
            }
            partsByWorkOrderId.get(part.Work_Order__c).add(part);
        }
        return partsByWorkOrderId;
    }
    private static void applyPartSummary(QueueItem item, List<Work_Order_Part__c> requestedParts) {
        Integer partCount = requestedParts == null ? 0 : requestedParts.size();
        item.partRequestCount = partCount;
        item.hasMultipleParts = partCount > 1;
        if (partCount == 0) return;
        if (partCount == 1) {
            Work_Order_Part__c part = requestedParts[0];
            item.partId = part.Id;
            item.partCatalogId = part.Part_Catalog__c;
            item.workOrderPartNumber = part.Name;
            item.partName = part.Part_Catalog__r == null ? part.Name : part.Part_Catalog__r.Name;
            item.partNumber = part.Part_Catalog__r == null ? null : part.Part_Catalog__r.Part_Number__c;
            item.quantity = part.Quantity__c;
            item.quantityNeeded = part.Quantity__c;
            return;
        }
        item.workOrderPartNumber = 'Multiple';
        item.partName = 'Multiple Parts to Order';
        item.partNumber = String.valueOf(partCount) + ' requested parts';
    }
    private static void loadAssignedVisits(OperationsData data) {
        List<WorkOrder> assignedWorkOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                Priority,
                Dispatch_Status__c,
                AccountId,
                Account.Name,
                AssetId,
                Asset.Name,
                Suggested_Technician__c,
                Suggested_Technician__r.Name,
                Scheduled_Visit__c,
                Service_Manager__c,
                OwnerId,
                Owner.Name,
                CreatedDate,
                LastModifiedDate
            FROM WorkOrder
            WHERE Dispatch_Status__c = 'Assigned'
            WITH USER_MODE
            ORDER BY Scheduled_Visit__c ASC NULLS LAST, Priority ASC
            LIMIT :WORK_ORDER_ROW_LIMIT
        ];
        for (WorkOrder workOrder : assignedWorkOrders) data.assignedVisits.add(toQueueItem(workOrder));
    }
    // Loads the actionable Work Order Part queues.
    private static void loadPartQueues(OperationsData data) {
        Set<String> actionableStatuses = new Set<String>{'Requested', 'Ordered', 'Shipped'};
        List<Work_Order_Part__c> parts = [
            SELECT
                Id,
                Name,
                Work_Order__c,
                Work_Order__r.WorkOrderNumber,
                Work_Order__r.Subject,
                Work_Order__r.Priority,
                Work_Order__r.Dispatch_Status__c,
                Work_Order__r.AccountId,
                Work_Order__r.Account.Name,
                Work_Order__r.AssetId,
                Work_Order__r.Asset.Name,
                Work_Order__r.Suggested_Technician__c,
                Work_Order__r.Suggested_Technician__r.Name,
                Work_Order__r.Scheduled_Visit__c,
                Machine__c,
                Machine__r.Name,
                Part_Catalog__c,
                Part_Catalog__r.Name,
                Part_Catalog__r.Part_Number__c,
                Quantity__c,
                Order_Status__c,
                Technician_Requested__c,
                Notes__c,
                Supplier_Name__c,
                Supplier_Phone__c,
                Order_URL__c,
                Ordered_By__c,
                Ordered_By__r.Name,
                CreatedDate,
                LastModifiedDate
            FROM Work_Order_Part__c
            WHERE Order_Status__c IN :actionableStatuses
                AND Work_Order__r.Dispatch_Status__c = 'Waiting on Parts'
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT :PART_ROW_LIMIT
        ];
        for (Work_Order_Part__c part : parts) {
            QueueItem item = toQueueItem(part);
            if (part.Order_Status__c == 'Requested') {
                data.partsToOrder.add(item);
            } else if (part.Order_Status__c == 'Ordered' || part.Order_Status__c == 'Shipped') {
                data.waitingOnParts.add(item);
            }
        }
    }
    private static QueueItem toQueueItem(Case serviceCase) {
        QueueItem item = new QueueItem();
        item.recordId = serviceCase.Id;
        item.actionRecordId = serviceCase.Id;
        item.objectApiName = 'Case';
        item.recordTypeLabel = 'Case';
        item.rowType = 'CASE';
        item.recordNumber = serviceCase.CaseNumber;
        item.subject = String.isBlank(serviceCase.Subject) ? 'Case ' + serviceCase.CaseNumber : serviceCase.Subject;
        item.accountName = serviceCase.Account == null ? null : serviceCase.Account.Name;
        item.assetName = serviceCase.Asset == null ? null : serviceCase.Asset.Name;
        item.priority = serviceCase.Priority;
        item.status = serviceCase.Status;
        item.ownerName = serviceCase.Owner == null ? null : serviceCase.Owner.Name;
        item.createdDate = serviceCase.CreatedDate;
        item.actionType = 'NAVIGATE';
        item.actionName = 'VIEW_CASE';
        item.actionLabel = 'Open Case';
        return item;
    }
    private static QueueItem toQueueItem(WorkOrder workOrder) {
        QueueItem item = new QueueItem();
        item.recordId = workOrder.Id;
        item.actionRecordId = workOrder.Id;
        item.workOrderId = workOrder.Id;
        item.relatedRecordId = workOrder.Id;
        item.objectApiName = 'WorkOrder';
        item.recordTypeLabel = 'Work Order';
        item.rowType = 'WORK_ORDER';
        item.recordNumber = workOrder.WorkOrderNumber;
        item.relatedRecordNumber = workOrder.WorkOrderNumber;
        item.subject = String.isBlank(workOrder.Subject) ? 'Work Order ' + workOrder.WorkOrderNumber : workOrder.Subject;
        item.accountName = workOrder.Account == null ? null : workOrder.Account.Name;
        item.assetName = workOrder.Asset == null ? null : workOrder.Asset.Name;
        item.priority = workOrder.Priority;
        item.status = getDisplayDispatchStatus(workOrder.Dispatch_Status__c);
        item.technicianName = workOrder.Suggested_Technician__r == null ? null : workOrder.Suggested_Technician__r.Name;
        item.ownerName = workOrder.Owner == null ? null : workOrder.Owner.Name;
        item.scheduledVisit = workOrder.Scheduled_Visit__c;
        item.createdDate = workOrder.CreatedDate;
        configureWorkOrderAction(item, workOrder.Dispatch_Status__c);
        return item;
    }
    private static QueueItem toQueueItem(Work_Order_Part__c part) {
        QueueItem item = new QueueItem();
        item.recordId = part.Id;
        item.partId = part.Id;
        item.workOrderId = part.Work_Order__c;
        item.relatedRecordId = part.Work_Order__c;
        item.objectApiName = 'Work_Order_Part__c';
        item.recordTypeLabel = 'Work Order Part';
        item.recordNumber = part.Name;
        item.workOrderPartNumber = part.Name;
        item.partName = part.Part_Catalog__r == null ? part.Name : part.Part_Catalog__r.Name;
        item.partNumber = part.Part_Catalog__r == null ? null : part.Part_Catalog__r.Part_Number__c;
        item.partCatalogId = part.Part_Catalog__c;
        item.partRequestCount = 1;
        item.hasMultipleParts = false;
        item.quantity = part.Quantity__c;
        item.quantityNeeded = part.Quantity__c;
        item.status = part.Order_Status__c;
        item.technicianRequested = part.Technician_Requested__c;
        item.partSourceLabel = part.Technician_Requested__c ? 'Technician Request' : 'Required Part';
        item.notes = part.Notes__c;
        item.supplierName = part.Supplier_Name__c;
        item.supplierPhone = part.Supplier_Phone__c;
        item.orderUrl = part.Order_URL__c;
        item.orderedByName = part.Ordered_By__r == null ? null : part.Ordered_By__r.Name;
        item.createdDate = part.CreatedDate;
        if (part.Work_Order__r != null) {
            item.relatedRecordNumber = part.Work_Order__r.WorkOrderNumber;
            item.workOrderSubject = part.Work_Order__r.Subject;
            item.accountName = part.Work_Order__r.Account == null ? null : part.Work_Order__r.Account.Name;
            item.priority = part.Work_Order__r.Priority;
            item.technicianName = part.Work_Order__r.Suggested_Technician__r == null ? null : part.Work_Order__r.Suggested_Technician__r.Name;
            item.scheduledVisit = part.Work_Order__r.Scheduled_Visit__c;
        }
        /*
         * Prefer the Work Order Part's Machine relationship. Fall back to the
         * parent Work Order's Asset if Machine__c is not populated.
         */
        if (part.Machine__r != null) {
            item.assetName = part.Machine__r.Name;
        } else if (part.Work_Order__r != null && part.Work_Order__r.Asset != null) {
            item.assetName = part.Work_Order__r.Asset.Name;
        }
        configurePartAction(item, part);
        return item;
    }
    private static void configureWorkOrderAction(QueueItem item, String dispatchStatus) {
        if (dispatchStatus == 'Pending') {
            configureLwcAction(item, 'REVIEW_WORK_ORDER', 'Review Work Order', item.workOrderId);
        } else if (dispatchStatus == 'Temporary Fix') {
            configureLwcAction(item, 'FOLLOW_UP_WORK_ORDER', 'Review Follow-Up', item.workOrderId);
        } else if (dispatchStatus == 'Parts to Order') {
            configureLwcAction(item, 'ORDER_REQUIRED_PARTS', 'Order Required Parts', item.workOrderId);
        } else if (dispatchStatus == 'Ready_to_Assign') {
            configureLwcAction(item, 'DISPATCH_TECHNICIAN', 'Dispatch Technician', item.workOrderId);
        } else {
            configureNavigationAction(item, 'VIEW_WORK_ORDER', 'Open Work Order');
        }
    }
    private static void configurePartAction(QueueItem item, Work_Order_Part__c part) {
        if (part.Order_Status__c == 'Requested') {
            item.rowType = 'TECHNICIAN_REQUESTED_PART';
            item.recordTypeLabel = 'Technician Part Request';
            item.subject = 'Requested part: ' + item.partName;
            configureLwcAction(item, 'ORDER_TECHNICIAN_REQUESTED_PART', 'Order Requested Part', part.Id);
        } else if (part.Order_Status__c == 'Ordered' || part.Order_Status__c == 'Shipped') {
            item.rowType = 'ORDERED_PART';
            item.recordTypeLabel = 'Ordered Part';
            item.subject = part.Order_Status__c + ' part: ' + item.partName;
            if (part.Work_Order__c != null) {
                configureLwcAction(item, 'RECEIVE_PARTS', 'Receive Parts', part.Work_Order__c);
            } else {
                configureNavigationAction(item, 'OPEN_PART_REQUEST', 'Open Part');
            }
        } else {
            item.rowType = 'WORK_ORDER_PART';
            item.subject = 'Part: ' + item.partName;
            configureNavigationAction(item, 'OPEN_PART_REQUEST', 'Open Part');
        }
    }
    private static String getDisplayDispatchStatus(String dispatchStatus) {
        return dispatchStatus == STATUS_READY_TO_ASSIGN ? LABEL_READY_TO_ASSIGN : dispatchStatus;
    }
    private static void configureLwcAction(QueueItem item, String actionName, String actionLabel, Id actionRecordId) {
        item.actionType = 'LWC';
        item.actionName = actionName;
        item.actionLabel = actionLabel;
        item.flowApiName = null;
        item.actionRecordId = actionRecordId;
    }
    private static void configureNavigationAction(QueueItem item, String actionName, String actionLabel) {
        item.actionType = 'NAVIGATE';
        item.actionName = actionName;
        item.actionLabel = actionLabel;
        item.actionRecordId = item.recordId;
    }
    public class OperationsData {
        @AuraEnabled public List<QueueItem> newCases { get; set; }
        @AuraEnabled public List<QueueItem> requiresReview { get; set; }
        @AuraEnabled public List<QueueItem> followUpRequired { get; set; }
        @AuraEnabled public List<QueueItem> partsToOrder { get; set; }
        @AuraEnabled public List<QueueItem> waitingOnParts { get; set; }
        @AuraEnabled public List<QueueItem> readyToAssign { get; set; }
        @AuraEnabled public List<QueueItem> assignedVisits { get; set; }
        @AuraEnabled public List<QueueItem> activeRepairs { get; set; }
        @AuraEnabled public Integer openServiceCasesCount { get; set; }
        @AuraEnabled public Integer newCasesCount { get; set; }
        @AuraEnabled public Integer requiresReviewCount { get; set; }
        @AuraEnabled public Integer followUpRequiredCount { get; set; }
        @AuraEnabled public Integer partsToOrderCount { get; set; }
        @AuraEnabled public Integer waitingOnPartsCount { get; set; }
        @AuraEnabled public Integer readyToAssignCount { get; set; }
        @AuraEnabled public Integer assignedVisitsCount { get; set; }
        @AuraEnabled public Integer activeRepairsCount { get; set; }
        @AuraEnabled public Datetime generatedAt { get; set; }
        public OperationsData() {
            newCases = new List<QueueItem>();
            requiresReview = new List<QueueItem>();
            followUpRequired = new List<QueueItem>();
            partsToOrder = new List<QueueItem>();
            waitingOnParts = new List<QueueItem>();
            readyToAssign = new List<QueueItem>();
            assignedVisits = new List<QueueItem>();
            activeRepairs = new List<QueueItem>();
        }
        public void calculateCounts() {
            newCasesCount = newCases.size();
            requiresReviewCount = requiresReview.size();
            followUpRequiredCount = followUpRequired.size();
            /*
             * Parts queues contain Work Order Part rows, so their dashboard
             * counts must represent distinct Work Orders rather than rows.
             */
            partsToOrderCount = ManagerOperationsCenterController.countDistinctWorkOrders(partsToOrder);
            waitingOnPartsCount = ManagerOperationsCenterController.countDistinctWorkOrders(waitingOnParts);
            readyToAssignCount = readyToAssign.size();
            assignedVisitsCount = assignedVisits.size();
            activeRepairsCount = activeRepairs.size();
        }
    }
    public class QueueItem {
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public Id actionRecordId { get; set; }
        @AuraEnabled public Id relatedRecordId { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public Id partId { get; set; }
        @AuraEnabled public Id partCatalogId { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String recordTypeLabel { get; set; }
        @AuraEnabled public String rowType { get; set; }
        @AuraEnabled public String recordNumber { get; set; }
        @AuraEnabled public String relatedRecordNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String workOrderSubject { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String partName { get; set; }
        @AuraEnabled public String partNumber { get; set; }
        @AuraEnabled public String workOrderPartNumber { get; set; }
        @AuraEnabled public Integer partRequestCount { get; set; }
        @AuraEnabled public Boolean hasMultipleParts { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal quantityNeeded { get; set; }
        @AuraEnabled public Boolean technicianRequested { get; set; }
        @AuraEnabled public String partSourceLabel { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public String supplierName { get; set; }
        @AuraEnabled public String supplierPhone { get; set; }
        @AuraEnabled public String orderUrl { get; set; }
        @AuraEnabled public String orderedByName { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String technicianName { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String actionType { get; set; }
        @AuraEnabled public String actionName { get; set; }
        @AuraEnabled public String actionLabel { get; set; }
        @AuraEnabled public String flowApiName { get; set; }
    }
}
