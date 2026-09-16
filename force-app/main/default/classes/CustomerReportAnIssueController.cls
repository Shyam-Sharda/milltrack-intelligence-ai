public with sharing class CustomerReportAnIssueController {
    private static final Integer MAX_MACHINES = 50;

    private static final Set<String> SUPPORTED_PRIORITIES = new Set<String>{
        'Critical',
        'High',
        'Medium',
        'Low'
    };

    @AuraEnabled
    public static ReportIssueData getReportIssueData() {
        try {
            CustomerContext customerContext = getCustomerContext();
            ReportIssueData reportData = new ReportIssueData();

            reportData.customerFirstName = customerContext.contact.FirstName;
            reportData.machines = loadAuthorizedMachines(customerContext.accountId);
            reportData.priorities = getPriorityOptions();
            reportData.defaultPriority = getDefaultPriority(reportData.priorities);

            return reportData;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'Your MillTrack service request form could not be loaded. Please refresh the page or try again later.'
            );
        }
    }

    @AuraEnabled
    public static SubmissionResult submitServiceRequest(
        Id assetId,
        String subject,
        String description,
        String errorCode,
        String priority,
        Boolean technicianRequested
    ) {
        try {
            validateSubmission(assetId, subject, description);

            CustomerContext customerContext = getCustomerContext();
            Asset authorizedAsset = getAuthorizedAsset(
                assetId,
                customerContext.accountId
            );

            if (authorizedAsset == null) {
                throw new AuraHandledException(
                    'We could not verify the selected machine for your MillTrack account.'
                );
            }

            String normalizedPriority = normalizePriority(priority);

            Map<String, Object> flowInputs = new Map<String, Object>{
                'inAccountId' => String.valueOf(customerContext.accountId),
                'inAssetId' => String.valueOf(authorizedAsset.Id),
                'inContactId' => String.valueOf(customerContext.contact.Id),
                'inDescription' => normalizeOptionalText(description),
                'inErrorCode' => normalizeOptionalText(errorCode),
                'inPriority' => normalizedPriority,
                'inSubject' => normalizeOptionalText(subject),
                'inTechnicianRequested' => technicianRequested == true
            };

            Flow.Interview.Create_Customer_Service_Case_Core flowInterview =
                new Flow.Interview.Create_Customer_Service_Case_Core(flowInputs);

            flowInterview.start();

            Boolean success = (Boolean) flowInterview.getVariableValue('outSuccess');
            String caseId = (String) flowInterview.getVariableValue('outCaseId');
            String caseNumber = (String) flowInterview.getVariableValue('outCaseNumber');
            String statusMessage = (String) flowInterview.getVariableValue('outStatusMessage');

            SubmissionResult result = new SubmissionResult();

            result.success = success == true;
            result.caseId = caseId;
            result.caseNumber = caseNumber;
            result.message = statusMessage;

            if (!result.success && String.isBlank(result.message)) {
                result.message =
                    'We could not create your service request. Please try again or contact MillTrack support.';
            }

            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'We could not submit your service request. Please try again or contact MillTrack support if the problem continues.'
            );
        }
    }

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
            SELECT Id, FirstName, AccountId
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

        customerContext.contact = contacts[0];
        customerContext.accountId = contacts[0].AccountId;

        return customerContext;
    }

    private static List<MachineOption> loadAuthorizedMachines(Id accountId) {
        List<Asset> machines = [
            SELECT
                Id,
                Name,
                Manufacturer__c,
                Model__c,
                Serial_Number__c,
                Machine_Status__c,
                Last_Service_Date__c,
                Portal_Image_Path__c,
                Portal_Manual_Path__c
            FROM Asset
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT :MAX_MACHINES
        ];

        List<MachineOption> machineOptions = new List<MachineOption>();

        for (Asset machine : machines) {
            machineOptions.add(new MachineOption(machine));
        }

        return machineOptions;
    }

    private static Asset getAuthorizedAsset(Id assetId, Id accountId) {
        List<Asset> assets = [
            SELECT Id
            FROM Asset
            WHERE Id = :assetId
            AND AccountId = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        return assets.isEmpty() ? null : assets[0];
    }

    private static List<PriorityOption> getPriorityOptions() {
        List<PriorityOption> priorityOptions = new List<PriorityOption>();

        for (Schema.PicklistEntry entry : Case.Priority.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) continue;
            if (!SUPPORTED_PRIORITIES.contains(entry.getValue())) continue;

            priorityOptions.add(
                new PriorityOption(
                    entry.getLabel(),
                    entry.getValue()
                )
            );
        }

        if (priorityOptions.isEmpty()) {
            throw new AuraHandledException(
                'Service request priorities are not currently configured.'
            );
        }

        return priorityOptions;
    }

    private static String getDefaultPriority(List<PriorityOption> priorityOptions) {
        for (PriorityOption option : priorityOptions) {
            if (option.value == 'Medium') return 'Medium';
        }

        return priorityOptions[0].value;
    }

    private static void validateSubmission(
        Id assetId,
        String subject,
        String description
    ) {
        if (assetId == null) {
            throw new AuraHandledException(
                'Please select the machine experiencing the issue.'
            );
        }

        if (String.isBlank(description)) {
            throw new AuraHandledException(
                'Please describe the problem you are experiencing.'
            );
        }

        if (subject != null && subject.trim().length() > 255) {
            throw new AuraHandledException(
                'Subject cannot exceed 255 characters.'
            );
        }
    }

    private static String normalizePriority(String priority) {
        if (SUPPORTED_PRIORITIES.contains(priority)) {
            return priority;
        }

        return 'Medium';
    }

    private static String normalizeOptionalText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private class CustomerContext {
        public Contact contact;
        public Id accountId;
    }

    public class ReportIssueData {
        @AuraEnabled public String customerFirstName { get; set; }
        @AuraEnabled public String defaultPriority { get; set; }
        @AuraEnabled public List<MachineOption> machines { get; set; }
        @AuraEnabled public List<PriorityOption> priorities { get; set; }

        public ReportIssueData() {
            customerFirstName = '';
            defaultPriority = 'Medium';
            machines = new List<MachineOption>();
            priorities = new List<PriorityOption>();
        }
    }

    public class MachineOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date lastServiceDate { get; set; }
        @AuraEnabled public String portalImagePath { get; set; }
        @AuraEnabled public String portalManualPath { get; set; }

        public MachineOption(Asset machine) {
            id = machine.Id;
            name = machine.Name;
            manufacturer = machine.Manufacturer__c;
            model = machine.Model__c;
            serialNumber = machine.Serial_Number__c;
            status = machine.Machine_Status__c;
            lastServiceDate = machine.Last_Service_Date__c;
            portalImagePath = machine.Portal_Image_Path__c;
            portalManualPath = machine.Portal_Manual_Path__c;
        }
    }

    public class PriorityOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public PriorityOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class SubmissionResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String caseId { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String message { get; set; }

        public SubmissionResult() {
            success = false;
            caseId = null;
            caseNumber = null;
            message = null;
        }
    }
}