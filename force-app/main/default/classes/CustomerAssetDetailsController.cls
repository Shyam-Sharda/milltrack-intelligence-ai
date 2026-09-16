/**
 * Supplies customer-safe Asset details, machine resources,
 * maintenance instructions, and service history for the
 * MillTrack Experience Cloud customer portal.
 */
public with sharing class CustomerAssetDetailsController {
    private static final Integer MAX_SERVICE_HISTORY = 50;
    private static final Integer MAX_MAINTENANCE_LIST_LENGTH = 32768;

    // =========================================================
    // Asset Details
    // =========================================================

    @AuraEnabled
    public static AssetDetailsData getAssetDetails(Id assetId) {
        if (assetId == null) {
            throw new AuraHandledException('An Asset ID is required.');
        }

        try {
            CustomerContext customerContext = getCustomerContext();
            Asset authorizedAsset = getAuthorizedAsset(assetId, customerContext.accountId);

            if (authorizedAsset == null) {
                throw new AuraHandledException(
                    'We could not verify this machine for your MillTrack account.'
                );
            }

            AssetDetailsData result = new AssetDetailsData();
            result.asset = new AssetSummary(authorizedAsset);
            result.serviceHistory = loadServiceHistory(authorizedAsset.Id);

            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'Your machine information could not be loaded. Please refresh the page or try again later.'
            );
        }
    }

    // =========================================================
    // Maintenance List
    // =========================================================

    @AuraEnabled
    public static SaveMaintenanceResult saveMaintenanceList(Id assetId, String maintenanceList) {
        if (assetId == null) {
            throw new AuraHandledException('An Asset ID is required.');
        }

        if (
            maintenanceList != null &&
            maintenanceList.length() > MAX_MAINTENANCE_LIST_LENGTH
        ) {
            throw new AuraHandledException(
                'The maintenance list is too long. Please shorten it before saving.'
            );
        }

        try {
            CustomerContext customerContext = getCustomerContext();
            Asset authorizedAsset = getAuthorizedAsset(assetId, customerContext.accountId);

            if (authorizedAsset == null) {
                throw new AuraHandledException(
                    'We could not verify this machine for your MillTrack account.'
                );
            }

            Asset assetToUpdate = new Asset(
                Id=authorizedAsset.Id,
                Customer_Maintenance_List__c=normalizeMaintenanceList(maintenanceList)
            );

            Database.update(assetToUpdate, AccessLevel.USER_MODE);

            SaveMaintenanceResult result = new SaveMaintenanceResult();
            result.success = true;
            result.maintenanceList = assetToUpdate.Customer_Maintenance_List__c;
            result.message = 'Maintenance list saved successfully.';

            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (DmlException dmlException) {
            throw new AuraHandledException(
                'We could not save the maintenance list. Please try again.'
            );
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'We could not save the maintenance list. Please try again later.'
            );
        }
    }

    // =========================================================
    // Customer Authorization
    // =========================================================

    private static CustomerContext getCustomerContext() {
        Id currentUserId = UserInfo.getUserId();

        List<User> portalUsers = [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :currentUserId
            WITH USER_MODE
            LIMIT 1
        ];

        if (portalUsers.isEmpty() || portalUsers[0].ContactId == null) {
            throw new AuraHandledException(
                'Your MillTrack customer profile could not be loaded.'
            );
        }

        Id contactId = portalUsers[0].ContactId;

        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
            LIMIT 1
        ];

        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            throw new AuraHandledException(
                'Your MillTrack customer account could not be loaded.'
            );
        }

        CustomerContext customerContext = new CustomerContext();
        customerContext.contactId = contacts[0].Id;
        customerContext.accountId = contacts[0].AccountId;

        return customerContext;
    }

    // =========================================================
    // Authorized Asset
    // =========================================================

    private static Asset getAuthorizedAsset(Id assetId, Id accountId) {
        List<Asset> assets = [
            SELECT
                Id,
                Name,
                Manufacturer__c,
                Model__c,
                Serial_Number__c,
                Machine_Status__c,
                Description,
                Install_Date__c,
                Warranty_Start_Date__c,
                Warranty_End_Date__c,
                Last_Service_Date__c,
                Portal_Image_Path__c,
                Portal_Manual_Path__c,
                Customer_Maintenance_List__c
            FROM Asset
            WHERE Id = :assetId
            AND AccountId = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        return assets.isEmpty() ? null : assets[0];
    }

    // =========================================================
    // Service History
    // =========================================================

    private static List<ServiceHistoryEntry> loadServiceHistory(Id assetId) {
        List<Maintenance_Log__c> maintenanceLogs = [
            SELECT
                Id,
                Name,
                Maintenance_Date__c,
                Maintenance_Type__c,
                Problem_Summary__c,
                Summary__c,
                Root_Cause__c,
                Parts_Used__c,
                Labor_Hours__c,
                Work_Order__c,
                Work_Order__r.WorkOrderNumber,
                Issue_Resolved__c,
                Follow_Up_Required__c
            FROM Maintenance_Log__c
            WHERE Asset__c = :assetId
            WITH USER_MODE
            ORDER BY Maintenance_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :MAX_SERVICE_HISTORY
        ];

        List<ServiceHistoryEntry> serviceHistory = new List<ServiceHistoryEntry>();

        for (Maintenance_Log__c maintenanceLog : maintenanceLogs) {
            serviceHistory.add(new ServiceHistoryEntry(maintenanceLog));
        }

        return serviceHistory;
    }

    // =========================================================
    // Helpers
    // =========================================================

    private static String normalizeMaintenanceList(String maintenanceList) {
        return String.isBlank(maintenanceList) ? null : maintenanceList.trim();
    }

    private static String determineServiceStatus(Boolean issueResolved, Boolean followUpRequired) {
        if (followUpRequired == true) return 'Follow-up Required';
        if (issueResolved == true) return 'Resolved';

        return 'Completed';
    }

    // =========================================================
    // Internal Context
    // =========================================================

    private class CustomerContext {
        public Id contactId;
        public Id accountId;
    }

    // =========================================================
    // Response Wrappers
    // =========================================================

    public class AssetDetailsData {
        @AuraEnabled public AssetSummary asset { get; set; }
        @AuraEnabled public List<ServiceHistoryEntry> serviceHistory { get; set; }

        public AssetDetailsData() {
            asset = null;
            serviceHistory = new List<ServiceHistoryEntry>();
        }
    }

    public class AssetSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Date installDate { get; set; }
        @AuraEnabled public Date warrantyStartDate { get; set; }
        @AuraEnabled public Date warrantyEndDate { get; set; }
        @AuraEnabled public Date lastServiceDate { get; set; }
        @AuraEnabled public String portalImagePath { get; set; }
        @AuraEnabled public String portalManualPath { get; set; }
        @AuraEnabled public String maintenanceList { get; set; }

        public AssetSummary(Asset machine) {
            id = machine.Id;
            name = machine.Name;
            manufacturer = machine.Manufacturer__c;
            model = machine.Model__c;
            serialNumber = machine.Serial_Number__c;
            status = machine.Machine_Status__c;
            description = machine.Description;
            installDate = machine.Install_Date__c;
            warrantyStartDate = machine.Warranty_Start_Date__c;
            warrantyEndDate = machine.Warranty_End_Date__c;
            lastServiceDate = machine.Last_Service_Date__c;
            portalImagePath = machine.Portal_Image_Path__c;
            portalManualPath = machine.Portal_Manual_Path__c;
            maintenanceList = machine.Customer_Maintenance_List__c;
        }
    }

    public class ServiceHistoryEntry {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String maintenanceNumber { get; set; }
        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public String maintenanceType { get; set; }
        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public String rootCause { get; set; }
        @AuraEnabled public String partsUsed { get; set; }
        @AuraEnabled public Decimal laborHours { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public Boolean issueResolved { get; set; }
        @AuraEnabled public Boolean followUpRequired { get; set; }
        @AuraEnabled public String status { get; set; }

        public ServiceHistoryEntry(Maintenance_Log__c maintenanceLog) {
            id = maintenanceLog.Id;
            maintenanceNumber = maintenanceLog.Name;
            maintenanceDate = maintenanceLog.Maintenance_Date__c;
            maintenanceType = maintenanceLog.Maintenance_Type__c;
            problemSummary = maintenanceLog.Problem_Summary__c;
            summary = maintenanceLog.Summary__c;
            rootCause = maintenanceLog.Root_Cause__c;
            partsUsed = maintenanceLog.Parts_Used__c;
            laborHours = maintenanceLog.Labor_Hours__c;
            workOrderId = maintenanceLog.Work_Order__c;

            workOrderNumber = maintenanceLog.Work_Order__r == null
                ? null
                : maintenanceLog.Work_Order__r.WorkOrderNumber;

            issueResolved = maintenanceLog.Issue_Resolved__c;
            followUpRequired = maintenanceLog.Follow_Up_Required__c;
            status = determineServiceStatus(issueResolved, followUpRequired);
        }
    }

    public class SaveMaintenanceResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String maintenanceList { get; set; }
        @AuraEnabled public String message { get; set; }

        public SaveMaintenanceResult() {
            success = false;
            maintenanceList = null;
            message = null;
        }
    }
}