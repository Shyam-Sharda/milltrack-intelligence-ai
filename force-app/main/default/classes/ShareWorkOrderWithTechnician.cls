// Deprecated: no longer used after Work Order ownership redesign.
// Work Order Owner is now set to the assigned Technician.
// Retained temporarily until final cleanup/deployment validation.

public without sharing class ShareWorkOrderWithTechnician {
    
    public class Request {
        @InvocableVariable(required=true)
        public Id workOrderId;

        @InvocableVariable(required=false)
        public Id technicianId;

        @InvocableVariable(required=false)
        public Id oldTechnicianId;
    }

    public class Result {
        @InvocableVariable
        public Id workOrderId;

        @InvocableVariable
        public String statusMessage;
    }

    @InvocableMethod(label='Share Work Order With Technician')
    public static List<Result> shareWorkOrders(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> workOrderIds = new Set<Id>();
        Set<Id> oldTechnicianIds = new Set<Id>();

        for (Request req : requests) {
            if (req.workOrderId != null) {
                workOrderIds.add(req.workOrderId);
            }
            if (req.oldTechnicianId != null) {
                oldTechnicianIds.add(req.oldTechnicianId);
            }
        }

        if (workOrderIds.isEmpty()) {
            return results;
        }

        // Remove old technician shares if reassigned
        if (!oldTechnicianIds.isEmpty()) {
            List<WorkOrderShare> oldShares = [
                SELECT Id
                FROM WorkOrderShare
                WHERE ParentId IN :workOrderIds
                AND UserOrGroupId IN :oldTechnicianIds
                AND RowCause = 'Manual'
            ];

            if (!oldShares.isEmpty()) {
                Database.delete(oldShares, false);
            }
        }

        // Prevent duplicate shares
        Set<String> existingShareKeys = new Set<String>();

        for (WorkOrderShare existingShare : [
            SELECT ParentId, UserOrGroupId
            FROM WorkOrderShare
            WHERE ParentId IN :workOrderIds
        ]) {
            existingShareKeys.add(
                String.valueOf(existingShare.ParentId) + '-' + String.valueOf(existingShare.UserOrGroupId)
            );
        }

        List<WorkOrderShare> sharesToInsert = new List<WorkOrderShare>();
        Map<String, Id> keyToWorkOrderId = new Map<String, Id>();

        for (Request req : requests) {
            Result res = new Result();
            res.workOrderId = req.workOrderId;

            if (req.workOrderId == null) {
                res.statusMessage = 'Skipped: missing Work Order Id.';
                results.add(res);
                continue;
            }

            if (req.technicianId == null) {
                res.statusMessage = 'Skipped: no technician assigned.';
                results.add(res);
                continue;
            }

            String shareKey = String.valueOf(req.workOrderId) + '-' + String.valueOf(req.technicianId);

            if (existingShareKeys.contains(shareKey)) {
                res.statusMessage = 'Skipped: share already exists.';
                results.add(res);
                continue;
            }

            WorkOrderShare newShare = new WorkOrderShare();
            newShare.ParentId = req.workOrderId;
            newShare.UserOrGroupId = req.technicianId;
            newShare.AccessLevel = 'Edit';
            newShare.RowCause = Schema.WorkOrderShare.RowCause.Manual;

            sharesToInsert.add(newShare);
            keyToWorkOrderId.put(shareKey, req.workOrderId);
            existingShareKeys.add(shareKey);

            res.statusMessage = 'Prepared share for technician.';
            results.add(res);
        }

        if (!sharesToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(sharesToInsert, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                if (!saveResults[i].isSuccess()) {
                    System.debug('Failed to create WorkOrderShare: ' + saveResults[i].getErrors()[0].getMessage());
                }
            }
        }

        return results;
    }
}