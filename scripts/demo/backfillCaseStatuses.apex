/*
 * MillTrack Intelligence
 * One-Time Case Status Backfill
 *
 * Purpose:
 * Bring older Case records into alignment with the current
 * Work Order lifecycle architecture.
 *
 * SAFETY:
 * - APPLY_UPDATES = false -> preview only
 * - APPLY_UPDATES = true  -> perform updates
 * - Closed Cases are ignored
 * - Completed / Cancelled Work Orders are ignored
 * - Cases with multiple active Work Orders are skipped
 */

Boolean APPLY_UPDATES = true;

/* =========================================================
   Work Order -> Case Status Mapping
   ========================================================= */

Map<String, String> caseStatusByDispatchStatus =
    new Map<String, String>{
        'Pending' => 'New',
        'Parts to Order' => 'In Progress',
        'Waiting on Parts' => 'In Progress',
        'Ready_to_Assign' => 'In Progress',
        'Assigned' => 'Scheduled',
        'In Progress' => 'In Progress',
        'Temporary Fix' => 'Follow-Up Required'
    };

/* =========================================================
   Retrieve Active Work Orders
   ========================================================= */

List<WorkOrder> activeWorkOrders = [
    SELECT
        Id,
        WorkOrderNumber,
        Subject,
        Dispatch_Status__c,
        CaseId,
        Case.CaseNumber,
        Case.Subject,
        Case.Status,
        Case.IsClosed
    FROM WorkOrder
    WHERE CaseId != null
        AND Dispatch_Status__c NOT IN ('Completed', 'Cancelled')
    ORDER BY Case.CaseNumber, WorkOrderNumber
];

/* =========================================================
   Protect Against Multiple Active Work Orders Per Case
   ========================================================= */

Map<Id, Integer> activeWorkOrderCountByCase =
    new Map<Id, Integer>();

for (WorkOrder workOrder : activeWorkOrders) {
    Integer existingCount =
        activeWorkOrderCountByCase.get(workOrder.CaseId);

    activeWorkOrderCountByCase.put(
        workOrder.CaseId,
        existingCount == null ? 1 : existingCount + 1
    );
}

/* =========================================================
   Determine Required Case Updates
   ========================================================= */

List<Case> casesToUpdate = new List<Case>();

Integer alreadyCorrect = 0;
Integer skippedClosed = 0;
Integer skippedMultipleWorkOrders = 0;
Integer skippedUnmappedStatus = 0;

System.debug('');
System.debug('=========================================================');
System.debug('MILLTRACK CASE STATUS BACKFILL');
System.debug(
    APPLY_UPDATES
        ? 'MODE: APPLY UPDATES'
        : 'MODE: PREVIEW ONLY'
);
System.debug('=========================================================');
System.debug('');

for (WorkOrder workOrder : activeWorkOrders) {

    if (workOrder.Case == null) {
        continue;
    }

    if (workOrder.Case.IsClosed) {
        skippedClosed++;

        System.debug(
            'SKIP CLOSED CASE | Case ' +
            workOrder.Case.CaseNumber +
            ' | Work Order ' +
            workOrder.WorkOrderNumber
        );

        continue;
    }

    Integer activeWorkOrderCount =
        activeWorkOrderCountByCase.get(workOrder.CaseId);

    if (
        activeWorkOrderCount != null &&
        activeWorkOrderCount > 1
    ) {
        skippedMultipleWorkOrders++;

        System.debug(
            'SKIP MULTIPLE ACTIVE WORK ORDERS | Case ' +
            workOrder.Case.CaseNumber +
            ' | Active Work Orders: ' +
            activeWorkOrderCount
        );

        continue;
    }

    String desiredCaseStatus =
        caseStatusByDispatchStatus.get(
            workOrder.Dispatch_Status__c
        );

    if (desiredCaseStatus == null) {
        skippedUnmappedStatus++;

        System.debug(
            'SKIP UNMAPPED STATUS | Case ' +
            workOrder.Case.CaseNumber +
            ' | Work Order ' +
            workOrder.WorkOrderNumber +
            ' | Dispatch Status: ' +
            workOrder.Dispatch_Status__c
        );

        continue;
    }

    if (workOrder.Case.Status == desiredCaseStatus) {
        alreadyCorrect++;

        System.debug(
            'ALREADY CORRECT | Case ' +
            workOrder.Case.CaseNumber +
            ' | Work Order ' +
            workOrder.WorkOrderNumber +
            ' | Status: ' +
            desiredCaseStatus
        );

        continue;
    }

    System.debug(
        'CHANGE | Case ' +
        workOrder.Case.CaseNumber +
        ' | Work Order ' +
        workOrder.WorkOrderNumber +
        ' | ' +
        workOrder.Case.Status +
        ' -> ' +
        desiredCaseStatus +
        ' | Dispatch Status: ' +
        workOrder.Dispatch_Status__c
    );

    casesToUpdate.add(
        new Case(
            Id = workOrder.CaseId,
            Status = desiredCaseStatus
        )
    );
}

/* =========================================================
   Apply Updates
   ========================================================= */

Integer successfulUpdates = 0;
Integer failedUpdates = 0;

if (APPLY_UPDATES && !casesToUpdate.isEmpty()) {

    Database.SaveResult[] results =
        Database.update(
            casesToUpdate,
            false
        );

    for (Integer index = 0; index < results.size(); index++) {

        Database.SaveResult result = results[index];

        if (result.isSuccess()) {
            successfulUpdates++;

            System.debug(
                'UPDATED | Case Id: ' +
                casesToUpdate[index].Id +
                ' | New Status: ' +
                casesToUpdate[index].Status
            );
        } else {
            failedUpdates++;

            for (Database.Error error : result.getErrors()) {
                System.debug(
                    'UPDATE FAILED | Case Id: ' +
                    casesToUpdate[index].Id +
                    ' | ' +
                    error.getStatusCode() +
                    ' | ' +
                    error.getMessage()
                );
            }
        }
    }
}

/* =========================================================
   Summary
   ========================================================= */

System.debug('');
System.debug('=========================================================');
System.debug('BACKFILL SUMMARY');
System.debug('=========================================================');

System.debug(
    'Active Work Orders inspected: ' +
    activeWorkOrders.size()
);

System.debug(
    'Cases needing status changes: ' +
    casesToUpdate.size()
);

System.debug(
    'Cases already correct: ' +
    alreadyCorrect
);

System.debug(
    'Closed Cases skipped: ' +
    skippedClosed
);

System.debug(
    'Cases with multiple active Work Orders skipped: ' +
    skippedMultipleWorkOrders
);

System.debug(
    'Unmapped Work Order statuses skipped: ' +
    skippedUnmappedStatus
);

if (APPLY_UPDATES) {
    System.debug(
        'Successful updates: ' +
        successfulUpdates
    );

    System.debug(
        'Failed updates: ' +
        failedUpdates
    );
} else {
    System.debug(
        'PREVIEW ONLY - No Salesforce records were changed.'
    );

    System.debug(
        'Set APPLY_UPDATES = true after reviewing the changes.'
    );
}

System.debug('=========================================================');