public with sharing class CustomerProgressTrackerController {
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getProgress(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('A Work Order record ID is required.');
        }

        try {
            List<WorkOrder> workOrders = [
                SELECT Id, WorkOrderNumber, Dispatch_Status__c
                FROM WorkOrder
                WHERE Id = :recordId
                WITH USER_MODE
                LIMIT 1
            ];

            if (workOrders.isEmpty()) {
                throw new AuraHandledException('The Work Order could not be found or you do not have access to it.');
            }

            return buildProgress(workOrders[0]);
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('The Work Order progress could not be loaded. Please try again or contact support.');
        }
    }

    private static Map<String, Object> buildProgress(WorkOrder workOrderRecord) {
        String dispatchStatus = workOrderRecord.Dispatch_Status__c;

        if (String.isBlank(dispatchStatus)) {
            dispatchStatus = '';
        }

        Boolean showPartsStage = dispatchStatus == 'Parts to Order' || dispatchStatus == 'Waiting on Parts';
        Boolean isCancelled = dispatchStatus == 'Cancelled';

        String currentStage;
        String customerMessage;

        switch on dispatchStatus {
            when 'Pending' {
                currentStage = 'Request Received';
                customerMessage = 'We received your service request.';
            }
            when 'Parts to Order' {
                currentStage = 'Waiting on Parts';
                customerMessage = 'Parts are being arranged for your service.';
            }
            when 'Waiting on Parts' {
                currentStage = 'Waiting on Parts';
                customerMessage = 'We are waiting for the required parts to arrive.';
            }
            when 'Ready_to_Assign' {
                currentStage = 'Under Review';
                customerMessage = 'Your service request has been reviewed and is being prepared for scheduling.';
            }
            when 'Assigned' {
                currentStage = 'Visit Scheduled';
                customerMessage = 'A technician has been assigned and your service visit is scheduled.';
            }
            when 'In Progress' {
                currentStage = 'Service in Progress';
                customerMessage = 'Your technician is currently working on this service.';
            }
            when 'Temporary Fix' {
                currentStage = 'Service in Progress';
                customerMessage = 'A temporary repair was completed. Additional service is being coordinated.';
            }
            when 'Completed' {
                currentStage = 'Completed';
                customerMessage = 'Your service has been completed.';
            }
            when 'Cancelled' {
                currentStage = 'Service Cancelled';
                customerMessage = 'This service work order has been cancelled.';
            }
            when else {
                currentStage = 'Under Review';
                customerMessage = 'Your service request is under review.';
            }
        }

        List<String> stageKeys = new List<String>{'requestReceived', 'underReview'};

        List<String> stageLabels = new List<String>{'Request Received', 'Under Review'};

        if (showPartsStage) {
            stageKeys.add('waitingOnParts');
            stageLabels.add('Waiting on Parts');
        }

        stageKeys.add('technicianAssigned');
        stageLabels.add('Technician Assigned');

        stageKeys.add('visitScheduled');
        stageLabels.add('Visit Scheduled');

        stageKeys.add('serviceInProgress');
        stageLabels.add('Service in Progress');

        stageKeys.add('completed');
        stageLabels.add('Completed');

        Integer currentStageIndex = findStageIndex(stageLabels, currentStage);

        List<Map<String, Object>> stages = new List<Map<String, Object>>();

        for (Integer index = 0; index < stageLabels.size(); index++) {
            String stageState = 'upcoming';

            if (isCancelled) {
                if (index == 0) {
                    stageState = 'completed';
                }
            } else if (index < currentStageIndex) {
                stageState = 'completed';
            } else if (index == currentStageIndex) {
                stageState = 'current';
            }

            stages.add(new Map<String, Object>{
                'key' => stageKeys[index],
                'label' => stageLabels[index],
                'state' => stageState
            });
        }

        return new Map<String, Object>{
            'workOrderNumber' => workOrderRecord.WorkOrderNumber,
            'currentStage' => currentStage,
            'message' => customerMessage,
            'isCancelled' => isCancelled,
            'showPartsStage' => showPartsStage,
            'stages' => stages
        };
    }

    private static Integer findStageIndex(List<String> stageLabels, String currentStage) {
        for (Integer index = 0; index < stageLabels.size(); index++) {
            if (stageLabels[index] == currentStage) {
                return index;
            }
        }

        return 1;
    }
}