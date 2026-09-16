public with sharing class ManagerServiceIntelligenceController {

    private static final Integer DEFAULT_DAYS_BACK = 90;
    private static final Integer MAX_DAYS_BACK = 3650;
    private static final Integer LOG_LIMIT = 2000;
    private static final Integer MODEL_LIMIT = 8;


    // =========================================================
    // Service Intelligence
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static ServiceIntelligenceData getServiceIntelligence(Integer daysBack) {
        Integer effectiveDaysBack = normalizeDaysBack(daysBack);
        Date endDate = Date.today();
        Date startDate = endDate.addDays(-(effectiveDaysBack - 1));

        List<Maintenance_Log__c> logs = [
            SELECT Id, Name, Maintenance_Date__c, Maintenance_Type__c, Labor_Hours__c,
                Issue_Resolved__c, Follow_Up_Required__c, Problem_Summary__c, Summary__c, Root_Cause__c, CreatedDate,
                Asset__c, Asset__r.Name, Asset__r.Manufacturer__c, Asset__r.Model__c, Asset__r.Serial_Number__c,
                Work_Order__c, Work_Order__r.WorkOrderNumber, Work_Order__r.Subject,
                Work_Order__r.AccountId, Work_Order__r.Account.Name,
                Work_Order__r.CaseId, Work_Order__r.Case.CaseNumber, Work_Order__r.Case.Subject,
                Performed_By__c, Performed_By__r.Name
            FROM Maintenance_Log__c
            WHERE Maintenance_Date__c >= :startDate
                AND Maintenance_Date__c <= :endDate
            WITH USER_MODE
            ORDER BY Maintenance_Date__c DESC, CreatedDate DESC
            LIMIT :LOG_LIMIT
        ];

        ServiceIntelligenceData result = buildServiceIntelligence(logs, effectiveDaysBack, startDate, endDate);
        return result;
    }


    // =========================================================
    // Build Response
    // =========================================================

    private static ServiceIntelligenceData buildServiceIntelligence(List<Maintenance_Log__c> logs, Integer daysBack, Date startDate, Date endDate) {
        ServiceIntelligenceData result = new ServiceIntelligenceData();
        result.daysBack = daysBack;
        result.startDate = startDate;
        result.endDate = endDate;
        result.models = new List<ModelServiceDTO>();

        Map<String, ModelAccumulator> modelMap = new Map<String, ModelAccumulator>();
        Set<Id> overallWorkOrderIds = new Set<Id>();

        for (Maintenance_Log__c logRecord : logs) {
            result.totalServiceVisits++;

            if (logRecord.Labor_Hours__c != null) result.totalLaborHours += logRecord.Labor_Hours__c;
            if (logRecord.Follow_Up_Required__c == true) result.totalFollowUps++;
            if (logRecord.Issue_Resolved__c == true) result.totalResolvedVisits++;

            if (logRecord.Work_Order__c != null) overallWorkOrderIds.add(logRecord.Work_Order__c);

            String manufacturer = logRecord.Asset__r == null ? null : cleanText(logRecord.Asset__r.Manufacturer__c);
            String model = logRecord.Asset__r == null ? null : cleanText(logRecord.Asset__r.Model__c);
            String assetName = logRecord.Asset__r == null ? null : cleanText(logRecord.Asset__r.Name);
            String modelKey = buildModelKey(manufacturer, model, assetName);

            if (!modelMap.containsKey(modelKey)) modelMap.put(modelKey, new ModelAccumulator(manufacturer, model, assetName));

            ModelAccumulator accumulator = modelMap.get(modelKey);
            accumulator.visitCount++;

            if (logRecord.Work_Order__c != null) accumulator.workOrderIds.add(logRecord.Work_Order__c);
            if (logRecord.Labor_Hours__c != null) accumulator.laborHours += logRecord.Labor_Hours__c;
            if (logRecord.Follow_Up_Required__c == true) accumulator.followUpCount++;
            if (logRecord.Issue_Resolved__c == true) accumulator.resolvedCount++;
            if (logRecord.Issue_Resolved__c != true && logRecord.Follow_Up_Required__c != true) accumulator.otherVisitCount++;

            if (accumulator.latestLog == null || isLogNewer(logRecord, accumulator.latestLog)) accumulator.latestLog = logRecord;
        }

        result.totalIssues = overallWorkOrderIds.size();

        List<ModelServiceDTO> rankedModels = new List<ModelServiceDTO>();

        for (ModelAccumulator accumulator : modelMap.values()) rankedModels.add(buildModelDTO(accumulator));

        rankedModels.sort();

        Integer maxVisitCount = rankedModels.isEmpty() ? 0 : rankedModels[0].serviceVisitCount;
        Integer modelsToReturn = Math.min(MODEL_LIMIT, rankedModels.size());

        for (Integer index = 0; index < modelsToReturn; index++) {
            ModelServiceDTO modelRecord = rankedModels[index];
            modelRecord.rank = index + 1;
            modelRecord.serviceLoadPercent = maxVisitCount == 0 ? 0 : Decimal.valueOf(modelRecord.serviceVisitCount * 100).divide(maxVisitCount, 1);
            result.models.add(modelRecord);
        }

        result.modelCount = modelMap.size();
        return result;
    }


    // =========================================================
    // Model DTO
    // =========================================================

    private static ModelServiceDTO buildModelDTO(ModelAccumulator accumulator) {
        ModelServiceDTO dto = new ModelServiceDTO();

        dto.manufacturer = accumulator.manufacturer;
        dto.model = accumulator.model;
        dto.machineLabel = buildMachineLabel(accumulator.manufacturer, accumulator.model, accumulator.assetName);
        dto.serviceVisitCount = accumulator.visitCount;
        dto.issueCount = accumulator.workOrderIds.size();
        dto.laborHours = accumulator.laborHours;
        dto.followUpCount = accumulator.followUpCount;
        dto.resolvedCount = accumulator.resolvedCount;
        dto.otherVisitCount = accumulator.otherVisitCount;

        if (accumulator.latestLog != null) applyLatestService(dto, accumulator.latestLog);

        return dto;
    }


    private static void applyLatestService(ModelServiceDTO dto, Maintenance_Log__c logRecord) {
        dto.latestMaintenanceLogId = logRecord.Id;
        dto.latestMaintenanceLogName = logRecord.Name;
        dto.latestMaintenanceDate = logRecord.Maintenance_Date__c;
        dto.latestMaintenanceType = cleanText(logRecord.Maintenance_Type__c);
        dto.latestProblemSummary = cleanText(logRecord.Problem_Summary__c);
        dto.latestRepairSummary = cleanText(logRecord.Summary__c);
        dto.latestRootCause = cleanText(logRecord.Root_Cause__c);

        dto.latestWorkOrderId = logRecord.Work_Order__c;
        dto.latestWorkOrderNumber = logRecord.Work_Order__r == null ? null : logRecord.Work_Order__r.WorkOrderNumber;
        dto.latestWorkOrderSubject = logRecord.Work_Order__r == null ? null : cleanText(logRecord.Work_Order__r.Subject);

        dto.latestAccountId = logRecord.Work_Order__r == null ? null : logRecord.Work_Order__r.AccountId;
        dto.latestAccountName = logRecord.Work_Order__r == null || logRecord.Work_Order__r.Account == null ? null : logRecord.Work_Order__r.Account.Name;

        dto.latestCaseId = logRecord.Work_Order__r == null ? null : logRecord.Work_Order__r.CaseId;
        dto.latestCaseNumber = logRecord.Work_Order__r == null || logRecord.Work_Order__r.Case == null ? null : logRecord.Work_Order__r.Case.CaseNumber;
        dto.latestCaseSubject = logRecord.Work_Order__r == null || logRecord.Work_Order__r.Case == null ? null : cleanText(logRecord.Work_Order__r.Case.Subject);

        dto.latestTechnicianId = logRecord.Performed_By__c;
        dto.latestTechnicianName = logRecord.Performed_By__r == null ? null : logRecord.Performed_By__r.Name;

        dto.latestWasResolved = logRecord.Issue_Resolved__c == true;
        dto.latestRequiresFollowUp = logRecord.Follow_Up_Required__c == true;
        dto.latestOutcomeKey = getOutcomeKey(logRecord);
        dto.latestOutcomeLabel = getOutcomeLabel(logRecord);
    }


    // =========================================================
    // Helpers
    // =========================================================

    private static Integer normalizeDaysBack(Integer daysBack) {
        if (daysBack == null) return DEFAULT_DAYS_BACK;
        if (daysBack < 1) throw new AuraHandledException('The reporting period must be at least one day.');
        if (daysBack > MAX_DAYS_BACK) throw new AuraHandledException('The reporting period is too large.');
        return daysBack;
    }


    private static Boolean isLogNewer(Maintenance_Log__c candidate, Maintenance_Log__c currentLatest) {
        if (candidate.Maintenance_Date__c > currentLatest.Maintenance_Date__c) return true;
        if (candidate.Maintenance_Date__c < currentLatest.Maintenance_Date__c) return false;
        return candidate.CreatedDate > currentLatest.CreatedDate;
    }


    private static String buildModelKey(String manufacturer, String model, String assetName) {
        String manufacturerKey = String.isBlank(manufacturer) ? 'UNKNOWN_MANUFACTURER' : manufacturer.trim().toUpperCase();
        String modelKey = String.isBlank(model) ? 'UNKNOWN_MODEL' : model.trim().toUpperCase();

        if (manufacturerKey == 'UNKNOWN_MANUFACTURER' && modelKey == 'UNKNOWN_MODEL') {
            return 'ASSET|' + (String.isBlank(assetName) ? 'UNKNOWN_ASSET' : assetName.trim().toUpperCase());
        }

        return manufacturerKey + '|' + modelKey;
    }


    private static String buildMachineLabel(String manufacturer, String model, String assetName) {
        List<String> parts = new List<String>();

        if (!String.isBlank(manufacturer)) parts.add(manufacturer.trim());
        if (!String.isBlank(model)) parts.add(model.trim());

        if (!parts.isEmpty()) return String.join(parts, ' ');
        if (!String.isBlank(assetName)) return assetName.trim();

        return 'Unknown Machine';
    }


    private static String getOutcomeKey(Maintenance_Log__c logRecord) {
        if (logRecord.Maintenance_Type__c == 'Temporary Repair') return 'TEMPORARY_REPAIR';
        if (logRecord.Follow_Up_Required__c == true) return 'FOLLOW_UP';
        if (logRecord.Issue_Resolved__c == true) return 'RESOLVED';
        return 'SERVICE_VISIT';
    }


    private static String getOutcomeLabel(Maintenance_Log__c logRecord) {
        if (logRecord.Maintenance_Type__c == 'Temporary Repair' && logRecord.Follow_Up_Required__c == true) return 'Temporary Repair · Follow-Up Required';
        if (logRecord.Maintenance_Type__c == 'Temporary Repair') return 'Temporary Repair';
        if (logRecord.Follow_Up_Required__c == true) return 'Follow-Up Required';
        if (logRecord.Issue_Resolved__c == true) return 'Resolved';
        return 'Service Visit';
    }


    private static String cleanText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }


    // =========================================================
    // Accumulator
    // =========================================================

    private class ModelAccumulator {
        public String manufacturer;
        public String model;
        public String assetName;
        public Integer visitCount = 0;
        public Decimal laborHours = 0;
        public Integer followUpCount = 0;
        public Integer resolvedCount = 0;
        public Integer otherVisitCount = 0;
        public Set<Id> workOrderIds = new Set<Id>();
        public Maintenance_Log__c latestLog;

        public ModelAccumulator(String manufacturer, String model, String assetName) {
            this.manufacturer = manufacturer;
            this.model = model;
            this.assetName = assetName;
        }
    }


    // =========================================================
    // Response DTO
    // =========================================================

    public class ServiceIntelligenceData {
        @AuraEnabled public Integer daysBack;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;

        @AuraEnabled public Integer totalServiceVisits = 0;
        @AuraEnabled public Integer totalIssues = 0;
        @AuraEnabled public Decimal totalLaborHours = 0;
        @AuraEnabled public Integer totalFollowUps = 0;
        @AuraEnabled public Integer totalResolvedVisits = 0;
        @AuraEnabled public Integer modelCount = 0;

        @AuraEnabled public List<ModelServiceDTO> models;
    }


    // =========================================================
    // Model DTO
    // =========================================================

    public class ModelServiceDTO implements Comparable {
        @AuraEnabled public Integer rank;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String model;
        @AuraEnabled public String machineLabel;

        @AuraEnabled public Integer serviceVisitCount;
        @AuraEnabled public Integer issueCount;
        @AuraEnabled public Decimal laborHours;
        @AuraEnabled public Integer followUpCount;
        @AuraEnabled public Integer resolvedCount;
        @AuraEnabled public Integer otherVisitCount;
        @AuraEnabled public Decimal serviceLoadPercent;

        @AuraEnabled public Id latestMaintenanceLogId;
        @AuraEnabled public String latestMaintenanceLogName;
        @AuraEnabled public Date latestMaintenanceDate;
        @AuraEnabled public String latestMaintenanceType;
        @AuraEnabled public String latestProblemSummary;
        @AuraEnabled public String latestRepairSummary;
        @AuraEnabled public String latestRootCause;

        @AuraEnabled public Id latestWorkOrderId;
        @AuraEnabled public String latestWorkOrderNumber;
        @AuraEnabled public String latestWorkOrderSubject;

        @AuraEnabled public Id latestAccountId;
        @AuraEnabled public String latestAccountName;

        @AuraEnabled public Id latestCaseId;
        @AuraEnabled public String latestCaseNumber;
        @AuraEnabled public String latestCaseSubject;

        @AuraEnabled public Id latestTechnicianId;
        @AuraEnabled public String latestTechnicianName;

        @AuraEnabled public Boolean latestWasResolved;
        @AuraEnabled public Boolean latestRequiresFollowUp;
        @AuraEnabled public String latestOutcomeKey;
        @AuraEnabled public String latestOutcomeLabel;


        public Integer compareTo(Object compareTo) {
            ModelServiceDTO other = (ModelServiceDTO) compareTo;

            if (serviceVisitCount > other.serviceVisitCount) return -1;
            if (serviceVisitCount < other.serviceVisitCount) return 1;

            Decimal thisLabor = laborHours == null ? 0 : laborHours;
            Decimal otherLabor = other.laborHours == null ? 0 : other.laborHours;

            if (thisLabor > otherLabor) return -1;
            if (thisLabor < otherLabor) return 1;

            String thisLabel = String.isBlank(machineLabel) ? '' : machineLabel.toLowerCase();
            String otherLabel = String.isBlank(other.machineLabel) ? '' : other.machineLabel.toLowerCase();

            return thisLabel.compareTo(otherLabel);
        }
    }
}