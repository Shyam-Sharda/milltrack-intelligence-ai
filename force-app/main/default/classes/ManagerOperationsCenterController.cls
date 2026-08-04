/**
 * Data controller for the Manager Operations Center Lightning Web Component.
 *
 * The controller is intentionally read-only. Manager actions are performed by
 * existing Screen Flows launched by the LWC.
 */
public with sharing class ManagerOperationsCenterController {

    private static final Integer CASE_ROW_LIMIT = 200;
    private static final Integer WORK_ORDER_ROW_LIMIT = 500;
    private static final Integer PART_ROW_LIMIT = 300;

    private static final String FLOW_REVIEW_WORK_ORDER = 'Generate_Work_Order_Proposal_From_Case';
    private static final String FLOW_ORDER_PARTS = 'X13_Order_Parts_From_Work_Order';
    private static final String FLOW_ORDER_TECHNICIAN_REQUESTED_PART = 'Order_Technician_Requested_Part';
    private static final String FLOW_RECEIVE_PARTS = 'Receive_Parts_From_Work_Order';
    private static final String FLOW_DISPATCH_TECHNICIAN = 'Dispatch_Technician';

    private static final String STATUS_READY_TO_ASSIGN = 'Ready_to_Assign';
    private static final String LABEL_READY_TO_ASSIGN = 'Ready to Assign';

    //Returns all Manager Operations Center queues in one cacheable response.
    @AuraEnabled(cacheable=true)
    public static OperationsData getOperationsData() {
        try {
            OperationsData data = new OperationsData();

            loadNewCases(data);
            loadWorkOrderQueues(data);
            loadAssignedVisits(data);
            loadPartQueues(data);

            data.calculateCounts();
            data.generatedAt = System.now();

            return data;
        } catch (Exception ex) {
            throw new AuraHandledException(
                'The Manager Operations Center could not be loaded. ' + 'Confirm that the Service Manager permission set provides ' +
                'access to the required Case, Work Order, Work Order Part, ' + 'Account, Asset, Part Catalog, and User fields.');
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

        for (Case serviceCase : cases) {
            data.newCases.add(toQueueItem(serviceCase));
        }
    }

    //Loads queues that continue to use Work Order rows.  
    private static void loadWorkOrderQueues(OperationsData data) {
        Set<String> queueStatuses = new Set<String>{'Pending', 'Parts to Order', 'Ready_to_Assign', 'In Progress', 'Temporary Fix'};

        List<WorkOrder> workOrders = [
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
            WHERE Dispatch_Status__c IN :queueStatuses
            WITH USER_MODE
            ORDER BY LastModifiedDate ASC
            LIMIT :WORK_ORDER_ROW_LIMIT
        ];

        for (WorkOrder workOrder : workOrders) {
            QueueItem item = toQueueItem(workOrder);

            if (workOrder.Dispatch_Status__c == 'Pending') {
                data.requiresReview.add(item);
            } else if (workOrder.Dispatch_Status__c == 'Parts to Order') {
                data.partsToOrder.add(item);
            } else if (workOrder.Dispatch_Status__c == 'Ready_to_Assign') {
                data.readyToAssign.add(item);
            } else if (workOrder.Dispatch_Status__c == 'In Progress' || workOrder.Dispatch_Status__c == 'Temporary Fix') {
                data.activeRepairs.add(item);
            }
        }
    }

    private static void loadAssignedVisits(OperationsData data) {
        Datetime currentMoment = System.now();

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
            WHERE Dispatch_Status__c = 'Assigned' AND Scheduled_Visit__c >= :currentMoment
            WITH USER_MODE
            ORDER BY Scheduled_Visit__c ASC, Priority ASC
            LIMIT :WORK_ORDER_ROW_LIMIT
        ];

        for (WorkOrder workOrder : assignedWorkOrders) {
            data.assignedVisits.add(toQueueItem(workOrder));
        }
    }

    //Loads the actionable Work Order Part queues.
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
                Quantity__c,
                Order_Status__c,
                Notes__c,
                Supplier_Name__c,
                Supplier_Phone__c,
                Order_URL__c,
                Ordered_By__c,
                Ordered_By__r.Name,
                CreatedDate,
                LastModifiedDate
            FROM Work_Order_Part__c
            WHERE Order_Status__c IN :actionableStatuses AND Work_Order__r.Dispatch_Status__c = 'Waiting on Parts'
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
        item.accountName = serviceCase.Account == null? null : serviceCase.Account.Name;
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
        item.partName = part.Part_Catalog__r == null ? part.Name : part.Part_Catalog__r.Name;
        item.partCatalogId = part.Part_Catalog__c;
        item.quantity = part.Quantity__c;
        item.quantityNeeded = part.Quantity__c;
        item.status = part.Order_Status__c;
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
            configureFlowAction(item, 'REVIEW_WORK_ORDER', 'Review Work Order', FLOW_REVIEW_WORK_ORDER, item.workOrderId);
        } else if (dispatchStatus == 'Parts to Order') {
            configureFlowAction(item, 'ORDER_REQUIRED_PARTS', 'Order Required Parts', FLOW_ORDER_PARTS, item.workOrderId);
        } else if (dispatchStatus == 'Ready_to_Assign') {
            configureFlowAction(item, 'DISPATCH_TECHNICIAN', 'Dispatch Technician', FLOW_DISPATCH_TECHNICIAN, item.workOrderId);
        } else {
            configureNavigationAction(item, 'VIEW_WORK_ORDER', 'Open Work Order');
        }
    }

    private static void configurePartAction(QueueItem item, Work_Order_Part__c part) {
        if (part.Order_Status__c == 'Requested') {
            item.rowType = 'TECHNICIAN_REQUESTED_PART';
            item.recordTypeLabel = 'Technician Part Request';
            item.subject = 'Requested part: ' + item.partName;

            configureFlowAction(item,
                'ORDER_TECHNICIAN_REQUESTED_PART',
                'Order Requested Part',
                FLOW_ORDER_TECHNICIAN_REQUESTED_PART,
                part.Id
            );
        } else if (part.Order_Status__c == 'Ordered' || part.Order_Status__c == 'Shipped') {
            item.rowType = 'ORDERED_PART';
            item.recordTypeLabel = 'Ordered Part';
            item.subject = part.Order_Status__c + ' part: ' + item.partName;

            if (part.Work_Order__c != null) {
                configureFlowAction(item, 'RECEIVE_PARTS', 'Receive Parts', FLOW_RECEIVE_PARTS, part.Work_Order__c);
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

    private static void configureFlowAction(QueueItem item, String actionName, String actionLabel, String flowApiName, Id actionRecordId) {
        item.actionType = 'FLOW';
        item.actionName = actionName;
        item.actionLabel = actionLabel;
        item.flowApiName = flowApiName;
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
        @AuraEnabled public List<QueueItem> partsToOrder { get; set; }
        @AuraEnabled public List<QueueItem> waitingOnParts { get; set; }
        @AuraEnabled public List<QueueItem> readyToAssign { get; set; }
        @AuraEnabled public List<QueueItem> assignedVisits { get; set; }
        @AuraEnabled public List<QueueItem> activeRepairs { get; set; }

        @AuraEnabled public Integer newCasesCount { get; set; }
        @AuraEnabled public Integer requiresReviewCount { get; set; }
        @AuraEnabled public Integer partsToOrderCount { get; set; }
        @AuraEnabled public Integer waitingOnPartsCount { get; set; }
        @AuraEnabled public Integer readyToAssignCount { get; set; }
        @AuraEnabled public Integer assignedVisitsCount { get; set; }
        @AuraEnabled public Integer activeRepairsCount { get; set; }

        @AuraEnabled public Datetime generatedAt { get; set; }

        public OperationsData() {
            newCases = new List<QueueItem>();
            requiresReview = new List<QueueItem>();
            partsToOrder = new List<QueueItem>();
            waitingOnParts = new List<QueueItem>();
            readyToAssign = new List<QueueItem>();
            assignedVisits = new List<QueueItem>();
            activeRepairs = new List<QueueItem>();
        }

        public void calculateCounts() {
            newCasesCount = newCases.size();
            requiresReviewCount = requiresReview.size();
            partsToOrderCount = partsToOrder.size();
            waitingOnPartsCount = waitingOnParts.size();
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
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal quantityNeeded { get; set; }
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