@IsTest
private class CustomerProgressTrackerTest {
    private static final String ACCOUNT_NAME = 'Progress Tracker Test Account';
    private static final String SUBJECT_PREFIX = 'Progress Tracker Test - ';

    @TestSetup
    static void createTestData() {
        Account customerAccount = new Account(Name = ACCOUNT_NAME);
        insert customerAccount;

        Asset testMachine = new Asset(
            Name = 'Progress Tracker Test Machine',
            AccountId = customerAccount.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'Test Model'
        );
        insert testMachine;

        List<String> dispatchStatuses = new List<String>{
            'Pending',
            'Parts to Order',
            'Waiting on Parts',
            'Ready_to_Assign',
            'Assigned',
            'In Progress',
            'Temporary Fix',
            'Completed',
            'Cancelled'
        };

        List<WorkOrder> workOrders = new List<WorkOrder>();

        for (String dispatchStatus : dispatchStatuses) {
            WorkOrder testWorkOrder = new WorkOrder(
                Subject = SUBJECT_PREFIX + dispatchStatus,
                Status = 'New',
                AccountId = customerAccount.Id,
                AssetId = testMachine.Id,
                Dispatch_Status__c = dispatchStatus
            );

            if (dispatchStatus == 'Temporary Fix' || dispatchStatus == 'Completed'
            ) {
                testWorkOrder.Technician_Notes__c = 'Test technician notes for ' + dispatchStatus + '.';
            }

            workOrders.add(testWorkOrder);
        }

        insert workOrders;
    }

    @IsTest
    static void getProgressMapsEveryDispatchStatus() {
        Map<String, String> expectedStageByStatus = new Map<String, String>{
            'Pending' => 'Request Received',
            'Parts to Order' => 'Waiting on Parts',
            'Waiting on Parts' => 'Waiting on Parts',
            'Ready_to_Assign' => 'Under Review',
            'Assigned' => 'Visit Scheduled',
            'In Progress' => 'Service in Progress',
            'Temporary Fix' => 'Service in Progress',
            'Completed' => 'Completed',
            'Cancelled' => 'Service Cancelled'
        };

        String subjectPattern = SUBJECT_PREFIX + '%';

        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Dispatch_Status__c
            FROM WorkOrder
            WHERE Subject LIKE :subjectPattern
        ];

        System.assertEquals(
            9,
            workOrders.size(),
            'The test setup should create one Work Order for every Dispatch Status.'
        );

        Test.startTest();

        for (WorkOrder workOrderRecord : workOrders) {
            Map<String, Object> result = CustomerProgressTrackerController.getProgress(workOrderRecord.Id);

            String dispatchStatus = workOrderRecord.Dispatch_Status__c;
            Boolean expectsPartsStage = dispatchStatus == 'Parts to Order' || dispatchStatus == 'Waiting on Parts';
            Boolean expectsCancellation = dispatchStatus == 'Cancelled';

            System.assertEquals(
                workOrderRecord.WorkOrderNumber,
                (String) result.get('workOrderNumber'),
                'The controller should return the correct Work Order number.'
            );
            System.assertEquals(
                expectedStageByStatus.get(dispatchStatus),
                (String) result.get('currentStage'),
                'Incorrect customer stage for ' + dispatchStatus + '.'
            );
            System.assertEquals(
                expectsPartsStage,
                (Boolean) result.get('showPartsStage'),
                'Incorrect parts-stage visibility for ' + dispatchStatus + '.'
            );
            System.assertEquals(
                expectsCancellation,
                (Boolean) result.get('isCancelled'),
                'Incorrect cancellation result for ' + dispatchStatus + '.'
            );
            System.assert(
                String.isNotBlank((String) result.get('message')),
                'Every status should return a customer-safe message.'
            );

            List<Map<String, Object>> stages = (List<Map<String, Object>>) result.get('stages');

            System.assertEquals(
                expectsPartsStage ? 7 : 6,
                stages.size(),
                'Incorrect number of tracker stages for ' + dispatchStatus + '.'
            );
            System.assertEquals(
                expectsPartsStage,
                containsStage(stages, 'Waiting on Parts'),
                'Waiting on Parts should only appear when applicable.'
            );
            System.assertEquals(
                expectsCancellation ? 0 : 1,
                countStagesWithState(stages, 'current'),
                'The tracker should have the correct number of current stages.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void getProgressRejectsMissingOrWrongRecordId() {
        Account customerAccount = [
            SELECT Id
            FROM Account
            WHERE Name = :ACCOUNT_NAME
            LIMIT 1
        ];

        Boolean missingIdWasRejected = false;
        Boolean wrongObjectIdWasRejected = false;

        Test.startTest();

        try {
            CustomerProgressTrackerController.getProgress(null);
        } catch (AuraHandledException expectedException) {
            missingIdWasRejected = true;
        }

        try {
            CustomerProgressTrackerController.getProgress(customerAccount.Id);
        } catch (AuraHandledException expectedException) {
            wrongObjectIdWasRejected = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            missingIdWasRejected,
            'A missing Work Order ID should be rejected.'
        );
        System.assertEquals(
            true,
            wrongObjectIdWasRejected,
            'An ID for another object should be rejected.'
        );
    }

    private static Boolean containsStage(List<Map<String, Object>> stages, String expectedLabel) {
        for (Map<String, Object> stage : stages) {
            if ((String) stage.get('label') == expectedLabel) {
                return true;
            }
        }

        return false;
    }

    private static Integer countStagesWithState(List<Map<String, Object>> stages, String expectedState) {
        Integer matchingStages = 0;

        for (Map<String, Object> stage : stages) {
            if ((String) stage.get('state') == expectedState) {
                matchingStages++;
            }
        }

        return matchingStages;
    }
}
