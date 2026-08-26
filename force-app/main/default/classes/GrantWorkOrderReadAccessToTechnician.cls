/**
 * Grants read-only access to a Work Order for a technician who previously
 * worked on the record but is no longer the Assigned Technician / Owner.
 *
 * The actual WorkOrderShare is created asynchronously so that an ownership
 * change performed by the same Flow transaction cannot remove the Manual share.
 */
public without sharing class GrantWorkOrderReadAccessToTechnician {

    public class Request {
        @InvocableVariable(required=true)
        public Id workOrderId;

        @InvocableVariable(required=true)
        public Id technicianId;
    }

    public class Result {
        @InvocableVariable
        public Id workOrderId;

        @InvocableVariable
        public Id technicianId;

        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String statusCode;

        @InvocableVariable
        public String statusMessage;
    }

    @InvocableMethod(
        label='Grant Work Order Read Access to Technician'
        description='Queues creation of read-only Work Order access for a technician after the current transaction commits.'
    )
    public static List<Result> grantReadAccess(List<Request> requests) {

        List<Result> results = new List<Result>();
        List<Id> workOrderIds = new List<Id>();
        List<Id> technicianIds = new List<Id>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (Request req : requests) {
            Result res = new Result();

            if (req != null) {
                res.workOrderId = req.workOrderId;
                res.technicianId = req.technicianId;
            }

            if (req == null) {
                res.success = false;
                res.statusCode = 'INVALID_REQUEST';
                res.statusMessage = 'Request was null.';
                results.add(res);
                continue;
            }

            if (req.workOrderId == null) {
                res.success = false;
                res.statusCode = 'MISSING_WORK_ORDER';
                res.statusMessage = 'Work Order Id is required.';
                results.add(res);
                continue;
            }

            if (req.technicianId == null) {
                res.success = false;
                res.statusCode = 'MISSING_TECHNICIAN';
                res.statusMessage = 'Technician Id is required.';
                results.add(res);
                continue;
            }

            workOrderIds.add(req.workOrderId);
            technicianIds.add(req.technicianId);

            res.success = true;
            res.statusCode = 'QUEUED';
            res.statusMessage =
                'Read-only Work Order access queued for technician.';

            results.add(res);
        }

        if (!workOrderIds.isEmpty()) {
            System.enqueueJob(
                new GrantReadAccessQueueable(
                    workOrderIds,
                    technicianIds
                )
            );
        }

        return results;
    }

    public class GrantReadAccessQueueable implements Queueable {

        private List<Id> workOrderIds;
        private List<Id> technicianIds;

        public GrantReadAccessQueueable(
            List<Id> workOrderIds,
            List<Id> technicianIds
        ) {
            this.workOrderIds = workOrderIds;
            this.technicianIds = technicianIds;
        }

        public void execute(QueueableContext context) {

            Set<Id> workOrderIdSet =
                new Set<Id>(workOrderIds);

            Set<Id> technicianIdSet =
                new Set<Id>(technicianIds);

            Set<String> existingManualShareKeys =
                new Set<String>();

            for (WorkOrderShare existingShare : [
                SELECT ParentId, UserOrGroupId
                FROM WorkOrderShare
                WHERE ParentId IN :workOrderIdSet
                AND UserOrGroupId IN :technicianIdSet
                AND RowCause = 'Manual'
            ]) {
                existingManualShareKeys.add(
                    buildKey(
                        existingShare.ParentId,
                        existingShare.UserOrGroupId
                    )
                );
            }

            List<WorkOrderShare> sharesToInsert =
                new List<WorkOrderShare>();

            for (Integer i = 0; i < workOrderIds.size(); i++) {

                Id workOrderId = workOrderIds[i];
                Id technicianId = technicianIds[i];

                String key =
                    buildKey(workOrderId, technicianId);

                if (existingManualShareKeys.contains(key)) {
                    continue;
                }

                WorkOrderShare shareRecord =
                    new WorkOrderShare();

                shareRecord.ParentId = workOrderId;
                shareRecord.UserOrGroupId = technicianId;
                shareRecord.AccessLevel = 'Read';
                shareRecord.RowCause =
                    Schema.WorkOrderShare.RowCause.Manual;

                sharesToInsert.add(shareRecord);
                existingManualShareKeys.add(key);
            }

            if (!sharesToInsert.isEmpty()) {

                Database.SaveResult[] saveResults = Database.insert(sharesToInsert, false, System.AccessLevel.SYSTEM_MODE);

                for (Database.SaveResult saveResult : saveResults) {
                    if (!saveResult.isSuccess()) {
                        for (Database.Error error : saveResult.getErrors()) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Failed to create technician WorkOrderShare: '
                                + error.getStatusCode()
                                + ' - '
                                + error.getMessage()
                            );
                        }
                    }
                }
            }
        }
    }

    private static String buildKey(
        Id workOrderId,
        Id technicianId
    ) {
        return String.valueOf(workOrderId)
            + '-'
            + String.valueOf(technicianId);
    }
}