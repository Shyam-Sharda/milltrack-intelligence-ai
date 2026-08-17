@IsTest
private class CustomerAssetServiceHistoryControlTest {
    @TestSetup
    static void createTestData() {
        String maintenanceType = firstActivePicklistValue(
            Maintenance_Log__c.Maintenance_Type__c
        );

        Account accountA = new Account(Name = 'MillTrack Controller Test Lab A');
        Account accountB = new Account(Name = 'MillTrack Controller Test Lab B');
        insert new List<Account>{ accountA, accountB };

        Asset assetA = new Asset(
            Name = 'Controller Test Mill A',
            AccountId = accountA.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Serial_Number__c = 'CTRL-A-001',
            Machine_Status__c = 'Active'
        );

        Asset assetB = new Asset(
            Name = 'Controller Test Mill B',
            AccountId = accountB.Id,
            Manufacturer__c = 'Roland',
            Model__c = 'DWX-52D',
            Serial_Number__c = 'CTRL-B-001',
            Machine_Status__c = 'Active'
        );
        insert new List<Asset>{ assetA, assetB };

        WorkOrder workOrderA = new WorkOrder(
            AccountId = accountA.Id,
            AssetId = assetA.Id,
            Subject = 'Controller service-history test',
            Status = 'New'
        );
        WorkOrder workOrderB = new WorkOrder(
            AccountId = accountB.Id,
            AssetId = assetB.Id,
            Subject = 'Controller service-history test B',
            Status = 'New'
        );
        insert new List<WorkOrder>{ workOrderA, workOrderB };

        Id currentUserId = UserInfo.getUserId();
        insert new List<Maintenance_Log__c>{
            new Maintenance_Log__c(
                Asset__c = assetA.Id,
                Work_Order__c = workOrderA.Id,
                Performed_By__c = currentUserId,
                Maintenance_Date__c = Date.newInstance(2026, 8, 3),
                Maintenance_Type__c = maintenanceType,
                Summary__c = 'Latest service visit',
                Root_Cause__c = 'Spindle calibration required',
                Parts_Used__c = 'Calibration tool',
                Labor_Hours__c = 2.25,
                Issue_Resolved__c = false,
                Follow_Up_Required__c = true
            ),
            new Maintenance_Log__c(
                Asset__c = assetA.Id,
                Work_Order__c = workOrderA.Id,
                Performed_By__c = currentUserId,
                Maintenance_Date__c = Date.newInstance(2026, 7, 15),
                Maintenance_Type__c = maintenanceType,
                Summary__c = 'Resolved service visit',
                Root_Cause__c = 'Routine component wear',
                Labor_Hours__c = 1.5,
                Issue_Resolved__c = true,
                Follow_Up_Required__c = false
            ),
            new Maintenance_Log__c(
                Asset__c = assetA.Id,
                Work_Order__c = workOrderA.Id,
                Performed_By__c = currentUserId,
                Maintenance_Date__c = Date.newInstance(2026, 6, 10),
                Maintenance_Type__c = maintenanceType,
                Summary__c = 'Routine maintenance visit',
                Root_Cause__c = 'Preventive maintenance interval reached',
                Labor_Hours__c = 1,
                Issue_Resolved__c = false,
                Follow_Up_Required__c = false
            ),
            new Maintenance_Log__c(
                Asset__c = assetB.Id,
                Work_Order__c = workOrderB.Id,
                Performed_By__c = currentUserId,
                Maintenance_Date__c = Date.newInstance(2026, 8, 4),
                Maintenance_Type__c = maintenanceType,
                Summary__c = 'Customer B service visit',
                Root_Cause__c = 'Calibration drift detected',
                Labor_Hours__c = 3,
                Issue_Resolved__c = true,
                Follow_Up_Required__c = false
            )
        };
    }

    @IsTest
    static void returnsMappedHistoryInDescendingDateOrder() {
        Asset assetA = [
            SELECT Id
            FROM Asset
            WHERE Name = 'Controller Test Mill A'
            LIMIT 1
        ];
        WorkOrder workOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = 'Controller service-history test'
            LIMIT 1
        ];

        Test.startTest();
        List<CustomerAssetServiceHistoryController.ServiceHistoryEntry> history =
            CustomerAssetServiceHistoryController.getServiceHistory(assetA.Id);
        Test.stopTest();

        System.assertEquals(3, history.size(), 'Only Asset A history should be returned.');

        CustomerAssetServiceHistoryController.ServiceHistoryEntry latest = history[0];
        System.assertNotEquals(null, latest.id);
        System.assertNotEquals(null, latest.maintenanceNumber);
        System.assertEquals(Date.newInstance(2026, 8, 3), latest.maintenanceDate);
        System.assertNotEquals(null, latest.maintenanceType);
        System.assertEquals('Latest service visit', latest.summary);
        System.assertEquals('Spindle calibration required', latest.rootCause);
        System.assertEquals('Calibration tool', latest.partsUsed);
        System.assertEquals(2.25, latest.laborHours);
        System.assertEquals(workOrder.Id, latest.workOrderId);
        System.assertEquals(workOrder.WorkOrderNumber, latest.workOrderNumber);
        System.assertEquals(false, latest.issueResolved);
        System.assertEquals(true, latest.followUpRequired);
        System.assertEquals('Follow-up Required', latest.status);

        System.assertEquals(Date.newInstance(2026, 7, 15), history[1].maintenanceDate);
        System.assertEquals('Resolved', history[1].status);

        System.assertEquals(Date.newInstance(2026, 6, 10), history[2].maintenanceDate);
        System.assertEquals('Completed', history[2].status);
    }

    @IsTest
    static void filtersHistoryByAsset() {
        Asset assetB = [
            SELECT Id
            FROM Asset
            WHERE Name = 'Controller Test Mill B'
            LIMIT 1
        ];

        Test.startTest();
        List<CustomerAssetServiceHistoryController.ServiceHistoryEntry> history =
            CustomerAssetServiceHistoryController.getServiceHistory(assetB.Id);
        Test.stopTest();

        System.assertEquals(1, history.size());
        System.assertEquals('Customer B service visit', history[0].summary);
        System.assertEquals('Resolved', history[0].status);
    }

    @IsTest
    static void rejectsMissingAssetId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            CustomerAssetServiceHistoryController.getServiceHistory(null);
        } catch (AuraHandledException expectedException) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A null Asset ID must be rejected.');
    }

    private static String firstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        throw new TestDataException('Maintenance Type requires an active picklist value.');
    }

    private class TestDataException extends Exception {
    }
}
