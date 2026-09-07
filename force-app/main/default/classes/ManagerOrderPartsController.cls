public with sharing class ManagerOrderPartsController {

    // =========================================================
    // READ DTOs
    // =========================================================

    public class OrderPartsContext {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public Boolean isEligible { get; set; }
        @AuraEnabled public String eligibilityMessage { get; set; }
        @AuraEnabled public Integer requestedPartCount { get; set; }
        @AuraEnabled public Decimal requestedUnitCount { get; set; }

        /*
         * Parts already beyond Requested that still belong to
         * the active parts lifecycle for this Work Order.
         *
         * Examples:
         * Ordered, Shipped, Received, Installed.
         *
         * These matter when previewing the final outcome before
         * the manager commits the current wizard decisions.
         */
        @AuraEnabled public Boolean hasExistingCommittedParts { get; set; }
        @AuraEnabled public Integer existingCommittedPartCount { get; set; }
        @AuraEnabled public List<RequestedPartRow> requestedParts { get; set; }

        public OrderPartsContext() {
            isEligible = false;
            requestedPartCount = 0;
            requestedUnitCount = 0;
            hasExistingCommittedParts = false;
            existingCommittedPartCount = 0;
            requestedParts = new List<RequestedPartRow>();
        }
    }

    public class RequestedPartRow {
        @AuraEnabled public Id workOrderPartId { get; set; }
        @AuraEnabled public Id partCatalogId { get; set; }
        @AuraEnabled public String partName { get; set; }
        @AuraEnabled public String partNumber { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public String supplierName { get; set; }
        @AuraEnabled public String supplierPhone { get; set; }
        @AuraEnabled public String orderUrl { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public String orderStatus { get; set; }
    }

    // =========================================================
    // SAVE DTOs
    // =========================================================

    public class PartOrderDecision {
        @AuraEnabled public Id workOrderPartId { get; set; }

        /*
         * Step 1:
         * true  = part is still required
         * false = manager removed it from the requirement
         */
        @AuraEnabled public Boolean keepRequired { get; set; }

        /*
         * Step 2:
         * true  = manager confirms the supplier order was placed
         * false = part is still required but has not yet been ordered
         */
        @AuraEnabled public Boolean orderConfirmed { get; set; }
    }

    public class SaveOrderPartsResult {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String workOrderStatus { get; set; }
        @AuraEnabled public String assetStatus { get; set; }
        @AuraEnabled public Boolean allOrderingComplete { get; set; }
        @AuraEnabled public Boolean readyToAssign { get; set; }
        @AuraEnabled public Integer orderedPartCount { get; set; }
        @AuraEnabled public Integer remainingPartCount { get; set; }
        @AuraEnabled public Integer cancelledPartCount { get; set; }
        @AuraEnabled public List<RequestedPartRow> orderedParts { get; set; }
        @AuraEnabled public List<RequestedPartRow> remainingRequestedParts { get; set; }
        @AuraEnabled public List<RequestedPartRow> cancelledParts { get; set; }
        @AuraEnabled public String nextStepLabel { get; set; }
        @AuraEnabled public String nextStepMessage { get; set; }

        public SaveOrderPartsResult() {
            allOrderingComplete = false;
            readyToAssign = false;
            orderedPartCount = 0;
            remainingPartCount = 0;
            cancelledPartCount = 0;
            orderedParts = new List<RequestedPartRow>();
            remainingRequestedParts = new List<RequestedPartRow>();
            cancelledParts = new List<RequestedPartRow>();
        }
    }

    // =========================================================
    // TECHNICIAN-REQUESTED PART DTOs
    // =========================================================

    public class TechnicianRequestedPartContext {
        @AuraEnabled public Id workOrderPartId { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public Boolean isEligible { get; set; }
        @AuraEnabled public String eligibilityMessage { get; set; }
        @AuraEnabled public RequestedPartRow requestedPart { get; set; }

        public TechnicianRequestedPartContext() {
            isEligible = false;
        }
    }

    public class TechnicianRequestedPartResult {
        @AuraEnabled public Id workOrderPartId { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String workOrderStatus { get; set; }
        @AuraEnabled public String partName { get; set; }
        @AuraEnabled public String partNumber { get; set; }
        @AuraEnabled public String orderStatus { get; set; }
        @AuraEnabled public String supplierName { get; set; }
        @AuraEnabled public String supplierPhone { get; set; }
        @AuraEnabled public String orderUrl { get; set; }
        @AuraEnabled public String nextStepLabel { get; set; }
        @AuraEnabled public String nextStepMessage { get; set; }
    }

    // =========================================================
    // READ
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static OrderPartsContext getOrderPartsContext(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException(
                'A Work Order Id is required to load parts ordering.'
            );
        }

        List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Dispatch_Status__c,
                AssetId,
                Asset.Name
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            throw new AuraHandledException(
                'The Work Order could not be found or you do not have access to it.'
            );
        }

        WorkOrder workOrderRecord = workOrders[0];
        OrderPartsContext context = new OrderPartsContext();
        context.workOrderId = workOrderRecord.Id;
        context.workOrderNumber = workOrderRecord.WorkOrderNumber;
        context.dispatchStatus = workOrderRecord.Dispatch_Status__c;
        context.assetId = workOrderRecord.AssetId;

        context.assetName =
            workOrderRecord.Asset != null
                ? workOrderRecord.Asset.Name
                : null;

        context.isEligible =
            workOrderRecord.Dispatch_Status__c == 'Parts to Order';

        if (!context.isEligible) {
            context.eligibilityMessage =
                'Parts ordering is only available while the Work Order is in Parts to Order. ' +
                'Current status: ' +
                (
                    String.isBlank(
                        workOrderRecord.Dispatch_Status__c
                    )
                        ? 'Not Set'
                        : workOrderRecord.Dispatch_Status__c
                );

            return context;
        }

        // =====================================================
        // CURRENT REQUESTED PARTS
        // =====================================================

        List<Work_Order_Part__c> requestedParts = [
            SELECT
                Id,
                Part_Catalog__c,
                Quantity__c,
                Notes__c,
                Order_Status__c,
                Supplier_Name__c,
                Supplier_Phone__c,
                Order_URL__c,
                Part_Catalog__r.Name,
                Part_Catalog__r.Part_Number__c,
                Part_Catalog__r.Parts_Category__c,
                Part_Catalog__r.Supplier_Name__c,
                Part_Catalog__r.Supplier_Phone__c,
                Part_Catalog__r.Order_URL__c
            FROM Work_Order_Part__c
            WHERE
                Work_Order__c =
                    :workOrderRecord.Id
                AND Order_Status__c =
                    'Requested'
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];

        Decimal totalUnits = 0;

        for (
            Work_Order_Part__c partRecord :
            requestedParts
        ) {
            RequestedPartRow row = buildPartRow(partRecord);

            totalUnits += row.quantity;

            context.requestedParts.add(
                row
            );
        }

        context.requestedPartCount = context.requestedParts.size();
        context.requestedUnitCount = totalUnits;

        // =====================================================
        // EXISTING COMMITTED PART LIFECYCLE
        //
        // These are records already beyond Requested that are
        // still part of the Work Order's parts history.
        //
        // This is used by the LWC only to PREVIEW the correct
        // next workflow state before final save.
        // =====================================================

        Integer existingCommittedPartCount = [
            SELECT COUNT()
            FROM Work_Order_Part__c
            WHERE
                Work_Order__c =
                    :workOrderRecord.Id
                AND Order_Status__c NOT IN (
                    'Requested',
                    'Cancelled'
                )
            WITH USER_MODE
        ];

        context.existingCommittedPartCount = existingCommittedPartCount;
        context.hasExistingCommittedParts = existingCommittedPartCount > 0;

        if (
            context.requestedParts.isEmpty()
        ) {
            context.eligibilityMessage = 'This Work Order is in Parts to Order, but it has no Requested parts remaining.';
        }

        return context;
    }

    @AuraEnabled(cacheable=true)
    public static TechnicianRequestedPartContext getTechnicianRequestedPartContext(Id workOrderPartId) {
        if (workOrderPartId == null) throw new AuraHandledException('A Work Order Part Id is required.');

        List<Work_Order_Part__c> parts = [
            SELECT Id, Work_Order__c, Work_Order__r.WorkOrderNumber, Work_Order__r.Dispatch_Status__c,
                Work_Order__r.AccountId, Work_Order__r.Account.Name, Work_Order__r.AssetId, Work_Order__r.Asset.Name,
                Part_Catalog__c, Quantity__c, Notes__c, Order_Status__c, Supplier_Name__c, Supplier_Phone__c, Order_URL__c,
                Part_Catalog__r.Name, Part_Catalog__r.Part_Number__c, Part_Catalog__r.Parts_Category__c,
                Part_Catalog__r.Supplier_Name__c, Part_Catalog__r.Supplier_Phone__c, Part_Catalog__r.Order_URL__c
            FROM Work_Order_Part__c
            WHERE Id = :workOrderPartId
            WITH USER_MODE
            LIMIT 1
        ];

        if (parts.isEmpty()) throw new AuraHandledException('The Work Order Part could not be found or you do not have access to it.');

        Work_Order_Part__c partRecord = parts[0];
        TechnicianRequestedPartContext context = new TechnicianRequestedPartContext();
        context.workOrderPartId = partRecord.Id;
        context.workOrderId = partRecord.Work_Order__c;
        context.workOrderNumber = partRecord.Work_Order__r != null ? partRecord.Work_Order__r.WorkOrderNumber : null;
        context.dispatchStatus = partRecord.Work_Order__r != null ? partRecord.Work_Order__r.Dispatch_Status__c : null;
        context.accountId = partRecord.Work_Order__r != null ? partRecord.Work_Order__r.AccountId : null;
        context.accountName = partRecord.Work_Order__r != null && partRecord.Work_Order__r.Account != null ? partRecord.Work_Order__r.Account.Name : null;
        context.assetId = partRecord.Work_Order__r != null ? partRecord.Work_Order__r.AssetId : null;
        context.assetName = partRecord.Work_Order__r != null && partRecord.Work_Order__r.Asset != null ? partRecord.Work_Order__r.Asset.Name : null;
        context.requestedPart = buildPartRow(partRecord);
        context.isEligible = partRecord.Order_Status__c == 'Requested' && context.dispatchStatus == 'Waiting on Parts';

        if (!context.isEligible) {
            String partStatus = String.isBlank(partRecord.Order_Status__c) ? 'Not Set' : partRecord.Order_Status__c;
            String workOrderStatus = String.isBlank(context.dispatchStatus) ? 'Not Set' : context.dispatchStatus;
            context.eligibilityMessage = 'This action requires a Requested Work Order Part whose Work Order is Waiting on Parts. Part status: ' +
                partStatus + '. Work Order status: ' + workOrderStatus + '.';
        }

        return context;
    }

    // =========================================================
    // SAVE
    // =========================================================

    @AuraEnabled
    public static SaveOrderPartsResult saveOrderingDecisions(Id workOrderId, List<PartOrderDecision> decisions) {
        if (workOrderId == null) {
            throw new AuraHandledException(
                'A Work Order Id is required.'
            );
        }

        if (decisions == null) {
            throw new AuraHandledException(
                'Parts ordering decisions are required.'
            );
        }

        Savepoint sp = Database.setSavepoint();

        try {

            // -------------------------------------------------
            // 1. Re-read and validate Work Order
            // -------------------------------------------------

            List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Dispatch_Status__c,
                AssetId,
                Asset.Machine_Status__c,
                CaseId
                FROM WorkOrder
                WHERE Id = :workOrderId
                WITH USER_MODE
                LIMIT 1
            ];

            if (workOrders.isEmpty()) {
                throw new AuraHandledException(
                    'The Work Order could not be found or you do not have access to it.'
                );
            }

            WorkOrder workOrderRecord = workOrders[0];

            if (
                workOrderRecord.Dispatch_Status__c !=
                'Parts to Order'
            ) {
                throw new AuraHandledException(
                    'This Work Order is no longer available for parts ordering. ' +
                    'Current status: ' +
                    workOrderRecord.Dispatch_Status__c
                );
            }

            // -------------------------------------------------
            // 2. Load the CURRENT Requested records
            // -------------------------------------------------

            List<Work_Order_Part__c> requestedParts = [
                SELECT
                    Id,
                    Work_Order__c,
                    Part_Catalog__c,
                    Quantity__c,
                    Notes__c,
                    Order_Status__c,
                    Ordered_By__c,
                    Supplier_Name__c,
                    Supplier_Phone__c,
                    Order_URL__c,
                    Part_Catalog__r.Name,
                    Part_Catalog__r.Part_Number__c,
                    Part_Catalog__r.Parts_Category__c,
                    Part_Catalog__r.Supplier_Name__c,
                    Part_Catalog__r.Supplier_Phone__c,
                    Part_Catalog__r.Order_URL__c
                FROM Work_Order_Part__c
                WHERE
                    Work_Order__c =
                        :workOrderRecord.Id
                    AND Order_Status__c =
                        'Requested'
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            if (requestedParts.isEmpty()) {
                throw new AuraHandledException(
                    'There are no Requested parts remaining on this Work Order.'
                );
            }

            // -------------------------------------------------
            // 3. Validate incoming decisions
            // -------------------------------------------------

            Map<Id, PartOrderDecision> decisionByPartId = new Map<Id, PartOrderDecision>();

            for (
                PartOrderDecision decision :
                decisions
            ) {
                if (
                    decision == null ||
                    decision.workOrderPartId == null
                ) {
                    throw new AuraHandledException(
                        'Every ordering decision must identify a Work Order Part.'
                    );
                }

                if (
                    decisionByPartId.containsKey(
                        decision.workOrderPartId
                    )
                ) {
                    throw new AuraHandledException(
                        'The same Work Order Part was submitted more than once.'
                    );
                }

                if (
                    decision.keepRequired != true &&
                    decision.orderConfirmed == true
                ) {
                    throw new AuraHandledException(
                        'A removed part cannot also be confirmed as ordered.'
                    );
                }

                decisionByPartId.put(
                    decision.workOrderPartId,
                    decision
                );
            }

            Set<Id> currentRequestedIds = new Set<Id>();

            for (
                Work_Order_Part__c partRecord :
                requestedParts
            ) {
                currentRequestedIds.add(
                    partRecord.Id
                );
            }

            /*
             * Require the UI to submit a decision for every record
             * that is currently Requested.
             *
             * This prevents a stale browser window from silently
             * overwriting changes made elsewhere.
             */
            if (
                decisionByPartId.keySet() !=
                currentRequestedIds
            ) {
                throw new AuraHandledException(
                    'The Requested parts changed while this wizard was open. ' +
                    'Refresh the wizard and review the current parts before saving.'
                );
            }

            // -------------------------------------------------
            // 4. Apply manager decisions
            // -------------------------------------------------

            List<Work_Order_Part__c> partsToUpdate = new List<Work_Order_Part__c>();
            SaveOrderPartsResult result = new SaveOrderPartsResult();
            result.workOrderId = workOrderRecord.Id;
            result.workOrderNumber = workOrderRecord.WorkOrderNumber;

            for (
                Work_Order_Part__c partRecord :
                requestedParts
            ) {
                PartOrderDecision decision =
                    decisionByPartId.get(
                        partRecord.Id
                    );

                Boolean keepRequired = decision.keepRequired == true;
                Boolean orderConfirmed = decision.orderConfirmed == true;

                // ---------------------------------------------
                // Removed during Step 1
                // ---------------------------------------------

                if (!keepRequired) {
                    partRecord.Order_Status__c = 'Cancelled';
                    partRecord.Ordered_By__c = null;

                    partsToUpdate.add(
                        partRecord
                    );

                    RequestedPartRow cancelledRow =
                        buildPartRow(
                            partRecord
                        );

                    result.cancelledParts.add(
                        cancelledRow
                    );

                    continue;
                }

                // ---------------------------------------------
                // Still required + manager confirmed ordering
                // ---------------------------------------------

                if (orderConfirmed) {
                    partRecord.Order_Status__c = 'Ordered';
                    partRecord.Ordered_By__c = UserInfo.getUserId();

                    /*
                     * Snapshot the supplier/order information onto
                     * the Work Order Part at the time of ordering.
                     *
                     * The Part Catalog remains the source for the
                     * ordering contact details, while the Work Order
                     * Part becomes the historical transaction record.
                     */
                    if (
                        partRecord.Part_Catalog__r !=
                        null
                    ) {
                        partRecord.Supplier_Name__c =
                            partRecord
                                .Part_Catalog__r
                                .Supplier_Name__c;

                        partRecord.Supplier_Phone__c =
                            partRecord
                                .Part_Catalog__r
                                .Supplier_Phone__c;

                        partRecord.Order_URL__c =
                            partRecord
                                .Part_Catalog__r
                                .Order_URL__c;
                    }

                    partsToUpdate.add(
                        partRecord
                    );

                    RequestedPartRow orderedRow =
                        buildPartRow(
                            partRecord
                        );

                    result.orderedParts.add(
                        orderedRow
                    );

                    continue;
                }

                // ---------------------------------------------
                // Still required, but not ordered yet
                // ---------------------------------------------

                RequestedPartRow remainingRow =
                    buildPartRow(
                        partRecord
                    );

                result.remainingRequestedParts.add(
                    remainingRow
                );
            }

            // -------------------------------------------------
            // 5. Save changed Work Order Parts
            // -------------------------------------------------

            if (
                !partsToUpdate.isEmpty()
            ) {
                Database.update(
                    partsToUpdate,
                    AccessLevel.USER_MODE
                );
            }

            // -------------------------------------------------
            // 6. Re-check COMPLETE Work Order Part state
            //
            // Important for subsequent partial-order sessions.
            // -------------------------------------------------

            List<Work_Order_Part__c> allWorkOrderParts = [
                SELECT
                    Id,
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE
                    Work_Order__c =
                        :workOrderRecord.Id
                WITH USER_MODE
            ];

            Boolean hasRequested = false;
            Boolean hasNonCancelledPart = false;

            for (
                Work_Order_Part__c existingPart :
                allWorkOrderParts
            ) {
                if (
                    existingPart.Order_Status__c ==
                    'Requested'
                ) {
                    hasRequested = true;
                }

                if (
                    existingPart.Order_Status__c !=
                    'Cancelled'
                ) {
                    hasNonCancelledPart = true;
                }
            }

            // -------------------------------------------------
            // 7. Determine next workflow state
            // -------------------------------------------------

            WorkOrder workOrderUpdate =
                new WorkOrder(
                    Id = workOrderRecord.Id
                );

            String nextCaseStatus;

            result.assetStatus =
                workOrderRecord.AssetId == null ||
                workOrderRecord.Asset == null
                    ? null
                    : workOrderRecord.Asset.Machine_Status__c;

            if (hasRequested) {

                /*
                * Partial ordering.
                *
                * At least one required part still needs to be
                * ordered, so manager work remains active.
                */

                workOrderUpdate.Dispatch_Status__c = 'Parts to Order';
                nextCaseStatus = 'In Progress';
                result.workOrderStatus = 'Parts to Order';
                result.allOrderingComplete = false;
                result.readyToAssign = false;
                result.nextStepLabel = 'Complete Remaining Parts Orders';

                result.nextStepMessage =
                    'One or more required parts still need to be ordered. ' +
                    'This Work Order remains in Parts to Order.';

            } else if (hasNonCancelledPart) {

                /*
                * Every required part has moved beyond Requested
                * and at least one real part remains in the lifecycle.
                *
                * The service is now genuinely waiting on delivery.
                */

                workOrderUpdate.Dispatch_Status__c = 'Waiting on Parts';
                nextCaseStatus = 'Waiting on Parts';
                result.workOrderStatus = 'Waiting on Parts';
                result.allOrderingComplete = true;
                result.readyToAssign = false;
                result.nextStepLabel = 'Waiting on Parts';

                result.nextStepMessage =
                    'All currently required parts have been ordered. ' +
                    'The Work Order is now waiting for parts to arrive.';

            } else {

                /*
                * Every requested part was removed and there are
                * no committed parts remaining.
                *
                * Nothing is blocking technician assignment.
                */

                workOrderUpdate.Dispatch_Status__c = 'Ready_to_Assign';
                nextCaseStatus = 'In Progress';
                result.workOrderStatus = 'Ready_to_Assign';
                result.allOrderingComplete = true;
                result.readyToAssign = true;
                result.nextStepLabel = 'Assign a Technician';

                result.nextStepMessage =
                    'No parts remain required for this repair. ' +
                    'The Work Order is ready for technician assignment.';
            }

            // -------------------------------------------------
            // 8. Save Work Order / Case lifecycle
            // -------------------------------------------------

            Database.update(
                workOrderUpdate,
                AccessLevel.USER_MODE
            );

            if (workOrderRecord.CaseId != null) {

                Case caseUpdate =
                    new Case(
                        Id = workOrderRecord.CaseId,
                        Status = nextCaseStatus
                    );

                Database.update(
                    caseUpdate,
                    AccessLevel.USER_MODE
                );
            }

            // -------------------------------------------------
            // 9. Final summary counts
            // -------------------------------------------------

            result.orderedPartCount = result.orderedParts.size();

            result.remainingPartCount =
                result
                    .remainingRequestedParts
                    .size();

            result.cancelledPartCount = result.cancelledParts.size();

            return result;
        }
        catch (Exception e) {

            Database.rollback(sp);

            throw new AuraHandledException(
                e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static TechnicianRequestedPartResult orderTechnicianRequestedPart(Id workOrderPartId, String supplierName, String supplierPhone, String orderUrl) {
        if (workOrderPartId == null) throw new AuraHandledException('A Work Order Part Id is required.');
        if (String.isBlank(supplierName)) throw new AuraHandledException('Supplier Name is required.');
        if (String.isBlank(supplierPhone)) throw new AuraHandledException('Supplier Phone is required.');
        if (String.isBlank(orderUrl)) throw new AuraHandledException('Supplier Order URL is required.');

        Savepoint sp = Database.setSavepoint();

        try {
            List<Work_Order_Part__c> parts = [
                SELECT Id, Work_Order__c, Work_Order__r.WorkOrderNumber, Work_Order__r.Dispatch_Status__c,
                    Part_Catalog__c, Quantity__c, Notes__c, Order_Status__c, Ordered_By__c,
                    Supplier_Name__c, Supplier_Phone__c, Order_URL__c,
                    Part_Catalog__r.Name, Part_Catalog__r.Part_Number__c, Part_Catalog__r.Parts_Category__c,
                    Part_Catalog__r.Supplier_Name__c, Part_Catalog__r.Supplier_Phone__c, Part_Catalog__r.Order_URL__c
                FROM Work_Order_Part__c
                WHERE Id = :workOrderPartId
                WITH USER_MODE
                LIMIT 1
            ];

            if (parts.isEmpty()) throw new AuraHandledException('The Work Order Part could not be found or you do not have access to it.');

            Work_Order_Part__c partRecord = parts[0];
            if (partRecord.Order_Status__c != 'Requested') {
                throw new AuraHandledException('This Work Order Part is no longer available for ordering. Current part status: ' + partRecord.Order_Status__c + '.');
            }

            String workOrderStatus = partRecord.Work_Order__r != null ? partRecord.Work_Order__r.Dispatch_Status__c : null;
            if (workOrderStatus != 'Waiting on Parts') {
                throw new AuraHandledException('Technician-requested parts can only be ordered while the Work Order is Waiting on Parts. Current Work Order status: ' +
                    (String.isBlank(workOrderStatus) ? 'Not Set' : workOrderStatus) + '.');
            }

            partRecord.Order_Status__c = 'Ordered';
            partRecord.Ordered_By__c = UserInfo.getUserId();
            partRecord.Supplier_Name__c = supplierName.trim();
            partRecord.Supplier_Phone__c = supplierPhone.trim();
            partRecord.Order_URL__c = orderUrl.trim();
            Database.update(partRecord, AccessLevel.USER_MODE);

            TechnicianRequestedPartResult result = new TechnicianRequestedPartResult();
            result.workOrderPartId = partRecord.Id;
            result.workOrderId = partRecord.Work_Order__c;
            result.workOrderNumber = partRecord.Work_Order__r != null ? partRecord.Work_Order__r.WorkOrderNumber : null;
            result.workOrderStatus = workOrderStatus;
            result.partName = partRecord.Part_Catalog__r != null ? partRecord.Part_Catalog__r.Name : null;
            result.partNumber = partRecord.Part_Catalog__r != null ? partRecord.Part_Catalog__r.Part_Number__c : null;
            result.orderStatus = partRecord.Order_Status__c;
            result.supplierName = partRecord.Supplier_Name__c;
            result.supplierPhone = partRecord.Supplier_Phone__c;
            result.orderUrl = partRecord.Order_URL__c;
            result.nextStepLabel = 'Wait for Part Delivery';
            result.nextStepMessage = 'The technician-requested part has been recorded as Ordered. The Work Order remains Waiting on Parts until the required part is received.';
            return result;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================
    // HELPERS
    // =========================================================

    private static RequestedPartRow buildPartRow(Work_Order_Part__c partRecord) {
        RequestedPartRow row = new RequestedPartRow();
        row.workOrderPartId = partRecord.Id;
        row.partCatalogId = partRecord.Part_Catalog__c;

        row.quantity =
            partRecord.Quantity__c == null
                ? 0
                : partRecord.Quantity__c;

        row.notes = partRecord.Notes__c;
        row.orderStatus = partRecord.Order_Status__c;

        if (
            partRecord.Part_Catalog__r != null
        ) {
            row.partName = partRecord.Part_Catalog__r.Name;

            row.partNumber =
                partRecord
                    .Part_Catalog__r
                    .Part_Number__c;

            row.category =
                partRecord
                    .Part_Catalog__r
                    .Parts_Category__c;
        }

        row.supplierName =
            String.isNotBlank(
                partRecord.Supplier_Name__c
            )
                ? partRecord.Supplier_Name__c
                : (
                    partRecord.Part_Catalog__r !=
                    null
                        ? partRecord
                            .Part_Catalog__r
                            .Supplier_Name__c
                        : null
                );

        row.supplierPhone =
            String.isNotBlank(
                partRecord.Supplier_Phone__c
            )
                ? partRecord.Supplier_Phone__c
                : (
                    partRecord.Part_Catalog__r !=
                    null
                        ? partRecord
                            .Part_Catalog__r
                            .Supplier_Phone__c
                        : null
                );

        row.orderUrl =
            String.isNotBlank(
                partRecord.Order_URL__c
            )
                ? partRecord.Order_URL__c
                : (
                    partRecord.Part_Catalog__r !=
                    null
                        ? partRecord
                            .Part_Catalog__r
                            .Order_URL__c
                        : null
                );

        return row;
    }
}
