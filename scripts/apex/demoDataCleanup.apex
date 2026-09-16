Savepoint sp = Database.setSavepoint();

try {
    Set<Id> millTrackAccountIds = new Set<Id>{
        '001gK00001Phf12QAB', // Apex Prosthetics Lab Ltd.
        '001gK00001Phf11QAB', // Lakeshore Dental Milling Inc.
        '001gK00001Phf13QAB', // Maple Ridge Dental Technologies Inc.
        '001gK00001Phf0zQAB', // NorthStar Dental Milling Ltd.
        '001gK00001Phf10QAB'  // Precision Smile Studio Inc.
    };

    List<Asset> assets = [
        SELECT Id, Name, Machine_Status__c, Last_Service_Date__c
        FROM Asset
        WHERE AccountId IN :millTrackAccountIds
    ];

    Set<Id> assetIds = new Map<Id, Asset>(assets).keySet();

    List<WorkOrder> workOrders = [
        SELECT Id
        FROM WorkOrder
        WHERE AssetId IN :assetIds
    ];

    Set<Id> workOrderIds = new Map<Id, WorkOrder>(workOrders).keySet();

    List<Work_Order_Part__c> workOrderParts = [
        SELECT Id
        FROM Work_Order_Part__c
        WHERE Work_Order__c IN :workOrderIds
    ];

    List<Maintenance_Log__c> maintenanceLogs = [
        SELECT Id
        FROM Maintenance_Log__c
        WHERE Asset__c IN :assetIds
        OR Work_Order__c IN :workOrderIds
    ];

    List<Case> cases = [
        SELECT Id
        FROM Case
        WHERE AssetId IN :assetIds
    ];

    System.debug('MillTrack Assets: ' + assets.size());
    System.debug('Cases to delete: ' + cases.size());
    System.debug('Work Orders to delete: ' + workOrders.size());
    System.debug('Maintenance Logs to delete: ' + maintenanceLogs.size());
    System.debug('Work Order Parts to delete: ' + workOrderParts.size());

    if (!workOrderParts.isEmpty()) {
        delete workOrderParts;
    }

    if (!maintenanceLogs.isEmpty()) {
        delete maintenanceLogs;
    }

    if (!workOrders.isEmpty()) {
        delete workOrders;
    }

    if (!cases.isEmpty()) {
        delete cases;
    }

    for (Asset assetRecord : assets) {
        assetRecord.Machine_Status__c = 'Active';
        assetRecord.Last_Service_Date__c = null;
    }

    if (!assets.isEmpty()) {
        update assets;
    }

    System.debug('=== MILLTRACK DEMO DATA CLEANUP COMPLETE ===');
    System.debug('Deleted Work Order Parts: ' + workOrderParts.size());
    System.debug('Deleted Maintenance Logs: ' + maintenanceLogs.size());
    System.debug('Deleted Work Orders: ' + workOrders.size());
    System.debug('Deleted Cases: ' + cases.size());
    System.debug('Reset Assets: ' + assets.size());

} catch (Exception e) {
    Database.rollback(sp);

    System.debug('=== CLEANUP ROLLED BACK ===');
    System.debug(e.getTypeName());
    System.debug(e.getMessage());
    System.debug(e.getStackTraceString());

    throw e;
}