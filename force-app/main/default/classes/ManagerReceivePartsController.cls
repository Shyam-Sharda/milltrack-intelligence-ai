public with sharing class ManagerReceivePartsController {

    private static final String STATUS_WAITING_ON_PARTS = 'Waiting on Parts';
    private static final String STATUS_READY_TO_ASSIGN = 'Ready_to_Assign';
    private static final String CASE_STATUS_IN_PROGRESS = 'In Progress';

    private static final String PART_REQUESTED = 'Requested';
    private static final String PART_ORDERED = 'Ordered';
    private static final String PART_SHIPPED = 'Shipped';
    private static final String PART_RECEIVED = 'Received';

    private static final Set<String> RECEIVABLE_STATUSES =
        new Set<String>{ PART_ORDERED, PART_SHIPPED };

    private static final Set<String> OUTSTANDING_STATUSES =
        new Set<String>{ PART_REQUESTED, PART_ORDERED, PART_SHIPPED };


    // =========================================================
    // READ CONTEXT
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static ReceivePartsContext getReceivePartsContext(Id workOrderId) {

        if (workOrderId == null) {
            throw handledException(
                'A Work Order Id is required.'
            );
        }

        List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                Dispatch_Status__c,
                AssetId,
                Asset.Name,
                Asset.Machine_Status__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            throw handledException(
                'The Work Order could not be found.'
            );
        }

        WorkOrder workOrderRecord =
            workOrders[0];

        ReceivePartsContext context =
            new ReceivePartsContext();

        context.workOrderId =
            workOrderRecord.Id;

        context.workOrderNumber =
            workOrderRecord.WorkOrderNumber;

        context.subject =
            workOrderRecord.Subject;

        context.dispatchStatus =
            workOrderRecord.Dispatch_Status__c;

        context.assetId =
            workOrderRecord.AssetId;

        context.assetName =
            workOrderRecord.AssetId == null
                ? null
                : workOrderRecord.Asset.Name;

        context.assetStatus =
            workOrderRecord.AssetId == null
                ? null
                : workOrderRecord.Asset.Machine_Status__c;

        context.isEligible =
            workOrderRecord.Dispatch_Status__c ==
            STATUS_WAITING_ON_PARTS;

        context.hasReceivableParts =
            false;

        context.receivableParts =
            new List<ReceivablePartRow>();

        context.receivablePartCount =
            0;

        context.receivableUnitCount =
            0;

        context.outstandingPartCount =
            0;

        context.outstandingUnitCount =
            0;

        if (!context.isEligible) {

            context.eligibilityMessage =
                'Parts can only be received while the Work Order is Waiting on Parts. ' +
                'Current status: ' +
                safeText(
                    workOrderRecord.Dispatch_Status__c
                ) +
                '.';

            return context;
        }

        List<Work_Order_Part__c> receivableParts = [
            SELECT
                Id,
                Name,
                Work_Order__c,
                Machine__c,
                Part_Catalog__c,
                Part_Catalog__r.Name,
                Part_Catalog__r.Part_Number__c,
                Part_Catalog__r.Parts_Category__c,
                Quantity__c,
                Supplier_Name__c,
                Supplier_Phone__c,
                Order_URL__c,
                Order_Status__c,
                Notes__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrderId
                AND Order_Status__c IN :RECEIVABLE_STATUSES
            WITH USER_MODE
            ORDER BY Name
        ];

        for (
            Work_Order_Part__c partRecord :
            receivableParts
        ) {

            context.receivableParts.add(
                buildReceivablePartRow(
                    partRecord
                )
            );

            context.receivablePartCount++;

            context.receivableUnitCount +=
                quantityOrZero(
                    partRecord.Quantity__c
                );
        }

        List<Work_Order_Part__c> outstandingParts = [
            SELECT
                Id,
                Quantity__c,
                Order_Status__c
            FROM Work_Order_Part__c
            WHERE Work_Order__c = :workOrderId
                AND Order_Status__c IN :OUTSTANDING_STATUSES
            WITH USER_MODE
        ];

        for (
            Work_Order_Part__c partRecord :
            outstandingParts
        ) {

            context.outstandingPartCount++;

            context.outstandingUnitCount +=
                quantityOrZero(
                    partRecord.Quantity__c
                );
        }

        context.hasReceivableParts =
            !context.receivableParts.isEmpty();

        if (context.hasReceivableParts) {

            context.eligibilityMessage =
                'Select each ordered or shipped part included in this delivery.';

        } else {

            context.eligibilityMessage =
                'No Ordered or Shipped parts are currently available to receive.';
        }

        return context;
    }


    // =========================================================
    // RECEIVE PARTS
    // =========================================================

    @AuraEnabled
    public static ReceivePartsResult receiveParts(
        Id workOrderId,
        List<Id> receivedPartIds
    ) {

        if (workOrderId == null) {
            throw handledException(
                'A Work Order Id is required.'
            );
        }

        if (
            receivedPartIds == null ||
            receivedPartIds.isEmpty()
        ) {
            throw handledException(
                'Select at least one part that has been received.'
            );
        }

        Set<Id> uniquePartIds =
            new Set<Id>();

        for (Id partId : receivedPartIds) {

            if (partId == null) {
                throw handledException(
                    'A selected Work Order Part is missing its record Id.'
                );
            }

            if (!uniquePartIds.add(partId)) {
                throw handledException(
                    'The same Work Order Part was submitted more than once.'
                );
            }
        }

        Savepoint savepointRecord =
            Database.setSavepoint();

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
                throw new ReceivePartsException(
                    'The Work Order could not be found.'
                );
            }

            WorkOrder workOrderRecord =
                workOrders[0];

            if (
                workOrderRecord.Dispatch_Status__c !=
                STATUS_WAITING_ON_PARTS
            ) {

                throw new ReceivePartsException(
                    'Parts can only be received while the Work Order is Waiting on Parts. ' +
                    'Current status: ' +
                    safeText(
                        workOrderRecord.Dispatch_Status__c
                    ) +
                    '.'
                );
            }


            // -------------------------------------------------
            // 2. Load and validate selected Work Order Parts
            // -------------------------------------------------

            List<Work_Order_Part__c> selectedParts = [
                SELECT
                    Id,
                    Name,
                    Work_Order__c,
                    Quantity__c,
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Id IN :uniquePartIds
                WITH USER_MODE
            ];

            if (
                selectedParts.size() !=
                uniquePartIds.size()
            ) {

                throw new ReceivePartsException(
                    'One or more selected Work Order Parts could not be found or are no longer accessible.'
                );
            }

            Integer receivedPartCount =
                0;

            Decimal receivedUnitCount =
                0;

            for (
                Work_Order_Part__c partRecord :
                selectedParts
            ) {

                if (
                    partRecord.Work_Order__c !=
                    workOrderId
                ) {

                    throw new ReceivePartsException(
                        'A selected part does not belong to this Work Order.'
                    );
                }

                if (
                    !RECEIVABLE_STATUSES.contains(
                        partRecord.Order_Status__c
                    )
                ) {

                    throw new ReceivePartsException(
                        'Work Order Part ' +
                        partRecord.Name +
                        ' is no longer available to receive. ' +
                        'Refresh the wizard and try again.'
                    );
                }

                receivedPartCount++;

                receivedUnitCount +=
                    quantityOrZero(
                        partRecord.Quantity__c
                    );

                partRecord.Order_Status__c =
                    PART_RECEIVED;
            }

            Database.update(
                selectedParts,
                AccessLevel.USER_MODE
            );


            // -------------------------------------------------
            // 3. Re-read COMPLETE outstanding part lifecycle
            // -------------------------------------------------

            /*
             * Requested, Ordered and Shipped all remain
             * outstanding.
             *
             * This means a Requested part still blocks
             * Ready to Assign, even if every currently
             * Ordered/Shipped delivery has arrived.
             */

            List<Work_Order_Part__c> outstandingParts = [
                SELECT
                    Id,
                    Quantity__c,
                    Order_Status__c
                FROM Work_Order_Part__c
                WHERE Work_Order__c = :workOrderId
                    AND Order_Status__c IN :OUTSTANDING_STATUSES
                WITH USER_MODE
            ];

            Integer outstandingPartCount =
                0;

            Decimal outstandingUnitCount =
                0;

            for (
                Work_Order_Part__c partRecord :
                outstandingParts
            ) {

                outstandingPartCount++;

                outstandingUnitCount +=
                    quantityOrZero(
                        partRecord.Quantity__c
                    );
            }

            Boolean allRequiredPartsReceived =
                outstandingPartCount == 0;


            // -------------------------------------------------
            // 4. Determine resulting lifecycle state
            // -------------------------------------------------

            String resultingWorkOrderStatus =
                workOrderRecord.Dispatch_Status__c;

            /*
             * Asset status represents the physical/service
             * condition of the machine.
             *
             * Receiving parts must not change it.
             */
            String resultingAssetStatus =
                workOrderRecord.AssetId == null
                    ? null
                    : workOrderRecord
                        .Asset
                        .Machine_Status__c;

            String resultingCaseStatus =
                allRequiredPartsReceived
                    ? CASE_STATUS_IN_PROGRESS
                    : STATUS_WAITING_ON_PARTS;


            // -------------------------------------------------
            // 5. Final delivery advances Work Order
            // -------------------------------------------------

            if (allRequiredPartsReceived) {

                WorkOrder workOrderUpdate =
                    new WorkOrder(
                        Id =
                            workOrderRecord.Id,

                        Dispatch_Status__c =
                            STATUS_READY_TO_ASSIGN
                    );

                Database.update(
                    workOrderUpdate,
                    AccessLevel.USER_MODE
                );

                resultingWorkOrderStatus =
                    STATUS_READY_TO_ASSIGN;
            }


            // -------------------------------------------------
            // 6. Keep related Case aligned
            // -------------------------------------------------

            if (
                workOrderRecord.CaseId !=
                null
            ) {

                Case caseUpdate =
                    new Case(
                        Id =
                            workOrderRecord.CaseId,

                        Status =
                            resultingCaseStatus
                    );

                Database.update(
                    caseUpdate,
                    AccessLevel.USER_MODE
                );
            }


            // -------------------------------------------------
            // 7. Build result
            // -------------------------------------------------

            ReceivePartsResult result =
                new ReceivePartsResult();

            result.workOrderId =
                workOrderRecord.Id;

            result.workOrderNumber =
                workOrderRecord.WorkOrderNumber;

            result.receivedPartCount =
                receivedPartCount;

            result.receivedUnitCount =
                receivedUnitCount;

            result.outstandingPartCount =
                outstandingPartCount;

            result.outstandingUnitCount =
                outstandingUnitCount;

            result.allRequiredPartsReceived =
                allRequiredPartsReceived;

            result.readyToAssign =
                allRequiredPartsReceived;

            result.workOrderStatus =
                resultingWorkOrderStatus;

            result.assetStatus =
                resultingAssetStatus;

            if (allRequiredPartsReceived) {

                result.nextStepLabel =
                    'Assign a Technician';

                result.message =
                    'All required parts have been received. ' +
                    'The Work Order is now Ready to Assign.';

            } else {

                result.nextStepLabel =
                    'Waiting on Parts';

                result.message =
                    'The selected parts were received successfully. ' +
                    'Additional parts are still outstanding.';
            }

            return result;

        } catch (ReceivePartsException e) {

            Database.rollback(
                savepointRecord
            );

            throw handledException(
                e.getMessage()
            );

        } catch (Exception e) {

            Database.rollback(
                savepointRecord
            );

            throw handledException(
                'Unable to receive the selected parts. ' +
                e.getMessage()
            );
        }
    }


    // =========================================================
    // HELPERS
    // =========================================================

    private static ReceivablePartRow buildReceivablePartRow(
        Work_Order_Part__c partRecord
    ) {

        ReceivablePartRow row =
            new ReceivablePartRow();

        row.workOrderPartId =
            partRecord.Id;

        row.workOrderPartNumber =
            partRecord.Name;

        row.partCatalogId =
            partRecord.Part_Catalog__c;

        if (
            partRecord.Part_Catalog__c !=
            null
        ) {

            row.partName =
                partRecord
                    .Part_Catalog__r
                    .Name;

            row.partNumber =
                partRecord
                    .Part_Catalog__r
                    .Part_Number__c;

            row.category =
                partRecord
                    .Part_Catalog__r
                    .Parts_Category__c;
        }

        row.quantity =
            partRecord.Quantity__c;

        row.supplierName =
            partRecord.Supplier_Name__c;

        row.supplierPhone =
            partRecord.Supplier_Phone__c;

        row.orderUrl =
            partRecord.Order_URL__c;

        row.orderStatus =
            partRecord.Order_Status__c;

        row.notes =
            partRecord.Notes__c;

        return row;
    }


    private static Decimal quantityOrZero(
        Decimal quantity
    ) {

        return quantity == null
            ? Decimal.valueOf('0')
            : quantity;
    }


    private static String safeText(
        String value
    ) {

        return String.isBlank(value)
            ? 'Unknown'
            : value;
    }


    private static AuraHandledException handledException(
        String message
    ) {

        AuraHandledException exceptionRecord =
            new AuraHandledException(
                message
            );

        exceptionRecord.setMessage(
            message
        );

        return exceptionRecord;
    }


    // =========================================================
    // DTOs
    // =========================================================

    public class ReceivePartsContext {

        @AuraEnabled
        public Id workOrderId { get; set; }

        @AuraEnabled
        public String workOrderNumber { get; set; }

        @AuraEnabled
        public String subject { get; set; }

        @AuraEnabled
        public String dispatchStatus { get; set; }

        @AuraEnabled
        public Id assetId { get; set; }

        @AuraEnabled
        public String assetName { get; set; }

        @AuraEnabled
        public String assetStatus { get; set; }

        @AuraEnabled
        public Boolean isEligible { get; set; }

        @AuraEnabled
        public Boolean hasReceivableParts { get; set; }

        @AuraEnabled
        public String eligibilityMessage { get; set; }

        @AuraEnabled
        public List<ReceivablePartRow> receivableParts { get; set; }

        @AuraEnabled
        public Integer receivablePartCount { get; set; }

        @AuraEnabled
        public Decimal receivableUnitCount { get; set; }

        @AuraEnabled
        public Integer outstandingPartCount { get; set; }

        @AuraEnabled
        public Decimal outstandingUnitCount { get; set; }
    }


    public class ReceivablePartRow {

        @AuraEnabled
        public Id workOrderPartId { get; set; }

        @AuraEnabled
        public String workOrderPartNumber { get; set; }

        @AuraEnabled
        public Id partCatalogId { get; set; }

        @AuraEnabled
        public String partName { get; set; }

        @AuraEnabled
        public String partNumber { get; set; }

        @AuraEnabled
        public String category { get; set; }

        @AuraEnabled
        public Decimal quantity { get; set; }

        @AuraEnabled
        public String supplierName { get; set; }

        @AuraEnabled
        public String supplierPhone { get; set; }

        @AuraEnabled
        public String orderUrl { get; set; }

        @AuraEnabled
        public String orderStatus { get; set; }

        @AuraEnabled
        public String notes { get; set; }
    }


    public class ReceivePartsResult {

        @AuraEnabled
        public Id workOrderId { get; set; }

        @AuraEnabled
        public String workOrderNumber { get; set; }

        @AuraEnabled
        public Integer receivedPartCount { get; set; }

        @AuraEnabled
        public Decimal receivedUnitCount { get; set; }

        @AuraEnabled
        public Integer outstandingPartCount { get; set; }

        @AuraEnabled
        public Decimal outstandingUnitCount { get; set; }

        @AuraEnabled
        public Boolean allRequiredPartsReceived { get; set; }

        @AuraEnabled
        public Boolean readyToAssign { get; set; }

        @AuraEnabled
        public String workOrderStatus { get; set; }

        @AuraEnabled
        public String assetStatus { get; set; }

        @AuraEnabled
        public String nextStepLabel { get; set; }

        @AuraEnabled
        public String message { get; set; }
    }


    private class ReceivePartsException
        extends Exception {
    }
}